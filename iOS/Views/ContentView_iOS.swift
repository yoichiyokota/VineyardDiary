//  Created by yoichi_yokota on 2025/12/16.
//


#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

// MARK: - iOS専用メインビュー
@MainActor
struct ContentView_iOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var thumbs = ThumbnailStore()
    
    // UI状態
    @State private var showEditorSheet = false
    @State private var showFolderPicker = false
    @State private var confirmDelete: DiaryEntry?
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                filtersSection
                entriesSection
            }
            .listStyle(.plain)
            .navigationTitle("Vineyard Diary")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showEditorSheet) { editorSheet }
            .fileImporter(isPresented: $showFolderPicker,
                         allowedContentTypes: [UTType.folder],
                         allowsMultipleSelection: false,
                         onCompletion: handleFolderSelection)
            .confirmationDialog("この日記を削除しますか?",
                              isPresented: confirmDeleteBinding,
                              actions: deleteDialogActions)
            .onAppear(perform: setupInitialState)
            .onChange(of: store.settings.blocks.map { $0.name }, perform: handleBlocksChange)
        }
    }
    
    // MARK: - Sections
    
    private var filtersSection: some View {
        Section {
            FiltersRow(
                availableYears: viewModel.availableYears,
                blockOptions: viewModel.blockOptions,
                selectedYear: $viewModel.selectedYear,
                selectedBlock: $viewModel.selectedBlock,
                sortAscending: $viewModel.sortAscending
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
    }
    
    private var entriesSection: some View {
        Section {
            let entries = viewModel.filteredAndSorted(
                from: store.entries,
                searchText: searchText
            )
            
            ForEach(entries) { entry in
                Button(action: { openEditor(entry) }) {
                    CompactEntryRow(entry: entry, weather: weather)
                        .environmentObject(thumbs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    deleteButton(for: entry)
                    editButton(for: entry)
                }
            }
            .onDelete(perform: handleSwipeDelete)
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            statisticsButton
            folderButton
            reimportButton
        }
    }
    
    private var statisticsButton: some View {
        NavigationLink {
            StatisticsView()
                .environmentObject(store)
                .environmentObject(weather)
        } label: {
            Label("統計", systemImage: "chart.xyaxis.line")
        }
    }
    
    private var folderButton: some View {
        Button {
            showFolderPicker = true
        } label: {
            Label("フォルダ", systemImage: "folder")
        }
    }
    
    private var reimportButton: some View {
        Button {
            Task { await performReimport() }
        } label: {
            Label("再取り込み", systemImage: "arrow.triangle.2.circlepath")
        }
    }
    
    // MARK: - Actions
    
    private func deleteButton(for entry: DiaryEntry) -> some View {
        Button(role: .destructive) {
            confirmDelete = entry
        } label: {
            Label("削除", systemImage: "trash")
        }
    }
    
    private func editButton(for entry: DiaryEntry) -> some View {
        Button {
            openEditor(entry)
        } label: {
            Label("編集", systemImage: "pencil")
        }
    }
    
    private func openEditor(_ entry: DiaryEntry?) {
        store.editingEntry = entry
        showEditorSheet = true
    }
    
    private var editorSheet: some View {
        EntryEditorView()
            .environmentObject(store)
            .environmentObject(weather)
    }
    
    // MARK: - Delete Handling
    
    private var confirmDeleteBinding: Binding<Bool> {
        Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )
    }
    
    @ViewBuilder
    private func deleteDialogActions() -> some View {
        Button("削除", role: .destructive) {
            if let entry = confirmDelete {
                store.removeEntry(entry)
                confirmDelete = nil
            }
        }
        Button("キャンセル", role: .cancel) {
            confirmDelete = nil
        }
    }
    
    private func handleSwipeDelete(_ offsets: IndexSet) {
        let entries = viewModel.filteredAndSorted(
            from: store.entries,
            searchText: searchText
        )
        for index in offsets {
            store.removeEntry(entries[index])
        }
    }
    
    // MARK: - Folder Handling
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            
            do {
                try SharedFolderBookmark.saveFolderURL(url)
                Task {
                    try? await SharedImporter.importAllIfConfigured(
                        into: store,
                        weather: weather
                    )
                }
            } catch {
                print("❌ saveFolderURL failed:", error)
            }
            
        case .failure(let error):
            print("❌ folder picker error:", error)
        }
    }
    
    private func performReimport() async {
        do {
            _ = try await SharedImporter.importAllIfConfigured(
                into: store,
                weather: weather
            )
            weather.load()
            await backfillDailyWeatherAndRefreshEntries(
                store: store,
                weather: weather
            )
        } catch {
            print("❌ Shared manual re-import failed:", error)
        }
    }
    
    // MARK: - Lifecycle
    
    private func setupInitialState() {
        viewModel.rebuildOptions(from: store)
        
        if viewModel.selectedYear == 0,
           let first = viewModel.availableYears.first {
            viewModel.selectedYear = first
        }
    }
    
    private func handleBlocksChange(_: Any) {
        viewModel.rebuildOptions(from: store)
        
        if !viewModel.blockOptions.contains(viewModel.selectedBlock) {
            viewModel.selectedBlock = ""
        }
    }
}


// MARK: - Supporting Views

private struct FiltersRow: View {
    let availableYears: [Int]
    let blockOptions: [String]
    @Binding var selectedYear: Int
    @Binding var selectedBlock: String
    @Binding var sortAscending: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            yearPicker
            blockPicker
            Spacer()
            sortPicker
        }
    }
    
    private var yearPicker: some View {
        HStack(spacing: 6) {
            Text("年").font(.subheadline)
            Picker("", selection: $selectedYear) {
                if availableYears.isEmpty {
                    Text("—").tag(0)
                } else {
                    ForEach(availableYears, id: \.self) { year in
                        Text(verbatim: "\(year)年").tag(year)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
    
    private var blockPicker: some View {
        HStack(spacing: 6) {
            Text("区画").font(.subheadline)
            Picker("", selection: $selectedBlock) {
                ForEach(blockOptions, id: \.self) { block in
                    Text(block.isEmpty ? "すべて" : block).tag(block)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
    
    private var sortPicker: some View {
        Picker("", selection: $sortAscending) {
            Text("新→旧").tag(false)
            Text("旧→新").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
    }
}

// MARK: - Supporting Types

private struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.vineyardDiary, .json] }
    static var writableContentTypes: [UTType] { [.vineyardDiary, .json] }
    
    var file: VineyardDiaryFile
    
    init(file: VineyardDiaryFile) {
        self.file = file
    }
    
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
