import Foundation

/// 設定（blocks）に基づいて日次気象を取得し、キャッシュへ反映してから
/// エントリ一覧の weather 表示を更新する共通関数。
@MainActor
func backfillDailyWeatherAndRefreshEntries(
    store: DiaryStore,
    weather: DailyWeatherStore
) async {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let year  = cal.component(.year, from: today)
    guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }

    // blocks は UI ストアから取得（呼び出し元は MainActor）
    let blocks = store.settings.blocks

    // ネットワーク取得は並列で（MainActor を外す）
    struct Batch { let block: String; let items: [DailyWeather] }
    var batches: [Batch] = []

    await withTaskGroup(of: Batch?.self) { group in
        for b in blocks {
            guard let lat = b.latitude, let lon = b.longitude else { continue }
            group.addTask {
                do {
                    let items = try await WeatherService.fetchDailyRange(
                        lat: lat, lon: lon, from: start, to: today
                    )
                    return Batch(block: b.name, items: items)
                } catch {
                    print("⚠️ iOS backfill failed for \(b.name):", error)
                    return nil
                }
            }
        }
        for await r in group { if let r { batches.append(r) } }
    }

    // キャッシュへ反映 → 一覧へ反映
    for batch in batches {
        for it in batch.items {
            weather.set(block: batch.block, item: it)
        }
    }
    weather.save()
    store.refreshEntriesWeatherFromCache(using: weather)
}
