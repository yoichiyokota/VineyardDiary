import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UniformTypeIdentifiers
#endif

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    // 共通状態
    @State private var sortAscending = false
    @State private var searchText = ""
    @State private var confirmDelete: DiaryEntry?

    // 年×区画フィルタ
    @State private var selectedYear: Int = 0          // 0 = すべて
    @State private var selectedBlock: String = ""     // "" = すべて
    @State private var availableYears: [Int] = []     // 降順
    @State private var blockOptions: [String] = []    // 先頭 "" = すべて → 設定順のみ

    @StateObject private var thumbs = ThumbnailStore()

    // iOS 専用
    #if os(iOS)
    @State private var showEditorSheet = false
    @State private var editingEntryForSheet: DiaryEntry?
    @State private var showFolderPicker = false
    #endif

    // macOS 専用
    #if os(macOS)
    @State private var editorWindows: [NSWindow] = []
    @State private var statsWindows:  [NSWindow] = []
    #endif

    var body: some View {
        #if os(iOS)
        iOSBody
        #else
        macOSBody
        #endif
    }

    // ============================================================
    // iOS
    // ============================================================
    #if os(iOS)
    private var iOSBody: some View {
        NavigationStack {
            List {
                // フィルタ行（List の先頭に置く）
                Section {
                    FiltersRow(
                        availableYears: availableYears,
                        blockOptions: blockOptions,
                        selectedYear: $selectedYear,
                        selectedBlock: $selectedBlock,
                        sortAscending: $sortAscending
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }

                // 一覧
                Section {
                    let entries = filteredAndSorted()
                    ForEach(entries) { entry in
                        Button { openEditor(entry) } label: {
                            CompactEntryRow(entry: entry, weather: weather)
                                .environmentObject(thumbs)          // ★ 追加
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { deleteRow(entry) } label: {
                                Label("削除", systemImage: "trash")
                            }
                            Button { openEditor(entry) } label: {
                                Label("編集", systemImage: "pencil")
                            }
                        }
                    }
                    .onDelete { offsets in onListSwipeDelete(offsets) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Vineyard Diary")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText)
            .onAppear {
                rebuildYearAndBlockOptions()
                if selectedYear == 0, let first = availableYears.first { selectedYear = first }
            }
            // 既存の onAppear の近くに追加
            .onChange(of: store.settings.blocks.map { $0.name }) { _ in
                rebuildYearAndBlockOptions()
                // 選択値が候補に無い場合は「すべて」に戻す
                if !blockOptions.contains(selectedBlock) {
                    selectedBlock = ""
                }
            }
            .confirmationDialog(
                "この日記を削除しますか？",
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                )
            ) {
                Button("削除", role: .destructive) {
                    if let e = confirmDelete { deleteEntry(e); confirmDelete = nil }
                }
                Button("キャンセル", role: .cancel) { confirmDelete = nil }
            }
            .sheet(isPresented: $showEditorSheet) {
                EntryEditorView()
                    .environmentObject(store)
                    .environmentObject(weather)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 統計へ
                    NavigationLink {
                        StatisticsView()
                            .environmentObject(store)
                            .environmentObject(weather)
                    } label: {
                        Label("統計", systemImage: "chart.xyaxis.line")
                    }

                    // 共有フォルダ選択（Files。選択直後に保存＆取り込み）
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("フォルダ", systemImage: "folder")
                    }

                    // 手動再取り込み
                    Button {
                        Task {
                            do {
                                // 共有フォルダから再取り込み
                                _ = try await SharedImporter.importAllIfConfigured(into: store, weather: weather)
                                // 取り込み後に気象を準備（統計のため）
                                weather.load()
                                await backfillDailyWeatherAndRefreshEntries(store: store, weather: weather)
                            } catch {
                                print("Shared manual re-import failed:", error)
                            }
                        }
                    } label: {
                        Label("再取り込み", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            // フォルダピッカー（exhaustive な switch）
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [UTType.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    // iOS でも一応 scope を開始（iOS16 以降はフォルダでも true が返る構成が多い）
                    let started = url.startAccessingSecurityScopedResource()
                    defer { if started { url.stopAccessingSecurityScopedResource() } }

                    do {
                        try SharedFolderBookmark.saveFolderURL(url)
                        Task { try? await SharedImporter.importAllIfConfigured(into: store, weather: weather) }
                    } catch {
                        print("saveFolderURL failed:", error)
                    }

                case .failure(let err):
                    print("folder picker error:", err)
                @unknown default:
                    break
                }
            }
        }
    }

    // フィルタ「行」（List セクション内に置く）
    private struct FiltersRow: View {
        let availableYears: [Int]
        let blockOptions: [String]
        @Binding var selectedYear: Int
        @Binding var selectedBlock: String
        @Binding var sortAscending: Bool

        var body: some View {
            HStack(spacing: 12) {
                // 年
                HStack(spacing: 6) {
                    Text("年").font(.subheadline)
                    Picker("", selection: $selectedYear) {
                        if availableYears.isEmpty {
                            Text("—").tag(0)
                        } else {
                            ForEach(availableYears, id: \.self) { y in
                                Text(verbatim: "\(y)年").tag(y)
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                // 区画
                HStack(spacing: 6) {
                    Text("区画").font(.subheadline)
                    Picker("", selection: $selectedBlock) {
                        ForEach(blockOptions, id: \.self) { b in
                            Text(b.isEmpty ? "すべて" : b).tag(b)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                Spacer()

                // 並び替え
                Picker("", selection: $sortAscending) {
                    Text("新→古").tag(false)
                    Text("古→新").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
    }
    #endif

    // ============================================================
    // macOS
    // ============================================================
    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 8) {
            headerBar

            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Text("日記データが見つかりません")
                        .font(.headline)
                    Text("設定や保存先の変更、データの互換性で読み込みに失敗している可能性があります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("再読み込み") { store.load() }
                        .buttonStyle(.bordered)
                }
                .padding()
            }

            List {
                let entries = filteredAndSorted()
                ForEach(entries) { entry in
                    Button { openEditor(entry) } label: { listRow(entry) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { deleteRow(entry) } label: { Label("削除", systemImage: "trash") }
                            Button { openEditor(entry) } label: { Label("編集", systemImage: "pencil") }
                        }
                }
                .onDelete { offsets in onListSwipeDelete(offsets) }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .automatic)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onAppear {
            rebuildYearAndBlockOptions()
            if selectedYear == 0, let first = availableYears.first { selectedYear = first }
        }
        // 既存の onAppear の近くに追加
        .onChange(of: store.settings.blocks.map { $0.name }) { _ in
            rebuildYearAndBlockOptions()
            // 選択値が候補に無い場合は「すべて」に戻す
            if !blockOptions.contains(selectedBlock) {
                selectedBlock = ""
            }
        }
        .confirmationDialog(
            "この日記を削除しますか？",
            isPresented: Binding(get: { confirmDelete != nil },
                                 set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("削除", role: .destructive) {
                if let e = confirmDelete { deleteEntry(e); confirmDelete = nil }
            }
            Button("キャンセル", role: .cancel) { confirmDelete = nil }
        }
    }
    #endif
    
#if os(macOS)
@MainActor
private func restoreFromBackupUnified() {
    BackupRestoreUI.runUnifiedRestore(store: store, weather: weather)
}
#endif

    // ============================================================
    // 共通 UI（macOS 行）
    // ============================================================
    private var headerBar: some View {
        HStack(spacing: 12) {
            Button { openEditor(nil) } label: { Label("日記を追加", systemImage: "plus.circle.fill") }

            // 年
            HStack(spacing: 6) {
                Text("年")
                Picker("", selection: $selectedYear) {
                    if availableYears.isEmpty {
                        Text("—").tag(0)
                    } else {
                        ForEach(availableYears, id: \.self) { y in
                            Text(verbatim: "\(y)年").tag(y)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // 区画
            HStack(spacing: 6) {
                Text("区画")
                Picker("", selection: $selectedBlock) {
                    ForEach(blockOptions, id: \.self) { b in
                        Text(b.isEmpty ? "すべて" : b).tag(b)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            Picker("並び", selection: $sortAscending) {
                Text("日付 降順（新しい順）").tag(false)
                Text("日付 昇順（古い順）").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            Button { openStatistics() } label: {
                Label("統計", systemImage: "chart.xyaxis.line")
            }
        }
    }

    private func listRow(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumb(for: entry)
                .frame(width: 72, height: 54)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            EntryRow(entry: entry, showLeadingThumbnail: false)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                if let tempText = tempLabel(for: entry) {
                    Text(tempText).font(.caption).foregroundStyle(.secondary)
                }
                if let sunText = sunshineLabel(for: entry) {
                    Text(sunText).font(.caption).foregroundStyle(.secondary)
                }
                if let rainText = rainLabel(for: entry) {
                    Text(rainText).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 160, alignment: .trailing)

            Button {
                confirmDelete = entry
            } label: {
                Image(systemName: "trash").foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("この日記を削除")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // Weather labels
    private func tempLabel(for entry: DiaryEntry) -> String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        if let w = weather.get(block: entry.block, date: day),
           let tmax = w.tMax, let tmin = w.tMin {
            return String(format: "最高 %.1f℃ / 最低 %.1f℃", tmax, tmin)
        }
        return nil
    }
    private func sunshineLabel(for entry: DiaryEntry) -> String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        if let w = weather.get(block: entry.block, date: day),
           let sun = w.sunshineHours {
            return String(format: "日照 %.1fh", sun)
        }
        return nil
    }
    private func rainLabel(for entry: DiaryEntry) -> String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        if let w = weather.get(block: entry.block, date: day),
           let r = w.precipitationMm {
            return String(format: "降水 %.1fmm", r)
        }
        return nil
    }

    // Filter & Sort
    private func filteredAndSorted() -> [DiaryEntry] {
        let yearBlockFiltered = store.entries.filter { e in
            yearMatches(e) && blockMatches(e)
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = q.isEmpty ? yearBlockFiltered : yearBlockFiltered.filter { e in
            e.block.lowercased().contains(q)
            || e.workNotes.lowercased().contains(q)
            || e.memo.lowercased().contains(q)
        }
        let s = searched.sorted { $0.date < $1.date }
        return sortAscending ? s : s.reversed()
    }
    private func yearMatches(_ e: DiaryEntry) -> Bool {
        guard selectedYear != 0 else { return true }
        return Calendar.current.component(.year, from: e.date) == selectedYear
    }
    private func blockMatches(_ e: DiaryEntry) -> Bool {
        guard !selectedBlock.isEmpty else { return true }
        return e.block.compare(selectedBlock, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func rebuildYearAndBlockOptions() {
        availableYears = Set(store.entries.map { Calendar.current.component(.year, from: $0.date) })
            .sorted(by: >)
        let fixed = store.settings.blocks
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        blockOptions = [""] + fixed

        if !availableYears.contains(selectedYear) {
            selectedYear = availableYears.first ?? 0
        }
        if !blockOptions.contains(selectedBlock) {
            selectedBlock = ""
        }
    }

    // Delete helpers
    private func onListSwipeDelete(_ offsets: IndexSet) {
        let arr = filteredAndSorted()
        for idx in offsets { store.removeEntry(arr[idx]) }
    }
    private func deleteRow(_ entry: DiaryEntry) { store.removeEntry(entry) }
    private func deleteEntry(_ entry: DiaryEntry) {
        if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
            store.entries.remove(at: idx)
            store.save()
        }
    }

    // Thumbnail
    private func thumb(for entry: DiaryEntry) -> some View {
        let size = CGSize(width: 180, height: 135)
        return Group {
            #if os(macOS)
            if let first = entry.photos.first, let img = thumbs.thumbnail(for: first) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15)))
            } else {
                placeholder(size)
            }
            #else
            placeholder(size)
            #endif
        }
    }
    private func placeholder(_ size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08))
            Image(systemName: "photo").foregroundStyle(.secondary)
        }
        .frame(width: size.width, height: size.height)
    }

    // macOS windows
    #if os(macOS)
    private func openEditorWindow(editing: DiaryEntry?) {
        if let e = editing { store.editingEntry = e } else { store.editingEntry = nil }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = editing == nil ? "日記を追加" : "日記を編集"
        win.isReleasedWhenClosed = false
        win.center()
        let root = EntryEditorView().environmentObject(store).environmentObject(weather)
        win.contentView = NSHostingView(rootView: root)
        win.makeKeyAndOrderFront(nil)
        editorWindows.append(win)
    }
    private func openStatisticsWindow() {
        // ★ 統計を開く直前に最新化
        Task { @MainActor in
            // 既存の日記データに対して欠損ぶんを取得・追記
            weather.load()  // キャッシュ読み
            await backfillDailyWeatherAndRefreshEntries(store: store, weather: weather)
        }
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "気象グラフ"
        win.isReleasedWhenClosed = false
        win.center()
        let root = StatisticsView().environmentObject(store).environmentObject(weather)
        win.contentView = NSHostingView(rootView: root)
        win.makeKeyAndOrderFront(nil)
        statsWindows.append(win)
    }
    #endif

    // エディタ/統計の入り口（共通）
    private func openEditor(_ entry: DiaryEntry?) {
        #if os(macOS)
        openEditorWindow(editing: entry)
        #else
        if let e = entry { store.editingEntry = e } else { store.editingEntry = nil }
        editingEntryForSheet = entry
        showEditorSheet = true
        #endif
    }
    private func openStatistics() {
        #if os(macOS)
        openStatisticsWindow()
        #endif
    }

    // Formatters
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy/MM/dd"
        return df
    }()
    private static let hmFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "HH:mm"
        return df
    }()
}

// 既存
fileprivate extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
    
}


#if os(iOS)
// iOS: JSON FileDocument（必要なら将来のインポート/エクスポートで再利用）
import UniformTypeIdentifiers
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.vineyardDiary, .json] }
    static var writableContentTypes: [UTType] { [.vineyardDiary, .json] }

    var file: VineyardDiaryFile

    init(file: VineyardDiaryFile) { self.file = file }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.file = try JSONDecoder().decode(VineyardDiaryFile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(file)
        return .init(regularFileWithContents: data)
    }
}
#endif

#if os(iOS)
// iOS: コンパクト行（サムネ対応 + フォールバック）
private struct CompactEntryRow: View {
    let entry: DiaryEntry
    @ObservedObject var weather: DailyWeatherStore
    @EnvironmentObject var thumbs: ThumbnailStore

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy/MM/dd (EEE)"
        return df
    }()

    var body: some View {
        HStack(spacing: 12) {
            // 写真サムネ
            thumbView()
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Self.dayFormatter.string(from: entry.date))
                        .font(.subheadline).fontWeight(.semibold)
                    if !entry.block.isEmpty {
                        Text("· \(entry.block)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)

                if !entry.workNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.workNotes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let t = tempLabel(for: entry) { Text(t).font(.caption2).foregroundStyle(.secondary) }
                if let s = sunshineLabel(for: entry) { Text(s).font(.caption2).foregroundStyle(.secondary) }
                if let r = rainLabel(for: entry) { Text(r).font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    // MARK: - サムネイルビュー（サムネ→元画像フォールバック）
    @ViewBuilder
    private func thumbView() -> some View {
        // まずは「元画像っぽい名前」を優先的に採用（*_thumb や -150x150 を避ける）
        let name = primaryPhotoName()

        if let name,
           let img = thumbs.thumbnail(for: name) {
            // ThumbnailStore が作ってくれた縮小画像
            Image(uiImage: img).resizable().scaledToFill()
        } else if let name {
            // フォールバック：サムネが未生成/見つからない場合に元画像を直接読み込み
            let originalURL = URL.documentsDirectory.appendingPathComponent(name)
            if let raw = UIImage(contentsOfFile: originalURL.path) {
                Image(uiImage: raw).resizable().scaledToFill()
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1))
            Image(systemName: "photo")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - “元画像”名の抽出（サムネ名を除外）
    private func primaryPhotoName() -> String? {
        guard !entry.photos.isEmpty else { return nil }
        // サムネっぽいものを除外して最初の1枚を選ぶ
        if let original = entry.photos.first(where: { !isThumbName($0) }) {
            return original
        }
        // 全部サムネ名しか無い場合は先頭を採用
        return entry.photos.first
    }

    private func isThumbName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("/thumb/") || lower.contains("/thumbs/") || lower.contains("/.thumbs/") { return true }
        if lower.contains("_thumb.") || lower.contains("-thumb.") || lower.contains(".thumb.") { return true }
        if lower.range(of: #"-\d{2,4}x\d{2,4}\."#, options: .regularExpression) != nil { return true }
        return false
    }

    // MARK: - Weather labels（既存）
    private func tempLabel(for entry: DiaryEntry) -> String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        if let w = weather.get(block: entry.block, date: day),
           let tmax = w.tMax, let tmin = w.tMin {
            return String(format: "%.0f/%.0f℃", tmax, tmin)
        }
        return nil
    }
    private func sunshineLabel(for entry: DiaryEntry) -> String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        if let w = weather.get(block: entry.block, date: day),
           let sun = w.sunshineHours {
            return String(format: "☀︎ %.1fh", sun)
        }
        return nil
    }
    private func rainLabel(for entry: DiaryEntry) -> String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        if let w = weather.get(block: entry.block, date: day),
           let r = w.precipitationMm {
            return String(format: "☂︎ %.0fmm", r)
        }
        return nil
    }
}
#endif
