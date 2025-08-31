import Foundation

/// 天気取得ユーティリティ
/// - 仕様: 指定範囲（from～to、どちらも含む）の日次データをまとめて取得して返す
/// - 取得元: Open-Meteo ERA5 アーカイブAPI（無料・APIキー不要）
///   https://archive-api.open-meteo.com/v1/era5
/// - 返却: DailyWeather の配列（date, tMax, tMin, sunshineHours, precipitationMm を充足）
enum WeatherService {

    // MARK: Public API

    /// 指定の緯度経度・日付範囲の「日次」天気項目を取得
    /// - Parameters:
    ///   - lat: 緯度
    ///   - lon: 経度
    ///   - from: 開始日（含む）
    ///   - to: 終了日（含む）
    /// - Returns: `DailyWeather` の配列（from→to の日付順）
    static func fetchDailyRange(
        lat: Double,
        lon: Double,
        from: Date,
        to: Date
    ) async throws -> [DailyWeather] {

        // Open-Meteo アーカイブ API（ERA5 再解析）
        // 最高/最低気温, 降水量合計, 日照時間(秒) を日次で取得
        // sunshine_duration(秒) は 3600 で割って時間に変換
        let startStr = DateFormatter.yyyyMMdd.string(from: from)
        let endStr   = DateFormatter.yyyyMMdd.string(from: to)

        // タイムゾーンはユーザー環境に合わせたいので "auto"
        let endpoint = "https://archive-api.open-meteo.com/v1/era5"
        let dailyParams = [
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_sum",
            "sunshine_duration"
        ].joined(separator: ",")

        var urlComp = URLComponents(string: endpoint)!
        urlComp.queryItems = [
            .init(name: "latitude", value: String(format: "%.6f", lat)),
            .init(name: "longitude", value: String(format: "%.6f", lon)),
            .init(name: "start_date", value: startStr),
            .init(name: "end_date", value: endStr),
            .init(name: "daily", value: dailyParams),
            .init(name: "timezone", value: "auto")
        ]

        guard let url = urlComp.url else {
            throw URLError(.badURL)
        }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OMDailyResponse.self, from: data)
        return mapOMDailyToModels(decoded)
    }

    // MARK: - Mapping

    /// Open-Meteo のレスポンスを `DailyWeather` 配列へ変換
    private static func mapOMDailyToModels(_ res: OMDailyResponse) -> [DailyWeather] {
        guard let daily = res.daily else { return [] }

        // Open-Meteo は「同じ長さの配列」を time / 各変数で返す想定
        let times = daily.time
        let tmaxs = daily.temperature_2m_max ?? Array(repeating: nil, count: times.count)
        let tmins = daily.temperature_2m_min ?? Array(repeating: nil, count: times.count)
        let rains = daily.precipitation_sum ?? Array(repeating: nil, count: times.count)
        let suns  = daily.sunshine_duration ?? Array(repeating: nil, count: times.count)

        var items: [DailyWeather] = []
        items.reserveCapacity(times.count)

        for i in 0..<times.count {
            let dayDate = DateFormatter.yyyyMMdd.date(from: times[i]) ?? Calendar.current.startOfDay(for: Date())

            let tMax = tmaxs[safe: i] ?? nil
            let tMin = tmins[safe: i] ?? nil
            let rain = rains[safe: i] ?? nil
            // sunshine_duration は秒 -> 時間
            let sunshineHours: Double?
            if let seconds = suns[safe: i], let s = seconds {
                sunshineHours = s / 3600.0
            } else {
                sunshineHours = nil
            }

            let item = DailyWeather(
                date: dayDate,
                tMax: tMax ?? nil,
                tMin: tMin ?? nil,
                sunshineHours: sunshineHours,
                precipitationMm: rain ?? nil
            )
            items.append(item)
        }

        // 念のため from→to 昇順に
        return items.sorted { $0.date < $1.date }
    }
}

// MARK: - Open-Meteo decode structs

/// Open-Meteo ERA5 アーカイブAPIの日次レスポンス
private struct OMDailyResponse: Decodable {
    let latitude: Double?
    let longitude: Double?
    let timezone: String?
    let daily: OMDailyBlock?
}

/// 日次配列ブロック
private struct OMDailyBlock: Decodable {
    let time: [String]                       // "yyyy-MM-dd"
    let temperature_2m_max: [Double?]?
    let temperature_2m_min: [Double?]?
    let precipitation_sum: [Double?]?        // mm/day
    let sunshine_duration: [Double?]?        // seconds/day
}

// MARK: - Helpers

private extension Array {
    /// out-of-range を安全に nil 返し
    subscript(safe index: Int) -> Element? {
        (indices ~= index) ? self[index] : nil
    }
}

