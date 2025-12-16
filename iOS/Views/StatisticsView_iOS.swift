#if os(iOS)
import SwiftUI
import Charts

// MARK: - Statistics View (iOS)

@MainActor
struct StatisticsView_iOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    
    @StateObject private var viewModel = StatisticsViewModel()
    
    // 期間フィルタ（iOS専用）
    @State private var span: TimeSpan = .month1
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                temperatureSection
                sunshineSection
                precipitationSection
                gddSection
                sunshineVarietySection
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .navigationTitle("統計")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            viewModel.initialize(
                store: store,
                weather: weather,
                settings: store.settings
            )
        }
        .onChange(of: store.settings.blocks) { _ in
            validateSelections()
        }
        .onChange(of: weather.data) { _ in
            validateSelections()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                blockPicker
                spanPicker
                Spacer()
                yearPicker
            }
        }
        .padding(.top, 6)
    }
    
    private var blockPicker: some View {
        Menu {
            ForEach(store.settings.blocks) { block in
                Button(block.name) {
                    viewModel.selectedBlock = block.name
                }
            }
        } label: {
            HStack {
                Text("区画")
                Text(viewModel.selectedBlock.isEmpty ? "未選択" : viewModel.selectedBlock)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
        }
    }
    
    private var spanPicker: some View {
        Picker("", selection: $span) {
            ForEach(TimeSpan.allCases, id: \.self) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }
    
    private var yearPicker: some View {
        HStack(spacing: 6) {
            Text("年")
            Picker("", selection: $viewModel.selectedYear) {
                ForEach(viewModel.availableYears(store: store, weather: weather), id: \.self) { y in
                    Text(verbatim: "\(y)年").tag(y)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
    }
    
    // MARK: - Sections
    
    private var temperatureSection: some View {
        ChartCard(title: "気温の推移（最高・最低）") {
            TemperatureChart(
                maxPoints: viewModel.temperatureMaxPoints(weather: weather),
                minPoints: viewModel.temperatureMinPoints(weather: weather),
                xDomain: xDomainForSpan(),
                hoverDate: $viewModel.hoverDateTemp
            )
        }
    }
    
    private var sunshineSection: some View {
        ChartCard(title: "日照時間（h/日）") {
            SunshineChart(
                points: viewModel.sunshinePoints(weather: weather),
                xDomain: xDomainForSpan(),
                hoverDate: $viewModel.hoverDateSun
            )
        }
    }
    
    private var precipitationSection: some View {
        ChartCard(title: "降水量（mm/日）") {
            PrecipitationChart(
                points: viewModel.precipitationPoints(weather: weather),
                xDomain: xDomainForSpan(),
                hoverDate: $viewModel.hoverDateRain
            )
        }
    }
    
    private var gddSection: some View {
        GDDPanel(
            selectedYear: $viewModel.selectedYear,
            selectedBlock: $viewModel.selectedBlock,
            xDomain: xDomainForSpan()
        )
        .environmentObject(store)
        .environmentObject(weather)
    }
    
    private var sunshineVarietySection: some View {
        ChartCard(title: "積算日照時間（品種別・満開以降）") {
            SunshineVarietyChart(
                series: viewModel.cumulativeSunshineVarietySeries(
                    store: store,
                    weather: weather
                ),
                xDomain: viewModel.xDomainApr1ToToday(weather: weather),
                hoverDate: $viewModel.hoverDateSunVar,
                viewModel: viewModel
            )
        }
    }
    
    // MARK: - Helpers
    
    private func xDomainForSpan() -> ClosedRange<Date> {
        let cal = Calendar.current
        let dm = viewModel.dayMap(weather: weather)
        let lastData = dm.last?.0 ?? cal.date(from: DateComponents(year: viewModel.selectedYear, month: 12, day: 31))!
        let today = cal.startOfDay(for: Date())
        let end = min(today, lastData)
        
        switch span {
        case .year1:
            let start = cal.date(from: DateComponents(year: viewModel.selectedYear, month: 1, day: 1))!
            return start...end
        case .month3:
            let start = cal.date(byAdding: .day, value: -91, to: end)!
            return start...end
        case .month1:
            let start = cal.date(byAdding: .day, value: -30, to: end)!
            return start...end
        }
    }
    
    private func validateSelections() {
        let blocks = viewModel.availableBlocks(settings: store.settings)
        if viewModel.selectedBlock.isEmpty || !blocks.contains(viewModel.selectedBlock) {
            viewModel.selectedBlock = blocks.first ?? ""
        }
        
        let years = viewModel.availableYears(store: store, weather: weather)
        if !years.contains(viewModel.selectedYear) {
            viewModel.selectedYear = years.max() ?? Calendar.current.component(.year, from: Date())
        }
    }
}

// MARK: - Supporting Types

private enum TimeSpan: String, CaseIterable {
    case month1 = "1ヶ月"
    case month3 = "3ヶ月"
    case year1 = "1年"
    
    var label: String { rawValue }
}

// MARK: - Chart Components

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
    }
}

private struct TemperatureChart: View {
    let maxPoints: [StatisticsDataPoint]
    let minPoints: [StatisticsDataPoint]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    
    var body: some View {
        Chart {
            ForEach(maxPoints) { p in
                if let y = p.value {
                    LineMark(
                        x: .value("日付", p.date, unit: .day),
                        y: .value("気温", y),
                        series: .value("種類", "最高")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(.red)
                }
            }
            
            ForEach(minPoints) { p in
                if let y = p.value {
                    LineMark(
                        x: .value("日付", p.date, unit: .day),
                        y: .value("気温", y),
                        series: .value("種類", "最低")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(.blue)
                }
            }
            
            if let date = hoverDate {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(minHeight: 220)
        .chartOverlay { proxy in
            ChartInteractionOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
    }
}

private struct SunshineChart: View {
    let points: [StatisticsDataPoint]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    
    var body: some View {
        Chart {
            ForEach(points) { p in
                if let y = p.value {
                    BarMark(
                        x: .value("日付", p.date, unit: .day),
                        y: .value("日照", y)
                    )
                }
            }
            
            if let date = hoverDate {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(minHeight: 200)
        .chartOverlay { proxy in
            ChartInteractionOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
    }
}

private struct PrecipitationChart: View {
    let points: [StatisticsDataPoint]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    
    var body: some View {
        Chart {
            ForEach(points) { p in
                if let y = p.value {
                    BarMark(
                        x: .value("日付", p.date, unit: .day),
                        y: .value("降水", y)
                    )
                }
            }
            
            if let date = hoverDate {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(minHeight: 200)
        .chartOverlay { proxy in
            ChartInteractionOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
    }
}

private struct SunshineVarietyChart: View {
    let series: [String: [StatisticsDataPoint]]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    let viewModel: StatisticsViewModel
    
    var body: some View {
        Chart {
            ForEach(series.keys.sorted(), id: \.self) { variety in
                if let points = series[variety] {
                    ForEach(points) { p in
                        if let y = p.value {
                            LineMark(
                                x: .value("日付", p.date, unit: .day),
                                y: .value("積算日照", y)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(by: .value("品種", variety))
                            .symbol(by: .value("品種", variety))
                        }
                    }
                }
            }
            
            if let date = hoverDate {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartLegend(.visible)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(minHeight: 240)
        .chartOverlay { proxy in
            ChartInteractionOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
    }
}

private struct ChartInteractionOverlay: View {
    let proxy: ChartProxy
    @Binding var hoverDate: Date?
    
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let frame = geo[proxy.plotAreaFrame]
                            let xInPlot = value.location.x - frame.origin.x
                            if let date: Date = proxy.value(atX: xInPlot) {
                                hoverDate = Calendar.current.startOfDay(for: date)
                            }
                        }
                        .onEnded { _ in
                            hoverDate = nil
                        }
                )
        }
    }
}

#endif

