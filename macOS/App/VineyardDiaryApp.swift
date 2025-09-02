import SwiftUI

@main
struct VineyardDiaryApp: App {
    @StateObject private var store   = DiaryStore()
    @StateObject private var weather = DailyWeatherStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(weather)
                .task {    // .onAppear より確実
                    weather.load()
                    await backfillDailyWeatherAndRefreshEntries()
                }
        }
        .commands {
            CommandMenu("データ") {
                Button("今年の気象データを再取得（全区画）") {
                    Task { await backfillDailyWeatherAndRefreshEntries() }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
            
                // バックアップ作成
                Button("バックアップを作成") {
                    Task { @MainActor in
                        do {
                            let url = try BackupManager.exportBackupWithPanel(
                                settings: store.settings,
                                entries: store.entries,
                                dailyWeather: weather.data
                            )
                            print("✅ バックアップ保存:", url.path)
                        } catch { print("❌ バックアップ作成失敗:", error) }
                    }
                }

                Button("バックアップから復元") {
                    Task { @MainActor in
                        do {
                            let payload = try BackupManager.importBackupWithPanel()
                            store.settings = payload.settings
                            store.entries  = payload.entries
                            weather.replaceAll(with: payload.dailyWeather) // ← 先ほどのメソッド
                            store.save()
                            print("✅ 復元完了")
                        } catch { print("❌ 復元失敗:", error) }
                    }
                }

                Divider()

                Button("CSVエクスポート") {
                    Task { @MainActor in
                        do {
                            let url = try CSVExporter.saveWithPanelFlatteningNewlines(entries: store.entries)
                            print("✅ CSV保存:", url.path)
                        } catch { print("❌ CSV失敗:", error) }
                    }

                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsRootView()
                .environmentObject(store)
                .environmentObject(weather)
                .frame(minWidth: 700, minHeight: 500)
                .padding()
        }
    }

    /// 年初(1/1)〜今日までを各区画でバックフィルし、完了後に日記へ反映
    @MainActor
    private func backfillDailyWeatherAndRefreshEntries() async {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let year  = cal.component(.year, from: today)
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today

        for block in store.settings.blocks {
            guard let lat = block.latitude, let lon = block.longitude else {
                print("⚠️ \(block.name) は緯度経度未設定のためスキップ")
                continue
            }
            do {
                let items = try await WeatherService.fetchDailyRange(lat: lat, lon: lon, from: start, to: today)
                for it in items { weather.set(block: block.name, item: it) }
                print("✅ \(block.name) 取得 \(items.count)件")
            } catch {
                print("❌ \(block.name) 取得失敗:", error)
            }
        }
        weather.save()

        // 取得分を日記に反映
        store.refreshEntriesWeatherFromCache(using: weather)
    }
}
