import Foundation
import AppKit
import UniformTypeIdentifiers

/// CSV エクスポート（改行は「 / 」へ置換して 1 セルに収め、BOM 付きで保存）
enum CSVExporter {
    // 以前の exportWithPanel(entries:) と被るのを避けるため命名変更
    @discardableResult
    static func saveWithPanelFlatteningNewlines(entries: [DiaryEntry]) throws -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyyMMdd_HHmm"

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "VineyardDiary_\(df.string(from: Date())).csv"
        if let csvUTType = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csvUTType]
        } else {
            panel.allowedContentTypes = [.commaSeparatedText]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            struct UserCancelled: Error {}
            throw UserCancelled()
        }

        try export(entries: entries, to: url, flattenNewlines: true)
        return url
    }

    static func export(entries: [DiaryEntry], to url: URL, flattenNewlines: Bool = true) throws {
        let headers: [String] = [
            "日付","区画","品種/ステージ","防除実施","液量(L)","薬剤(倍率)",
            "作業時間","作業内容","備考","ボランティア","写真枚数",
            "最低気温(℃)","最高気温(℃)","日照時間(h)","降水量(mm)"
        ]

        var rows: [String] = []
        rows.append(headers.map { csvCell($0, flattenNewlines: flattenNewlines) }.joined(separator: ","))

        let dfmt = DateFormatter()
        dfmt.locale = Locale(identifier: "ja_JP")
        dfmt.calendar = Calendar(identifier: .gregorian)
        dfmt.dateFormat = "yyyy/MM/dd"

        let hm = DateFormatter()
        hm.locale = Locale(identifier: "ja_JP")
        hm.calendar = Calendar(identifier: .gregorian)
        hm.dateFormat = "HH:mm"

        for e in entries {
            let varietalStage = e.varieties.map { vs in
                let name = vs.varietyName
                let stage = vs.stage
                if name.isEmpty && stage.isEmpty { return "" }
                if stage.isEmpty { return "\(name)" }
                if name.isEmpty { return "\(stage)" }
                return "\(name): \(stage)"
            }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

            let sprayApplied = e.isSpraying ? "はい" : "いいえ"
            let liters = e.sprayTotalLiters.trimmingCharacters(in: .whitespacesAndNewlines)

            let chemicals = e.sprays.map { s -> String in
                let name = s.chemicalName.trimmingCharacters(in: .whitespacesAndNewlines)
                let d    = s.dilution.trimmingCharacters(in: .whitespacesAndNewlines)
                switch (name.isEmpty, d.isEmpty) {
                case (false, false): return "\(name)(\(d)倍)"
                case (false, true):  return "\(name)"
                case (true,  false): return "\(d)倍"
                default:             return ""
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "・")

            let workTimes = e.workTimes.map {
                "\(hm.string(from: $0.start))〜\(hm.string(from: $0.end))"
            }
            .joined(separator: ", ")

            let volunteers = e.volunteers.joined(separator: ", ")
            let photoCount = e.photos.count

            let tMin = e.weatherMin.map { String(format: "%.1f", $0) } ?? ""
            let tMax = e.weatherMax.map { String(format: "%.1f", $0) } ?? ""
            let sun  = e.sunshineHours.map { String(format: "%.1f", $0) } ?? ""
            let rain = e.precipitationMm.map { String(format: "%.1f", $0) } ?? ""

            let record: [String] = [
                dfmt.string(from: e.date),
                e.block,
                varietalStage,
                sprayApplied,
                liters,
                chemicals,
                workTimes,
                e.workNotes,
                e.memo,
                volunteers,
                String(photoCount),
                tMin,
                tMax,
                sun,
                rain
            ]

            rows.append(record.map { csvCell($0, flattenNewlines: flattenNewlines) }.joined(separator: ","))
        }

        let csv = rows.joined(separator: "\r\n") + "\r\n"

        // UTF-8 BOM を付与して Excel 文字化け防止
        var data = Data()
        if let bom = "\u{FEFF}".data(using: .utf8) { data.append(bom) }
        data.append(csv.data(using: .utf8)!)

        try data.write(to: url, options: .atomic)
    }

    private static func csvCell(_ raw: String, flattenNewlines: Bool) -> String {
        var s = raw
        if flattenNewlines {
            s = s.replacingOccurrences(of: "\r\n", with: " / ")
                 .replacingOccurrences(of: "\r", with: " / ")
                 .replacingOccurrences(of: "\n", with: " / ")
            while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        }
        s = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(s)\""
    }
}
