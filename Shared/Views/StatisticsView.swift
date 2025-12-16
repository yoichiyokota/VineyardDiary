// Shared/Views/StatisticsView.swift
// プラットフォーム振り分け用の統合ファイル

import SwiftUI

/// 統計ビュー
/// - iOS/macOSで異なる実装を自動的に振り分けます
@MainActor
struct StatisticsView: View {
    var body: some View {
        #if os(iOS)
        StatisticsView_iOS()
        #elseif os(macOS)
        StatisticsView_macOS()
        #else
        UnsupportedStatisticsView()
        #endif
    }
}

// MARK: - 未対応プラットフォーム用

private struct UnsupportedStatisticsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("統計機能はこのプラットフォームでは利用できません")
                .font(.headline)
            
            Text("iOS または macOS でご利用ください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("iOS") {
    NavigationStack {
        StatisticsView()
            .environmentObject(DiaryStore())
            .environmentObject(DailyWeatherStore())
    }
}

#if os(macOS)
#Preview("macOS") {
    StatisticsView()
        .environmentObject(DiaryStore())
        .environmentObject(DailyWeatherStore())
        .frame(width: 1100, height: 760)
}
#endif
#endif

