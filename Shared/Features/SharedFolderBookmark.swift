// Shared/Features/SharedFolderBookmark.swift
import Foundation

enum SharedFolderBookmark {
    private static let defaultsKey = "SharedFolderURLBookmark"

    static func saveFolderURL(_ url: URL) throws {
        if let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir != true {
            throw NSError(domain: "SharedFolderBookmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "URL is not a folder"])
        }

        // 可能なら scope を開始（iOS でも true が返ることがある）
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        #if os(macOS)
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func loadFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var stale = false
        do {
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
            if stale { try saveFolderURL(url) }
            return url
        } catch {
            print("resolve bookmark failed:", error)
            return nil
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// 参照時に必要なら security-scope を開始/終了する薄いヘルパ
extension URL {
    /// iOS/macOS 共通：セキュリティスコープを開始（macOS でも true が返る）
    @discardableResult
    func beginSecurityScopedAccessIfNeeded() -> Bool {
        return self.startAccessingSecurityScopedResource()
    }

    /// セキュリティスコープ終了
    func endSecurityScopedAccessIfNeeded() {
        self.stopAccessingSecurityScopedResource()
    }
}
