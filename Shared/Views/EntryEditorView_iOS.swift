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

    // 写真ピッカー
    @State private var selectedItems: [PhotosPickerItem] = []

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

                    // 参考（保存後に付与される気象）
                    HStack {
                        Label("最高/最低", systemImage: "thermometer.sun")
                        Spacer()
                        Text(tempLabel(for: working) ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("日照", systemImage: "sun.max")
                        Spacer()
                        Text(sunshineLabel(for: working) ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("降水", systemImage: "cloud.rain")
                        Spacer()
                        Text(rainLabel(for: working) ?? "—")
                            .foregroundStyle(.secondary)
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
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
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
                                Button(role: .destructive) {
                                    working.sprays.remove(at: i)
                                } label: {
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
                    TextField("作業内容", text: $working.workNotes, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("備考", text: $working.memo, axis: .vertical)
                        .lineLimit(2...4)
                }

                // 作業時間
                Section(header: Text("作業時間")) {
                    ForEach(working.workTimes.indices, id: \.self) { i in
                        HStack {
                            DatePicker("開始", selection: Binding(
                                get: { working.workTimes[i].start },
                                set: { working.workTimes[i].start = $0 }),
                                       displayedComponents: .hourAndMinute)
                            DatePicker("終了", selection: Binding(
                                get: { working.workTimes[i].end },
                                set: { working.workTimes[i].end = $0 }),
                                       displayedComponents: .hourAndMinute)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                working.workTimes.remove(at: i)
                            } label: {
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

                // 写真
                Section(header: Text("写真")) {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 12,
                        matching: .images
                    ) {
                        Label("写真を追加", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedItems) { _, items in
                        importPhotos(items)
                    }

                    if working.photos.isEmpty {
                        Text("写真はまだありません").foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [.init(.adaptive(minimum: thumbSize.width), spacing: 12)], spacing: 12) {
                            ForEach(working.photos, id: \.self) { name in
                                VStack(spacing: 6) {
                                    Button {
                                        // iOS 簡易版：プレビューは後日。まずは保存・一覧を優先
                                    } label: {
                                        photoThumb(name: name, size: thumbSize)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)

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

        // volunteers を同期
        working.volunteers = volunteersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // まずエントリ保存
        if let editing = store.editingEntry {
            var updated = working; updated.id = editing.id
            store.updateEntry(updated); store.editingEntry = nil
        } else {
            store.addEntry(working)
        }
        store.save()

        // 区画の座標があれば気象取得
        guard let blk = store.settings.blocks.first(where: { $0.name == working.block }),
              let lat = blk.latitude, let lon = blk.longitude
        else {
            dismiss(); return
        }

        let day = Calendar.current.startOfDay(for: working.date)
        // 既にキャッシュがあるなら即反映
        if let w = weather.get(block: blk.name, date: day) {
            applyWeather(w)
            dismiss()
            return
        }

        // ネット取得
        do {
            let items = try await WeatherService.fetchDailyRange(lat: lat, lon: lon, from: day, to: day)
            if let first = items.first {
                weather.set(block: blk.name, item: first)
                weather.save()
                applyWeather(first)
                store.save()
            }
        } catch {
            // サイレント失敗（オフライン等）。編集は保存済み。
            print("iOS weather fetch failed:", error)
        }

        dismiss()
    }

    private func applyWeather(_ w: DailyWeather) {
        if let idx = store.entries.firstIndex(where: { $0.id == working.id }) {
            store.entries[idx].weatherMin        = w.tMin
            store.entries[idx].weatherMax        = w.tMax
            store.entries[idx].sunshineHours     = w.sunshineHours
            store.entries[idx].precipitationMm   = w.precipitationMm
        }
    }

    // MARK: - 写真取り込み（Documents に保存）
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

    // MARK: - サムネ描画（超軽量）
    private func photoThumb(name: String, size: CGSize) -> some View {
        let url = URL.documentsDirectory.appendingPathComponent(name)
        if let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15)))
                .eraseToAnyView()
        } else {
            return ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08))
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
            .frame(width: size.width, height: size.height)
            .eraseToAnyView()
        }
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

// ちょい便利
fileprivate extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
#endif
