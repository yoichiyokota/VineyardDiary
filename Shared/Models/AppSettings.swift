
import Foundation

// アプリ全体の設定
struct AppSettings: Codable {
    var blocks: [BlockSetting] = [
      //  .init(name: "田麦(430m)", latitude: 36.76714, longitude: 138.33700),
      //  .init(name: "深沢(630m)", latitude: 36.78139, longitude: 138.39299)
    ]
    var varieties: [VarietySetting] = [
      //  .init(name: "シャルドネ"),
      //  .init(name: "カベルネ・ソーヴィニヨン")
    ]
    var stages: [StageSetting] = [
        .init(code: 5,  label: "burst 萌芽（ほうが）"),
        .init(code: 7,  label: "1 leaf 第１展葉"),
        .init(code: 9,  label: "2-3 leaves 葉が２～３枚展葉"),
        .init(code: 12, label: "5-6 leaves 葉が５～６枚展葉"),
        .init(code: 15, label: "closely 1つ1つの花蕾が膨らみ始める"),
        .init(code: 17, label: "separat 花蕾が充分成長した状態"),
        .init(code: 19, label:"10% 開花開始【最初のキャップがおちた状態】"),
        .init(code: 21, label:"25% 開花初期 【キャップ（花冠）の25％が萼（がく）から離れた状態】"),
        .init(code: 23, label:"50% 満開期 【キャップ（花冠）の50％が萼（がく）から離れた状態】"),
        .init(code:25, label:"80% 開花後期 【キャップ（花冠）の80％が萼（がく）から離れた状態】"),
        .init(code:27, label:"100% 結実期"),
        .init(code:29, label:"3mm マッチ棒の頭大の果粒サイズ"),
        .init(code:31, label:"6mm 小豆粒大の果粒サイズ"),
        .init(code:33, label:"9mm 果粒肥大期"),
        .init(code:35, label:"6-8° 着色成熟開始期"),
        .init(code:38, label:"10-15° 収穫にむけての成熟期"),
        .init(code:40, label:"harvest 収穫"),
        .init(code:41, label:"After harvest, end of wood maturation"),
        .init(code:43, label:"Begining of leaf fall"),
        .init(code:47, label:"End of leaf fall")

    ]
    
    // ← ここが今回 “追加” したい2項目
    var gddStartRule: GDDStartRule = .autoBudbreakOrApril1
    var gddMethod: GDDMethod = .effective
}

// 旧データ互換：キーが無い場合はデフォルト値で復元
extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.blocks    = try c.decodeIfPresent([BlockSetting].self, forKey: .blocks)    ?? []
        self.varieties = try c.decodeIfPresent([VarietySetting].self, forKey: .varieties) ?? []
        self.stages    = try c.decodeIfPresent([StageSetting].self, forKey: .stages)    ?? []
        self.gddStartRule = try c.decodeIfPresent(GDDStartRule.self, forKey: .gddStartRule) ?? .autoBudbreakOrApril1
        self.gddMethod    = try c.decodeIfPresent(GDDMethod.self, forKey: .gddMethod)       ?? .effective
    }
}

