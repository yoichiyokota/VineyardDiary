//  Created by yoichi_yokota on 2025/12/16.
//


#if os(macOS)
import SwiftUI
import AppKit

// MARK: - macOS専用メインビュー
@MainActor
struct ContentView_macOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var thumbs = ThumbnailStore()
    
    // UI状態
    @State private var searchText = ""
    @State private var confirmDelete: DiaryEntry?
    @State private var editorWindows: [NSWindow] = []
    @State private var statsWindows: [NSWindow] = []
    
    var body: some View {
        VStack(spacing: 8) {
            headerBar
            
            if store.entries.isEmpty {
                emptyStateView
            } else {
                entryList
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .searchable(text: $searchText, placement: .automatic)
        .confirmationDialog("この日記を削除しますか?",
                          isPresented: confirmDeleteBinding,
                          actions: deleteDialogActions)
        .onAppear(perform: setupInitialState)
        .onChange(of: store.settings.blocks.map { $0.name }, perform: handleBlocksChange)
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            addButton
            yearPicker
            blockPicker
            sortPicker
            Spacer()
            statisticsButton
        }
    }
    
    private var addButton: some View {
        Button {
            openEditor(nil)
        } label: {
            Label("日記を追加", systemImage: "plus.circle.fill")
        }
    }
    
    private var yearPicker: some View {
        HStack(spacing: 6) {
            Text("年")
            Picker("", selection: $viewModel.selectedYear) {
                if viewModel.availableYears.isEmpty {
                    Text("—").tag(0)
                } else {
                    ForEach(viewModel.availableYears, id: \.self) { year in
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
            Text("区画")
            Picker("", selection: $viewModel.selectedBlock) {
                ForEach(viewModel.blockOptions, id: \.self) { block in
                    Text(block.isEmpty ? "すべて" : block).tag(block)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
    
    private var sortPicker: some View {
        Picker("並び", selection: $viewModel.sortAscending) {
            Text("日付 降順（新しい順）").tag(false)
            Text("日付 昇順（古い順）").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }
    
    private var statisticsButton: some View {
        Button {
            openStatistics()
        } label: {
            Label("統計", systemImage: "chart.xyaxis.line")
        }
    }
    
    // MARK: - Content
    
    private var emptyStateView: some View {
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
    
    private var entryList: some View {
        List {
            let entries = viewModel.filteredAndSorted(
                from: store.entries,
                searchText: searchText
            )
            
            ForEach(entries) { entry in
                Button {
                    openEditor(entry)
                } label: {
                    EntryListRow(
                        entry: entry,
                        weather: weather,
                        thumbs: thumbs,
                        onDelete: { confirmDelete = entry }
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    deleteMenuItem(for: entry)
                    editMenuItem(for: entry)
                }
            }
            .onDelete(perform: handleSwipeDelete)
        }
        .listStyle(.plain)
    }
    
    // MARK: - Context Menu
    
    private func deleteMenuItem(for entry: DiaryEntry) -> some View {
        Button(role: .destructive) {
            confirmDelete = entry
        } label: {
            Label("削除", systemImage: "trash")
        }
    }
    
    private func editMenuItem(for entry: DiaryEntry) -> some View {
        Button {
            openEditor(entry)
        } label: {
            Label("編集", systemImage: "pencil")
        }
    }
    
    // MARK: - Window Management
    
    private func openEditor(_ entry: DiaryEntry?) {
        store.editingEntry = entry
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = entry == nil ? "日記を追加" : "日記を編集"
        window.isReleasedWhenClosed = false
        window.center()
        
        let rootView = EntryEditorView()
            .environmentObject(store)
            .environmentObject(weather)
        
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        editorWindows.append(window)
    }
    
    private func openStatistics() {
        // 統計を開く直前に最新化
        Task { @MainActor in
            weather.load()
            await backfillDailyWeatherAndRefreshEntries(
                store: store,
                weather: weather
            )
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "気象グラフ"
        window.isReleasedWhenClosed = false
        window.center()
        
        let rootView = StatisticsView()
            .environmentObject(store)
            .environmentObject(weather)
        
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        statsWindows.append(window)
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

// MARK: - Entry List Row

private struct EntryListRow: View {
    let entry: DiaryEntry
    @ObservedObject var weather: DailyWeatherStore
    @ObservedObject var thumbs: ThumbnailStore
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            entryDetails
            weatherInfo
            deleteButton
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    private var thumbnail: some View {
        Group {
            if let first = entry.photos.first,
               let img = thumbs.thumbnail(for: first) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 54)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.15))
                    )
            } else {
                placeholder
            }
        }
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
        .frame(width: 72, height: 54)
    }
    
    private var entryDetails: some View {
        EntryRow(entry: entry, showLeadingThumbnail: false)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var weatherInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let tempText = temperatureLabel {
                Text(tempText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sunText = sunshineLabel {
                Text(sunText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let rainText = rainLabel {
                Text(rainText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 160, alignment: .trailing)
    }
    
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help("この日記を削除")
    }
    
    // MARK: - Weather Labels
    
    private var temperatureLabel: String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let w = weather.get(block: entry.block, date: day),
              let tmax = w.tMax,
              let tmin = w.tMin else {
            return nil
        }
        return String(format: "最高 %.1f℃ / 最低 %.1f℃", tmax, tmin)
    }
    
    private var sunshineLabel: String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let w = weather.get(block: entry.block, date: day),
              let sun = w.sunshineHours else {
            return nil
        }
        return String(format: "日照 %.1fh", sun)
    }
    
    private var rainLabel: String? {
        let day = Calendar.current.startOfDay(for: entry.date)
        guard let w = weather.get(block: entry.block, date: day),
              let r = w.precipitationMm else {
            return nil
        }
        return String(format: "降水 %.1fmm", r)
    }
}

#endif
