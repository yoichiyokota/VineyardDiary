// Shared/Features/ThumbnailKit.swift
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 画像Data -> サムネイルJPEG Data（長辺 maxPixel、品質 quality）
/// 変換に失敗したら nil を返します。
func makeThumbnailJPEG(data: Data, maxPixel: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
    #if os(iOS)
    guard let img = UIImage(data: data) else { return nil }
    let w = img.size.width, h = img.size.height
    let scale = min(1, maxPixel / max(w, h))
    let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))

    // 既に小さければそのまま再エンコードだけ
    if scale >= 1 {
        return img.jpegData(compressionQuality: quality)
    }

    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    img.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return resized?.jpegData(compressionQuality: quality)

    #else
    guard let nsimg = NSImage(data: data) else { return nil }
    var rect = CGRect(origin: .zero, size: nsimg.size)
    let w = rect.width, h = rect.height
    let scale = min(1, maxPixel / max(w, h))
    let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))

    // NSImage -> CGImage
    guard let cgRep = nsimg.bestRepresentation(for: CGRect(origin: .zero, size: nsimg.size), context: nil, hints: nil) else { return nil }
    guard let cgImage = cgRep.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }

    // リサイズ
    guard let ctx = CGContext(
        data: nil,
        width: Int(newSize.width),
        height: Int(newSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
    guard let resizedCG = ctx.makeImage() else { return nil }

    // JPEGエンコード
    let dest = NSMutableData()
    guard let cgDest = CGImageDestinationCreateWithData(dest, AVFileType.jpeg as CFString, 1, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(cgDest, resizedCG, options as CFDictionary)
    guard CGImageDestinationFinalize(cgDest) else { return nil }
    return dest as Data
    #endif
}
