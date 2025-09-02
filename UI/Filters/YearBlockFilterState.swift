import Foundation
import Combine

/// 年（0=すべてではなく「当年」を既定にする方針）と区画の UI 状態を保持。
final class YearBlockFilterState: ObservableObject {
    /// 0 を保存していた場合は次回起動時に当年へフォールバック（=常に4桁西暦を保持）
    @Published var selectedYear: Int {
        didSet { UserDefaults.standard.set(selectedYear, forKey: "selectedYear") }
    }

    /// "" は「すべて」を表す
    @Published var selectedBlock: String {
        didSet { UserDefaults.standard.set(selectedBlock, forKey: "selectedBlock") }
    }

    /// UI表示用の区画候補（先頭に ""=すべて を含める）
    @Published var blocks: [String] = []

    init() {
        let savedYear = UserDefaults.standard.integer(forKey: "selectedYear")
        if savedYear == 0 {
            self.selectedYear = Calendar.current.component(.year, from: Date())
        } else {
            self.selectedYear = savedYear
        }
        self.selectedBlock = UserDefaults.standard.string(forKey: "selectedBlock") ?? ""
    }

    /// nil なら「すべて」（＝絞り込まない）
    var effectiveYear: Int? { selectedYear <= 0 ? nil : selectedYear }
    /// nil なら「すべて」
    var effectiveBlock: String? { selectedBlock.isEmpty ? nil : selectedBlock }
}