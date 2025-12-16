//
//  Created by yoichi_yokota on 2025/12/16.
//


#if os(iOS)
import SwiftUI
import PhotosUI

// MARK: - Entry Editor (iOS)

@MainActor
struct EntryEditorView_iOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel = EntryEditorViewModel()
    
    // UI状態
    @State private var isSaving = false
    @State private var showDeletePhotoAlert = false
    @State private var photoToDelete: String?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    var body: some View {
        NavigationStack {
            Form {
                basicSection
                varietiesSection
                sprayingSection
                workNotesSection
                workTimesSection
                volunteersSection
                photosSection
            }
            .navigationTitle(viewModel.isEditing ? "日記を編集" : "日記を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("写真を削除しますか?", isPresented: $showDeletePhotoAlert) {
                deletePhotoAlertActions
            }
            .onAppear {
                viewModel.initialize(from: store.editingEntry, settings: store.settings)
            }
        }
    }
    
    // MARK: - Sections
    
    private var basicSection: some View {
        Section(header: Text("基本")) {
            DatePicker("日付", selection: $viewModel.date, displayedComponents: .date)
            
            Picker("区画", selection: $viewModel.block) {
                Text("未選択").tag("")
                ForEach(store.settings.blocks) { block in
                    Text(block.name).tag(block.name)
                }
            }
            
            weatherInfoRows
        }
    }
    
    private var weatherInfoRows: some View {
        Group {
            HStack {
                Label("最高/最低", systemImage: "thermometer.sun")
                Spacer()
                Text(viewModel.temperatureLabel ?? "—")
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Label("日照", systemImage: "sun.max")
                Spacer()
                Text(viewModel.sunshineLabel ?? "—")
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Label("降水", systemImage: "cloud.rain")
                Spacer()
                Text(viewModel.rainLabel ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var varietiesSection: some View {
        Section(header: Text("品種・ステージ")) {
            ForEach(viewModel.varieties.indices, id: \.self) { index in
                VarietyStageRow(
                    variety: $viewModel.varieties[index],
                    settings: store.settings,
                    onDelete: {
                        viewModel.removeVariety(at: index)
                    }
                )
            }
            
            Button {
                viewModel.addVariety()
            } label: {
                Label("品種を追加", systemImage: "plus.circle")
            }
        }
    }
    
    private var sprayingSection: some View {
        Section(header: Text("防除")) {
            Toggle("防除実施", isOn: $viewModel.isSpraying)
            
            if viewModel.isSpraying {
                TextField("総使用量（L）", text: $viewModel.sprayTotalLiters)
                    .keyboardType(.decimalPad)
                
                ForEach(viewModel.sprays.indices, id: \.self) { index in
                    SprayItemRow(
                        spray: $viewModel.sprays[index],
                        onDelete: {
                            viewModel.removeSpray(at: index)
                        }
                    )
                }
                
                Button {
                    viewModel.addSpray()
                } label: {
                    Label("薬剤を追加", systemImage: "plus.circle")
                }
            }
        }
    }
    
    private var workNotesSection: some View {
        Section(header: Text("作業メモ")) {
            TextField("作業内容", text: $viewModel.workNotes, axis: .vertical)
                .lineLimit(3...6)
            TextField("備考", text: $viewModel.memo, axis: .vertical)
                .lineLimit(2...4)
        }
    }
    
    private var workTimesSection: some View {
        Section(header: Text("作業時間")) {
            ForEach(viewModel.workTimes.indices, id: \.self) { index in
                WorkTimeRow(
                    workTime: $viewModel.workTimes[index],
                    onDelete: {
                        viewModel.removeWorkTime(at: index)
                    }
                )
            }
            
            Button {
                viewModel.addWorkTime()
            } label: {
                Label("時間帯を追加", systemImage: "plus.circle")
            }
        }
    }
    
    private var volunteersSection: some View {
        Section(header: Text("ボランティア")) {
            TextField("氏名（カンマ区切り）", text: $viewModel.volunteersText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
    
    private var photosSection: some View {
        Section(header: Text("写真")) {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 12,
                matching: .images
            ) {
                Label("写真を追加（アプリ内にコピー）", systemImage: "photo.on.rectangle.angled")
            }
            .onChange(of: selectedPhotos) { _, items in
                Task {
                    await viewModel.importPhotos(items)
                    selectedPhotos.removeAll()
                }
            }
            
            if viewModel.photos.isEmpty {
                Text("写真はまだありません")
                    .foregroundStyle(.secondary)
            } else {
                PhotosGrid(
                    photos: $viewModel.photos,
                    captions: $viewModel.photoCaptions,
                    onDelete: { name in
                        photoToDelete = name
                        showDeletePhotoAlert = true
                    }
                )
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("キャンセル") {
                dismiss()
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task { await saveEntry() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("保存")
                }
            }
            .disabled(isSaving)
        }
    }
    
    // MARK: - Delete Photo Alert
    
    @ViewBuilder
    private var deletePhotoAlertActions: some View {
        Button("削除", role: .destructive) {
            if let name = photoToDelete {
                viewModel.deletePhoto(name)
            }
        }
        Button("キャンセル", role: .cancel) {}
    }
    
    // MARK: - Save
    
    private func saveEntry() async {
        isSaving = true
        defer { isSaving = false }
        
        await viewModel.save(
            to: store,
            weather: weather,
            settings: store.settings
        )
        
        dismiss()
    }
}

// MARK: - Supporting Views

private struct VarietyStageRow: View {
    @Binding var variety: VarietyStageItem
    let settings: AppSettings
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("品種", selection: $variety.varietyName) {
                Text("未選択").tag("")
                ForEach(settings.varieties) { v in
                    Text(v.name).tag(v.name)
                }
            }
            
            Picker("成長ステージ", selection: $variety.stage) {
                Text("未選択").tag("")
                ForEach(settings.stages) { s in
                    Text("\(s.code): \(s.label)").tag("\(s.code): \(s.label)")
                }
            }
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

private struct SprayItemRow: View {
    @Binding var spray: SprayItem
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            TextField("薬剤名", text: $spray.chemicalName)
            HStack {
                Text("希釈倍率")
                TextField("例) 1000倍", text: $spray.dilution)
                    .keyboardType(.numbersAndPunctuation)
            }
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

private struct WorkTimeRow: View {
    @Binding var workTime: WorkTime
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            DatePicker("開始", selection: $workTime.start, displayedComponents: .hourAndMinute)
            DatePicker("終了", selection: $workTime.end, displayedComponents: .hourAndMinute)
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

private struct PhotosGrid: View {
    @Binding var photos: [String]
    @Binding var captions: [String: String]
    let onDelete: (String) -> Void
    
    private let thumbSize = CGSize(width: 84, height: 63)
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(photos, id: \.self) { name in
                PhotoThumbnailView(
                    name: name,
                    caption: Binding(
                        get: { captions[name] ?? "" },
                        set: { captions[name] = $0 }
                    ),
                    size: thumbSize,
                    onDelete: { onDelete(name) }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PhotoThumbnailView: View {
    let name: String
    @Binding var caption: String
    let size: CGSize
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            thumbnailImage
            
            TextField("キャプション", text: $caption)
                .textFieldStyle(.roundedBorder)
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
    
    private var thumbnailImage: some View {
        Group {
            if let ui = localUIImage() {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                PlaceholderCloudThumb(size: size)
            }
        }
    }
    
    private func localUIImage() -> UIImage? {
        let url = URL.documentsDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct PlaceholderCloudThumb: View {
    let size: CGSize
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
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
    }
}

#endif
