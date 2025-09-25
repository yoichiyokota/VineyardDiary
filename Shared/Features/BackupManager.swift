import Foundation

// 既存フォーマットはそのまま
//struct BackupPayload: Codable {
//    var settings: AppSettings
//    var entries: [DiaryEntry]
//    /// blockName -> dateISO(yyyy-MM-dd) -> DailyWeather
//    var dailyWeather: [String: [String: DailyWeather]]
//}

enum BackupManager {
    // ベース名（拡張子はここでは付けない）
    static let fileBaseName = "VineyardDiary_Backup"
    static let fileExtension = "vydbackup"

    /// 既定の保存先（Documents 直下 / 拡張子は一元管理）
    static var defaultURL: URL {
        URL.documentsDirectory
            .appendingPathComponent(fileBaseName)
            .appendingPathExtension(fileExtension)
    }

    // MARK: - 書き出し（固定名；互換用）
    /// 既存互換：Documents 直下の固定ファイル名へ保存
    @discardableResult
    static func exportBackup(
        settings: AppSettings,
        entries: [DiaryEntry],
        dailyWeather: [String:[String:DailyWeather]]
    ) throws -> URL {
        let payload = BackupPayload(settings: settings, entries: entries, dailyWeather: dailyWeather)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(payload)

        try data.write(to: defaultURL, options: .atomic)
        return defaultURL
    }

    // MARK: - 書き出し（タイムスタンプ版；運用に便利）
    /// 日付入りファイル名で保存（例: VineyardDiary_Backup_2025-09-01_2215.vydbackup）
    @discardableResult
    static func exportBackupWithTimestamp(
        settings: AppSettings,
        entries: [DiaryEntry],
        dailyWeather: [String:[String:DailyWeather]]
    ) throws -> URL {
        let payload = BackupPayload(settings: settings, entries: entries, dailyWeather: dailyWeather)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(payload)

        let ts = Self.timestampString() // yyyy-MM-dd_HHmm
        let url = URL.documentsDirectory
            .appendingPathComponent("\(fileBaseName)_\(ts)")
            .appendingPathExtension(fileExtension)

        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 読み込み（固定名；互換用）
    static func importBackup() throws -> BackupPayload {
        let data = try Data(contentsOf: defaultURL)
        let dec = JSONDecoder()
        return try dec.decode(BackupPayload.self, from: data)
    }

    // MARK: - 任意パスから読み込み（必要に応じて利用）
    static func importBackup(from url: URL) throws -> BackupPayload {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        return try dec.decode(BackupPayload.self, from: data)
    }

    // MARK: - （参考）CSV 1行生成（既存のまま温存）
    static func lineForCSV(entry: DiaryEntry) -> [String] {
        func s(_ d: Double?) -> String { d.map { String(format: "%.1f", $0) } ?? "" }
        let dateStr = ISO8601DateFormatter.yyyyMMdd.string(from: entry.date)
        let varietiesStr = entry.varieties.map { "\($0.varietyName) [\($0.stage)]" }.joined(separator: "; ")
        let spraysStr = entry.sprays.map { "\($0.chemicalName) x\($0.dilution)" }.joined(separator: "; ")
        let volunteersStr = entry.volunteers.joined(separator: ", ")
        let photosStr = entry.photos.joined(separator: "; ")

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

    // MARK: - Util
    private static func timestampString() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd_HHmm"
        return df.string(from: Date())
    }
}
