import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedBlock: String = ""

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
                    temperatureSection   // ← 最高/最低を“系列”で分離
                    sunshineSection
                    cumulativeTemperatureSection
                    cumulativeSunshineSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .onAppear {
            if selectedBlock.isEmpty {
                selectedBlock = store.settings.blocks.first?.name ?? ""
            }
        }
        .padding(.top, 8)
        .frame(minWidth: 980, minHeight: 700)
    }

    // MARK: Header
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
            .frame(width: 220)
        }
        .padding(.horizontal, 16)
    }

    // MARK: 気温（最高/最低を別シリーズに）
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
                        y: .value(p.series, p.value),
                        series: .value("系列", p.series)
                    )
                    .interpolationMethod(.monotone)
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

    // MARK: 日照（棒）
    private var sunshineSection: some View {
        Group {
            Text("日照時間の推移（棒グラフ）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(points(kind: .sun)) { p in
                    if let v = p.value {
                        BarMark(x: .value("日付", p.date),
                                y: .value("日照(h)", v))
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

    // MARK: 積算温度
    private var cumulativeTemperatureSection: some View {
        Group {
            Text("有効積算温度（4/1〜、最高気温が10℃以上の日の最高気温を加算）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(cumulativeActiveTempPoints()) { p in
                    if let v = p.value {
                        LineMark(x: .value("日付", p.date),
                                 y: .value("積算温度(℃)", v))
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

    // MARK: 積算日照（満開以降）
    private var cumulativeSunshineSection: some View {
        Group {
            Text("積算日照時間（満開日以降）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(cumulativeSunshinePoints()) { p in
                    if let v = p.value {
                        LineMark(x: .value("日付", p.date),
                                 y: .value("積算日照(h)", v))
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

    // MARK: データ整形
    private enum SeriesKind { case tMax, tMin, sun }
    private struct Point: Identifiable { let id = UUID(); let date: Date; let value: Double? }

    private func daySequence() -> [(Date, DailyWeather)] {
        guard !selectedBlock.isEmpty, let map = weather.data[selectedBlock] else { return [] }
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

    private func cumulativeSunshinePoints() -> [Point] {
        let seq = daySequence()
        guard !seq.isEmpty else { return [] }
        guard let bloom = store.bloomDate(block: selectedBlock, year: selectedYear) else { return [] }

        var sum = 0.0
        var pts: [Point] = []
        let start = Calendar.current.startOfDay(for: bloom)
        for (d, dw) in seq where d >= start {
            if let h = dw.sunshineHours { sum += h }
            pts.append(Point(date: d, value: sum))
        }
        return pts
    }
}

// MARK: - 見た目
private extension View {
    func panelBackground() -> some View {
        self
            .background(Color.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
