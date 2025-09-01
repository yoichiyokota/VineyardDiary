import SwiftUI
import AppKit

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var sortAscending = false
    @State private var searchText = ""
    @State private var confirmDelete: DiaryEntry?
    // ① 追加：一覧サムネイル用の軽量キャッシュ
    @StateObject private var thumbs = ThumbnailStore()

    // 生成したウインドウを保持（ARCで消えないように）
    @State private var editorWindows: [NSWindow] = []
    @State private var statsWindows:  [NSWindow] = []

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
                    Button("再読み込み") {
                        store.load()
                    }
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
        
        // ContentView の body の最後でチェーン（.toolbar の後など、どこでもOK）
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

            Picker("並び", selection: $sortAscending) {
                Text("日付 降順（新しい順）").tag(false)
                Text("日付 昇順（古い順）").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            Button {
                openStatisticsWindow()
            } label: {
                Label("統計", systemImage: "chart.xyaxis.line")
            }
        }
    }

    // MARK: - Row
    private func listRow(_ entry: DiaryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // サムネイルは現状通り残す
            thumb(for: entry)
                .frame(width: 72, height: 54)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // ここを EntryRow に差し替える
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
            // 🗑️ ゴミ箱（追加）
            Button {
                confirmDelete = entry
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("この日記を削除")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    // MARK: - Labels
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

    // MARK: - Filtering / Sorting
    private func filteredAndSorted() -> [DiaryEntry] {
        let base = store.entries.filter { e in
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            let q = searchText.lowercased()
            return e.block.lowercased().contains(q)
                || e.workNotes.lowercased().contains(q)
                || e.memo.lowercased().contains(q)
        }
        let s = base.sorted { $0.date < $1.date }
        return sortAscending ? s : s.reversed()
    }

    // MARK: - Delete
    private func onListSwipeDelete(_ offsets: IndexSet) {
        let arr = filteredAndSorted()
        for idx in offsets {
            store.removeEntry(arr[idx])
        }
    }
    private func deleteRow(_ entry: DiaryEntry) {
        store.removeEntry(entry)
    }

    // MARK: - Thumbs
    // ContentView.swift 内：listRow(_:) で呼ばれるサムネイル表示ヘルパを差し替え
    private func thumb(for entry: DiaryEntry) -> some View {
        let size = CGSize(width: 180, height: 135)   // 表示サイズ（ThumbnailStoreと合わせる）
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
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.08))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    // MARK: - Open windows (Editor / Statistics)
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

fileprivate extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
