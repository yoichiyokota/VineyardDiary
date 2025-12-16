//
//  Created by yoichi_yokota on 2025/12/16.
//


// Shared/ViewModels/EntryEditorViewModel.swift
// EntryEditorView用のビジネスロジック（iOS/macOS共通）

import Foundation
import SwiftUI
#if os(iOS)
import PhotosUI
#endif

/// EntryEditorViewのビジネスロジックを管理するViewModel
@MainActor
final class EntryEditorViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var date: Date = Date()
    @Published var block: String = ""
    @Published var varieties: [VarietyStageItem] = []
    @Published var isSpraying: Bool = false
    @Published var sprayTotalLiters: String = ""
    @Published var sprays: [SprayItem] = []
    @Published var workNotes: String = ""
    @Published var memo: String = ""
    @Published var workTimes: [WorkTime] = []
    @Published var volunteersText: String = ""
    @Published var photos: [String] = []
    @Published var photoCaptions: [String: String] = [:]
    
    // 気象データ（表示用）
    @Published var weatherMin: Double?
    @Published var weatherMax: Double?
    @Published var sunshineHours: Double?
    @Published var precipitationMm: Double?
    
    // MARK: - Private Properties
    
    private var originalEntry: DiaryEntry?
    private var entryID: UUID?
    
    // MARK: - Computed Properties
    
    var isEditing: Bool {
        originalEntry != nil
    }
    
    var temperatureLabel: String? {
        guard let tmax = weatherMax, let tmin = weatherMin else {
            return nil
        }
        return String(format: "最高 %.1f℃ / 最低 %.1f℃", tmax, tmin)
    }
    
    var sunshineLabel: String? {
        guard let sun = sunshineHours else { return nil }
        return String(format: "%.1fh", sun)
    }
    
    var rainLabel: String? {
        guard let rain = precipitationMm else { return nil }
        return String(format: "%.1fmm", rain)
    }
    
    // MARK: - Initialization
    
    func initialize(from entry: DiaryEntry?, settings: AppSettings) {
        if let entry = entry {
            // 編集モード
            loadFromEntry(entry)
        } else {
            // 新規作成モード
            setupNewEntry(settings: settings)
        }
    }
    
    private func loadFromEntry(_ entry: DiaryEntry) {
        originalEntry = entry
        entryID = entry.id
        
        date = entry.date
        block = entry.block
        varieties = entry.varieties
        isSpraying = entry.isSpraying
        sprayTotalLiters = entry.sprayTotalLiters
        sprays = entry.sprays
        workNotes = entry.workNotes
        memo = entry.memo
        workTimes = entry.workTimes
        volunteersText = entry.volunteers.joined(separator: ", ")
        photos = entry.photos
        photoCaptions = entry.photoCaptions
        
        weatherMin = entry.weatherMin
        weatherMax = entry.weatherMax
        sunshineHours = entry.sunshineHours
        precipitationMm = entry.precipitationMm
    }
    
    private func setupNewEntry(settings: AppSettings) {
        date = Date()
        block = settings.blocks.first?.name ?? ""
        varieties = [VarietyStageItem()]
        isSpraying = false
        sprayTotalLiters = ""
        sprays = []
        workNotes = ""
        memo = ""
        workTimes = []
        volunteersText = ""
        photos = []
        photoCaptions = [:]
        
        weatherMin = nil
        weatherMax = nil
        sunshineHours = nil
        precipitationMm = nil
    }
    
    // MARK: - Array Management
    
    func addVariety() {
        varieties.append(VarietyStageItem())
    }
    
    func removeVariety(at index: Int) {
        guard varieties.count > 1 else {
            varieties[0] = VarietyStageItem()
            return
        }
        varieties.remove(at: index)
    }
    
    func addSpray() {
        sprays.append(SprayItem())
    }
    
    func removeSpray(at index: Int) {
        sprays.remove(at: index)
    }
    
    func addWorkTime() {
        workTimes.append(WorkTime(start: Date(), end: Date()))
    }
    
    func removeWorkTime(at index: Int) {
        workTimes.remove(at: index)
    }
    
    func deletePhoto(_ name: String) {
        if let index = photos.firstIndex(of: name) {
            photos.remove(at: index)
        }
        photoCaptions[name] = nil
    }
    
    // MARK: - Photo Import (iOS)
    
    #if os(iOS)
    func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               !data.isEmpty {
                let name = "photo_\(UUID().uuidString).jpg"
                let url = URL.documentsDirectory.appendingPathComponent(name)
                
                do {
                    try data.write(to: url, options: .atomic)
                    await MainActor.run {
                        photos.append(name)
                    }
                } catch {
                    print("❌ write photo failed:", error)
                }
            }
        }
    }
    #endif
    
    // MARK: - Save
    
    func save(
        to store: DiaryStore,
        weather: DailyWeatherStore,
        settings: AppSettings
    ) async {
        // ボランティア氏名をパース
        let volunteers = parseVolunteers(from: volunteersText)
        
        // エントリを構築
        let entry = buildEntry(volunteers: volunteers)
        
        // ストアに保存
        if isEditing {
            store.updateEntry(entry)
        } else {
            store.addEntry(entry)
        }
        
        store.editingEntry = nil
        store.save()
        
        // 気象データを取得・反映
        await fetchAndApplyWeather(
            entry: entry,
            store: store,
            weather: weather,
            settings: settings
        )
    }
    
    private func parseVolunteers(from text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    private func buildEntry(volunteers: [String]) -> DiaryEntry {
        var entry = DiaryEntry(
            id: entryID ?? UUID(),
            date: date,
            block: block,
            varieties: varieties,
            isSpraying: isSpraying,
            sprayTotalLiters: sprayTotalLiters,
            sprays: sprays,
            workNotes: workNotes,
            memo: memo,
            workTimes: workTimes,
            volunteers: volunteers,
            photos: photos,
            photoCaptions: photoCaptions,
            weatherMin: weatherMin,
            weatherMax: weatherMax,
            sunshineHours: sunshineHours,
            precipitationMm: precipitationMm
        )
        
        return entry
    }
    
    private func fetchAndApplyWeather(
        entry: DiaryEntry,
        store: DiaryStore,
        weather: DailyWeatherStore,
        settings: AppSettings
    ) async {
        guard let block = settings.blocks.first(where: { $0.name == entry.block }),
              let lat = block.latitude,
              let lon = block.longitude else {
            return
        }
        
        let day = Calendar.current.startOfDay(for: entry.date)
        
        // キャッシュチェック
        if let cached = weather.get(block: block.name, date: day) {
            applyWeatherToEntry(cached, entry: entry, store: store)
            return
        }
        
        // API取得
        do {
            let items = try await WeatherService.fetchDailyRange(
                lat: lat,
                lon: lon,
                from: day,
                to: day
            )
            
            if let first = items.first {
                weather.set(block: block.name, item: first)
                weather.save()
                applyWeatherToEntry(first, entry: entry, store: store)
                store.save()
            }
        } catch {
            print("❌ weather fetch failed:", error)
        }
    }
    
    private func applyWeatherToEntry(
        _ w: DailyWeather,
        entry: DiaryEntry,
        store: DiaryStore
    ) {
        guard let index = store.entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        
        store.entries[index].weatherMin = w.tMin
        store.entries[index].weatherMax = w.tMax
        store.entries[index].sunshineHours = w.sunshineHours
        store.entries[index].precipitationMm = w.precipitationMm
    }
}

// MARK: - Validation

extension EntryEditorViewModel {
    
    /// エントリが保存可能な状態か
    var canSave: Bool {
        !block.isEmpty
    }
    
    /// 必須フィールドのバリデーション
    var validationErrors: [String] {
        var errors: [String] = []
        
        if block.isEmpty {
            errors.append("区画を選択してください")
        }
        
        return errors
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension EntryEditorViewModel {
    
    var debugDescription: String {
        """
        EntryEditorViewModel:
        - isEditing: \(isEditing)
        - date: \(date)
        - block: "\(block)"
        - varieties: \(varieties.count)
        - isSpraying: \(isSpraying)
        - photos: \(photos.count)
        """
    }
    
    func resetForTesting() {
        date = Date()
        block = ""
        varieties = []
        isSpraying = false
        sprays = []
        workNotes = ""
        memo = ""
        workTimes = []
        photos = []
        photoCaptions = [:]
        originalEntry = nil
        entryID = nil
    }
}
#endif
