#if os(macOS)

import SwiftUI
import AppKit
import PhotosUI
import UniformTypeIdentifiers

struct EntryEditorView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var thumbs = ThumbnailStore()

    @State private var working = DiaryEntry(date: Date(), block: "")
    @State private var volunteersText = ""
    @State private var previewName: String? = nil
    @State private var isShowingPreview = false
    @State private var selectedPhotos: [PhotosPickerItem] = []  // 写真App選択結果
    
    private let labelWidth: CGFloat = 96
    private let drugNameFieldWidth: CGFloat = 220
    private let dilutionFieldWidth: CGFloat = 140
    private let tankFieldWidth: CGFloat = 160
    private let photoThumbSize = CGSize(width: 90, height: 68)
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerBar
                    dateAndWeather
                    blockPicker
                    varietiesSection
                    sprayingSection
                    workNotesEditors
                    workTimesSection
                    volunteersSection
                    photosSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            footerBar
        }
        .frame(minWidth: 900, minHeight: 820)
        .onAppear { initializeWorkingBuffer() }
        .sheet(isPresented: $isShowingPreview, onDismiss: {
            previewName = nil
        }) {
            if let name = previewName {
                PreviewSheetView(fileName: name)
            } else {
                Text("画像を読み込めませんでした").padding()
            }
        }
    }
    
    @available(macOS 13.0, *)
    private func importPhotosFromPhotosApp(items: [PhotosPickerItem]) {
        Task {
            for item in items {
                // 画像データを直接取得
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    let name = "photo_\(UUID().uuidString).jpg"
                    let url  = URL.documentsDirectory.appendingPathComponent(name)
                    do {
                        try data.write(to: url, options: .atomic)
                        // working に追記（あなたの変数名が違う場合は合わせてください）
                        working.photos.append(name)
                    } catch {
                        print("write photo failed:", error)
                    }
                }
            }
            await MainActor.run { selectedPhotos.removeAll() }
        }
    }

    
    // MARK: - Header
    private var headerBar: some View {
        HStack {
            Text(store.editingEntry == nil ? "日記を追加" : "日記を編集")
                .font(.headline)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    // MARK: - Sections
    private var dateAndWeather: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 10) {
            GridRow {
                Text("日付").frame(width: labelWidth, alignment: .leading)
                DatePicker("", selection: $working.date, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                Text("").frame(width: labelWidth)
                Group {
                    if let min = working.weatherMin, let max = working.weatherMax {
                        Text("気温: 最低 \(min, specifier: "%.1f")℃ / 最高 \(max, specifier: "%.1f")℃")
                    } else {
                        Text("気温: 未取得（保存時に取得）")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                Text("").frame(width: labelWidth)
                Group {
                    if let sun = working.sunshineHours {
                        Text("日照時間: \(sun, specifier: "%.1f") h")
                    } else {
                        Text("日照時間: 未取得（保存時に取得）")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                Text("").frame(width: labelWidth)
                Group {
                    if let rain = working.precipitationMm {
                        Text("降水量: \(rain, specifier: "%.1f") mm")
                    } else {
                        Text("降水量: 未取得（保存時に取得）")
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var blockPicker: some View {
        Grid {
            GridRow {
                Text("区画").frame(width: labelWidth, alignment: .leading)
                Picker("", selection: $working.block) {
                    Text("未選択").tag("")
                    ForEach(store.settings.blocks) { b in
                        Text(b.name).tag(b.name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var varietiesSection: some View {
        Grid {
            ForEach(working.varieties.indices, id: \.self) { i in
                GridRow {
                    Text("品種").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: $working.varieties[i].varietyName) {
                        Text("未選択").tag("")
                        ForEach(store.settings.varieties) { v in
                            Text(v.name).tag(v.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: working.varieties[i].varietyName) { _, _ in
                        if working.varieties[i].stage.isEmpty,
                           let prev = store.previousStage(block: working.block,
                                                          variety: working.varieties[i].varietyName,
                                                          before: working.date) {
                            working.varieties[i].stage = prev
                        }
                    }
                }
                GridRow {
                    Text("成長ステージ").frame(width: labelWidth, alignment: .leading)
                    HStack(spacing: 8) {
                        Picker("", selection: $working.varieties[i].stage) {
                            Text("未選択").tag("")
                            ForEach(store.settings.stages) { s in
                                Text("\(s.code): \(s.label)").tag("\(s.code): \(s.label)")
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(role: .destructive) {
                            if working.varieties.count > 1 {
                                working.varieties.remove(at: i)
                            } else {
                                working.varieties[0] = .init(varietyName: "", stage: "")
                            }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            GridRow {
                Text("").frame(width: labelWidth)
                Button {
                    working.varieties.append(.init())
                } label: { Label("品種を追加", systemImage: "plus.circle") }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var sprayingSection: some View {
        Grid {
            GridRow {
                Text("防除実施").frame(width: labelWidth, alignment: .leading)
                Toggle("", isOn: $working.isSpraying)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if working.isSpraying {
                GridRow {
                    Text("使用L").frame(width: labelWidth, alignment: .leading)
                    TextField("", text: $working.sprayTotalLiters)
                        .frame(width: tankFieldWidth, alignment: .leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(working.sprays.indices, id: \.self) { i in
                    GridRow {
                        Text("").frame(width: labelWidth)
                        HStack(spacing: 8) {
                            TextField("薬剤名", text: $working.sprays[i].chemicalName)
                                .frame(width: drugNameFieldWidth, alignment: .leading)
                                .textFieldStyle(.roundedBorder)
                            Text("希釈倍率").frame(width: 72, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("", text: $working.sprays[i].dilution)
                                .frame(width: dilutionFieldWidth, alignment: .leading)
                                .textFieldStyle(.roundedBorder)
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                working.sprays.remove(at: i)
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                GridRow {
                    Text("").frame(width: labelWidth)
                    Button {
                        working.sprays.append(.init())
                    } label: { Label("薬剤を追加", systemImage: "plus.circle") }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    private var workNotesEditors: some View {
        Grid {
            GridRow {
                Text("作業内容").frame(width: labelWidth, alignment: .leading)
                TextEditor(text: $working.workNotes)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.2)))
            }
            GridRow {
                Text("備考").frame(width: labelWidth, alignment: .leading)
                TextEditor(text: $working.memo)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.2)))
            }
        }
    }
    
    private var workTimesSection: some View {
        Grid {
            ForEach(working.workTimes.indices, id: \.self) { i in
                GridRow {
                    Text(i == 0 ? "作業時間" : "").frame(width: labelWidth, alignment: .leading)
                    HStack {
                        DatePicker("", selection: Binding(
                            get: { working.workTimes[i].start },
                            set: { working.workTimes[i].start = $0 }),
                                   displayedComponents: .hourAndMinute)
                        .labelsHidden().frame(width: 170)
                        Text("〜")
                        DatePicker("", selection: Binding(
                            get: { working.workTimes[i].end },
                            set: { working.workTimes[i].end = $0 }),
                                   displayedComponents: .hourAndMinute)
                        .labelsHidden().frame(width: 170)
                        Button(role: .destructive) {
                            working.workTimes.remove(at: i)
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            GridRow {
                Text("").frame(width: labelWidth)
                Button {
                    working.workTimes.append(.init(start: Date(), end: Date()))
                } label: { Label("時間帯を追加", systemImage: "plus.circle") }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var volunteersSection: some View {
        Grid {
            GridRow {
                Text("ボランティア氏名").frame(width: labelWidth, alignment: .leading)
                TextField("", text: $volunteersText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Photos section (platform split)
    private var photosSection: some View {
        Grid {
            GridRow {
                Text("写真").frame(width: labelWidth, alignment: .leading)
                HStack(spacing: 12) {
                  
                    if #available(macOS 13.0, *) {
                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 12,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("写真を追加（写真App）", systemImage: "photo.on.rectangle.angled")
                        }
                        .onChange(of: selectedPhotos) { _, items in
                            importPhotosFromPhotosApp(items: items)
                        }
                    }
                    
                    Button {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                autoreleasepool {
                                    do {
                                        let data = try Data(contentsOf: url)
                                        let ext  = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                                        let name = "photo_\(UUID().uuidString).\(ext)"
                                        let dest = URL.documentsDirectory.appendingPathComponent(name)
                                        try data.write(to: dest, options: .atomic)
                                        working.photos.append(name)
                                    } catch {
                                        print("import from file failed:", error)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("ファイルから追加", systemImage: "folder.badge.plus")
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !working.photos.isEmpty {
                GridRow {
                    Text("").frame(width: labelWidth)
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            ForEach(working.photos, id: \.self) { name in
                                PhotoThumbWithCaptionView(
                                    fileName: name,
                                    size: photoThumbSize,
                                    thumbnailStore: thumbs,
                                    caption: Binding(
                                        get: { working.photoCaptions[name] ?? "" },
                                        set: { working.photoCaptions[name] = $0 }
                                    ),
                                    onTap: {
                                        previewName = name
                                        isShowingPreview = true
                                    },
                                    onDelete: {
                                        if let idx = working.photos.firstIndex(of: name) {
                                            working.photos.remove(at: idx)
                                        }
                                        working.photoCaptions[name] = nil
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private var footerBar: some View {
        HStack {
            Spacer()
            Button("閉じる") { closeWindow() }
            Button("保存") { saveEntryAndAttachWeather() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        
    }
    
    // MARK: - Logic
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
    
    private func saveEntryAndAttachWeather() {
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
        
        guard let blk = store.settings.blocks.first(where: { $0.name == working.block }),
              let lat = blk.latitude, let lon = blk.longitude else {
            closeWindow(); return
        }
        let targetDate = Calendar.current.startOfDay(for: working.date)
        
        if let cached = weather.get(block: blk.name, date: targetDate) {
            applyWeather(cached); closeWindow(); return
        }
        
        Task {
            do {
                let items = try await WeatherService.fetchDailyRange(lat: lat, lon: lon, from: targetDate, to: targetDate)
                if let first = items.first {
                    await MainActor.run {
                        weather.set(block: blk.name, item: first)
                        weather.save()
                        applyWeather(first)
                        store.save()
                    }
                }
            } catch {
                print("fetch one day failed:", error)
            }
            await MainActor.run { closeWindow() }
        }
    }
    
    private func applyWeather(_ w: DailyWeather) {
        if let idx = store.entries.firstIndex(where: { $0.id == working.id }) {
            store.entries[idx].weatherMin = w.tMin
            store.entries[idx].weatherMax = w.tMax
            store.entries[idx].sunshineHours = w.sunshineHours
            store.entries[idx].precipitationMm = w.precipitationMm
        }
    }
    
    private func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
 
}

// MARK: - Thumb views (platform-safe)
private struct PhotoThumbWithCaptionView: View {
    let fileName: String
    let size: CGSize
    let thumbnailStore: ThumbnailStore
    @Binding var caption: String
    var onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onTap) {
                if let nsimg = thumbnailStore.thumbnail(for: fileName) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                } else {
                    placeholderThumb
                }
            }
            .buttonStyle(.plain)

            TextField("キャプション", text: $caption)
                .textFieldStyle(.roundedBorder)
                .frame(width: size.width)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var placeholderThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
                .frame(width: size.width, height: size.height)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview sheet (platform split)
private struct PreviewSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let fileName: String
    @State private var bigImage: NSImage? = nil

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.trailing, 8)

            if let img = bigImage {
                GeometryReader { geo in
                    let maxW = geo.size.width - 32
                    let maxH = geo.size.height - 32
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxW, maxHeight: maxH)
                        .padding(16)
                }
            } else {
                ProgressView().padding()
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            let url = URL.documentsDirectory.appendingPathComponent(fileName)
            bigImage = autoreleasepool(invoking: { NSImage(contentsOf: url) })
        }
        .onDisappear { bigImage = nil }
        .interactiveDismissDisabled(false)
    }
}

#endif
