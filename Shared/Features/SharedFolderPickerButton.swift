// Shared/Features/SharedFolderPickerButton.swift
import SwiftUI

#if os(macOS)
import AppKit

/// macOS: 共有フォルダを選んでブックマーク保存するボタン
struct SharedFolderPickerButton: View {
    /// 現在設定中の共有フォルダURL（表示用にオプション）
    @Binding var currentURL: URL?

    var body: some View {
        Button {
            pickFolder()
        } label: {
            Label("共有フォルダを設定…", systemImage: "folder.badge.plus")
        }
        .help("iCloud Drive 上の “VineyardDiaryShared” などを選んでください。")
    }

    @MainActor
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try SharedFolderBookmark.saveFolderURL(url)  // ← ここを最新APIに統一
                currentURL = url
                print("✅ 共有フォルダを保存: \(url.path)")
            } catch {
                print("❌ 共有フォルダの保存に失敗:", error)
            }
        }
    }
}

#endif

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
/// iOS: フォルダ内の「任意のファイル」を選ばせて、その親フォルダを共有フォルダとして保存するボタン
struct SharedFolderPickerButton: View {
    var onPicked: (URL?) -> Void

    @State private var showImporter = false

    var body: some View {
        Button {
            showImporter = true
        } label: {
            Label("フォルダで開く", systemImage: "folder")
        }
        // フォルダ直接選択は環境依存で落ちることがあるため、.item も許可して親フォルダを採用する
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { onPicked(nil); return }

                // フォルダ or ファイル どちらが来てもフォルダ URL に正規化
                let folderURL: URL
                if (try? picked.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    folderURL = picked
                } else {
                    folderURL = picked.deletingLastPathComponent()
                }

                // セキュリティスコープ確保（失敗しても続行はできるが念のため）
                let ok = folderURL.startAccessingSecurityScopedResource()
                defer { if ok { folderURL.stopAccessingSecurityScopedResource() } }

                // 共有フォルダのブックマークを保存（あなたの実装に合わせて呼び出し）
                do {
                    try SharedFolderBookmark.saveFolderURL(folderURL)
                    onPicked(folderURL)
                } catch {
                    print("saveFolderURL failed:", error)
                    onPicked(nil)
                }

            case .failure(let error):
                print("fileImporter error:", error)
                onPicked(nil)
            }
        }
    }
}
#endif
