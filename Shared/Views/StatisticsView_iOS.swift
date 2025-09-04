#if os(iOS)
import SwiftUI

@MainActor
struct StatisticsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var selectedBlock: String = ""
    @State private var range: RangePreset = .thisYear

    @State private var isFetching = false
    @State private var fetchError: String? = nil
    @State private var showError = false

    enum RangePreset: String, CaseIterable, Identifiable {
        case last30   = "直近30日"
        case thisYear = "今年"
        case last365  = "直近1年"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            List(series(), id: \.date) { w in
                HStack {
                    Text(df.string(from: w.date))
                    Spacer()
                    Text(w.tMax.map { String(format: "Max %.1f℃", $0) } ?? "-")
                    Text(w.tMin.map { String(format: "Min %.1f℃", $0) } ?? "-")
                    Text(w.sunshineHours.map { String(format: "☀︎ %.1fh", $0) } ?? "-")
                    Text(w.precipitationMm.map { String(format: "☂︎ %.0fmm", $0) } ?? "-")
                }
                .font(.caption)
            }
            .overlay {
                if series().isEmpty && !isFetching {
                    VStack(spacing: 8) {
                        Text("この期間の気象データがありません").font(.subheadline)
                        Text("「取得」ボタンで iPhone 側に保存できます。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding(.horizontal, 12)
        .navigationTitle("統計")
        .onAppear {
            if selectedBlock.isEmpty {
                selectedBlock = store.settings.blocks.first?.name ?? ""
            }
        }
        .alert("取得に失敗しました", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(fetchError ?? "-")
        })
    }

    // MARK: - Header（区画・期間 + 取得ボタン）
    private var header: some View {
        HStack(spacing: 12) {
            Picker("区画", selection: $selectedBlock) {
                ForEach(store.settings.blocks) { b in
                    Text(b.name).tag(b.name)
                }
            }
            .pickerStyle(.menu)

            Picker("期間", selection: $range) {
                ForEach(RangePreset.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            Spacer()

            // 選択中の区画＋期間を取得
            Button {
                Task { await fetchCurrentSelection() }
            } label: {
                if isFetching {
                    ProgressView().controlSize(.small)
                } else {
                    Label("取得", systemImage: "arrow.down.circle")
                }
            }
            .disabled(isFetching || selectedBlock.isEmpty)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Data（表示用）
    /// 範囲内の日付を1日刻みで走査し、DailyWeatherStore.get(block:date:) から取得
    private func series() -> [DailyWeather] {
        guard !selectedBlock.isEmpty else { return [] }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = dateRange().from

        var out: [DailyWeather] = []
        var d = from
        while d <= today {
            let day = cal.startOfDay(for: d)
            if let w = weather.get(block: selectedBlock, date: day) {
                out.append(w)
            }
            guard let nd = cal.date(byAdding: .day, value: 1, to: day) else { break }
            d = nd
        }
        return out
    }

    private func dateRange() -> (from: Date, to: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch range {
        case .last30:
            return (cal.date(byAdding: .day, value: -30, to: today) ?? today, today)
        case .thisYear:
            let y = cal.component(.year, from: today)
            let start = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? today
            return (start, today)
        case .last365:
            return (cal.date(byAdding: .day, value: -365, to: today) ?? today, today)
        }
    }

    // MARK: - Fetch（取得→保存）
    private func fetchCurrentSelection() async {
        guard !selectedBlock.isEmpty else { return }
        guard let blk = store.settings.blocks.first(where: { $0.name == selectedBlock }),
              let lat = blk.latitude, let lon = blk.longitude else {
            fetchError = "区画「\(selectedBlock)」に緯度・経度が設定されていません。設定画面で座標を入力してください。"
            showError = true
            return
        }

        isFetching = true
        defer { isFetching = false }

        let (from, to) = dateRange()
        do {
            // WeatherService は Shared 側の実装を利用（mac と同じ）
            let items = try await WeatherService.fetchDailyRange(lat: lat, lon: lon, from: from, to: to)
            for it in items {
                weather.set(block: blk.name, item: it)
            }
            weather.save()
        } catch {
            fetchError = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Date formatter
    private let df: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy/MM/dd"
        return df
    }()
}
#endif
