import Foundation

extension DateFormatter {
    /// 共通：yyyy-MM-dd（UTC, POSIX）— どのファイルからでも使えるよう internal
    static let yyyyMMdd: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

extension URL {
    /// ドキュメントディレクトリ（共通ヘルパー）
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

// "2025-08-29" のような ISO 8601 形式 (日付のみ) を扱うための共通フォーマッタ
extension ISO8601DateFormatter {
    /// "yyyy-MM-dd" を返す DateFormatter（互換目的で型は DateFormatter）
    static let yyyyMMdd: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale   = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)   // 日付キーのズレ防止
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}
