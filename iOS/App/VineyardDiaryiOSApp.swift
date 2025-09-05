import SwiftUI

@main
struct VineyardDiaryiOSApp: App {
    @StateObject private var store = DiaryStore()
    @StateObject private var weather = DailyWeatherStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(weather)
            }
            // 起動時：共有取り込み → 天気ロード → バックフィル
            .task {
                await runStartupImportsAndBackfill(store: store, weather: weather)
            }
            // 復帰時も同様に（iOS 17+ の onChange 形式）
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await runStartupImportsAndBackfill(store: store, weather: weather) }
                }
            }
        }
    }
}

/// 起動/復帰時ルーチン：重い処理はBG、UI反映は MainActor
private func runStartupImportsAndBackfill(store: DiaryStore, weather: DailyWeatherStore) async {
    // 1) 共有パッケージ取り込み
    await importSharedPackage(into: store, weather: weather)

    // 2) 天気キャッシュ読込（UI系オブジェクトなので MainActor で）
    await MainActor.run { weather.load() }

    // 3) バックフィル（ネットワークは BG、反映は最後に Main）
    await backfillDailyWeatherIfNeeded(store: store, weather: weather)
}

/// 共有パッケージ取り込み
private func importSharedPackage(into store: DiaryStore, weather: DailyWeatherStore) async {
    do {
        try await SharedImporter.importAllIfConfigured(into: store, weather: weather)
    } catch {
        print("⚠️ SharedImporter failed:", error)
    }
}

/// 必要に応じて日次気象を補完（ネットワークは BG、反映は Main）
private func backfillDailyWeatherIfNeeded(store: DiaryStore, weather: DailyWeatherStore) async {
    // UI ストアから最低限の値を MainActor 上で取り出す
    let blocks: [BlockSetting] = await MainActor.run { store.settings.blocks }
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let year  = cal.component(.year, from: today)
    guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return }

    struct Batch { let block: String; let items: [DailyWeather] }
    var batches: [Batch] = []

    // ネットワークは並列
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
                    print("⚠️ backfill failed for \(b.name):", error)
                    return nil
                }
            }
        }
        for await r in group { if let r { batches.append(r) } }
    }

    // 反映は MainActor
    await MainActor.run {
        for batch in batches {
            for it in batch.items { weather.set(block: batch.block, item: it) }
        }
        weather.save()
        store.refreshEntriesWeatherFromCache(using: weather)
    }
}
