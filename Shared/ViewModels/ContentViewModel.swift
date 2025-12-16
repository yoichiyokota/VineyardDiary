//
//  Created by yoichi_yokota on 2025/12/16.
//


// Shared/ViewModels/ContentViewModel.swift
// ContentView用のビジネスロジック（iOS/macOS共通）

import Foundation
import Combine

/// ContentViewのビジネスロジックを管理するViewModel
/// - iOS/macOS両方で使用可能
/// - フィルタリング、ソート、選択肢生成などのロジックを集約
@MainActor
final class ContentViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 選択中の年（0 = すべて）
    @Published var selectedYear: Int = 0
    
    /// 選択中の区画（"" = すべて）
    @Published var selectedBlock: String = ""
    
    /// ソート順（true = 昇順、false = 降順）
    @Published var sortAscending: Bool = false
    
    /// 利用可能な年の選択肢（降順）
    @Published private(set) var availableYears: [Int] = []
    
    /// 区画の選択肢（先頭 "" = すべて + 設定順）
    @Published private(set) var blockOptions: [String] = []
    
    // MARK: - Initialization
    
    init() {
        // 必要に応じて初期値を設定
    }
    
    // MARK: - Public Methods
    
    /// エントリリストから年と区画の選択肢を再構築
    /// - Parameter store: DiaryStore
    func rebuildOptions(from store: DiaryStore) {
        rebuildYearOptions(from: store.entries)
        rebuildBlockOptions(from: store.settings)
        validateSelections()
    }
    
    /// エントリをフィルタ＆ソートして返す
    /// - Parameters:
    ///   - entries: 全エントリ
    ///   - searchText: 検索テキスト
    /// - Returns: フィルタ・ソート済みのエントリ配列
    func filteredAndSorted(
        from entries: [DiaryEntry],
        searchText: String
    ) -> [DiaryEntry] {
        let filtered = filterEntries(entries, searchText: searchText)
        return sortEntries(filtered)
    }
    
    // MARK: - Private Methods - Options Building
    
    /// 年の選択肢を構築（降順）
    private func rebuildYearOptions(from entries: [DiaryEntry]) {
        let years = Set(
            entries.map { entry in
                Calendar.current.component(.year, from: entry.date)
            }
        )
        availableYears = Array(years).sorted(by: >)
    }
    
    /// 区画の選択肢を構築（設定順を維持）
    private func rebuildBlockOptions(from settings: AppSettings) {
        let fixedBlocks = settings.blocks
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // 先頭に空文字（すべて）を追加
        blockOptions = [""] + fixedBlocks
    }
    
    /// 選択値が有効か検証し、必要なら修正
    private func validateSelections() {
        // 年の検証
        if !availableYears.contains(selectedYear) {
            selectedYear = availableYears.first ?? 0
        }
        
        // 区画の検証
        if !blockOptions.contains(selectedBlock) {
            selectedBlock = ""
        }
    }
    
    // MARK: - Private Methods - Filtering
    
    /// エントリをフィルタリング
    private func filterEntries(
        _ entries: [DiaryEntry],
        searchText: String
    ) -> [DiaryEntry] {
        // 1. 年・区画でフィルタ
        let yearBlockFiltered = entries.filter { entry in
            yearMatches(entry) && blockMatches(entry)
        }
        
        // 2. 検索テキストでフィルタ
        return applySearchFilter(to: yearBlockFiltered, query: searchText)
    }
    
    /// 年のマッチング
    private func yearMatches(_ entry: DiaryEntry) -> Bool {
        guard selectedYear != 0 else { return true }
        
        let entryYear = Calendar.current.component(.year, from: entry.date)
        return entryYear == selectedYear
    }
    
    /// 区画のマッチング（大文字小文字・発音記号を無視）
    private func blockMatches(_ entry: DiaryEntry) -> Bool {
        guard !selectedBlock.isEmpty else { return true }
        
        return entry.block.compare(
            selectedBlock,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
    
    /// 検索テキストでフィルタリング
    private func applySearchFilter(
        to entries: [DiaryEntry],
        query: String
    ) -> [DiaryEntry] {
        let trimmedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        guard !trimmedQuery.isEmpty else {
            return entries
        }
        
        return entries.filter { entry in
            searchMatches(entry, query: trimmedQuery)
        }
    }
    
    /// エントリが検索クエリにマッチするか
    private func searchMatches(_ entry: DiaryEntry, query: String) -> Bool {
        entry.block.lowercased().contains(query) ||
        entry.workNotes.lowercased().contains(query) ||
        entry.memo.lowercased().contains(query)
    }
    
    // MARK: - Private Methods - Sorting
    
    /// エントリをソート
    private func sortEntries(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        let sorted = entries.sorted { $0.date < $1.date }
        return sortAscending ? sorted : sorted.reversed()
    }
}

// MARK: - Convenience Extensions

extension ContentViewModel {
    
    /// 現在選択中の年が有効か
    var hasValidYearSelection: Bool {
        selectedYear != 0 && availableYears.contains(selectedYear)
    }
    
    /// 現在選択中の区画が有効か（空 = すべては有効とみなす）
    var hasValidBlockSelection: Bool {
        selectedBlock.isEmpty || blockOptions.contains(selectedBlock)
    }
    
    /// フィルタが適用されているか
    var isFiltering: Bool {
        selectedYear != 0 || !selectedBlock.isEmpty
    }
    
    /// すべてのフィルタをクリア
    func clearFilters() {
        selectedYear = availableYears.first ?? 0
        selectedBlock = ""
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension ContentViewModel {
    
    /// デバッグ用：現在の状態を文字列で返す
    var debugDescription: String {
        """
        ContentViewModel:
        - selectedYear: \(selectedYear)
        - selectedBlock: "\(selectedBlock)"
        - sortAscending: \(sortAscending)
        - availableYears: \(availableYears)
        - blockOptions: \(blockOptions)
        """
    }
    
    /// テスト用：状態をリセット
    func resetForTesting() {
        selectedYear = 0
        selectedBlock = ""
        sortAscending = false
        availableYears = []
        blockOptions = []
    }
}
#endif
