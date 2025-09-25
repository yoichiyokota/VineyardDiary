// iOS/Features/SharedImporter.swift
#if os(iOS)
import Foundation

/// iOS：共有フォルダに設定があれば entries.json / settings.json / photos_index.json を読み込む
/// - 注意: 写真そのもの（Photos/*.jpg）はここでは一括ダウンロードしない
enum SharedImporter {
    /// 共有フォルダが設定されていれば、entries/settings/photos_index を取り込み
    /// - Returns: 取り込みを実施したら true（フォルダ未設定は false）
    @MainActor
    static func importAllIfConfigured(into store: DiaryStore,
                                      weather: DailyWeatherStore) async throws -> Bool {
        guard let folder = SharedFolderBookmark.loadFolderURL() else {
            print("ℹ️ 共有フォルダ未設定")
            return false
        }

        // セキュリティスコープ開始（iOSのみ有効）
        let didAccess = folder.beginSecurityScopedAccessIfNeeded()
        defer { if didAccess { folder.endSecurityScopedAccessIfNeeded() } }

        let fm = FileManager.default

        let entriesURL     = folder.appendingPathComponent("entries.json")
        let settingsURL    = folder.appendingPathComponent("settings.json")
        let photosIndexURL = folder.appendingPathComponent("photos_index.json")
        let photosDirURL   = folder.appendingPathComponent("Photos", isDirectory: true)

        // iCloud 管理下ならダウンロード要求だけ出す（存在しなくても安全）
        ensureDownloadedIfNeeded(at: entriesURL)
        ensureDownloadedIfNeeded(at: settingsURL)
        ensureDownloadedIfNeeded(at: photosIndexURL)
        if fm.fileExists(atPath: photosDirURL.path) {
            // ディレクトリ自体はOK。中身は必要時にダウンロードする方針。
        }

        // 軽く到達待ち（短いタイムアウト）
        waitUntilDownloaded(entriesURL, timeout: 2.0)
        waitUntilDownloaded(settingsURL, timeout: 2.0)
        waitUntilDownloaded(photosIndexURL, timeout: 2.0)

        // JSON 読み込み
        let decoder = JSONDecoder()

        // settings.json
        if let data = try? Data(contentsOf: settingsURL),
           let f = try? decoder.decode(VineyardSettingsFile.self, from: data) {
            store.settings.blocks    = f.blocks
            store.settings.varieties = f.varieties
            store.settings.stages    = f.stages
            // オプション項目（無ければ現行設定を温存）
            if let r = f.gddStartRule { store.settings.gddStartRule = r }
            if let m = f.gddMethod    { store.settings.gddMethod    = m }
        } else {
            print("⚠️ settings.json の読み込みに失敗（存在しない/未ダウンロード/形式不正）")
        }

        // entries.json
        if let data = try? Data(contentsOf: entriesURL),
           let file = try? decoder.decode(VineyardDiaryFile.self, from: data) {
            store.entries = file.entries
            
            // ← ここを追加：参照される写真だけ iOS ドキュメントへコピー
            if fm.fileExists(atPath: photosDirURL.path) {
                copyReferencedPhotosIfNeeded(from: photosDirURL, entries: store.entries)
            }
        } else {
            print("⚠️ entries.json の読み込みに失敗（存在しない/未ダウンロード/形式不正）")
        }

        // 写真インデックス（必須ではないので失敗しても致命的でない）
        if let data = try? Data(contentsOf: photosIndexURL) {
            // ここで必要に応じてインデックスを使う（今は読み捨て）
            print("ℹ️ photos_index.json 読み込み: \(data.count) bytes")
        }

        store.save() // ローカルへ反映
        return true
    }

    // MARK: - iCloud ヘルパ

    /// iCloud 上の項目ならダウンロード要求を出す
    private static func ensureDownloadedIfNeeded(at url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                          .ubiquitousItemDownloadingStatusKey])
            if values.isUbiquitousItem == true {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                // ここでは成功/失敗に深追いしない
            }
        } catch {
            // 失敗しても次の機会に拾えるので致命的ではない
            print("iCloud startDownloading failed for \(url.lastPathComponent):", error)
        }
    }

    /// ダウンロード完了（or 非 iCloud or 既に存在）を少しだけ待つ
    private static func waitUntilDownloaded(_ url: URL, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let vals = try url.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey,
                    .isRegularFileKey
                ])

                // 非 iCloud か、通常ファイルとして存在していれば終わり
                if vals.isUbiquitousItem != true { return }
                if vals.isRegularFile == true { return }

                // status が .current / .downloaded 相当なら終わり
                if let status = vals.ubiquitousItemDownloadingStatus {
                    if status == URLUbiquitousItemDownloadingStatus.current ||
                       status == URLUbiquitousItemDownloadingStatus.downloaded {
                        return
                    }
                }
            } catch {
                // まだ読み取れない → 少し待つ
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }
    
    // 参照されている写真（ファイル名配列）だけ、共有フォルダの Photos から
    // アプリの Documents へコピー（存在しなければ）。小容量サムネ前提で全量OK。
    @MainActor
    private static func copyReferencedPhotosIfNeeded(from photosDirURL: URL, entries: [DiaryEntry]) {
        let fm = FileManager.default
        let doc = URL.documentsDirectory

        // 参照されるファイル名（重複除去）
        let names = Array(Set(entries.flatMap { $0.photos }))

        for name in names {
            let src = photosDirURL.appendingPathComponent(name)
            let dst = doc.appendingPathComponent(name)

            // 既にローカルにあればスキップ
            if fm.fileExists(atPath: dst.path) { continue }

            // iCloud 管理下なら個別ファイルのダウンロードも要求
            ensureDownloadedIfNeeded(at: src)
            waitUntilDownloaded(src, timeout: 3.0) // 少し長めに待つ

            // まだ存在しなければコピーを試みる
            do {
                if fm.fileExists(atPath: src.path) {
                    try fm.copyItem(at: src, to: dst)
                } else {
                    // 共有側にファイルが無い（または未ダウンロード）の場合はスキップ
                    // 必要ならログ
                    // print("⚠️ photo missing in shared: \(name)")
                }
            } catch {
                print("⚠️ 写真コピー失敗 \(name):", error)
            }
        }
    }
}
#endif
