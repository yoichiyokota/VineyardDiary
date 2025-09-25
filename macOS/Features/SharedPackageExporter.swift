#if os(macOS)
import Foundation
import AppKit

/// 元画像から縮小 JPEG データを作成
fileprivate func makeThumbnailJPEG(
    from srcURL: URL,
    maxSize: CGSize = .init(width: 1200, height: 900), // お好みで
    quality: CGFloat = 0.7                              // 0.0〜1.0
) -> Data? {
    guard let img = NSImage(contentsOf: srcURL) else { return nil }
    let scaled = img.resizedToFit(maxSize: maxSize)
    return scaled.jpegData(compressionQuality: quality)
}

fileprivate extension NSImage {
    /// 最大サイズ内に収まるよう等比縮小
    func resizedToFit(maxSize: CGSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        let ratio = min(maxSize.width/size.width, maxSize.height/size.height, 1.0)
        let newSize = CGSize(width: floor(size.width * ratio), height: floor(size.height * ratio))
        let img = NSImage(size: newSize)
        img.lockFocus(); defer { img.unlockFocus() }
        draw(in: .init(origin: .zero, size: newSize),
             from: .init(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        return img
    }

    /// JPEG データ化（圧縮率指定）
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}

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

            // 4) Photos フォルダへ “サムネ化した JPEG” を保存
            let photosFolder = folder.appendingPathComponent("Photos", isDirectory: true)
            try FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)

            for name in Set(store.entries.flatMap { $0.photos }) {
                let src = URL.documentsDirectory.appendingPathComponent(name)
                let dst = photosFolder.appendingPathComponent(name) // 同名で OK（拡張子もそのまま）

                guard FileManager.default.fileExists(atPath: src.path) else { continue }

                // 既存があれば消す
                if FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.removeItem(at: dst)
                }

                // 縮小 JPEG を書き出し（失敗時はスキップ）
                if let jpg = makeThumbnailJPEG(from: src) {
                    try jpg.write(to: dst, options: Data.WritingOptions.atomic)
                } else {
                    // フォーマット不明などでサムネ化できなければ、そのままコピー（保険）
                    try? FileManager.default.copyItem(at: src, to: dst)
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
