// Shared/Logic/EGDD.swift
import Foundation

/// eGDD の調整係数（“Yoichi 係数”）
/// 必要になったら Settings に出して UI から変えられるようにしてもOK。
struct EGDDConfig {
    var base: Double = 10.0      // 基準温度
    var linearStart: Double = 30 // ここから線形減衰
    var quadStart: Double = 35   // ここから二次ペナルティ
    var dailyCap: Double = 22    // 1日の上限（「上限あり」運用）

    // 線形減衰の傾き（30→35℃ で 1.0→linearFloor へ）
    var linearFloor: Double = 0.50

    // 35℃超の二次ペナルティ係数（大きいほど強く減衰）
    var quadK: Double = 0.10

    // VPD 補正（kPa）
    var vpdMin: Double = 0.8     // ここまでは 1.0
    var vpdMax: Double = 2.5     // ここで vpdFloor まで低下
    var vpdFloor: Double = 0.70  // 乾燥が強いとここまで落とす

    // フェーズ重み（ステージコードの代表帯）
    var wVeg: Double   = 1.00    // 5..20 萌芽～展葉
    var wBloom: Double = 0.95    // 21..30 開花・結実
    var wVer: Double   = 1.05    // 31..39 着色～成熟
}

/// eGDD 関数群
enum EGDD {

    /// 1日の eGDD（tmin/tmax ベース、内部で時間分割平均）
    @MainActor
    static func daily(tmin: Double, tmax: Double, date: Date, store: DiaryStore, variety: String?, config: EGDDConfig = .init()) -> Double {
        // 1) 温度プロファイルの重み付き平均（24分割サンプリング）
        let base = config.base
        let samples = 24
        var sumEff = 0.0
        for i in 0..<samples {
            // ざっくり単正弦近似（午前低く、午後ピーク）
            let theta = Double(i) / Double(samples - 1) * Double.pi
            let T = tmin + (tmax - tmin) * sin(theta)   // [tmin .. tmax]
            sumEff += effectiveContribution(T: T, base: base, cfg: config)
        }
        var tempEff = sumEff / Double(samples)         // 日平均の“有効温度寄与”

        // 2) VPD 補正：Tmin≈露点から RH を概算 → VPD を推定
        let tMean = (tmin + tmax) / 2
        let vpd = estimateVPD(tAir: tMean, tDew: tmin)
        let vpdF = vpdFactor(vpd, cfg: config)
        tempEff *= vpdF

        // 3) フェーズ重み
        tempEff *= phaseWeight(on: date, variety: variety, store: store, cfg: config)

        // 4) 日上限
        tempEff = min(tempEff, config.dailyCap)

        // “積算温度”なので base を引いた surplus と解釈（0 未満は 0）
        return max(tempEff - base, 0)
    }

    // MARK: - 温度の効果関数
    private static func effectiveContribution(T: Double, base: Double, cfg: EGDDConfig) -> Double {
        if T <= base { return base } // 0 寄与（後で base を引く）
        if T <= cfg.linearStart { return T }
        if T <= cfg.quadStart {
            // 30→35℃ の線形減衰：1.0→linearFloor
            let p = (T - cfg.linearStart) / (cfg.quadStart - cfg.linearStart)
            let w = 1.0 - (1.0 - cfg.linearFloor) * p
            return base + (T - base) * w
        }
        // 35℃超：二次ペナルティ（max で下駄）
        let penalty = cfg.quadK * pow(T - cfg.quadStart, 2.0)
        let w = max(0.0, cfg.linearFloor - penalty)
        return base + (T - base) * w
    }

    // MARK: - VPD 推定と補正
    /// Tetens式で飽和水蒸気圧 es(T) [kPa]
    private static func es(_ T: Double) -> Double {
        0.6108 * exp((17.27 * T) / (T + 237.3))
    }
    /// VPD ≈ es(Tair) - ea、ea は露点から算出（Tdew≒Tmin 仮定）
    private static func estimateVPD(tAir: Double, tDew: Double) -> Double {
        let esAir = es(tAir)
        let esDew = es(tDew)   // ≈ ea
        return max(esAir - esDew, 0)
    }
    /// VPD 補正係数（高VPDで減衰）
    private static func vpdFactor(_ v: Double, cfg: EGDDConfig) -> Double {
        if v <= cfg.vpdMin { return 1.0 }
        if v >= cfg.vpdMax { return cfg.vpdFloor }
        let p = (v - cfg.vpdMin) / (cfg.vpdMax - cfg.vpdMin)
        return 1.0 - (1.0 - cfg.vpdFloor) * p
    }

    // MARK: - フェーズ重み
    @MainActor
    private static func phaseWeight(on day: Date, variety: String?, store: DiaryStore, cfg: EGDDConfig) -> Double {
        // その日までに記録された最新ステージコードを拾う
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: day)
        var latestCode: Int?

        for e in store.entries where cal.startOfDay(for: e.date) <= targetDay {
            for v in e.varieties {
                if let name = variety, !name.isEmpty, v.varietyName.caseInsensitiveCompare(name) != .orderedSame {
                    continue
                }
                if let code = stageCode(from: v.stage) {
                    latestCode = max(latestCode ?? code, code)
                }
            }
        }

        guard let code = latestCode else { return cfg.wVeg } // データ無ければ等倍

        switch code {
        case ..<5:           return 0.0           // 萌芽前は寄与 0（実質的には起点手前）
        case 5...20:         return cfg.wVeg      // 萌芽～展葉
        case 21...30:        return cfg.wBloom    // 開花・結実
        case 31...39:        return cfg.wVer      // 着色～成熟
        default:             return 0.0           // 40=収穫以降は寄与 0（通常は終点で打ち切り）
        }
    }

    private static func stageCode(from stageText: String) -> Int? {
        // "23: 開花" / "23" どちらも許可
        if let head = stageText.split(separator: ":").first {
            return Int(head.trimmingCharacters(in: .whitespaces))
        }
        return Int(stageText.trimmingCharacters(in: .whitespaces))
    }
}
