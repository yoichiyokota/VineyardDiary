import Foundation

// 区画（畑）
struct BlockSetting: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double?   // nil なら未設定
    var longitude: Double?
}

// 品種マスタ
struct VarietySetting: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

// ステージマスタ（コードとラベル）
struct StageSetting: Identifiable, Codable, Hashable {
    var id = UUID()
    var code: Int           // 例: 23
    var label: String       // 例: 満開期
}

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
}

// エントリ内の品種×ステージ
struct VarietyStageItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var varietyName: String
    var stage: String   // "23: 満開期" のような表記
    init(varietyName: String = "", stage: String = "") {
        self.varietyName = varietyName
        self.stage = stage
    }
}

// 防除アイテム（薬剤名＋希釈倍率）
struct SprayItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var chemicalName: String
    var dilution: String
    init(chemicalName: String = "", dilution: String = "") {
        self.chemicalName = chemicalName
        self.dilution = dilution
    }
}

// 時間帯
struct WorkTime: Identifiable, Codable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
}

// 日記エントリ
struct DiaryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var block: String
    var varieties: [VarietyStageItem] = []
    var isSpraying: Bool = false
    var sprayTotalLiters: String = ""          // 使用L（共通）
    var sprays: [SprayItem] = []               // 薬剤リスト
    var workNotes: String = ""                 // 作業内容
    var memo: String = ""                      // 備考
    var workTimes: [WorkTime] = []             // 作業時間帯(複数)
    var volunteers: [String] = []              // ボランティア氏名
    var photos: [String] = []                  // ← 追加（ファイル名配列）

    // 気象
    var weatherMin: Double? = nil
    var weatherMax: Double? = nil
    var sunshineHours: Double? = nil
    var precipitationMm: Double? = nil
}

