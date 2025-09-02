import Foundation
import AppKit
import UniformTypeIdentifiers

// CSVExporter のパネル付き保存を本体の export(entries:to:) に委譲して一元化。
// ・nameFieldStringValue に拡張子は付けない（OS が自動付与）
// ・中身は CSVExporter.export(entries:to:flattenNewlines: true) を利用（改行つぶし+BOM）
extension CSVExporter {

    /// 保存先を選んでCSVを書き出します（UTF-8 BOM付き、Excelの日本語化け回避、改行は「 / 」に統一）
    @MainActor
    static func exportWithPanel(entries: [DiaryEntry]) throws -> URL {
        let panel = NSSavePanel()
        panel.title = "CSV エクスポート"
        // ← 拡張子を書かない。macOS が allowedContentTypes に従って .csv を付与する
        panel.nameFieldStringValue = "VineyardDiary_Export"

        // CSV の UTType を指定（.commaSeparatedText は macOS 標準）
        panel.allowedContentTypes = [.commaSeparatedText]

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CocoaError(.userCancelled)
        }

        // 生成は本体の共通関数へ委譲（改行は1セル内で「 / 」にフラット化、BOM付与あり）
        try CSVExporter.export(entries: entries, to: url, flattenNewlines: true)
        return url
    }
}
