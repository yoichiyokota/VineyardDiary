import Foundation

enum CSVExporter {
    static func export(entries: [DiaryEntry]) throws -> URL {
        let headers = [
            "日付","区画","品種(ステージ)","防除(1/0)","使用L","薬剤(倍率)",
            "作業内容","備考","最低気温(℃)","最高気温(℃)","日照(h)","ボランティア","写真ファイル"
        ]

        var rows: [[String]] = [headers]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            rows.append(BackupManager.lineForCSV(entry: e))
        }

        let csv = rows.map { row in
            row.map { escapeCSV($0) }.joined(separator: ",")
        }.joined(separator: "\n")

        let url = URL.documentsDirectory.appendingPathComponent("VineyardDiary_Export.csv")
        // Excel向け：UTF-8 BOM付与
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(csv.data(using: .utf8)!)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
