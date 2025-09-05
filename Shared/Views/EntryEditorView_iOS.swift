#if os(iOS)
import SwiftUI
import PhotosUI

@MainActor
struct EntryEditorView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    @Environment(\.dismiss) private var dismiss

    // 編集用ワーキングコピー
    @State private var working = DiaryEntry(date: Date(), block: "")
    @State private var volunteersText = ""

    // UI 状態
    @State private var isSaving = false
    @State private var showDeletePhotoAlert = false
    @State private var photoToDelete: String? = nil

    // 写真ピッカー（アプリ内に“新規取り込み”する時だけ使用）
    @State private var selectedItems: [PhotosPickerItem] = []

    // プレビュー（後日拡張用のダミー）
    @State private var previewName: String? = nil
    @State private var showingPreview = false

    // レイアウト
    private let thumbSize = CGSize(width: 84, height: 63)

    var body: some View {
        NavigationStack {
            Form {
                // 基本情報
                Section(header: Text("基本")) {
                    DatePicker("日付", selection: $working.date, displayedComponents: .date)

                    Picker("区画", selection: $working.block) {
                        Text("未選択").tag("")
                        ForEach(store.settings.blocks) { b in
                            Text(b.name).tag(b.name)
                        }
                    }

                    HStack {
                        Label("最高/最低", systemImage: "thermometer.sun")
                        Spacer()
                        Text(tempLabel(for: working) ?? "—").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("日照", systemImage: "sun.max")
                        Spacer()
                        Text(sunshineLabel(for: working) ?? "—").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("降水", systemImage: "cloud.rain")
                        Spacer()
                        Text(rainLabel(for: working) ?? "—").foregroundStyle(.secondary)
                    }
                }

                // 品種とステージ
                Section(header: Text("品種・ステージ")) {
                    ForEach(working.varieties.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("品種", selection: $working.varieties[i].varietyName) {
                                Text("未選択").tag("")
                                ForEach(store.settings.varieties) { v in
                                    Text(v.name).tag(v.name)
                                }
                            }
                            Picker("成長ステージ", selection: $working.varieties[i].stage) {
                                Text("未選択").tag("")
                                ForEach(store.settings.stages) { s in
                                    Text("\(s.code): \(s.label)").tag("\(s.code): \(s.label)")
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                if working.varieties.count > 1 {
                                    working.varieties.remove(at: i)
                                } else {
                                    working.varieties[0] = .init(varietyName: "", stage: "")
                                }
                            } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                    Button {
                        working.varieties.append(.init())
                    } label: {
                        Label("品種を追加", systemImage: "plus.circle")
                    }
                }

                // 防除
                Section(header: Text("防除")) {
                    Toggle("防除実施", isOn: $working.isSpraying)
                    if working.isSpraying {
                        TextField("総使用量（L）", text: $working.sprayTotalLiters)
                            .keyboardType(.decimalPad)

                        ForEach(working.sprays.indices, id: \.self) { i in
                            VStack(alignment: .leading) {
                                TextField("薬剤名", text: $working.sprays[i].chemicalName)
                                HStack {
                                    Text("希釈倍率")
                                    TextField("例) 1000倍", text: $working.sprays[i].dilution)
                                        .keyboardType(.numbersAndPunctuation)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { working.sprays.remove(at: i) } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }

                        Button {
                            working.sprays.append(.init())
                        } label: {
                            Label("薬剤を追加", systemImage: "plus.circle")
                        }
                    }
                }

                // 作業メモ
                Section(header: Text("作業メモ")) {
                    TextField("作業内容", text: $working.workNotes, axis: .vertical).lineLimit(3...6)
                    TextField("備考", text: $working.memo, axis: .vertical).lineLimit(2...4)
                }

                // 作業時間
                Section(header: Text("作業時間")) {
                    ForEach(working.workTimes.indices, id: \.self) { i in
                        HStack {
                            DatePicker("開始",
                                       selection: Binding(get: { working.workTimes[i].start },
                                                          set: { working.workTimes[i].start = $0 }),
                                       displayedComponents: .hourAndMinute)
                            DatePicker("終了",
                                       selection: Binding(get: { working.workTimes[i].end },
                                                          set: { working.workTimes[i].end = $0 }),
                                       displayedComponents: .hourAndMinute)
                        }
                        .swipeActions {
                            Button(role: .destructive) { working.workTimes.remove(at: i) } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        working.workTimes.append(.init(start: Date(), end: Date()))
                    } label: {
                        Label("時間帯を追加", systemImage: "plus.circle")
                    }
                }

                // ボランティア
                Section(header: Text("ボランティア")) {
                    TextField("氏名（カンマ区切り）", text: $volunteersText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                // 写真（※ここが“ノンブロッキング”版）
                Section(header: Text("写真")) {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 12, matching: .images) {
                        Label("写真を追加（アプリ内にコピー）", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedItems) { _, items in importPhotos(items) }

                    if working.photos.isEmpty {
                        Text("写真はまだありません").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [.init(.adaptive(minimum: thumbSize.width), spacing: 12)], spacing: 12) {
                            ForEach(working.photos, id: \.self) { name in
                                VStack(spacing: 6) {
                                    // ① まずアプリ内ドキュメント（即表示可）
                                    if let ui = localUIImage(for: name) {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: thumbSize.width, height: thumbSize.height)
                                            .clipped()
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        // ② 共有パッケージ上の写真は“雲”でプレース（非同期ダウンロードは指示だけ）
                                        PlaceholderCloudThumb(caption: working.photoCaptions[name] ?? "",
                                                              size: thumbSize,
                                                              sharedURL: sharedPhotoURL(for: name))
                                    }

                                    TextField("キャプション",
                                              text: Binding(
                                                get: { working.photoCaptions[name] ?? "" },
                                                set: { working.photoCaptions[name] = $0 }
                                              ))
                                    .textFieldStyle(.roundedBorder)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        photoToDelete = name
                                        showDeletePhotoAlert = true
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(store.editingEntry == nil ? "日記を追加" : "日記を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveEntryAndAttachWeather() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存") }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("写真を削除しますか？", isPresented: $showDeletePhotoAlert) {
                Button("削除", role: .destructive) {
                    if let n = photoToDelete {
                        if let idx = working.photos.firstIndex(of: n) {
                            working.photos.remove(at: idx)
                        }
                        working.photoCaptions[n] = nil
                    }
                }
                Button("キャンセル", role: .cancel) {}
            }
            .onAppear { initializeWorkingBuffer() }
        }
    }

    // MARK: - 初期化
    private func initializeWorkingBuffer() {
        if let editing = store.editingEntry {
            working = editing
        } else {
            let defBlock = store.settings.blocks.first?.name ?? ""
            working = DiaryEntry(date: Date(), block: defBlock)
            working.varieties = [VarietyStageItem()]
        }
        volunteersText = working.volunteers.joined(separator: ", ")
    }

    // MARK: - 保存 & 気象付与（iOS版）
    private func saveEntryAndAttachWeather() async {
        isSaving = true
        defer { isSaving = false }

        working.volunteers = volunteersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let editing = store.editingEntry {
            var updated = working; updated.id = editing.id
            store.updateEntry(updated); store.editingEntry = nil
        } else {
            store.addEntry(working)
        }
        store.save()

        guard let blk = store.settings.blocks.first(where: { $0.name == working.block }),
              let lat = blk.latitude, let lon = blk.longitude else {
            dismiss(); return
        }

        let day = Calendar.current.startOfDay(for: working.date)
        if let w = weather.get(block: blk.name, date: day) {
            applyWeather(w); dismiss(); return
        }

        do {
            let items = try await WeatherService.fetchDailyRange(lat: lat, lon: lon, from: day, to: day)
            if let first = items.first {
                weather.set(block: blk.name, item: first)
                weather.save()
                applyWeather(first)
                store.save()
            }
        } catch {
            print("iOS weather fetch failed:", error)
        }
        dismiss()
    }

    private func applyWeather(_ w: DailyWeather) {
        if let idx = store.entries.firstIndex(where: { $0.id == working.id }) {
            store.entries[idx].weatherMin      = w.tMin
            store.entries[idx].weatherMax      = w.tMax
            store.entries[idx].sunshineHours   = w.sunshineHours
            store.entries[idx].precipitationMm = w.precipitationMm
        }
    }

    // MARK: - 写真取り込み（アプリ内 Documents に保存）
    private func importPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    let name = "photo_\(UUID().uuidString).jpg"
                    let url  = URL.documentsDirectory.appendingPathComponent(name)
                    do {
                        try data.write(to: url, options: .atomic)
                        working.photos.append(name)
                    } catch {
                        print("write photo failed:", error)
                    }
                }
            }
            await MainActor.run { selectedItems.removeAll() }
        }
    }

    // MARK: - ローカル画像 & 共有写真URL（非ブロッキング）
    private func localUIImage(for name: String) -> UIImage? {
        let url = URL.documentsDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// 共有パッケージの Photos/ 内のURLを *必要な時だけ* 作る（存在確認やダウンロードは行わない）
    private func sharedPhotoURL(for name: String) -> URL? {
        guard let folder = SharedFolderBookmark.loadFolderURL() else { return nil }
        return folder.appendingPathComponent("Photos").appendingPathComponent(name)
    }

    // MARK: - ラベル（参考表示）
    private func tempLabel(for entry: DiaryEntry) -> String? {
        if let tmax = entry.weatherMax, let tmin = entry.weatherMin {
            return String(format: "最高 %.1f℃ / 最低 %.1f℃", tmax, tmin)
        }
        return nil
    }
    private func sunshineLabel(for entry: DiaryEntry) -> String? {
        if let s = entry.sunshineHours { return String(format: "%.1fh", s) }
        return nil
    }
    private func rainLabel(for entry: DiaryEntry) -> String? {
        if let r = entry.precipitationMm { return String(format: "%.1fmm", r) }
        return nil
    }
}

/// 雲プレースホルダ（共有 URL が来ても **ダウンロード待ちはしない**）
private struct PlaceholderCloudThumb: View {
    let caption: String
    let size: CGSize
    let sharedURL: URL? // 参考表示のみ。ここでは触らない

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08))
            VStack(spacing: 6) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("iCloud準備中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(6)
        }
        .frame(width: size.width, height: size.height)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15))
        )
        .help(sharedURL?.lastPathComponent ?? "iCloud")
    }
}
#endif
