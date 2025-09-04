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

    // MARK: - States (common)
    @State private var sortAscending = false
    @State private var searchText = ""
    @State private var confirmDelete: DiaryEntry?

    // 年×区画フィルタ
    @State private var selectedYear: Int = 0          // 0 = すべて
    @State private var selectedBlock: String = ""     // "" = すべて
    @State private var availableYears: [Int] = []     // 降順
    @State private var blockOptions: [String] = []    // 先頭 "" = すべて → 設定順のみ

    // サムネイル（macOSで利用／iOSはプレースホルダ）
    @StateObject private var thumbs = ThumbnailStore()

    // MARK: - iOS states
    #if os(iOS)
    @State private var showEditorSheet = false
    @State private var editingEntryForSheet: DiaryEntry?
    #endif

    // MARK: - macOS states
    #if os(macOS)
    @State private var editorWindows: [NSWindow] = []  // ウインドウ保持（ARCで消えないように）
    @State private var statsWindows:  [NSWindow] = []
    #endif

    // MARK: - Body
    var body: some View {
        #if os(iOS)
        iOSBody
        #else
        macOSBody
        #endif
    }

    // ============================================================
    // MARK: - iOS body（最上位List・シンプル表示・スクロール最優先）
    // ============================================================
    #if os(iOS)
    private var iOSBody: some View {
        List {
            Section {
                ForEach(filteredAndSorted()) { entry in
                    CompactEntryRow(entry: entry, weather: weather)
                        .contentShape(Rectangle())
                        .onTapGesture { openEditor(entry) }
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
            } header: {
                filtersHeader
            }
        }
        .listStyle(.plain) // スクロール性重視
        .searchable(text: $searchText)
        .onAppear {
            rebuildYearAndBlockOptions()
            if selectedYear == 0, let first = availableYears.first { selectedYear = first }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                // 統計画面へ遷移（NavigationStack 内想定）
                NavigationLink {
                    StatisticsView()
                        .environmentObject(store)
                        .environmentObject(weather)
                } label: {
                    Label("統計", systemImage: "chart.xyaxis.line")
                }
            }
        }
    }

    // iOS: フィルタ（セクションヘッダ）
    private var filtersHeader: some View {
        HStack(spacing: 12) {
            // 年（カンマ無しの4桁 + 「年」）
            HStack(spacing: 6) {
                Text("年").font(.subheadline)
                Picker("", selection: $selectedYear) {
                    if availableYears.isEmpty {
                        Text("—").tag(0)
                    } else {
                        ForEach(availableYears, id: \.self) { y in
                            Text(verbatim: "\(y)年").tag(y) // 明示的に文字列化（カンマ回避）
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // 区画（設定順のみ）
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

            // 並び替え（コンパクト）
            Picker("", selection: $sortAscending) {
                Text("新→古").tag(false)
                Text("古→新").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.vertical, 4)
    }
    #endif

    // ============================================================
    // MARK: - macOS body（従来のVStack＋ヘッダバー＋List）
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
                ForEach(filteredAndSorted()) { entry in
                    Button {
                        openEditor(entry)
                    } label: {
                        listRow(entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteRow(entry)
                        } label: { Label("削除", systemImage: "trash") }

                        Button {
                            openEditor(entry)
                        } label: { Label("編集", systemImage: "pencil") }
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
        .confirmationDialog(
            "この日記を削除しますか？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                if let e = confirmDelete {
                    deleteEntry(e); confirmDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) { confirmDelete = nil }
        }
    }
    #endif

    // ============================================================
    // MARK: - 共通（macOS行UI）
    // ============================================================
    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                openEditor(nil)
            } label: {
                Label("日記を追加", systemImage: "plus.circle.fill")
            }

            // 年セレクタ（4桁+「年」、カンマ無し）
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

            // 区画セレクタ（設定順のみ）
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

            Button {
                openStatistics()
            } label: {
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

            EntryRow(entry: entry)
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

    // MARK: - Weather Labels
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

    // MARK: - Filter & Sort
    private func filteredAndSorted() -> [DiaryEntry] {
        // 年＆区画
        let yearBlockFiltered = store.entries.filter { e in
            yearMatches(e) && blockMatches(e)
        }

        // 検索
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = q.isEmpty ? yearBlockFiltered : yearBlockFiltered.filter { e in
            e.block.lowercased().contains(q)
            || e.workNotes.lowercased().contains(q)
            || e.memo.lowercased().contains(q)
        }

        // 並び
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

    // MARK: - Options builder
    private func rebuildYearAndBlockOptions() {
        // 年候補：ユニーク抽出 → 降順（最新が先頭）
        availableYears = Set(store.entries.map { Calendar.current.component(.year, from: $0.date) })
            .sorted(by: >)

        // 区画：設定順（EntryEditorView と同じ）だけを採用
        let fixed = store.settings.blocks
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 先頭に「すべて」
        blockOptions = [""] + fixed

        // 妥当性
        if !availableYears.contains(selectedYear) {
            selectedYear = availableYears.first ?? 0
        }
        if !blockOptions.contains(selectedBlock) {
            selectedBlock = "" // すべて
        }
    }

    // MARK: - Helpers
    private func yearTitle(_ y: Int) -> String { "\(y)年" }

    private func canonical(_ s: String) -> String {
        s.replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func stableUniq(_ array: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in array {
            let trimmed = raw.replacingOccurrences(of: "　", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = canonical(trimmed)
            if !key.isEmpty && !seen.contains(key) {
                seen.insert(key); result.append(trimmed)
            }
        }
        return result
    }

    // MARK: - Delete
    private func onListSwipeDelete(_ offsets: IndexSet) {
        let arr = filteredAndSorted()
        for idx in offsets { store.removeEntry(arr[idx]) }
    }
    private func deleteRow(_ entry: DiaryEntry) { store.removeEntry(entry) }

    // MARK: - Thumbnail
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
            placeholder(size) // iOS は暫定プレースホルダ
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

    // MARK: - Editor / Statistics entry points (platform split)
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

    // MARK: - macOS windows
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

        let root = EntryEditorView()
            .environmentObject(store)
            .environmentObject(weather)
        win.contentView = NSHostingView(rootView: root)

        win.makeKeyAndOrderFront(nil)
        editorWindows.append(win)
    }

    private func openStatisticsWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "気象グラフ"
        win.isReleasedWhenClosed = false
        win.center()

        let root = StatisticsView()
            .environmentObject(store)
            .environmentObject(weather)
        win.contentView = NSHostingView(rootView: root)

        win.makeKeyAndOrderFront(nil)
        statsWindows.append(win)
    }
    #endif

    private func deleteEntry(_ entry: DiaryEntry) {
        if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
            store.entries.remove(at: idx)
            store.save()
        }
    }

    // MARK: - Formatters
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

// ============================================================
// MARK: - iOS: コンパクト行（軽量・2行構成）
// ============================================================
#if os(iOS)
private struct CompactEntryRow: View {
    let entry: DiaryEntry
    @ObservedObject var weather: DailyWeatherStore

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy/MM/dd (EEE)"
        return df
    }()

    var body: some View {
        HStack(spacing: 12) {
            // サムネ（いったんプレースホルダ。後でUIImage対応に置換）
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1))
                Image(systemName: "photo")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                // 1行目：日付 + 区画
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

                // 2行目：作業内容の先頭だけ
                if !entry.workNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.workNotes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // 右側：天気のチップ（あれば）
            VStack(alignment: .trailing, spacing: 2) {
                if let t = tempLabel(for: entry) {
                    Text(t).font(.caption2).foregroundStyle(.secondary)
                }
                if let s = sunshineLabel(for: entry) {
                    Text(s).font(.caption2).foregroundStyle(.secondary)
                }
                if let r = rainLabel(for: entry) {
                    Text(r).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    // ラベル取得
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
