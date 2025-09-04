import Foundation

/// 設定をやり取りするためのシンプルな JSON ペイロード
/// ※ Settings 型には依存しない。既存の配列型で保持する。
struct VineyardSettingsFile: Codable {
    var blocks: [BlockSetting]
    var varieties: [VarietySetting]
    var stages: [StageSetting]
}
