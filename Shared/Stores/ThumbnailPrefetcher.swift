//
//  ThumbnailPrefetcher.swift
//  Vineyard Diary
//
//  Created by yoichi_yokota on 2025/09/05.
//


// ThumbnailPrefetcher.swift （新規／Shared配下でもOK）
#if os(iOS)

import Foundation
import UIKit
import ImageIO
import MobileCoreServices

actor ThumbnailPrefetcher {
    static let shared = ThumbnailPrefetcher()

    private let cache = NSCache<NSString, UIImage>()
    private let semaphore = AsyncSemaphore(value: 2)
    private var warming = false

    func warmUpThumbnailsIfNeeded(from folder: URL) async {
        guard !warming else { return }
        warming = true
        defer { warming = false }

        let photosDir = folder.appendingPathComponent("Photos", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: photosDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // ここでは参照だけ（読み込まない）→ iCloud ダウンロード要求を出さない
        for case let fileURL as URL in enumerator {
            if cache.object(forKey: fileURL.path as NSString) != nil { continue }
        }
    }

    func thumbnail(for url: URL, maxPixel: CGFloat = 300) async -> UIImage? {
        if let img = cache.object(forKey: url.path as NSString) { return img }

        await semaphore.wait()
        // defer 内で await は使えない → Task 経由で非同期に signal
        defer { Task { await semaphore.signal() } }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgimg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let ui = UIImage(cgImage: cgimg)
        cache.setObject(ui, forKey: url.path as NSString)
        return ui
    }
}

/// シンプル async セマフォ
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.value = value }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func signal() async {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
#endif
