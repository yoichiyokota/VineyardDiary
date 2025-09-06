#if os(macOS)
import Foundation
import AppKit

/// macOS: 設定（blocks/varieties/stages）だけを書き出す簡易エクスポータ
enum SettingsExporter {
    /// 保存ダイアログを出して JSON を書き出す
    static func exportSettingsWithPanel(store: DiaryStore) async {
        await MainActor.run {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.title = "設定を書き出し"
            panel.nameFieldStringValue = "settings.json"
            panel.allowedContentTypes = [.json]

            panel.begin { resp in
                guard resp == .OK, let url = panel.url else { return }
                do {
                    // いまは従来どおりの3フィールドのみ書き出す
                    let payload = VineyardSettingsFile(
                        blocks: store.settings.blocks,
                        varieties: store.settings.varieties,
                        stages: store.settings.stages,
                        gddStartRule: store.settings.gddStartRule,
                        gddMethod: store.settings.gddMethod
                    )
                    let data = try JSONEncoder().encode(payload)
                    // 明示的に options の型を与える（.atomic 推論エラー回避）
                    try data.write(to: url, options: Data.WritingOptions.atomic)
                    print("✅ settings.json exported:", url.path)
                } catch {
                    print("❌ settings export failed:", error)
                }
            }
        }
    }
}
#endif
