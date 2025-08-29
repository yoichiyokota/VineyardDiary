import Foundation

struct DailyWeather: Codable, Hashable {
    let dateISO: String        // "yyyy-MM-dd"
    let tMin: Double?
    let tMax: Double?
    let sunshineHours: Double?
}

@MainActor
final class DailyWeatherStore: ObservableObject {
    @Published private(set) var data: [String: [String: DailyWeather]] = [:]
    private let fileURL = URL.documentsDirectory.appendingPathComponent("daily_weather.json")

    func get(block: String, date: Date) -> DailyWeather? {
        let iso = ISO8601DateFormatter.yyyyMMdd.string(from: date)
        return data[block]?[iso]
    }

    func set(block: String, item: DailyWeather) {
        var byDate = data[block] ?? [:]
        byDate[item.dateISO] = item
        data[block] = byDate
    }

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
    func replaceAll(with newData: [String: [String: DailyWeather]]) {
        self.data = newData
        self.save()
    }
}


