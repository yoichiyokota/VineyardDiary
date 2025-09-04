#if os(iOS)
import SwiftUI

@main
struct VineyardDiaryiOSApp: App {
    @StateObject var store = DiaryStore()
    @StateObject var weather = DailyWeatherStore()
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
                    .navigationTitle("Vineyard Diary")
            }
            .environmentObject(store)
            .environmentObject(weather)
            .task {
                // 設定と日記データのロード（アプリ独自の保存場所から）
                store.load()
                weather.load()
            }
        }
    }
}
#endif
