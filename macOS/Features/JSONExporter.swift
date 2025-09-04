#if os(macOS)
import Foundation
import AppKit
import UniformTypeIdentifiers

struct JSONExporter {
    static func run(entries: [DiaryEntry]) {
        let panel = NSSavePanel()
        panel.title = "JSON エクスポート"
        panel.nameFieldStringValue = "VineyardDiary_Export.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            let file = VineyardDiaryFile(entries: entries)
            do {
                let data = try JSONEncoder().encode(file)
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
#endif
