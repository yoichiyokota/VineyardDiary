#if os(macOS)
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
                .task {
                    // 起動時：キャッシュ読み込み → 今年分バックフィル（UIを塞がない）
                    weather.load()
                    Task.detached(priority: .utility) {
                        await backfillDailyWeatherAndRefreshEntries(store: store, weather: weather)
                    }
                }
        }
        .commands {
            CommandMenu("データ") {

                // 年初〜今日まで、全区画の気象データを再取得
                Button("今年の気象データを再取得（全区画）") {
                    Task.detached(priority: .utility) {
                        await backfillDailyWeatherAndRefreshEntries(store: store, weather: weather)
                    }
                }
                .keyboardShortcut("R", modifiers: [.command, .shift]) // ⌘⇧R

                // iOS 共有パッケージを書き出し
                Button("iOSと共有データを書き出し…") {
                    Task { await SharedPackageExporter.exportSharedPackageWithPanel(store: store, weather: weather) }
                }

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
                        } catch {
                            print("❌ バックアップ作成失敗:", error)
                        }
                    }
                }

                // バックアップから復元
                Button("バックアップから復元") {
                    Task { @MainActor in
                        do {
                            let payload = try BackupManager.importBackupWithPanel()
                            store.settings = payload.settings
                            store.entries  = payload.entries
                            weather.replaceAll(with: payload.dailyWeather)
                            store.save()
                            print("✅ 復元完了")
                        } catch {
                            print("❌ 復元失敗:", error)
                        }
                    }
                }

                Divider()
                
   
                // 既存の CSV エクスポート
                Button("CSVエクスポート") {
                    Task { @MainActor in
                        do {
                            let url = try CSVExporter.saveWithPanelFlatteningNewlines(entries: store.entries)
                            print("✅ CSV保存:", url.path)
                        } catch {
                            print("❌ CSV失敗:", error)
                        }
                    }
                }
                .keyboardShortcut("E", modifiers: [.command, .shift]) // ⌘⇧E
                
                // 追加: 設定だけ復元
                Button("バックアップから『設定だけ』復元") {
                    Task { @MainActor in
                        QuickRestoreSettings.restoreSettingsFromBackupWithPanel(store: store)
                    }
                }
                    
            }
        }

        // ここは "Settings" シーンと自作型 Settings の衝突を避けるために SwiftUI. を明示
        SwiftUI.Settings {
            SettingsRootView()
                .environmentObject(store)
                .environmentObject(weather)
                .frame(minWidth: 700, minHeight: 500)
                .padding()
        }
    }
}
#endif
