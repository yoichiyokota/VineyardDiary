//
//  QuickRestoreSettings.swift
//  Vineyard Diary
//
//  Created by yoichi_yokota on 2025/09/05.
//


// macOS/Features/QuickRestoreSettings.swift
#if os(macOS)
import SwiftUI

enum QuickRestoreSettings {
    /// バックアップから「設定だけ」復元する（entries/dailyWeather は触らない）
    @MainActor
    static func restoreSettingsFromBackupWithPanel(store: DiaryStore) {
        do {
            let payload = try BackupManager.importBackupWithPanel()
            store.settings = payload.settings
            store.saveSettings()
            print("✅ 設定だけ復元完了")
        } catch {
            print("❌ 設定だけ復元失敗:", error)
        }
    }
}
#endif