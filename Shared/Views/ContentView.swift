import SwiftUI
import AppKit

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var sortAscending = false
    @State private var searchText = ""
    @State private var confirmDelete: DiaryEntry?

    @StateObject private var thumbs = ThumbnailStore()

    @State private var editorWindows: [NSWindow] = []
    @State private var statsWindows:  [NSWindow] = []

    // === 年 × 区画 フィルタ ===
    @State private var selectedYear: Int = 0          // 0=すべて（初期は後で当年に寄せる）
    @State private var selectedBlock: String = ""     // ""=すべて
    @State private var availableYears: [Int] = []     // 降順
    @State private var blockOptions: [String] = []    // 先頭 "" = すべて。以降は設定順→出現順

    var body: some View {
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
                        openEditorWindow(editing: entry)
                    } label: {
                        listRow(entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteRow(entry)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button {
                            openEditorWindow(editing: entry)
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
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
            // 既定：当年（データが無ければ 0=すべてのまま）
            if selectedYear == 0, let first = availableYears.first {
                selectedYear = first
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
                if let e = confirmDelete {
                    deleteEntry(e)
                    confirmDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) { confirmDelete = nil }
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                openEditorWindow(editing: nil)
            } label: {
                Label("日記を追加", systemImage: "plus.circle.fill")
            }

            // 年セレクタ（表示は 4桁+「年」、カンマ無し）
            HStack(spacing: 6) {
                Text("年")
                Picker("", selection: $selectedYear) {
                    if availableYears.isEmpty {
                        Text("—").tag(0)
                    } else {
                        ForEach(availableYears, id: \.self) { y in
                            Text(yearTitle(y)).tag(y)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // 区画セレクタ（先頭は必ず「すべて」）
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

            Button { openStatisticsWindow() } label: {
                Label("統計", systemImage: "chart.xyaxis.line")
            }
        }
    }

    // MARK: - 行表示
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

    // MARK: - ラベル（既存）
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

    // MARK: - フィルタ & 並び
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
        // 完全一致。部分一致にしたい場合は contains を利用
        return e.block.compare(selectedBlock, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    // MARK: - 候補構築（「固定順 → 出現順」）
    private func rebuildYearAndBlockOptions() {
        // 年候補：データからユニーク抽出 → 降順（最新が先頭）
        availableYears = Set(store.entries.map { Calendar.current.component(.year, from: $0.date) })
            .sorted(by: >)

        // 区画候補：設定順をそのまま採用（EntryEditorView と同じ）
        // store.settings.blocks は Identifiable な配列想定（.name を使用）
        let fixed = store.settings.blocks
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 追加：設定に無い区画がデータ側にあれば“出現順”で後ろに足す
        // （余裕があれば、ここごと削って「固定順のみ」にしてもOK）
        let fixedKeys = Set(fixed.map { canonical($0) })
        var extrasOrdered: [String] = []
        var seen = Set<String>()
        for e in store.entries {
            let raw = e.block.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = canonical(raw)
            guard !raw.isEmpty else { continue }
            if !fixedKeys.contains(key) && !seen.contains(key) {
                seen.insert(key)
                extrasOrdered.append(raw)
            }
        }

        // 先頭に ""（=すべて）→ 設定順 → 追加分（出現順）
        blockOptions = [""] + fixed + extrasOrdered

        // 選択の妥当性
        if !availableYears.contains(selectedYear) {
            selectedYear = availableYears.first ?? 0
        }
        if !blockOptions.contains(selectedBlock) {
            selectedBlock = "" // すべて
        }
    }
    // MARK: - ヘルパー（ここが前回は“関数の中”に入っていた可能性大）
    // 4桁 + 「年」（カンマ無し）
    private func yearTitle(_ y: Int) -> String { "\(String(y))年" }

    // 正規化キー：全角→半角スペース、前後空白除去、小文字化
    private func canonical(_ s: String) -> String {
        s.replacingOccurrences(of: "　", with: " ")
         .trimmingCharacters(in: .whitespacesAndNewlines)
         .lowercased()
    }

    // 入力順を維持したまま重複排除（正規化キーで判定）
    private func stableUniq(_ array: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in array {
            let trimmed = raw.replacingOccurrences(of: "　", with: " ")
                             .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = canonical(trimmed)
            if !key.isEmpty && !seen.contains(key) {
                seen.insert(key)
                result.append(trimmed)
            }
        }
        return result
    }

    // MARK: - Delete（既存）
    private func onListSwipeDelete(_ offsets: IndexSet) {
        let arr = filteredAndSorted()
        for idx in offsets { store.removeEntry(arr[idx]) }
    }
    private func deleteRow(_ entry: DiaryEntry) { store.removeEntry(entry) }

    // MARK: - Thumbs（既存）
    private func thumb(for entry: DiaryEntry) -> some View {
        let size = CGSize(width: 180, height: 135)
        return Group {
            if let first = entry.photos.first, let img = thumbs.thumbnail(for: first) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15)))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08))
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    // MARK: - Window（既存）
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

    private func deleteEntry(_ entry: DiaryEntry) {
        if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
            store.entries.remove(at: idx)
            store.save()
        }
    }

    // MARK: - Formatters（既存）
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
