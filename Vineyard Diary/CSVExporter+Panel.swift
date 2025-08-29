import Foundation
import AppKit
import UniformTypeIdentifiers

// 既存の CSVExporter を拡張。
// 「保存先を選んでCSVを出力」するメソッドを追加します。
// 本体の行生成は既存の BackupManager.lineForCSV(entry:) を再利用します。
extension CSVExporter {

    /// 保存先を選んでCSVを書き出します（UTF-8 BOM付き、Excelでの日本語化け対策）
    @MainActor
    static func exportWithPanel(entries: [DiaryEntry]) throws -> URL {
        let panel = NSSavePanel()
        panel.title = "CSV エクスポート"
        panel.nameFieldStringValue = "VineyardDiary_Export.csv"
        panel.allowedContentTypes = [.commaSeparatedText] // macOSのCSVタイプ

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }

        // 既存のCSVフォーマットに合わせる（ヘッダは CSVExporter.export と同一）
        let headers = [
            "日付","区画","品種(ステージ)","防除(1/0)","使用L","薬剤(倍率)",
            "作業内容","備考","最低気温(℃)","最高気温(℃)","日照(h)","ボランティア","写真ファイル"
        ]

        var rows: [[String]] = [headers]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            rows.append(BackupManager.lineForCSV(entry: e))
        }

        let csvBody = rows
            .map { row in row.map { escapeCSVForPanel($0) }.joined(separator: ",") }
            .joined(separator: "\n")

        // Excel向け：UTF-8 BOM 付与
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(csvBody.data(using: .utf8)!)

        try data.write(to: url, options: .atomic)
        return url
    }

    // CSVのセルを安全にクォート
    private static func escapeCSVForPanel(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
