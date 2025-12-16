//
//  Created by yoichi_yokota on 2025/12/16.
//


#if os(macOS)
import SwiftUI
import AppKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Entry Editor (macOS)

@MainActor
struct EntryEditorView_macOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    
    @StateObject private var viewModel = EntryEditorViewModel()
    @StateObject private var thumbs = ThumbnailStore()
    
    // UI状態
    @State private var previewPhotoName: String?
    @State private var isShowingPreview = false
    @State private var selectedPhotosFromApp: [PhotosPickerItem] = []
    
    // レイアウト定数
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
        .onAppear {
            viewModel.initialize(from: store.editingEntry, settings: store.settings)
        }
        .sheet(isPresented: $isShowingPreview, onDismiss: {
            previewPhotoName = nil
        }) {
            if let name = previewPhotoName {
                PreviewSheet(fileName: name)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack {
            Text(viewModel.isEditing ? "日記を編集" : "日記を追加")
                .font(.headline)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    // MARK: - Date & Weather
    
    private var dateAndWeather: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 10) {
            GridRow {
                Text("日付").frame(width: labelWidth, alignment: .leading)
                DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            weatherInfoRows
        }
    }
    
    private var weatherInfoRows: some View {
        Group {
            GridRow {
                Text("").frame(width: labelWidth)
                Text(viewModel.temperatureLabel ?? "気温: 未取得（保存時に取得）")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GridRow {
                Text("").frame(width: labelWidth)
                Text(viewModel.sunshineLabel.map { "日照時間: \($0)" } ?? "日照時間: 未取得（保存時に取得）")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            GridRow {
                Text("").frame(width: labelWidth)
                Text(viewModel.rainLabel.map { "降水量: \($0)" } ?? "降水量: 未取得（保存時に取得）")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Block Picker
    
    private var blockPicker: some View {
        Grid {
            GridRow {
                Text("区画").frame(width: labelWidth, alignment: .leading)
                Picker("", selection: $viewModel.block) {
                    Text("未選択").tag("")
                    ForEach(store.settings.blocks) { block in
                        Text(block.name).tag(block.name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Varieties
    
    private var varietiesSection: some View {
        Grid {
            ForEach(viewModel.varieties.indices, id: \.self) { index in
                GridRow {
                    Text("品種").frame(width: labelWidth, alignment: .leading)
                    Picker("", selection: $viewModel.varieties[index].varietyName) {
                        Text("未選択").tag("")
                        ForEach(store.settings.varieties) { v in
                            Text(v.name).tag(v.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: viewModel.varieties[index].varietyName) { _, _ in
                        autoFillPreviousStage(for: index)
                    }
                }
                
                GridRow {
                    Text("成長ステージ").frame(width: labelWidth, alignment: .leading)
                    HStack(spacing: 8) {
                        Picker("", selection: $viewModel.varieties[index].stage) {
                            Text("未選択").tag("")
                            ForEach(store.settings.stages) { s in
                                Text("\(s.code): \(s.label)").tag("\(s.code): \(s.label)")
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(role: .destructive) {
                            viewModel.removeVariety(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            GridRow {
                Text("").frame(width: labelWidth)
                Button {
                    viewModel.addVariety()
                } label: {
                    Label("品種を追加", systemImage: "plus.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func autoFillPreviousStage(for index: Int) {
        guard viewModel.varieties[index].stage.isEmpty,
              let prev = store.previousStage(
                block: viewModel.block,
                variety: viewModel.varieties[index].varietyName,
                before: viewModel.date
              ) else {
            return
        }
        viewModel.varieties[index].stage = prev
    }
    
    // MARK: - Spraying
    
    private var sprayingSection: some View {
        Grid {
            GridRow {
                Text("防除実施").frame(width: labelWidth, alignment: .leading)
                Toggle("", isOn: $viewModel.isSpraying)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if viewModel.isSpraying {
                GridRow {
                    Text("使用L").frame(width: labelWidth, alignment: .leading)
                    TextField("", text: $viewModel.sprayTotalLiters)
                        .frame(width: tankFieldWidth, alignment: .leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                ForEach(viewModel.sprays.indices, id: \.self) { index in
                    GridRow {
                        Text("").frame(width: labelWidth)
                        HStack(spacing: 8) {
                            TextField("薬剤名", text: $viewModel.sprays[index].chemicalName)
                                .frame(width: drugNameFieldWidth, alignment: .leading)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("希釈倍率")
                                .frame(width: 72, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            
                            TextField("", text: $viewModel.sprays[index].dilution)
                                .frame(width: dilutionFieldWidth, alignment: .leading)
                                .textFieldStyle(.roundedBorder)
                            
                            Spacer(minLength: 0)
                            
                            Button(role: .destructive) {
                                viewModel.removeSpray(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                
                GridRow {
                    Text("").frame(width: labelWidth)
                    Button {
                        viewModel.addSpray()
                    } label: {
                        Label("薬剤を追加", systemImage: "plus.circle")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    // MARK: - Work Notes
    
    private var workNotesEditors: some View {
        Grid {
            GridRow {
                Text("作業内容").frame(width: labelWidth, alignment: .leading)
                TextEditor(text: $viewModel.workNotes)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.gray.opacity(0.2))
                    )
            }
            
            GridRow {
                Text("備考").frame(width: labelWidth, alignment: .leading)
                TextEditor(text: $viewModel.memo)
                    .frame(minHeight: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.gray.opacity(0.2))
                    )
            }
        }
    }
    
    // MARK: - Work Times
    
    private var workTimesSection: some View {
        Grid {
            ForEach(viewModel.workTimes.indices, id: \.self) { index in
                GridRow {
                    Text(index == 0 ? "作業時間" : "")
                        .frame(width: labelWidth, alignment: .leading)
                    HStack {
                        DatePicker("", selection: $viewModel.workTimes[index].start, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 170)
                        Text("〜")
                        DatePicker("", selection: $viewModel.workTimes[index].end, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 170)
                        Button(role: .destructive) {
                            viewModel.removeWorkTime(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            GridRow {
                Text("").frame(width: labelWidth)
                Button {
                    viewModel.addWorkTime()
                } label: {
                    Label("時間帯を追加", systemImage: "plus.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Volunteers
    
    private var volunteersSection: some View {
        Grid {
            GridRow {
                Text("ボランティア氏名").frame(width: labelWidth, alignment: .leading)
                TextField("", text: $viewModel.volunteersText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Photos
    
    private var photosSection: some View {
        Grid {
            GridRow {
                Text("写真").frame(width: labelWidth, alignment: .leading)
                HStack(spacing: 12) {
                    if #available(macOS 13.0, *) {
                        PhotosPicker(
                            selection: $selectedPhotosFromApp,
                            maxSelectionCount: 12,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("写真を追加（写真App）", systemImage: "photo.on.rectangle.angled")
                        }
                        .onChange(of: selectedPhotosFromApp) { _, items in
                            Task {
                                await viewModel.importPhotosFromApp(items)
                                selectedPhotosFromApp.removeAll()
                            }
                        }
                    }
                    
                    Button {
                        importFromFilePicker()
                    } label: {
                        Label("ファイルから追加", systemImage: "folder.badge.plus")
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !viewModel.photos.isEmpty {
                GridRow {
                    Text("").frame(width: labelWidth)
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.photos, id: \.self) { name in
                                PhotoThumbWithCaption(
                                    fileName: name,
                                    size: photoThumbSize,
                                    thumbnailStore: thumbs,
                                    caption: Binding(
                                        get: { viewModel.photoCaptions[name] ?? "" },
                                        set: { viewModel.photoCaptions[name] = $0 }
                                    ),
                                    onTap: {
                                        previewPhotoName = name
                                        isShowingPreview = true
                                    },
                                    onDelete: {
                                        viewModel.deletePhoto(name)
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
    
    private func importFromFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                autoreleasepool {
                    do {
                        let data = try Data(contentsOf: url)
                        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                        let name = "photo_\(UUID().uuidString).\(ext)"
                        let dest = URL.documentsDirectory.appendingPathComponent(name)
                        try data.write(to: dest, options: .atomic)
                        viewModel.photos.append(name)
                    } catch {
                        print("❌ import from file failed:", error)
                    }
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerBar: some View {
        HStack {
            Spacer()
            Button("閉じる") {
                closeWindow()
            }
            Button("保存") {
                Task {
                    await viewModel.save(
                        to: store,
                        weather: weather,
                        settings: store.settings
                    )
                    closeWindow()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    private func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}

// MARK: - Supporting Views

private struct PhotoThumbWithCaption: View {
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2))
                        )
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

private struct PreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fileName: String
    @State private var bigImage: NSImage?
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
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
            bigImage = autoreleasepool { NSImage(contentsOf: url) }
        }
        .onDisappear {
            bigImage = nil
        }
        .interactiveDismissDisabled(false)
    }
}

// MARK: - ViewModel Extension for macOS Photos

extension EntryEditorViewModel {
    #if os(macOS)
    @available(macOS 13.0, *)
    func importPhotosFromApp(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               !data.isEmpty {
                let name = "photo_\(UUID().uuidString).jpg"
                let url = URL.documentsDirectory.appendingPathComponent(name)
                
                do {
                    try data.write(to: url, options: .atomic)
                    await MainActor.run {
                        photos.append(name)
                    }
                } catch {
                    print("❌ write photo failed:", error)
                }
            }
        }
    }
    #endif
}

#endif
