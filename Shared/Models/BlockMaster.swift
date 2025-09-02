import Foundation
import CoreData

/// 区画候補を taskNote（作業メモ）から推定して作る簡易ヘルパ。
/// 先頭に ""（=すべて）を付与して UI で「すべて」を表す。
func buildBlocks(context: NSManagedObjectContext) -> [String] {
    var set = Set<String>()

    // 1) ユーザー固定リストを優先的に追加（任意）
    if let fixed = UserDefaults.standard.array(forKey: "block.fixed.list") as? [String] {
        fixed.forEach {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
    }

    // 2) 既存の taskNote から推定
    let fetch = NSFetchRequest<NSDictionary>(entityName: "DiaryEntry")
    fetch.propertiesToFetch = ["taskNote"]
    fetch.resultType = .dictionaryResultType
    fetch.fetchBatchSize = 300

    if let rows = try? context.fetch(fetch) {
        for row in rows {
            guard let note = row["taskNote"] as? String else { continue }
            for name in extractBlockHints(from: note) where !name.isEmpty {
                set.insert(name)
            }
        }
    }

    let names = Array(set).sorted()
    return [""] + names
}

/// taskNote から「区画名らしき文字列」を抽出する簡易ロジック。
/// 例: "区画: 深沢A" / "Block: Fukasawa-630" / "[深沢A]"
private func extractBlockHints(from text: String) -> [String] {
    var results: [String] = []
    let s = text as NSString
    let patterns = [
        #"区画[:：]\s*([^\s,、\[\]]+)"#,
        #"Block[:：]\s*([^\s,、\[\]]+)"#,
        #"\[([^\[\]]+)\]"#
    ]
    for p in patterns {
        if let regex = try? NSRegularExpression(pattern: p, options: []) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: s.length))
            for m in matches where m.numberOfRanges >= 2 {
                let name = s.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { results.append(name) }
            }
        }
    }
    return results
}
