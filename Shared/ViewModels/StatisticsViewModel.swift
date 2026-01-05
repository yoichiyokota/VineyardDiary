//
//  Created by yoichi_yokota on 2025/12/16.
//


// Shared/ViewModels/StatisticsViewModel.swift
// StatisticsView用のビジネスロジック（iOS/macOS共通）

import Foundation
import Combine

/// 統計画面のデータポイント
struct StatisticsDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double?
}

/// StatisticsViewのビジネスロジックを管理するViewModel
@MainActor
final class StatisticsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var selectedBlock: String = ""
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    // ホバー中の日付（グラフインタラクション用）
    @Published var hoverDateTemp: Date?
    @Published var hoverDateSun: Date?
    @Published var hoverDateRain: Date?
    @Published var hoverDateSunVar: Date?
    
    // MARK: - Dependencies
    
    private var store: DiaryStore?
    private var weather: DailyWeatherStore?
    
    // MARK: - Computed Properties
    
    /// 利用可能な年のリスト
    func availableYears(store: DiaryStore, weather: DailyWeatherStore) -> [Int] {
        var years = Set<Int>()
        
        if let dict = weather.data[selectedBlock] {
            for key in dict.keys {
                if let date = DateFormatters.yyyyMMdd.date(from: key) {
                    years.insert(Calendar.current.component(.year, from: date))
                }
            }
        }
        
        if years.isEmpty {
            let entryYears = store.entries
                .filter { $0.block == selectedBlock }
                .map { Calendar.current.component(.year, from: $0.date) }
            years.formUnion(entryYears)
        }
        
        if years.isEmpty {
            years.insert(Calendar.current.component(.year, from: Date()))
        }
        
        return Array(years).sorted()
    }
    
    /// 利用可能な区画のリスト
    func availableBlocks(settings: AppSettings) -> [String] {
        settings.blocks.map { $0.name }
    }
    
    // MARK: - Data Generation
    
    /// 日次気象データのマップを取得
    func dayMap(weather: DailyWeatherStore) -> [(Date, DailyWeather)] {
        guard let dict = weather.data[selectedBlock] else { return [] }
        
        let arr: [(Date, DailyWeather)] = dict.compactMap { (key, value) in
            if let date = DateFormatters.yyyyMMdd.date(from: key) {
                return (date, value)
            }
            return nil
        }
        
        let filtered = arr.filter {
            Calendar.current.component(.year, from: $0.0) == selectedYear
        }
        
        return filtered.sorted { $0.0 < $1.0 }
    }
    
    /// 最高気温データポイント
    func temperatureMaxPoints(weather: DailyWeatherStore) -> [StatisticsDataPoint] {
        dayMap(weather: weather).map {
            StatisticsDataPoint(date: $0.0, value: $0.1.tMax)
        }
    }
    
    /// 最低気温データポイント
    func temperatureMinPoints(weather: DailyWeatherStore) -> [StatisticsDataPoint] {
        dayMap(weather: weather).map {
            StatisticsDataPoint(date: $0.0, value: $0.1.tMin)
        }
    }
    
    /// 日照時間データポイント
    func sunshinePoints(weather: DailyWeatherStore) -> [StatisticsDataPoint] {
        dayMap(weather: weather).map {
            StatisticsDataPoint(date: $0.0, value: $0.1.sunshineHours)
        }
    }
    
    /// 降水量データポイント
    func precipitationPoints(weather: DailyWeatherStore) -> [StatisticsDataPoint] {
        dayMap(weather: weather).map {
            StatisticsDataPoint(date: $0.0, value: $0.1.precipitationMm)
        }
    }
    
    // MARK: - 品種別積算日照
    
    /// 品種別の積算日照時間シリーズ
    func cumulativeSunshineVarietySeries(
        store: DiaryStore,
        weather: DailyWeatherStore
    ) -> [String: [StatisticsDataPoint]] {
        let varieties = varietiesInYearBlock(store: store)
        let dm = dayMap(weather: weather)
        
        guard !dm.isEmpty else { return [:] }
        
        var result: [String: [StatisticsDataPoint]] = [:]
        
        for variety in varieties {
            guard let bloomDate = bloomDate(
                store: store,
                variety: variety
            ) else {
                continue
            }
            
            var sum: Double = 0
            var points: [StatisticsDataPoint] = []
            
            for (date, dailyWeather) in dm where date >= bloomDate {
                if let sun = dailyWeather.sunshineHours {
                    sum += sun
                }
                points.append(StatisticsDataPoint(date: date, value: sum))
            }
            
            if !points.isEmpty {
                result[variety] = points
            }
        }
        
        return result
    }
    
    /// 指定年・区画に登場する品種名
    private func varietiesInYearBlock(store: DiaryStore) -> [String] {
        let cal = Calendar.current
        let names = store.entries.compactMap { entry -> [String]? in
            guard entry.block == selectedBlock,
                  cal.component(.year, from: entry.date) == selectedYear else {
                return nil
            }
            return entry.varieties
                .map { $0.varietyName }
                .filter { !$0.isEmpty }
        }.flatMap { $0 }
        
        return Array(Set(names)).sorted()
    }
    
    /// 満開日（ステージコード23以上の最初の日付）
    private func bloomDate(
        store: DiaryStore,
        variety: String
    ) -> Date? {
        let cal = Calendar.current
        
        let candidates = store.entries.compactMap { entry -> Date? in
            guard entry.block == selectedBlock,
                  cal.component(.year, from: entry.date) == selectedYear else {
                return nil
            }
            
            for vs in entry.varieties where vs.varietyName == variety {
                if let code = stageCode(from: vs.stage), code >= 23 {
                    return cal.startOfDay(for: entry.date)
                }
            }
            return nil
        }
        
        return candidates.min()
    }
    
    /// ステージ文字列からコード番号を抽出
    private func stageCode(from stageText: String) -> Int? {
        let parts = stageText.split(separator: ":")
        if let first = parts.first,
           let value = Int(first.trimmingCharacters(in: .whitespaces)) {
            return value
        }
        return Int(stageText.trimmingCharacters(in: .whitespaces))
    }
    
    // MARK: - Hover Utilities
    
    /// 指定日付のデータポイント値を取得
    func valueOn(
        date: Date,
        from points: [StatisticsDataPoint]
    ) -> Double? {
        let day = Calendar.current.startOfDay(for: date)
        return points.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: day)
        })?.value
    }
    
    // MARK: - Date Domain
    
    /// X軸のドメイン範囲（年の1/1 〜 今日まで）
    func xDomainForYear() -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: selectedYear, month: 1, day: 1))!
        let endOfYear = cal.date(from: DateComponents(year: selectedYear, month: 12, day: 31))!
        let end = min(Date(), endOfYear)
        return start...end
    }
    
    /// X軸のドメイン範囲（4/1 〜 今日まで）
    func xDomainApr1ToToday(weather: DailyWeatherStore) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: selectedYear, month: 4, day: 1))!
        let lastData = dayMap(weather: weather).last?.0 ?? start
        let end = min(cal.startOfDay(for: Date()), lastData)
        
        // lowerBound > upperBound の場合は入れ替える
        if start > end {
            return end...start
        }
        return start...end
    }
    
    // MARK: - Initialization
    
    func initialize(
        store: DiaryStore,
        weather: DailyWeatherStore,
        settings: AppSettings
    ) {
        self.store = store
        self.weather = weather
        
        let blocks = availableBlocks(settings: settings)
        if selectedBlock.isEmpty || !blocks.contains(selectedBlock) {
            selectedBlock = blocks.first ?? ""
        }
        
        let years = availableYears(store: store, weather: weather)
        if !years.contains(selectedYear) {
            selectedYear = years.max() ?? Calendar.current.component(.year, from: Date())
        }
    }
}

// MARK: - Date Formatters

private enum DateFormatters {
    static let yyyyMMdd: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    static let monthDay: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "M/d"
        return df
    }()
}

// MARK: - Debug Helpers

#if DEBUG
extension StatisticsViewModel {
    var debugDescription: String {
        """
        StatisticsViewModel:
        - selectedBlock: "\(selectedBlock)"
        - selectedYear: \(selectedYear)
        """
    }
}
#endif
