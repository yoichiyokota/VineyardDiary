#if os(macOS)
import Foundation
import AppKit
import UniformTypeIdentifiers

struct SettingsExporter {
    static func run(blocks: [BlockSetting], varieties: [VarietySetting], stages: [StageSetting]) {
        let panel = NSSavePanel()
        panel.title = "設定を書き出す"
        panel.nameFieldStringValue = "VineyardSettings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            let payload = VineyardSettingsFile(blocks: blocks, varieties: varieties, stages: stages)
            do {
                let data = try JSONEncoder().encode(payload)
                try data.write(to: url) // options は省略でOK
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}
#endif
