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
    var photos: [String] = []                  // ファイル名配列
    var photoCaptions: [String: String] = [:]  //写真キャプション（キー＝ファイル名）
    var updatedAt: Date = Date()


    // 気象
    var weatherMin: Double? = nil
    var weatherMax: Double? = nil
    var sunshineHours: Double? = nil
    var precipitationMm: Double? = nil
    
    // 互換性確保：旧データに photoCaptions が無くても読み込めるように
       enum CodingKeys: String, CodingKey {
           case id, date, block, varieties, isSpraying, sprayTotalLiters, sprays,
                workNotes, memo, workTimes, volunteers, photos, photoCaptions,
                weatherMin, weatherMax, sunshineHours, precipitationMm
       }

}

