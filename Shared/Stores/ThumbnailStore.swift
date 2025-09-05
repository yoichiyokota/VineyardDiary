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

    /// サムネイル（PlatformImage）を取得（無ければ生成）
    func thumbnail(for originalName: String) -> PlatformImage? {
        if let hit = cache.object(forKey: originalName as NSString) { return hit }

        let thName = "th_\(Int(targetSize.width))x\(Int(targetSize.height))_\(originalName)"
        let thumbURL = folderURL.appendingPathComponent(thName)

        // ディスクキャッシュ
        #if os(macOS)
        if let img = NSImage(contentsOf: thumbURL) {
            cache.setObject(img, forKey: originalName as NSString)
            return img
        }
        #else
        if let data = try? Data(contentsOf: thumbURL), let img = UIImage(data: data) {
            cache.setObject(img, forKey: originalName as NSString)
            return img
        }
        #endif

        // オリジナルから生成
        let originalURL = URL.documentsDirectory.appendingPathComponent(originalName)
        #if os(macOS)
        guard let src = NSImage(contentsOf: originalURL) else { return nil }
        let scaled = src.resizedToFit(maxSize: targetSize)
        if let png = scaled.pngData() {
            try? png.write(to: thumbURL, options: .atomic)
        }
        cache.setObject(scaled, forKey: originalName as NSString)
        return scaled
        #else
        guard let src = UIImage(contentsOfFile: originalURL.path) else { return nil }
        let scaled = src.resizedToFit(maxSize: targetSize)
        if let png = scaled.pngData() {
            try? png.write(to: thumbURL, options: .atomic)
        }
        cache.setObject(scaled, forKey: originalName as NSString)
        return scaled
        #endif
    }

    /// 明示的にメモリキャッシュを破棄
    func purgeMemory() { cache.removeAllObjects() }
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
