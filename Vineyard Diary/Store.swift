import Foundation
import SwiftUI

@MainActor
final class DiaryStore: ObservableObject {
    @Published var entries: [DiaryEntry] = []
    @Published var settings = AppSettings()
    @Published var editingEntry: DiaryEntry?

    private let entriesURL  = URL.documentsDirectory.appendingPathComponent("diary_entries.json")
    private let settingsURL = URL.documentsDirectory.appendingPathComponent("settings.json")

    init() {
        load()
        loadSettings()
    }

    // MARK: - CRUD
    func addEntry(_ entry: DiaryEntry) {
        entries.append(entry)
        save()
    }

    func updateEntry(_ entry: DiaryEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            save()
        }
    }

    func deleteEntry(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    // MARK: - 永続化
    func save() {
        do {
            let enc = JSONEncoder()
            let raw = try enc.encode(entries)
            try raw.write(to: entriesURL, options: .atomic)
        } catch {
            print("エントリ保存失敗:", error)
        }
    }

    func load() {
        do {
            let raw = try Data(contentsOf: entriesURL)
            let dec = JSONDecoder()
            self.entries = try dec.decode([DiaryEntry].self, from: raw)
        } catch {
            self.entries = []
        }
    }

    func saveSettings() {
        do {
            let enc = JSONEncoder()
            let raw = try enc.encode(settings)
            try raw.write(to: settingsURL, options: .atomic)
        } catch {
            print("設定保存失敗:", error)
        }
    }

    func loadSettings() {
        do {
            let raw = try Data(contentsOf: settingsURL)
            let dec = JSONDecoder()
            self.settings = try dec.decode(AppSettings.self, from: raw)
        } catch {
            self.settings = AppSettings()
        }
    }

    // MARK: - ステージコードのパースと判定
    /// "23: 満開期" → 23 を返す。数値化できなければ nil
    func stageCode(from stageString: String) -> Int? {
        let head = stageString.split(separator: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return Int(head)
    }

    /// ステージが 23 以上（満開〜収穫期等）かどうか
    func isStageAtLeast23(_ stageString: String) -> Bool {
        guard let code = stageCode(from: stageString) else { return false }
        return code >= 23
    }

    // MARK: - 直近ステージ取得（エディタの初期値用）
    /// 直近の成長ステージ（同じ区画・品種で、指定日より前で最後に記録した値）を返す
    func previousStage(block: String, variety: String, before date: Date) -> String? {
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: date)

        // 同じ区画・品種、かつ対象日より前
        let candidates = entries
            .filter { $0.block == block && cal.startOfDay(for: $0.date) < targetDay }
            .sorted { $0.date > $1.date } // 近いものから

        for e in candidates {
            if let found = e.varieties.first(where: { $0.varietyName == variety })?.stage,
               !found.isEmpty {
                return found
            }
        }
        return nil
    }

    /// 直近のステージが「23以上」のものだけ欲しい場合（必要ならこちらを使用）
    func previousStageAtLeast23(block: String, variety: String, before date: Date) -> String? {
        let cal = Calendar.current
        let targetDay = cal.startOfDay(for: date)

        let candidates = entries
            .filter { $0.block == block && cal.startOfDay(for: $0.date) < targetDay }
            .sorted { $0.date > $1.date }

        for e in candidates {
            if let s = e.varieties.first(where: { $0.varietyName == variety })?.stage,
               !s.isEmpty,
               isStageAtLeast23(s) {
                return s
            }
        }
        return nil
    }

    // MARK: - 満開日（ステージ23以上の最初の日）をブロック×年で検索
    /// 指定ブロック・年において、**ステージコードが 23 以上**の最初の日付を返す。
    /// どの品種でも 23 以上があれば、その日を「満開日」とみなす。
    func bloomDate(block: String, year: Int) -> Date? {
        let cal = Calendar.current

        // 対象年＆ブロックのみ抽出して、古い順に
        let inYear = entries
            .filter { $0.block == block && cal.component(.year, from: $0.date) == year }
            .sorted { $0.date < $1.date }

        for e in inYear {
            // いずれかの品種で 23 以上があれば、その日を満開日として返す
            if e.varieties.contains(where: { vs in
                isStageAtLeast23(vs.stage)
            }) {
                return cal.startOfDay(for: e.date)
            }
        }
        return nil
    }

    // MARK: - バックグラウンド気象を日記へ反映
    /// BGキャッシュ（DailyWeatherStore）から、各日記の 気温/日照 を更新
    func refreshEntriesWeatherFromCache(using weather: DailyWeatherStore) {
        let df = ISO8601DateFormatter.yyyyMMdd
        let cal = Calendar.current

        var changed = false
        for i in entries.indices {
            let entry = entries[i]
            let day = cal.startOfDay(for: entry.date)
            let iso = df.string(from: day)
            if let w = weather.data[entry.block]?[iso] {
                if entries[i].weatherMin != w.tMin ||
                   entries[i].weatherMax != w.tMax ||
                   entries[i].sunshineHours != w.sunshineHours {
                    entries[i].weatherMin = w.tMin
                    entries[i].weatherMax = w.tMax
                    entries[i].sunshineHours = w.sunshineHours
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    // MARK: - 1日分だけ取得して付与（キャッシュ優先）
    func attachWeatherIfNeeded(for entry: DiaryEntry,
                               weatherStore: DailyWeatherStore,
                               completion: @escaping (DailyWeather?) -> Void)
    {
        let iso = ISO8601DateFormatter.yyyyMMdd.string(from: entry.date)

        // 1) キャッシュ
        if let cached = weatherStore.data[entry.block]?[iso] {
            completion(cached)
            return
        }

        // 2) ブロック設定
        guard let blk = settings.blocks.first(where: { $0.name == entry.block }),
              let lat = blk.latitude, let lon = blk.longitude else {
            completion(nil)
            return
        }

        // 3) 当日のみ取得
        Task {
            do {
                let d0 = Calendar.current.startOfDay(for: entry.date)
                let items = try await WeatherService.fetchDailyRange(lat: lat, lon: lon, from: d0, to: d0)
                let first = items.first
                await MainActor.run {
                    if let it = first {
                        weatherStore.set(block: entry.block, item: it)
                        weatherStore.save()
                    }
                    completion(first)
                }
            } catch {
                print("fetchDailyRange failed:", error)
                await MainActor.run { completion(nil) }
            }
        }
    }
}
