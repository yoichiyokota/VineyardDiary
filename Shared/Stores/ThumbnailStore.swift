// Shared/Stores/ThumbnailStore.swift
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 一覧用の軽量サムネイルを生成・ディスク/メモリにキャッシュする
final class ThumbnailStore: ObservableObject {

    // ===== macOS 実装 =====
    #if os(macOS)
    /// 一覧のサムネイル表示サイズ（必要に応じて調整）
    let targetSize = CGSize(width: 180, height: 135)

    private let cache = NSCache<NSString, NSImage>()
    private let folderURL: URL

    init() {
        // ~/Library/Caches/VineyardDiary/Thumbs 以下にサムネイルを書き出し
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        folderURL = cacheBase.appendingPathComponent("VineyardDiary/Thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    /// サムネイルを取得（無ければ生成）
    func thumbnail(for originalName: String) -> NSImage? {
        if let hit = cache.object(forKey: originalName as NSString) { return hit }

        let thumbURL = folderURL.appendingPathComponent("th_\(Int(targetSize.width))x\(Int(targetSize.height))_\(originalName)")
        if let img = NSImage(contentsOf: thumbURL) {
            cache.setObject(img, forKey: originalName as NSString)
            return img
        }

        // 元画像から生成（オートリリースプールで一時メモリを即解放）
        return autoreleasepool(invoking: { () -> NSImage? in
            let originalURL = URL.documentsDirectory.appendingPathComponent(originalName)
            guard let src = NSImage(contentsOf: originalURL) else { return nil }
            let scaled = src.resizedToFit(maxSize: targetSize)

            if let png = scaled.pngData() {
                try? png.write(to: thumbURL, options: .atomic)
            }
            cache.setObject(scaled, forKey: originalName as NSString)
            return scaled
        })
    }

    /// 明示的にメモリキャッシュを捨てたい場合に
    func purgeMemory() { cache.removeAllObjects() }

    // ===== iOS 実装 =====
    #else
    private let cache = NSCache<NSString, UIImage>()

    init() {}

    /// iOS は後で実装（まずはビルドを通すため nil を返す）
    func thumbnail(for fileName: String) -> UIImage? {
        // ここを後日、Documents から UIImage を作る実装に差し替え予定
        // 例：
        // let url = URL.documentsDirectory.appendingPathComponent(fileName)
        // if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
        //     cache.setObject(img, forKey: fileName as NSString)
        //     return img
        // }
        return nil
    }

    func purgeMemory() { cache.removeAllObjects() }
    #endif
}

// MARK: - NSImage helpers (macOSのみ)
#if os(macOS)
private extension NSImage {
    /// 最大サイズ内に収まるよう等比縮小
    func resizedToFit(maxSize: CGSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        let ratio = min(maxSize.width / size.width, maxSize.height / size.height, 1.0)
        let newSize = CGSize(width: floor(size.width * ratio), height: floor(size.height * ratio))

        let img = NSImage(size: newSize)
        img.lockFocus()
        defer { img.unlockFocus() }

        draw(in: .init(origin: .zero, size: newSize),
             from: .init(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        return img
    }

    /// PNGデータ化（AppKit）
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return data
    }
}
#endif
