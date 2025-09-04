#if os(macOS)
import SwiftUI

struct ExportJSONCommands: Commands {
    // EnvironmentObject ではなく ObservedObject で受け取る
    @ObservedObject var store: DiaryStore

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("JSONを書き出す…") {
                JSONExporter.run(entries: store.entries)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift]) // ⌘⇧E
        }
    }
}
#endif
