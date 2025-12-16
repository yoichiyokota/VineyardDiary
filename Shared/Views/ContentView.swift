//  Created by yoichi_yokota on 2025/12/16.
//


// Shared/Views/ContentView.swift
// プラットフォーム振り分け用の統合ファイル

import SwiftUI

/// メインコンテンツビュー
/// - iOS/macOSで異なる実装を自動的に振り分けます
@MainActor
struct ContentView: View {
    var body: some View {
        #if os(iOS)
        ContentView_iOS()
        #elseif os(macOS)
        ContentView_macOS()
        #else
        // その他のプラットフォーム用フォールバック
        UnsupportedPlatformView()
        #endif
    }
}

// MARK: - 未対応プラットフォーム用

private struct UnsupportedPlatformView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("このプラットフォームは未対応です")
                .font(.headline)
            
            Text("iOS または macOS でご利用ください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("iOS") {
    ContentView()
        .environmentObject(DiaryStore())
        .environmentObject(DailyWeatherStore())
}

#if os(macOS)
#Preview("macOS") {
    ContentView()
        .environmentObject(DiaryStore())
        .environmentObject(DailyWeatherStore())
        .frame(width: 1000, height: 700)
}
#endif
