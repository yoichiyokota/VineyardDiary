import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var showStats = false
    @State private var sortAscending = false
    @State private var searchText: String = ""

    private var filteredAndSortedEntries: [DiaryEntry] {
        let base = store.entries.filter { e in
            guard !searchText.isEmpty else { return true }
            let hay = [
                ISO8601DateFormatter.yyyyMMdd.string(from: e.date),
                e.block,
                e.workNotes,
                e.memo,
                e.varieties.map { $0.varietyName }.joined(separator: " "),
                e.varieties.map { $0.stage }.joined(separator: " "),
                e.sprays.map { $0.chemicalName }.joined(separator: " "),
                e.volunteers.joined(separator: " ")
            ].joined(separator: " ").lowercased()
            return hay.contains(searchText.lowercased())
        }
        return base.sorted { sortAscending ? $0.date < $1.date : $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            // タイトル＋操作バー（左寄せ）
            HStack(spacing: 12) {
                Text("Vineyard Diary")
                    .font(.title2).bold()

                Divider().frame(height: 18)

                Picker("", selection: $sortAscending) {
                    Text("日付 降順（新しい順）").tag(false)
                    Text("日付 昇順（古い順）").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer()

                TextField("検索", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                Button {
                    EditorWindowManager.shared.openEditor(store: store, weather: weather, editing: nil)
                } label: {
                    Label("日記を追加", systemImage: "plus.circle.fill")
                }

                Button {
                    StatisticsWindowManager.shared.openStats(store: store, weather: weather)
                } label: {
                    Label("統計", systemImage: "chart.xyaxis.line")
                }

                SettingsLink {
                    Label("設定", systemImage: "gearshape")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            // 本体リスト
            List {
                ForEach(filteredAndSortedEntries) { entry in
                    EntryRow(entry: entry, onDelete: {
                        if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                            store.entries.remove(at: idx)
                            store.save()
                        }
                    })
                    .contentShape(Rectangle())
                    .onTapGesture {
                        EditorWindowManager.shared.openEditor(store: store, weather: weather, editing: entry)
                    }
                    .contextMenu {
                        Button("この日記を編集") {
                            EditorWindowManager.shared.openEditor(store: store, weather: weather, editing: entry)
                        }
                        Button(role: .destructive) {
                            if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                                store.entries.remove(at: idx)
                                store.save()
                            }
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: store.deleteEntry)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}

// MARK: - 行ビュー
private let metaFont: Font = .caption
private let bodyFont: Font = .callout

private struct EntryRow: View {
    let entry: DiaryEntry
    let onDelete: () -> Void

    // 作業時間を 09:00–11:30, 13:10–14:00 のように連結（WorkTime の start/end は非Optional）
    private var workTimeLine: String? {
        guard !entry.workTimes.isEmpty else { return nil }
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP_POSIX")
        df.timeZone = .current
        df.dateFormat = "HH:mm"
        let parts = entry.workTimes.map { r in
            "\(df.string(from: r.start))–\(df.string(from: r.end))"
        }
        return parts.joined(separator: ", ")
    }

    // 防除の表示行（赤）
    private var sprayLine: String? {
        guard entry.isSpraying else { return nil }
        let chems = entry.sprays.map { s in
            s.dilution.isEmpty ? s.chemicalName : "\(s.chemicalName)(\(s.dilution))"
        }.joined(separator: ", ")
        let liters = entry.sprayTotalLiters.trimmingCharacters(in: .whitespaces)
        let litersPart = liters.isEmpty ? "" : " 使用L:\(liters)"
        let head = chems.isEmpty ? "防除実施" : "防除: \(chems)"
        return head + litersPart
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左：サムネイル
            if let firstName = entry.photos.first,
               let img = NSImage(contentsOf: URL.documentsDirectory.appendingPathComponent(firstName)) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.06))
                        .frame(width: 72, height: 72)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }

            // 中央：テキスト（全文表示）
            VStack(alignment: .leading, spacing: 6) {
                // 1行目：日付・区画
                Text("\(ISO8601DateFormatter.yyyyMMdd.string(from: entry.date))  \(entry.block)")
                    .font(.headline)

                // 品種(ステージ)の一覧（ある場合のみ）
                if !entry.varieties.isEmpty {
                    Text(entry.varieties.map { v in
                        v.stage.isEmpty ? v.varietyName : "\(v.varietyName)(\(v.stage))"
                    }.joined(separator: " / "))
                    .font(metaFont)
                    .foregroundStyle(.secondary)
                }

                // 防除（赤）
                if let spray = sprayLine {
                    Text(spray)
                        .font(bodyFont.weight(.semibold))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 作業時間（1行）
                if let wt = workTimeLine {
                    HStack(spacing: 8) {
                        Text("作業時間:").font(metaFont).foregroundStyle(.secondary)
                        Text(wt).font(bodyFont)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                // 作業内容（全文表示）
                if !entry.workNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("作業内容").font(metaFont).foregroundStyle(.secondary)
                        Text(entry.workNotes)
                            .font(bodyFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // 備考（全文表示）
                if !entry.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("備考").font(metaFont).foregroundStyle(.secondary)
                        Text(entry.memo)
                            .font(bodyFont)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // ボランティア氏名（任意）※配列を「, 」で結合表示
                if !entry.volunteers.isEmpty {
                    HStack(spacing: 8) {
                        Text("ボランティア").font(metaFont).foregroundStyle(.secondary)
                        Text(entry.volunteers.joined(separator: ", ")).font(bodyFont)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右：気温・日照 + 削除
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .trailing, spacing: 4) {
                    if let min = entry.weatherMin, let max = entry.weatherMax {
                        Text("最高 \(max, specifier: "%.1f")℃ / 最低 \(min, specifier: "%.1f")℃")
                    } else {
                        Text("気温 未取得").foregroundStyle(.secondary)
                    }
                    if let sun = entry.sunshineHours {
                        Text("日照 \(sun, specifier: "%.1f") h")
                    } else {
                        Text("日照 未取得").foregroundStyle(.secondary)
                    }
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("この日記を削除")
            }
            .font(.caption)
            .frame(minWidth: 180, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 編集ウインドウ（赤・黄・緑ボタンあり）
import AppKit

@MainActor
final class EditorWindowManager: NSObject, NSWindowDelegate {
    static let shared = EditorWindowManager()
    private var windows: [NSWindow] = []

    func openEditor(store: DiaryStore, weather: DailyWeatherStore, editing: DiaryEntry?) {
        store.editingEntry = editing

        let root = EntryEditorView()
            .environmentObject(store)
            .environmentObject(weather)

        let vc = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: vc)
        w.title = editing == nil ? "日記を追加" : "日記を編集"
        w.setContentSize(NSSize(width: 960, height: 820))
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.center()
        w.delegate = self                 // ← ここがポイント
        w.makeKeyAndOrderFront(nil)

        windows.append(w)
    }

    // NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow {
            windows.removeAll { $0 == w } // ← MainActor 上なので Sendable 警告は出ません
        }
    }
}

// MARK: - 統計ウインドウ
@MainActor
final class StatisticsWindowManager: NSObject, NSWindowDelegate {
    static let shared = StatisticsWindowManager()
    private var windows: [NSWindow] = []

    func openStats(store: DiaryStore, weather: DailyWeatherStore) {
        let root = StatisticsView()
            .environmentObject(store)
            .environmentObject(weather)

        let vc = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: vc)
        w.title = "統計情報"
        w.setContentSize(NSSize(width: 1000, height: 760))
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.center()
        w.delegate = self                 // ← ここがポイント
        w.makeKeyAndOrderFront(nil)

        windows.append(w)
    }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow {
            windows.removeAll { $0 == w }
        }
    }
}
