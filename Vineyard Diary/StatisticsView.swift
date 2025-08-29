import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedBlock: String = ""

    // 「2,025」ではなく「2025」のための整形
    private let nfNoGrouping: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .none
        nf.usesGroupingSeparator = false
        return nf
    }()

    var body: some View {
        VStack(spacing: 8) {
            header

            ScrollView(.vertical) {
                VStack(spacing: 28) {
                    temperatureSection                 // 最高=赤 / 最低=青
                    sunshineSection                    // 日照（棒）
                    cumulativeTemperatureSection       // 有効積算温度（畑ごと1本）
                    cumulativeSunshineVarietySection   // 積算日照（品種別・色分け）
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .onAppear {
            let validNames = Set(store.settings.blocks.map { $0.name })
            // 未選択 or 設定に存在しない場合は先頭に補正
            if selectedBlock.isEmpty || !validNames.contains(selectedBlock) {
                selectedBlock = store.settings.blocks.first?.name ?? ""
            }
        }
        .padding(.top, 8)
        .frame(minWidth: 980, minHeight: 700)
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Text("\(nfNoGrouping.string(from: NSNumber(value: selectedYear)) ?? String(selectedYear))年 統計")
                .font(.headline)
            Spacer()

            Picker("年", selection: $selectedYear) {
                let y = Calendar.current.component(.year, from: Date())
                ForEach((y-5)...(y+1), id: \.self) { yy in
                    Text("\(nfNoGrouping.string(from: NSNumber(value: yy)) ?? String(yy))年").tag(yy)
                }
            }
            .frame(width: 140)

            Picker("区画", selection: $selectedBlock) {
                ForEach(store.settings.blocks) { b in
                    Text(b.name).tag(b.name)
                }
            }
            .frame(width: 240)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 気温（最高/最低：色分け）
    private struct TempPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let series: String   // "最高" / "最低"
    }

    private var temperatureSection: some View {
        Group {
            Text("気温の推移（最高・最低）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(tempPoints()) { p in
                    LineMark(
                        x: .value("日付", p.date),
                        y: .value(p.series, p.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("系列", p.series)) // ← 色分けキー
                }
            }
            .chartForegroundStyleScale([
                "最高": .red,
                "最低": .blue
            ])
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 340)
            .panelBackground()
        }
    }

    private func tempPoints() -> [TempPoint] {
        let seq = daySequence()
        var pts: [TempPoint] = []
        for (d, dw) in seq {
            if let tmax = dw.tMax {
                pts.append(TempPoint(date: d, value: tmax, series: "最高"))
            }
            if let tmin = dw.tMin {
                pts.append(TempPoint(date: d, value: tmin, series: "最低"))
            }
        }
        return pts
    }

    // MARK: - 日照（棒）
    private enum SeriesKind { case tMax, tMin, sun }
    private struct Point: Identifiable { let id = UUID(); let date: Date; let value: Double? }

    private var sunshineSection: some View {
        Group {
            Text("日照時間の推移（棒グラフ）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(points(kind: .sun)) { p in
                    if let v = p.value {
                        BarMark(
                            x: .value("日付", p.date),
                            y: .value("日照(h)", v)
                        )
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 260)
            .panelBackground()
        }
    }

    // MARK: - 有効積算温度（4/1〜、最高気温が10℃以上の日の最高気温を加算）※畑ごと1本
    private var cumulativeTemperatureSection: some View {
        Group {
            Text("有効積算温度（4/1〜：最高気温が10℃以上の日の最高気温を加算）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(cumulativeActiveTempPoints()) { p in
                    if let v = p.value {
                        LineMark(
                            x: .value("日付", p.date),
                            y: .value("積算温度(℃)", v)
                        )
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 300)
            .panelBackground()
        }
    }

    private func cumulativeActiveTempPoints() -> [Point] {
        let seq = daySequence()
        guard !seq.isEmpty else { return [] }
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: selectedYear, month: 4, day: 1))!

        var sum = 0.0
        var pts: [Point] = []
        for (d, dw) in seq where d >= start {
            if let tmax = dw.tMax, tmax >= 10.0 { sum += tmax }
            pts.append(Point(date: d, value: sum))
        }
        return pts
    }

    // MARK: - 積算日照（品種別に同一グラフへ）
    private struct SeriesPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double?
        let series: String // 品種名
    }

    private var cumulativeSunshineVarietySection: some View {
        Group {
            Text("積算日照時間（品種別・満開=ステージNo.23以降を累積）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(cumulativeSunshineVarietyPoints()) { p in
                    if let v = p.value {
                        LineMark(
                            x: .value("日付", p.date),
                            y: .value("積算日照(h)", v)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("品種", p.series)) // ← 品種ごと色分け
                    }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 320)
            .panelBackground()
        }
    }

    private func cumulativeSunshineVarietyPoints() -> [SeriesPoint] {
        let seq = daySequence()
        guard !seq.isEmpty else { return [] }

        var all: [SeriesPoint] = []
        let varieties = varietiesInYearAndBlock()

        // 日付→日照の辞書（高速化）
        let sunByDate: [Date: Double] = Dictionary(uniqueKeysWithValues:
            seq.map { (d, dw) in (d, dw.sunshineHours ?? 0.0) }
        )

        for variety in varieties {
            guard let bloom = bloomDate(block: selectedBlock, variety: variety, year: selectedYear) else {
                // 満開日が見つからない品種は線を描かない
                continue
            }
            var sum = 0.0
            let points = seq.map { (d, _) -> SeriesPoint in
                if d >= bloom {
                    sum += sunByDate[d] ?? 0.0
                    return SeriesPoint(date: d, value: sum, series: variety)
                } else {
                    return SeriesPoint(date: d, value: nil, series: variety)
                }
            }
            all.append(contentsOf: points)
        }
        return all
    }

    // MARK: - データ整形ユーティリティ
    private func daySequence() -> [(Date, DailyWeather)] {
        // 設定に無い区画は描画対象外（古いデータを握っていても見せない）
        let validNames = Set(store.settings.blocks.map { $0.name })
        guard !selectedBlock.isEmpty, validNames.contains(selectedBlock),
              let map = weather.data[selectedBlock] else { return [] }

        let df = ISO8601DateFormatter.yyyyMMdd
        let cal = Calendar.current
        return map.compactMap { (key, dw) in
            guard let d = df.date(from: key) else { return nil }
            return (d, dw)
        }
        .filter { cal.component(.year, from: $0.0) == selectedYear }
        .sorted { $0.0 < $1.0 }
    }

    private func points(kind: SeriesKind) -> [Point] {
        daySequence().map { (d, dw) in
            switch kind {
            case .tMax: return Point(date: d, value: dw.tMax)
            case .tMin: return Point(date: d, value: dw.tMin)
            case .sun:  return Point(date: d, value: dw.sunshineHours)
            }
        }
    }

    // 品種別の満開日（ステージNo.23以上の最初の日）を検索
    private func bloomDate(block: String, variety: String, year: Int) -> Date? {
        let cal = Calendar.current
        let entries = store.entries
            .filter { $0.block == block && cal.component(.year, from: $0.date) == year }
            .sorted { $0.date < $1.date }

        for e in entries {
            // その日の varieties から、対象品種のステージ番号を抽出（先頭の数字を読む）
            if let item = e.varieties.first(where: { $0.varietyName == variety }) {
                if let no = leadingStageNumber(item.stage), no >= 23 {
                    return cal.startOfDay(for: e.date)
                }
            }
        }
        return nil
    }

    // "23: 満開期" のような文字列の先頭数値を取り出す
    private func leadingStageNumber(_ s: String) -> Int? {
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }

    // 対象年・区画で現れた品種一覧を抽出
    private func varietiesInYearAndBlock() -> [String] {
        let cal = Calendar.current
        let set = Set(
            store.entries
                .filter { $0.block == selectedBlock && cal.component(.year, from: $0.date) == selectedYear }
                .flatMap { $0.varieties.map { $0.varietyName } }
        )
        return Array(set).sorted()
    }
}

// MARK: - 見た目ユーティリティ
private extension View {
    func panelBackground() -> some View {
        self
            .background(Color.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
