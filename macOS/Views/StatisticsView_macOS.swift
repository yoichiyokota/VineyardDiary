//
//  Created by yoichi_yokota on 2025/12/16.
//


#if os(macOS)
import SwiftUI
import Charts

// MARK: - Statistics View (macOS)

@MainActor
struct StatisticsView_macOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    
    @StateObject private var viewModel = StatisticsViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    temperatureSection
                    sunshineSection
                    precipitationSection
                    gddSection
                    sunshineVarietySection
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
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
        .frame(minWidth: 1100, minHeight: 760)
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 16) {
            Text(verbatim: "\(viewModel.selectedYear)年")
                .font(.title2)
                .bold()
            Spacer()
            yearPicker
            blockPicker
        }
        .padding(.horizontal, 12)
    }
    
    private var yearPicker: some View {
        HStack(spacing: 8) {
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
    
    private var blockPicker: some View {
        HStack(spacing: 6) {
            Text("区画")
            Picker("", selection: $viewModel.selectedBlock) {
                Text("すべて").tag("")
                ForEach(store.settings.blocks, id: \.id) { block in
                    Text(block.name).tag(block.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
    
    // MARK: - Sections
    
    private var temperatureSection: some View {
        SectionCard(title: "気温の推移（最高・最低）") {
            TemperatureChart(
                maxPoints: viewModel.temperatureMaxPoints(weather: weather),
                minPoints: viewModel.temperatureMinPoints(weather: weather),
                xDomain: viewModel.xDomainForYear(),
                hoverDate: $viewModel.hoverDateTemp,
                viewModel: viewModel
            )
        }
    }
    
    private var sunshineSection: some View {
        SectionCard(title: "日照時間の推移（h/日）") {
            SunshineChart(
                points: viewModel.sunshinePoints(weather: weather),
                xDomain: viewModel.xDomainForYear(),
                hoverDate: $viewModel.hoverDateSun,
                viewModel: viewModel
            )
        }
    }
    
    private var precipitationSection: some View {
        SectionCard(title: "降水量の推移（mm/日）") {
            PrecipitationChart(
                points: viewModel.precipitationPoints(weather: weather),
                xDomain: viewModel.xDomainForYear(),
                hoverDate: $viewModel.hoverDateRain,
                viewModel: viewModel
            )
        }
    }
    
    private var gddSection: some View {
        GDDPanel(
            selectedYear: $viewModel.selectedYear,
            selectedBlock: $viewModel.selectedBlock,
            xDomain: viewModel.xDomainApr1ToToday(weather: weather)
        )
        .environmentObject(store)
        .environmentObject(weather)
    }
    
    private var sunshineVarietySection: some View {
        SectionCard(title: "積算日照時間（品種別・満開以降）") {
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

// MARK: - Supporting Views

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15)))
    }
}

// MARK: - Chart Components

private struct TemperatureChart: View {
    let maxPoints: [StatisticsDataPoint]
    let minPoints: [StatisticsDataPoint]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    let viewModel: StatisticsViewModel
    
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
            
            if let date = hoverDate,
               let tmax = viewModel.valueOn(date: date, from: maxPoints),
               let tmin = viewModel.valueOn(date: date, from: minPoints) {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("日付", date, unit: .day), y: .value("最高", tmax))
                    .foregroundStyle(.red)
                PointMark(x: .value("日付", date, unit: .day), y: .value("最低", tmin))
                    .foregroundStyle(.blue)
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
        .frame(minHeight: 240)
        .chartOverlay { proxy in
            ChartHoverOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
        .overlay(alignment: .topLeading) {
            if let date = hoverDate,
               let tmax = viewModel.valueOn(date: date, from: maxPoints),
               let tmin = viewModel.valueOn(date: date, from: minPoints) {
                HoverBubble {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatDate(date)).font(.caption).bold()
                        Text("最高 \(String(format: "%.1f", tmax))℃").foregroundStyle(.red)
                        Text("最低 \(String(format: "%.1f", tmin))℃").foregroundStyle(.blue)
                    }
                }
            }
        }
    }
}

private struct SunshineChart: View {
    let points: [StatisticsDataPoint]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    let viewModel: StatisticsViewModel
    
    var body: some View {
        Chart {
            ForEach(points) { p in
                if let y = p.value {
                    BarMark(
                        x: .value("日付", p.date, unit: .day),
                        y: .value("日照時間", y)
                    )
                    .foregroundStyle(.yellow)
                }
            }
            
            if let date = hoverDate,
               let value = viewModel.valueOn(date: date, from: points) {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("日付", date, unit: .day), y: .value("日照", value))
                    .foregroundStyle(.yellow)
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
            ChartHoverOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
        .overlay(alignment: .topLeading) {
            if let date = hoverDate,
               let value = viewModel.valueOn(date: date, from: points) {
                HoverBubble {
                    Text("\(formatDate(date))  日照 \(String(format: "%.1f", value)) h")
                        .font(.caption)
                }
            }
        }
    }
}

private struct PrecipitationChart: View {
    let points: [StatisticsDataPoint]
    let xDomain: ClosedRange<Date>
    @Binding var hoverDate: Date?
    let viewModel: StatisticsViewModel
    
    var body: some View {
        Chart {
            ForEach(points) { p in
                if let y = p.value {
                    BarMark(
                        x: .value("日付", p.date, unit: .day),
                        y: .value("降水量", y)
                    )
                    .foregroundStyle(.teal)
                }
            }
            
            if let date = hoverDate,
               let value = viewModel.valueOn(date: date, from: points) {
                RuleMark(x: .value("日付", date, unit: .day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("日付", date, unit: .day), y: .value("降水", value))
                    .foregroundStyle(.teal)
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
            ChartHoverOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
        .overlay(alignment: .topLeading) {
            if let date = hoverDate,
               let value = viewModel.valueOn(date: date, from: points) {
                HoverBubble {
                    Text("\(formatDate(date))  降水 \(String(format: "%.1f", value)) mm")
                        .font(.caption)
                }
            }
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
            ChartHoverOverlay(proxy: proxy, hoverDate: $hoverDate)
        }
        .overlay(alignment: .topLeading) {
            if let date = hoverDate {
                let varieties = series.keys.sorted()
                let lines = varieties.compactMap { v -> String? in
                    if let pts = series[v], let y = viewModel.valueOn(date: date, from: pts) {
                        return "\(v): \(String(format: "%.1f", y)) h"
                    }
                    return nil
                }
                if !lines.isEmpty {
                    HoverBubble {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(date)).font(.caption).bold()
                            ForEach(lines, id: \.self) { line in
                                Text(line).font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ChartHoverOverlay: View {
    let proxy: ChartProxy
    @Binding var hoverDate: Date?
    
    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pos):
                        let frame = geo[proxy.plotAreaFrame]
                        let xInPlot = pos.x - frame.origin.x
                        if let date: Date = proxy.value(atX: xInPlot) {
                            hoverDate = Calendar.current.startOfDay(for: date)
                        }
                    case .ended:
                        hoverDate = nil
                    }
                }
        }
    }
}

private struct HoverBubble<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.thinMaterial)
                    .shadow(radius: 6)
            )
            .padding(8)
    }
}

private func formatDate(_ date: Date) -> String {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "ja_JP")
    df.dateFormat = "M/d"
    return df.string(from: date)
}

#endif
