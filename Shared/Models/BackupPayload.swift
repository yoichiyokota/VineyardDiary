//
//  BackupPayload.swift
//  Vineyard Diary
//
//  Created by yoichi_yokota on 2025/09/25.
//


import Foundation

// バックアップの中身（iOS/macOS 共通で参照できる場所に置く）
struct BackupPayload: Codable {
    var settings: AppSettings
    var entries: [DiaryEntry]
    /// blockName -> dateISO(yyyy-MM-dd) -> DailyWeather
    var dailyWeather: [String: [String: DailyWeather]]
}