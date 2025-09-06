import Foundation

public enum GDDStartRule: String, Codable, CaseIterable, Equatable {
    case fixedApril1                 // 4/1 固定
    case autoBudbreakOrApril1       // 萌芽 or 4/1 の早い方
}


public enum GDDMethod: String, Codable, CaseIterable, Equatable {
    case classicBase10              // 従来: 基準10℃
    case effective                  // 有効積算温度（減衰・上限あり）
}

// ---- 互換レイヤ（既存コードが旧名を使っていてもビルドを通す）----
public extension GDDStartRule {
    static var april1Fixed: GDDStartRule { .fixedApril1 }
    static var budbreakOrApril1: GDDStartRule { .autoBudbreakOrApril1 }
}
