import Foundation

struct BackupPayload: Codable {
    var settings: AppSettings
    var entries: [DiaryEntry]
    var dailyWeather: [String: [String: DailyWeather]] // blockName -> dateISO -> DailyWeather
}

enum BackupManager {
    static let backupFileName = "VineyardDiary_Backup.vydbackup"

    // 書き出し（Documents直下に保存）
    static func exportBackup(settings: AppSettings,
                             entries: [DiaryEntry],
                             dailyWeather: [String:[String:DailyWeather]]) throws -> URL {
        let payload = BackupPayload(settings: settings, entries: entries, dailyWeather: dailyWeather)
        let url = URL.documentsDirectory.appendingPathComponent(backupFileName)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    // 読み込み
    static func importBackup() throws -> BackupPayload {
        let url = URL.documentsDirectory.appendingPathComponent(backupFileName)
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        return try dec.decode(BackupPayload.self, from: data)
    }

    // 参考：CSV用に行へ展開（Optionalは安全に文字列へ）
    static func lineForCSV(entry: DiaryEntry) -> [String] {
        func s(_ d: Double?) -> String { d.map { String(format: "%.1f", $0) } ?? "" }
        let dateStr = ISO8601DateFormatter.yyyyMMdd.string(from: entry.date)
        let varietiesStr = entry.varieties.map { "\($0.varietyName) [\($0.stage)]" }.joined(separator: "; ")
        let spraysStr = entry.sprays.map { "\($0.chemicalName) x\($0.dilution)" }.joined(separator: "; ")
        let volunteersStr = entry.volunteers.joined(separator: ", ")
        let photosStr = entry.photos.joined(separator: "; ")

        // Optional Double を無理にアンラップしない
        return [
            dateStr,
            entry.block,
            varietiesStr,
            entry.isSpraying ? "1" : "0",
            entry.sprayTotalLiters,
            spraysStr,
            entry.workNotes.replacingOccurrences(of: "\n", with: " "),
            entry.memo.replacingOccurrences(of: "\n", with: " "),
            s(entry.weatherMin),
            s(entry.weatherMax),
            s(entry.sunshineHours),
            volunteersStr,
            photosStr
        ]
    }
}
