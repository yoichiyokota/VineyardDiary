import Foundation

enum WeatherService {

    struct OMResponse: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let sunshine_duration: [Double?] // 秒
        }
        let daily: Daily
    }

    /// 指定期間の “日別” 気象（tmax/tmin/sunshine_hours）を返す。
    /// ※ 期間に応じて forecast / archive を自動切替（必要なら分割して結合）
    static func fetchDailyRange(lat: Double, lon: Double, from: Date, to: Date) async throws -> [DailyWeather] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fromDay = cal.startOfDay(for: from)
        let toDay   = cal.startOfDay(for: to)

        var chunks: [(Date, Date, Endpoint)] = []

        if toDay < today {
            // 全部過去 → archive だけ
            chunks.append((fromDay, toDay, .archive))
        } else if fromDay >= today {
            // 全部未来/当日以降 → forecast だけ（today も forecast でOK）
            chunks.append((fromDay, toDay, .forecast))
        } else {
            // またぎ：過去部分は archive、当日〜終端は forecast
            let pastEnd = cal.date(byAdding: .day, value: -1, to: today) ?? today
            chunks.append((fromDay, pastEnd, .archive))
            chunks.append((today, toDay, .forecast))
        }

        var all: [DailyWeather] = []
        for (s, e, ep) in chunks {
            let part = try await fetchDailyRangeSingleEndpoint(lat: lat, lon: lon, from: s, to: e, endpoint: ep)
            all.append(contentsOf: part)
        }

        // 重複をつぶして日付昇順
        let merged = Dictionary(grouping: all, by: { $0.dateISO })
            .compactMap { (k, arr) -> DailyWeather? in
                // 同じ日が重なったら、archive を優先（より安定）
                // ここでは最後に来た方を優先でもOK。必要なら精緻化。
                return arr.last
            }
            .sorted { $0.dateISO < $1.dateISO }

        return merged
    }

    // MARK: - 内部実装

    private enum Endpoint {
        case forecast
        case archive

        var baseURL: String {
            switch self {
            case .forecast: return "https://api.open-meteo.com/v1/forecast"
            case .archive:  return "https://archive-api.open-meteo.com/v1/archive"
            }
        }
    }

    private static func fetchDailyRangeSingleEndpoint(
        lat: Double,
        lon: Double,
        from: Date,
        to: Date,
        endpoint: Endpoint
    ) async throws -> [DailyWeather] {

        guard from <= to else { return [] }

        let df = ISO8601DateFormatter.yyyyMMdd
        let start = df.string(from: from)
        let end   = df.string(from: to)

        var comps = URLComponents(string: endpoint.baseURL)!
        comps.queryItems = [
            .init(name: "latitude", value: "\(lat)"),
            .init(name: "longitude", value: "\(lon)"),
            .init(name: "timezone", value: "auto"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunshine_duration"),
            .init(name: "start_date", value: start),
            .init(name: "end_date", value: end),
            // 念のため単位も明示（デフォルトは摂氏/Cだが将来変更に備える）
            .init(name: "temperature_unit", value: "celsius")
        ]

        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)

        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // サーバー本文にエラー詳細が入っていれば表示
            let serverMsg = String(data: data, encoding: .utf8) ?? ""
            print("❌ Open-Meteo error \(endpoint) \(httpStatusString(resp)): \(serverMsg)")
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OMResponse.self, from: data)
        let d = decoded.daily

        var result: [DailyWeather] = []
        let n = d.time.count
        for i in 0..<n {
            let iso = d.time[i]
            let tmax = (i < d.temperature_2m_max.count) ? d.temperature_2m_max[i] : nil
            let tmin = (i < d.temperature_2m_min.count) ? d.temperature_2m_min[i] : nil
            let sunS = (i < d.sunshine_duration.count) ? d.sunshine_duration[i] : nil
            let sunH = sunS.map { $0 / 3600.0 } // 秒 → 時間
            result.append(DailyWeather(dateISO: iso, tMin: tmin, tMax: tmax, sunshineHours: sunH))
        }
        return result
    }

    private static func httpStatusString(_ resp: URLResponse) -> String {
        if let h = resp as? HTTPURLResponse {
            return "\(h.statusCode)"
        }
        return "unknown"
    }
}
