// Shared/Logic/GDD.swift
import Foundation

struct GDDPoint: Identifiable, Hashable {
    let id = UUID()
    let day: Date
    let value: Double
}

/// GDD / eGDD 計算ビルダー
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
            let blk = block ?? guessBlock(for: store, on: day)
            if let w = weather.get(block: blk, date: day),
               let tmax = w.tMax, let tmin = w.tMin {
                let v: Double
                switch method {
                case .classicBase10:
                    v = gddClassic(tmin: tmin, tmax: tmax, base: base)
                case .effective:
                    v = EGDD.daily(tmin: tmin, tmax: tmax, date: day,
                                   store: store, variety: variety)
                }
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

    // MARK: - 起点・終点
    @MainActor
    private static func startDate(store: DiaryStore, year: Int, rule: GDDStartRule, variety: String?) -> Date? {
        let cal = Calendar.current
        let apr1 = cal.date(from: DateComponents(year: year, month: 4, day: 1))!

        switch rule {
        case .fixedApril1: return apr1
        case .autoBudbreakOrApril1:
            if let bud = firstStageDate(store: store, year: year, minStageCode: 5, variety: variety) {
                return min(bud, apr1)
            }
            return apr1
        }
    }

    @MainActor
    //private static func endDate(store: DiaryStore, year: Int, variety: String?) -> Date? {
    //    if let harvest = firstStageDate(store: store, year: year, minStageCode: 40, variety: variety) {
    //        return harvest
    //    }
    //    return Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31))
    //}
    private static func endDate(store: DiaryStore, year: Int, variety: String?) -> Date? {
        Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31))
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

    // 従来方式 GDD
    private static func gddClassic(tmin: Double, tmax: Double, base: Double) -> Double {
        let avg = (tmin + tmax) / 2
        return max(avg - base, 0)
    }
}
