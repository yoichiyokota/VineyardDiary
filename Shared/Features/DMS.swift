// Shared/Features/DMS.swift
import Foundation

// 入力エラー（UI に表示できるよう LocalizedError 準拠）
public enum DMSError: Error, LocalizedError {
    case invalidFormat
    case outOfRangeLat
    case outOfRangeLon

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "度分秒（DMS）の形式を解釈できません。例: 36°46'01.7\"N / 138°20'13.2\"E"
        case .outOfRangeLat:
            return "緯度は -90〜90 の範囲で入力してください。"
        case .outOfRangeLon:
            return "経度は -180〜180 の範囲で入力してください。"
        }
    }
}

/// 10進度 → DMS + 方位記号（N/E/S/W）
public func ddToDMSWithHemisphere(_ dd: Double, isLat: Bool) -> String {
    let absVal = abs(dd)
    let deg = Int(absVal.rounded(.down))
    let minFloat = (absVal - Double(deg)) * 60.0
    let min = Int(minFloat.rounded(.down))
    let sec = (minFloat - Double(min)) * 60.0

    let hemi: String
    if isLat {
        hemi = dd >= 0 ? "N" : "S"
    } else {
        hemi = dd >= 0 ? "E" : "W"
    }
    return String(format: "%d°%02d'%05.1f\"%@", deg, min, sec, hemi)
}

/// DMS(+方位記号) 文字列 → 10進度
/// 受け入れ例: `36°46'01.7"N`, `-36 46 1.7`, `138d20m13.2sE`, `36°46'N`（秒省略）
public func dmsToDDWithHemisphere(_ s: String, isLat: Bool) -> Result<Double, DMSError> {
    let str = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    // 方位記号（任意）
    var sign: Double = 1.0
    if let last = str.last, "NSEW".contains(last) {
        if last == "S" || last == "W" { sign = -1.0 }
    }

    // 数字部分のみを正規表現で抽出（度 分 秒）
    let pattern = #"^\s*([+-]?\d+)[°D\s]+(\d+)?['M\s]*([0-9.]+)?[""S\s]*[NSEW]?\s*$"#
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return .failure(.invalidFormat)
    }
    let ns = str as NSString
    guard let m = re.firstMatch(in: str, options: [], range: NSRange(location: 0, length: ns.length)) else {
        return .failure(.invalidFormat)
    }

    func group(_ i: Int) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }

    guard let degStr = group(1), let deg = Double(degStr) else { return .failure(.invalidFormat) }
    let min = Double(group(2) ?? "0") ?? 0
    let sec = Double(group(3) ?? "0") ?? 0

    var value = abs(deg) + (min / 60.0) + (sec / 3600.0)

    // 先頭の +/- がある場合はそれを優先、無ければ N/E/S/W の符号を使う
    if degStr.hasPrefix("-") {
        value = -value
    } else {
        value = sign * value
    }

    // 範囲チェック
    if isLat {
        guard (-90...90).contains(value) else { return .failure(.outOfRangeLat) }
    } else {
        guard (-180...180).contains(value) else { return .failure(.outOfRangeLon) }
    }
    return .success(value)
}
