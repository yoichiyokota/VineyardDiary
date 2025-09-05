#if os(macOS)
import Foundation
import AppKit

enum SharedPackageExporter {
    /// iCloud Drive 等のフォルダをユーザに選ばせ、そこへ一括書き出し
    @MainActor
    static func exportSharedPackageWithPanel(store: DiaryStore, weather: DailyWeatherStore) async {
        // フォルダ選択
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "iOS と共有するフォルダを選択してください（空でも既存でも可）"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            // 1) settings.json
            let settingsPayload = VineyardSettingsFile(
                blocks: store.settings.blocks,
                varieties: store.settings.varieties,
                stages: store.settings.stages
            )
            let settingsURL = folder.appendingPathComponent("settings.json")
            try JSONEncoder().encode(settingsPayload).write(to: settingsURL, options: .atomic)

            // 2) entries.json
            let entriesPayload = VineyardDiaryFile(entries: store.entries)
            let entriesURL = folder.appendingPathComponent("entries.json")
            try JSONEncoder().encode(entriesPayload).write(to: entriesURL, options: .atomic)

            // 3) photos_index.json（参照名と簡易メタ）
            let index = PhotosIndex(index: store.entries.flatMap { e in
                e.photos.map { PhotosIndex.Item(fileName: $0,
                                                caption: e.photoCaptions[$0] ?? "",
                                                usedInEntryID: e.id.uuidString) }
            })
            let photosIndexURL = folder.appendingPathComponent("photos_index.json")
            try JSONEncoder().encode(index).write(to: photosIndexURL, options: .atomic)

            // 4) Photos フォルダへ実ファイルをコピー（なければ作成）
            let photosFolder = folder.appendingPathComponent("Photos", isDirectory: true)
            try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)

            for name in Set(store.entries.flatMap { $0.photos }) {
                let src = URL.documentsDirectory.appendingPathComponent(name)
                let dst = photosFolder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path) {
                    if FileManager.default.fileExists(atPath: dst.path) {
                        try FileManager.default.removeItem(at: dst)
                    }
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }

            // 共有フォルダのブックマーク保存（次回以降 iOS で参照可能）
            try SharedFolderBookmark.saveFolderURL(folder)
            print("✅ 共有パッケージ書き出し完了:", folder.path)

        } catch {
            print("❌ 共有パッケージ書き出し失敗:", error)
        }
    }
}
#endif
