import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// 復元モード
enum RestoreMode {
    case all           // 設定 + 日記 + 気象を全置換
    case settingsOnly  // 設定のみ適用（エントリ・気象は触らない）
}

// MARK: - DiaryStore への適用（必要最低限）
extension DiaryStore {
    /// 設定 + 日記をバックアップで全置換
    func applyBackupAll(_ payload: BackupPayload) throws {
        self.settings = payload.settings
        self.entries  = payload.entries
        self.save()
    }

    /// 設定だけ適用（エントリは維持）
    func applyBackupSettingsOnly(_ payload: BackupPayload) throws {
        self.settings = payload.settings
        self.save()
    }
}

// MARK: - DailyWeatherStore への適用
extension DailyWeatherStore {
    /// バックアップの気象データで全置換
    func applyBackupAllWeather(_ weatherMap: [String : [String : DailyWeather]]) {
        // 置換 → 保存（replaceAll は提示実装に準拠）
        self.replaceAll(with: weatherMap)
        // 必要に応じて読み直し
        self.load()
    }
}

// MARK: - コア復元ロジック（UI抜き）
@MainActor
func restore(from payload: BackupPayload,
             mode: RestoreMode,
             store: DiaryStore,
             weather: DailyWeatherStore) async {
    switch mode {
    case .all:
        do {
            try store.applyBackupAll(payload)
            weather.applyBackupAllWeather(payload.dailyWeather)
            // 互換・整合（欠損があれば埋め、統計に反映）
            await backfillDailyWeatherAndRefreshEntries(store: store, weather: weather)
        } catch {
            #if os(macOS)
            showErrorAlert(title: "復元（全データ）に失敗", error: error)
            #else
            print("restore all failed:", error)
            #endif
        }

    case .settingsOnly:
        do {
            try store.applyBackupSettingsOnly(payload)
            // 気象は触らない。最低限の再読み込みだけ（必要に応じて）。
            weather.load()
        } catch {
            #if os(macOS)
            showErrorAlert(title: "復元（設定だけ）に失敗", error: error)
            #else
            print("restore settings-only failed:", error)
            #endif
        }
    }
}

#if os(macOS)
// MARK: - macOS: パネル + モード選択 UI 付きのユーティリティ
enum BackupRestoreUI {

    /// パネルを出して復元（全部/設定だけ）を選ばせて実行
    @MainActor
    static func runUnifiedRestore(store: DiaryStore, weather: DailyWeatherStore) {
        do {
            // 1) バックアップを選択（.vydbackup）
            let payload = try BackupManager.importBackupWithPanel()

            // 2) モード選択
            let alert = NSAlert()
            alert.messageText = "バックアップから復元"
            alert.informativeText = "復元する対象を選択してください。"
            alert.addButton(withTitle: "全データを復元")   // first
            alert.addButton(withTitle: "設定だけを復元")   // second
            alert.addButton(withTitle: "キャンセル")      // third

            let resp = alert.runModal()
            switch resp {
            case .alertFirstButtonReturn:
                Task { await restore(from: payload, mode: .all,          store: store, weather: weather) }
            case .alertSecondButtonReturn:
                Task { await restore(from: payload, mode: .settingsOnly, store: store, weather: weather) }
            default:
                return
            }
        } catch {
            showErrorAlert(title: "バックアップ読み込みに失敗", error: error)
        }
    }
}

// エラーダイアログ
@MainActor
private func showErrorAlert(title: String, error: Error) {
    let a = NSAlert()
    a.alertStyle = .warning
    a.messageText = title
    a.informativeText = error.localizedDescription
    a.addButton(withTitle: "OK")
    a.runModal()
}
#endif

// MARK: - ISO yyyy-MM-dd（BackupPayload.dailyWeather と互換のため）
//extension DateFormatter {
//    static let yyyyMMdd: DateFormatter = {
//        let f = DateFormatter()
//        f.calendar = Calendar(identifier: .gregorian)
//        f.locale = Locale(identifier: "en_US_POSIX")
//        f.timeZone = TimeZone(secondsFromGMT: 0)
//        f.dateFormat = "yyyy-MM-dd"
//        return f
//}()
//}
