import Foundation

// MARK: - Model

struct DailyWeather: Codable, Hashable {
    /// 該当日の 00:00（startOfDay）
    var date: Date

    /// 最高/最低（摂氏）
    var tMax: Double?
    var tMin: Double?

    /// 日照時間（時間）
    var sunshineHours: Double?

    /// 降水量（mm/日）
    var precipitationMm: Double?

    /// キー化（yyyy-MM-dd）
    var dateISO: String {
        DateFormatter.yyyyMMdd.string(from: date)
    }

    // 互換維持のためのカスタム init
    init(
        date: Date,
        tMax: Double? = nil,
        tMin: Double? = nil,
        sunshineHours: Double? = nil,
        precipitationMm: Double? = nil
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.tMax = tMax
        self.tMin = tMin
        self.sunshineHours = sunshineHours
        self.precipitationMm = precipitationMm
    }
}

// MARK: - Store

@MainActor
final class DailyWeatherStore: ObservableObject {
    /// data[blockName][yyyy-MM-dd] = DailyWeather
    @Published private(set) var data: [String: [String: DailyWeather]] = [:]

    private let fileURL: URL = {
        URL.documentsDirectory.appendingPathComponent("daily_weather.json")
    }()

    // 取得
    func get(block: String, date: Date) -> DailyWeather? {
        let day = Calendar.current.startOfDay(for: date)
        let iso = DateFormatter.yyyyMMdd.string(from: day)
        return data[block]?[iso]
    }

    // Upsert 1日
    func set(block: String, item: DailyWeather) {
        var byDate = data[block] ?? [:]
        byDate[item.dateISO] = item
        data[block] = byDate
    }

    // 複数まとめて投入
    func setMany(block: String, items: [DailyWeather]) {
        guard !items.isEmpty else { return }
        var byDate = data[block] ?? [:]
        for it in items { byDate[it.dateISO] = it }
        data[block] = byDate
    }

    // 値だけ更新
    func upsert(
        block: String,
        date: Date,
        tMax: Double? = nil,
        tMin: Double? = nil,
        sunshineHours: Double? = nil,
        precipitationMm: Double? = nil
    ) {
        let day = Calendar.current.startOfDay(for: date)
        let key = DateFormatter.yyyyMMdd.string(from: day)
        var byDate = data[block] ?? [:]
        var item = byDate[key] ?? DailyWeather(date: day)
        if let tMax { item.tMax = tMax }
        if let tMin { item.tMin = tMin }
        if let sunshineHours { item.sunshineHours = sunshineHours }
        if let precipitationMm { item.precipitationMm = precipitationMm }
        byDate[key] = item
        data[block] = byDate
    }

    // I/O
    func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let raw = try enc.encode(data)
            try raw.write(to: fileURL, options: .atomic)
        } catch {
            print("DailyWeather save error:", error)
        }
    }

    func load() {
        do {
            let raw = try Data(contentsOf: fileURL)
            let dec = JSONDecoder()
            self.data = try dec.decode([String:[String:DailyWeather]].self, from: raw)
        } catch {
            self.data = [:]
        }
    }

    // 全置換
    func replaceAll(with newData: [String: [String: DailyWeather]]) {
        self.data = newData
        self.save()
    }
}

extension DailyWeatherStore {
    func all(for block: String) -> [DailyWeather] {
        data[block]?.values.sorted(by: { $0.date < $1.date }) ?? []
    }
}
