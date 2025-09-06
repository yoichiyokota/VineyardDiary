import Foundation

struct GDDPoint: Identifiable, Hashable {
    let id = UUID()
    let day: Date
    let value: Double
}

enum GDDSeriesBuilder {
    /// DiaryStore / DailyWeatherStore を読むので MainActor 上で動かす
    @MainActor
    static func dailySeries(
        store: DiaryStore,
        weather: DailyWeatherStore,
        year: Int,
        block: String?,
        variety: String?,
        method: GDDMethod,
        rule: GDDStartRule,
        base: Double = 10.0
    ) -> [GDDPoint] {
        guard let start = startDate(store: store, year: year, rule: rule, variety: variety),
              let end   = endDate(store: store, year: year, variety: variety) else { return [] }
        
        var day = Calendar.current.startOfDay(for: start)
        let last = Calendar.current.startOfDay(for: end)
        var points: [GDDPoint] = []
        
        while day <= last {
            // ← 指定 block があれば必ずそれを使う
            let blkName = (block?.isEmpty == false) ? block! : guessBlock(for: store, on: day)
            
            if let w = weather.get(block: blkName, date: day),
               let tmax = w.tMax, let tmin = w.tMin {
                let v = gddForDay(
                    tmin: tmin,
                    tmax: tmax,
                    base: base,
                    method: method,
                    date: day,
                    store: store,
                    variety: variety)
                points.append(.init(day: day, value: max(v, 0)))
            } else {
                points.append(.init(day: day, value: 0))
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return points
    }

    static func cumulativeSeries(from daily: [GDDPoint]) -> [GDDPoint] {
        var sum = 0.0
        return daily.map { p in sum += p.value; return .init(day: p.day, value: sum) }
    }

    // MARK: - 起点・終点（MainActor：store/entriesへアクセス）
    @MainActor
    private static func startDate(store: DiaryStore, year: Int, rule: GDDStartRule, variety: String?) -> Date? {
        let cal = Calendar.current
        let apr1 = cal.date(from: DateComponents(year: year, month: 4, day: 1))!

        switch rule {
        case .fixedApril1:
            return apr1
        case .autoBudbreakOrApril1:
            if let bud = firstStageDate(store: store, year: year, minStageCode: 5, variety: variety) {
                return min(bud, apr1)
            }
            return apr1
        }
    }

    @MainActor
    private static func endDate(store: DiaryStore, year: Int, variety: String?) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        if let harvest = firstStageDate(store: store, year: year, minStageCode: 40, variety: variety) {
            // 収穫日が未来に設定されていても、今日までにキャップ
            return min(harvest, today)
        }
        // 収穫記録が無ければ「今日」まで
        return today
    }

    @MainActor
    private static func firstStageDate(store: DiaryStore, year: Int, minStageCode: Int, variety: String?) -> Date? {
        let cal = Calendar.current
        let entries = store.entries.filter { cal.component(.year, from: $0.date) == year }

        func code(from s: String) -> Int? {
            s.split(separator: ":").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        let dates: [Date] = entries.compactMap { e in
            let hit = e.varieties.contains { vi in
                if let v = variety, !v.isEmpty {
                    guard vi.varietyName.compare(v, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { return false }
                }
                guard let c = code(from: vi.stage) else { return false }
                return c >= minStageCode
            }
            return hit ? e.date : nil
        }
        return dates.min()
    }

    @MainActor
    private static func guessBlock(for store: DiaryStore, on day: Date) -> String {
        let cal = Calendar.current
        if let e = store.entries.first(where: { cal.isDate($0.date, inSameDayAs: day) && !$0.block.isEmpty }) {
            return e.block
        }
        return store.settings.blocks.first?.name ?? ""
    }

    @MainActor
    private static func gddForDay(tmin: Double, tmax: Double, base: Double, method: GDDMethod, date: Date, store: DiaryStore, variety: String?) -> Double {
        switch method {
        case .classicBase10:
            // 旧来：日平均(Tmean) - base（負は0）
            let avg = (tmin + tmax) / 2
            return max(avg - base, 0)

        case .effective:
            // 新方式：eGDD
            return EGDD.daily(tmin: tmin, tmax: tmax, date: date, store: store, variety: variety)
        }
    }
}

// ===== ここから下を GDD.swift の同じファイル内（GDDSeriesBuilderの外でもOK）に追記 =====

/// eGDD（日次）の簡易モデル
/// - base: 10℃
/// - 30℃を超えると線形減衰（30→35℃で寄与0）
/// - 35℃超は二次ペナルティを追加で弱める
/// - 1日あたり上限（cap）を設定（必要に応じて調整）
private func effectiveDailyGDD(tmin: Double, tmax: Double, base: Double) -> Double {
    let tavg = (tmin + tmax) / 2.0

    // まずは base 超過分の熱量（旧方式と同じ起点）
    var heat = max(tavg - base, 0)

    // 30〜35℃の高温で線形に減衰（tavg 基準の簡易モデル）
    //   tavg <= 30 : 係数 1.0
    //   tavg >= 35 : 係数 0.0
    //   その間は線形
    let over30Avg = max(tavg - 30.0, 0)
    let linearAttenuation = max(0.0, 1.0 - min(over30Avg / 5.0, 1.0)) // [0,1]

    // さらに Tmax が 35℃を超える日は追加ペナルティ（連続・滑らか）
    //   over35Max が大きいほど 1/(1+x^2) で弱める
    let over35Max = max(tmax - 35.0, 0)
    let quadraticPenalty = 1.0 / (1.0 + pow(over35Max / 5.0, 2.0))   // (0,1]

    heat *= linearAttenuation * quadraticPenalty

    // 1日上限（必要に応じて調整。例: 20 DD/day）
    let capPerDay = 20.0
    return min(max(heat, 0), capPerDay)
}
