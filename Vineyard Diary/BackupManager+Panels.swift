import Foundation
import AppKit
import UniformTypeIdentifiers

// 既存の BackupPayload / BackupManager を拡張。
// ここでは「保存先/復元ファイルをユーザーに選ばせる」UI付きメソッドを提供します。
extension BackupManager {

    /// ファイル保存ダイアログを出してバックアップを書き出します（JSON, 拡張子 .vydbackup）
    @MainActor
    static func exportBackupWithPanel(
        settings: AppSettings,
        entries: [DiaryEntry],
        dailyWeather: [String : [String : DailyWeather]]
    ) throws -> URL {

        let savePanel = NSSavePanel()
        savePanel.title = "バックアップを保存"
        savePanel.nameFieldStringValue = "VineyardDiary_Backup.vydbackup"

        // .vydbackup を UTType として扱う（不明ならデータとして許可）
        if let custom = UTType(filenameExtension: "vydbackup") {
            savePanel.allowedContentTypes = [custom]
        } else {
            savePanel.allowedContentTypes = [.data]
        }

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            throw CocoaError(.userCancelled)
        }

        // 既存のバックアップフォーマット（BackupPayload）でJSON化して保存
        let payload = BackupPayload(settings: settings, entries: entries, dailyWeather: dailyWeather)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(payload)
        try data.write(to: url, options: .atomic)

        return url
    }

    /// ファイルを選んでバックアップから復元します（読み取りのみ・適用は呼び出し側で）
    @MainActor
    static func importBackupWithPanel() throws -> BackupPayload {
        let open = NSOpenPanel()
        open.title = "バックアップファイルを選択"
        open.allowsMultipleSelection = false
        if let custom = UTType(filenameExtension: "vydbackup") {
            open.allowedContentTypes = [custom]
        } else {
            open.allowedContentTypes = [.data]
        }

        guard open.runModal() == .OK, let url = open.url else {
            throw CocoaError(.userCancelled)
        }

        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        return try dec.decode(BackupPayload.self, from: data)
    }
}
