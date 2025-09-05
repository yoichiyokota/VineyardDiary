// iOS/Features/SharedImporter.swift
#if os(iOS)

import Foundation

// MARK: - iCloud ヘルパ

/// iCloud のダウンロード状態を見て、必要なら開始だけして“今回はスキップ”
@discardableResult
private func ensureLocalFileIfPossible(_ url: URL) throws -> Bool {
    let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey
    ]
    let rv = try url.resourceValues(forKeys: keys)

    // iCloud 管理下でない → そのまま使える
    guard rv.isUbiquitousItem == true else { return true }

    // ダウンロード状況（← “Key” ではなく値プロパティ）
    let status = rv.ubiquitousItemDownloadingStatus   // String?（"current" / "downloaded" / "notDownloaded"）
    switch status {
    case URLUbiquitousItemDownloadingStatus.current,
         URLUbiquitousItemDownloadingStatus.downloaded:
        return true
    default:
        // まだ来ていない → ダウンロードだけ要求して今回は諦める
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return false
    }
}

/// iCloud 上の項目ならダウンロード要求を出す（失敗しても致命的ではない）
private func ensureDownloadedIfNeeded(at url: URL) {
    do {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    } catch {
        print("iCloud startDownloading failed:", error)
    }
}

/// ダウンロード完了（or 非 iCloud / 既に存在）を少しだけ待つ
private func waitUntilDownloaded(_ url: URL, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        do {
            let vals = try url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .isUbiquitousItemKey,
                .isRegularFileKey
            ])
            // 既にローカル or 非 iCloud なら抜ける
            if vals.isUbiquitousItem != true { return }
            let status = vals.ubiquitousItemDownloadingStatus // ← 値プロパティ
            if status == URLUbiquitousItemDownloadingStatus.current ||
               status == URLUbiquitousItemDownloadingStatus.downloaded {
                return
            }
            if FileManager.default.fileExists(atPath: url.path) { return }
        } catch {
            // まだ取得できない → 少し待って再試行
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
}

// MARK: - 共有パッケージ取り込み

/// iOS：共有フォルダに設定があれば entries.json / settings.json / photos_index.json を読み込む
/// - 写真そのもの（Photos/xxx.jpg）は一括ダウンロードしない
enum SharedImporter {
    /// 共有フォルダが設定されていれば、entries/settings/photos_index を取り込み
    @MainActor
    static func importAllIfConfigured(into store: DiaryStore, weather: DailyWeatherStore) async throws -> Bool {
        guard let folder = SharedFolderBookmark.loadFolderURL() else {
            print("ℹ️ 共有フォルダ未設定")
            return false
        }

        // iOS: セキュリティスコープ開始/終了（macOS は no-op）
        let started = folder.beginSecurityScopedAccessIfNeeded()
        defer { if started { folder.endSecurityScopedAccessIfNeeded() } }

        let fm = FileManager.default
        let entriesURL     = folder.appendingPathComponent("entries.json")
        let settingsURL    = folder.appendingPathComponent("settings.json")
        let photosIndexURL = folder.appendingPathComponent("photos_index.json")
        let photosDirURL   = folder.appendingPathComponent("Photos", isDirectory: true)

        // まずダウンロード要求だけ出す（存在しなくても安全）
        ensureDownloadedIfNeeded(at: entriesURL)
        ensureDownloadedIfNeeded(at: settingsURL)
        ensureDownloadedIfNeeded(at: photosIndexURL)
        if fm.fileExists(atPath: photosDirURL.path) {
            // ディレクトリの存在確認のみ（中身の写真は必要時に個別ダウンロード）
        }

        // 短時間だけ待機（UI をブロックしないよう必要最小限）
        waitUntilDownloaded(entriesURL, timeout: 2.0)
        waitUntilDownloaded(settingsURL, timeout: 2.0)
        waitUntilDownloaded(photosIndexURL, timeout: 1.0)

        // 読み込み（取れなければログを出しつつ継続）
        let decoder = JSONDecoder()

        do {
            if try ensureLocalFileIfPossible(settingsURL),
               let data = try? Data(contentsOf: settingsURL) {
                if let f = try? decoder.decode(VineyardSettingsFile.self, from: data) {
                    store.settings.blocks    = f.blocks
                    store.settings.varieties = f.varieties
                    store.settings.stages    = f.stages
                } else {
                    print("⚠️ settings.json のデコードに失敗")
                }
            } else {
                print("⚠️ settings.json が未ダウンロードのためスキップ")
            }
        }

        do {
            if try ensureLocalFileIfPossible(entriesURL),
               let data = try? Data(contentsOf: entriesURL) {
                if let file = try? decoder.decode(VineyardDiaryFile.self, from: data) {
                    store.entries = file.entries
                } else {
                    print("⚠️ entries.json のデコードに失敗")
                }
            } else {
                print("⚠️ entries.json が未ダウンロードのためスキップ")
            }
        }

        // 写真インデックス（必須ではない）
        _ = try? ensureLocalFileIfPossible(photosIndexURL)
        // 必要なら data = try? Data(contentsOf: photosIndexURL) で内容を利用

        store.save() // ローカルへ反映
        return true
    }
}

#endif
