import Foundation

// MARK: - DMS <-> Decimal Degrees

/// 10進度(Double) → DMS文字列（Google Maps風）
public func ddToDMS(_ value: Double, isLat: Bool) -> String {
    let positive = value >= 0
    let absV = abs(value)

    let deg = Int(absV)
    let minFloat = (absV - Double(deg)) * 60.0
    let min = Int(minFloat)
    let sec = (minFloat - Double(min)) * 60.0

    let hemi: String = {
        if isLat { return positive ? "N" : "S" }
        else     { return positive ? "E" : "W" }
    }()

    // 秒は小数1桁で整形
    let secStr = String(format: "%.1f", sec)
    // 例: 36°46'01.7"N
    return "\(deg)°\(String(format: "%02d", min))'\(secStr)\"\(hemi)"
}

/// DMS文字列（Google Maps風）→ 10進度(Double)
/// 例: 36°46'01.7"N / 138°20'13.2"E / 36 46 1.7 N / 36°46' N 等のゆるい表記も許容
public func dmsToDD(_ dms: String, isLat: Bool) -> Double? {
    // 前後空白除去＆大文字化
    var s = dms.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.isEmpty { return nil }

    // 末尾の方位記号を取得（無くてもOK、無い場合は正とみなす）
    let hemiSign: Double = {
        if s.hasSuffix("N") { s.removeLast(); return +1 }
        if s.hasSuffix("E") { s.removeLast(); return +1 }
        if s.hasSuffix("S") { s.removeLast(); return -1 }
        if s.hasSuffix("W") { s.removeLast(); return -1 }
        return +1
    }()

    // 記号をスペースに置換して分割しやすく
    let replaced = s
        .replacingOccurrences(of: "°", with: " ")
        .replacingOccurrences(of: "′", with: " ")
        .replacingOccurrences(of: "'", with: " ")
        .replacingOccurrences(of: "’", with: " ")
        .replacingOccurrences(of: "”", with: " ")
        .replacingOccurrences(of: "\"", with: " ")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // 半角/全角スペースで分割
    let parts = replaced.split { $0 == " " || $0 == "　" }.map(String.init)
    if parts.isEmpty { return nil }

    func parseDouble(_ str: String) -> Double? {
        Double(str.replacingOccurrences(of: ",", with: ""))
    }

    guard let deg = parseDouble(parts[0]) else { return nil }
    let minutes: Double = (parts.count >= 2) ? (parseDouble(parts[1]) ?? 0) : 0
    let seconds: Double = (parts.count >= 3) ? (parseDouble(parts[2]) ?? 0) : 0

    var dd = deg + minutes / 60.0 + seconds / 3600.0
    dd *= hemiSign

    // 範囲チェック
    if isLat {
        guard (-90.0...90.0).contains(dd) else { return nil }
    } else {
        guard (-180.0...180.0).contains(dd) else { return nil }
    }
    return dd
}
