// Shared/Logic/EGDD.swift
import Foundation

/// eGDD（有効積算温度）Yoichi版
/// - 基本: 標準GDD = max(0, (Tmax+Tmin)/2 - 10)
/// - 補正係数 m（Tmax依存）を掛ける:
///     m = 1                                  (Tmax ≤ 30)
///     m = 1 - α (Tmax - 30)                  (30 < Tmax ≤ 35)
///     m = [1 - α*5] - β (Tmax - 35)^2        (Tmax > 35)
///   ※ m は [0,1] にクランプ
/// - キャップなし、フェーズ重みなし（シンプル運用）
/// - 既存呼び出し互換のため DiaryStore/variety を引数に持つが未使用
enum EGDD {

    /// 日次 eGDD（Yoichi版）
    /// - Parameters:
    ///   - tmin: 日最低気温
    ///   - tmax: 日最高気温
    ///   - date: 該当日（未使用）
    ///   - store: DiaryStore（未使用・呼び出し互換のため）
    ///   - variety: 品種名（未使用）
    /// - Returns: eGDD(day)
    @MainActor
    static func daily(
        tmin: Double,
        tmax: Double,
        date: Date,
        store: DiaryStore,
        variety: String?
    ) -> Double {
        // 互換用（未使用引数の警告抑制）
        _ = date; _ = store; _ = variety

        let core = coreGDD(tmin: tmin, tmax: tmax, base: 10.0)
        let m    = mFactor(tmax: tmax, alpha: 0.04, beta: 0.02)
        return core * m
    }

    // MARK: - 基本GDD（世界標準）
    /// GDD_core = max(0, (Tmax+Tmin)/2 - base)
    static func coreGDD(tmin: Double, tmax: Double, base: Double = 10.0) -> Double {
        let avg = (tmin + tmax) / 2.0
        return max(0.0, avg - base)
    }

    // MARK: - 補正係数 m（Tmax に依存）
    /// m:
    ///  - ≤30: 1
    ///  - 30〜35: 1 - α (Tmax - 30)
    ///  - >35: (1 - α*5) - β (Tmax - 35)^2
    ///  0〜1 にクランプ
    static func mFactor(tmax: Double, alpha: Double = 0.04, beta: Double = 0.02) -> Double {
        let m: Double
        if tmax <= 30.0 {
            m = 1.0
        } else if tmax <= 35.0 {
            m = 1.0 - alpha * (tmax - 30.0)
        } else {
            m = (1.0 - alpha * 5.0) - beta * pow(tmax - 35.0, 2.0)
        }
        return min(1.0, max(0.0, m))
    }
}
