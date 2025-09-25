// Shared/Stores/ThumbnailStore.swift
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 一覧/編集で使う軽量サムネイルのキャッシュ
final class ThumbnailStore: ObservableObject {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif

    /// 一覧のサムネイル表示サイズ（必要に応じて調整）
    let targetSize = CGSize(width: 180, height: 135)

    private let folderURL: URL

    #if os(macOS)
    private let cache = NSCache<NSString, NSImage>()
    #else
    private let cache = NSCache<NSString, UIImage>()
    #endif

    init() {
        // ~/Library/Caches/VineyardDiary/Thumbs 以下にサムネイルを書き出し
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        folderURL = cacheBase.appendingPathComponent("VineyardDiary/Thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// サムネイル（PlatformImage）を取得（無ければ生成）
    /// - Parameter originalName: 元画像の **はず** のファイル名だが、
    ///   *_thumb / -150x150 等のサムネ名が渡ってきても OK。内部で元名へ正規化する。
    func thumbnail(for originalName: String) -> PlatformImage? {
        // 1) どんな名前が来ても「元画像名」に正規化
        let baseName = normalizedOriginalName(originalName)

        // 2) メモリキャッシュ
        if let hit = cache.object(forKey: baseName as NSString) { return hit }

        // 3) ディスクキャッシュ（ファイル名は baseName を使って固定化）
        let thName = "th_\(Int(targetSize.width))x\(Int(targetSize.height))_\(baseName)"
        let thumbURL = folderURL.appendingPathComponent(thName)

        #if os(macOS)
        if let img = NSImage(contentsOf: thumbURL) {
            cache.setObject(img, forKey: baseName as NSString)
            return img
        }
        #else
        if let data = try? Data(contentsOf: thumbURL), let img = UIImage(data: data) {
            cache.setObject(img, forKey: baseName as NSString)
            return img
        }
        #endif

        // 4) オリジナルから生成（Documents 配下、正規化後のパス）
        let originalURL = URL.documentsDirectory.appendingPathComponent(baseName)

        #if os(macOS)
        guard let src = NSImage(contentsOf: originalURL) else { return nil }
        let scaled = src.resizedToFit(maxSize: targetSize)
        if let png = scaled.pngData() {
            try? png.write(to: thumbURL, options: .atomic)
        }
        cache.setObject(scaled, forKey: baseName as NSString)
        return scaled
        #else
        guard let src = UIImage(contentsOfFile: originalURL.path) else { return nil }
        let scaled = src.resizedToFit(maxSize: targetSize)
        if let png = scaled.pngData() {
            try? png.write(to: thumbURL, options: .atomic)
        }
        cache.setObject(scaled, forKey: baseName as NSString)
        return scaled
        #endif
    }

    /// 明示的にメモリキャッシュを破棄
    func purgeMemory() { cache.removeAllObjects() }

    // MARK: - Normalization

    /// entry.photos 内に混在しがちな「サムネ名・サイズ付き名」を
    /// 1つの“元画像名”に収束させる（拡張子は保持）
    ///
    /// 例:
    ///   "IMG_0012_thumb.jpg"   -> "IMG_0012.jpg"
    ///   "IMG-0012-thumb.PNG"   -> "IMG-0012.PNG"
    ///   "foo.thumb.jpeg"       -> "foo.jpeg"
    ///   "bar-150x150.png"      -> "bar.png"
    ///   "thumbs/IMG_9.jpg"     -> "IMG_9.jpg"
    private func normalizedOriginalName(_ name: String) -> String {
        // パス区切りの最後の要素だけにする
        var last = name.split(separator: "/").last.map(String.init) ?? name
        // 大文字拡張子に引っ張られないよう lowercased で判定しつつ、拡張子自体は保持
        let lower = last.lowercased()

        // 拡張子を保持
        let ext: String
        if let dot = last.lastIndex(of: ".") {
            ext = String(last[dot...]) // 例: ".jpg"
            last = String(last[..<dot]) // ベース名
        } else {
            ext = ""
        }

        var base = lower
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }

        // 1) サムネトークンの除去
        //    *_thumb / -thumb / .thumb（拡張子の前）
        base = base
            .replacingOccurrences(of: "_thumb", with: "")
            .replacingOccurrences(of: "-thumb", with: "")
            .replacingOccurrences(of: ".thumb", with: "")

        // 2) サイズサフィックスの除去（WordPress系: -123x456）
        base = base.replacingOccurrences(of: #"-\d{2,4}x\d{2,4}$"#,
                                         with: "",
                                         options: .regularExpression)

        // 3) フォルダ名が thumb/ thumbs/ の場合（既に分解しているので無視でOK）

        // 元の大文字小文字は気にしない方針。最終名は base + 元拡張子
        return base + ext.lowercased()
    }
}

// MARK: - Platform helpers

#if os(macOS)
// AppKit
private extension NSImage {
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
    /// PNG化
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data
    }
}
#else
// UIKit
private extension UIImage {
    /// 最大サイズ内に収まるよう等比縮小
    func resizedToFit(maxSize: CGSize) -> UIImage {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return self }
        let ratio = min(maxSize.width/w, maxSize.height/h, 1.0)
        let newSize = CGSize(width: floor(w*ratio), height: floor(h*ratio))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
