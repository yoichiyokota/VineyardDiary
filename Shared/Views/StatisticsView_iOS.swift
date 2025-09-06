#if os(iOS)
import SwiftUI
import Charts

// 軽量データ点
fileprivate struct Pt: Identifiable {
    let id = UUID()
    let d: Date
    let y: Double?
}

// 期間（左から 1か月 / 3か月 / 1年）
fileprivate enum Span: String, CaseIterable {
    case m1 = "1か月"
    case m3 = "3か月"
    case y1 = "1年"

    static var ordered: [Span] { [.m1, .m3, .y1] }
}

@MainActor
struct StatisticsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var selectedBlock: String = ""
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var span: Span = .m1   // 既定：1か月

    // ホバー日付（タップ/ドラッグ中のカーソル日付）
    @State private var hoverTemp: Date? = nil
    @State private var hoverSun:  Date? = nil
    @State private var hoverRain: Date? = nil
    @State private var hoverAT:   Date? = nil
    @State private var hoverSunVar: Date? = nil  // ← 品種別 日照

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                tempsSection()
                sunshineDailySection()
                precipitationSection()
                GDDPanel(selectedYear: $selectedYear, selectedBlock: $selectedBlock)        // //4) 有効積算温度 (eGDD版）
                    .environmentObject(store)
                    .environmentObject(weather)
                sunshineVarietySection()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .onAppear {
            if selectedBlock.isEmpty { selectedBlock = store.settings.blocks.first?.name ?? "" }
            if !availableYears().contains(selectedYear) {
                selectedYear = availableYears().max() ?? selectedYear
            }
        }
        
        // データ更新時に選択が無効化された場合も自動矯正
        .onAppear {
            if selectedBlock.isEmpty { selectedBlock = store.settings.blocks.first?.name ?? "" }
            if !availableYears().contains(selectedYear) {
                selectedYear = availableYears().max() ?? selectedYear
            }
        }
        .onChange(of: store.settings.blocks) { _ in
            if selectedBlock.isEmpty || !store.settings.blocks.map(\.name).contains(selectedBlock) {
                selectedBlock = store.settings.blocks.first?.name ?? ""
            }
        }
        .onChange(of: weather.data) { _ in
            // 年候補が変わったときの保険（必要なら）
            if !availableYears().contains(selectedYear) {
                selectedYear = availableYears().max() ?? Calendar.current.component(.year, from: Date())
            }
        }
        .navigationTitle("統計")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header（区画＆期間＆年）
    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 区画プルダウン（設定順）
                Menu {
                    ForEach(store.settings.blocks) { b in
                        Button(b.name) { selectedBlock = b.name }
                    }
                } label: {
                    HStack {
                        Text("区画")
                        Text(selectedBlock.isEmpty ? "未選択" : selectedBlock)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
                }

                // 期間タグ（1か月 / 3か月 / 1年）
                Picker("", selection: $span) {
                    ForEach(Span.ordered, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer()

                // 年（カンマ無し4桁）
                HStack(spacing: 6) {
                    Text("年")
                    Picker("", selection: $selectedYear) {
                        ForEach(availableYears(), id: \.self) { y in
                            Text(verbatim: "\(y)年").tag(y)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - Sections

    // 1) 最高・最低気温
    private func tempsSection() -> some View {
        let maxPts = tempMaxPoints()
        let minPts = tempMinPoints()

        return card(title: "気温の推移（最高・最低）") {
            Chart {
                ForEach(maxPts) { p in
                    if let y = p.y {
                        LineMark(
                            x: .value("日付", p.d, unit: .day),
                            y: .value("気温", y),
                            series: .value("種類", "最高")
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(.red)
                    }
                }
                ForEach(minPts) { p in
                    if let y = p.y {
                        LineMark(
                            x: .value("日付", p.d, unit: .day),
                            y: .value("気温", y),
                            series: .value("種類", "最低")
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(.blue)
                    }
                }

                if let d = hoverTemp,
                   let tmax = valueOn(d, from: maxPts),
                   let tmin = valueOn(d, from: minPts) {
                    RuleMark(x: .value("日付", d, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", d, unit: .day), y: .value("最高", tmax))
                        .foregroundStyle(.red)
                    PointMark(x: .value("日付", d, unit: .day), y: .value("最低", tmin))
                        .foregroundStyle(.blue)
                }
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(minHeight: 220)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in hoverTemp = xToDate(v.location, proxy, geo) }
                                .onEnded { _ in hoverTemp = nil }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                if let d = hoverTemp {
                    let tmax = valueOn(d, from: maxPts)
                    let tmin = valueOn(d, from: minPts)
                    bubble {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateLabel(d)).font(.caption).bold()
                            if let v = tmax { Text("最高 \(String(format: "%.1f", v))℃").foregroundStyle(.red) }
                            if let v = tmin { Text("最低 \(String(format: "%.1f", v))℃").foregroundStyle(.blue) }
                        }
                    }
                }
            }
        }
    }

    // 2) 日照（棒）
    private func sunshineDailySection() -> some View {
        let sunPts = sunshineDailyPoints()
        return card(title: "日照時間（h/日）") {
            Chart {
                ForEach(sunPts) { p in
                    if let y = p.y {
                        BarMark(
                            x: .value("日付", p.d, unit: .day),
                            y: .value("日照", y)
                        )
                    }
                }
                if let d = hoverSun, let v = valueOn(d, from: sunPts) {
                    RuleMark(x: .value("日付", d, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", d, unit: .day), y: .value("日照", v))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(minHeight: 200)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in hoverSun = xToDate(v.location, proxy, geo) }
                                .onEnded { _ in hoverSun = nil }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                if let d = hoverSun, let v = valueOn(d, from: sunPts) {
                    bubble { Text("\(dateLabel(d))  \(String(format: "%.1f", v)) h").font(.caption) }
                }
            }
        }
    }

    // 3) 降水（棒）
    private func precipitationSection() -> some View {
        let prPts = precipPoints()
        return card(title: "降水量（mm/日）") {
            Chart {
                ForEach(prPts) { p in
                    if let y = p.y {
                        BarMark(
                            x: .value("日付", p.d, unit: .day),
                            y: .value("降水", y)
                        )
                    }
                }
                if let d = hoverRain, let v = valueOn(d, from: prPts) {
                    RuleMark(x: .value("日付", d, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", d, unit: .day), y: .value("降水", v))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(minHeight: 200)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in hoverRain = xToDate(v.location, proxy, geo) }
                                .onEnded { _ in hoverRain = nil }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                if let d = hoverRain, let v = valueOn(d, from: prPts) {
                    bubble { Text("\(dateLabel(d))  \(String(format: "%.1f", v)) mm").font(.caption) }
                }
            }
        }
    }

   /*
    // 4) 有効積算温度（4/1〜、Tmax≥10 の日の Tmax を累積）
    private func activeTempSection() -> some View {
        let atPts = activeTempPoints()
        return card(title: "有効積算温度（4/1〜、Tmax≥10）") {
            Chart {
                let method = store.settings.gddMethod
                let rule   = store.settings.gddStartRule

                let daily = GDDSeriesBuilder.dailySeries(
                    store: store, weather: weather,
                    year: year,
                    block: selectedBlock,
                    variety: nil,
                    method: method,
                    rule: rule,
                    base: 10.0
                )
                let cumulative = GDDSeriesBuilder.cumulativeSeries(from: daily)
                if let d = hoverAT, let v = valueOn(d, from: atPts) {
                    RuleMark(x: .value("日付", d, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", d, unit: .day), y: .value("積算温度", v))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(minHeight: 220)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in hoverAT = xToDate(v.location, proxy, geo) }
                                .onEnded { _ in hoverAT = nil }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                if let d = hoverAT, let v = valueOn(d, from: atPts) {
                    bubble { Text("\(dateLabel(d))  \(String(format: "%.0f", v))").font(.caption) }
                }
            }
        }
    }
*/
    // 5) 積算日照（品種別・満開以降）← 追加
    private func sunshineVarietySection() -> some View {
        let series = cumulativeSunshineVarietySeries()
        let varietals = series.keys.sorted()

        return card(title: "積算日照時間（品種別・満開以降）") {
            Chart {
                ForEach(varietals, id: \.self) { vname in
                    if let pts = series[vname] {
                        ForEach(pts) { p in
                            if let y = p.y {
                                LineMark(
                                    x: .value("日付", p.d, unit: .day),
                                    y: .value("積算日照", y)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(by: .value("品種", vname))
                                .symbol(by: .value("品種", vname))
                            }
                        }
                    }
                }

                if let d = hoverSunVar {
                    RuleMark(x: .value("日付", d, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                }
            }
            .chartLegend(.visible)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(minHeight: 240)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in hoverSunVar = xToDate(v.location, proxy, geo) }
                                .onEnded { _ in hoverSunVar = nil }
                        )
                }
            }
            .overlay(alignment: .topLeading) {
                if let d = hoverSunVar {
                    let lines: [String] = varietals.compactMap { name in
                        if let pts = series[name], let y = valueOn(d, from: pts) {
                            return "\(name): \(String(format: "%.1f", y)) h"
                        }
                        return nil
                    }
                    if !lines.isEmpty {
                        bubble {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dateLabel(d)).font(.caption).bold()
                                ForEach(lines, id: \.self) { Text($0).font(.caption) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - データ整形

    /// block/year/期間に応じた (Date, DailyWeather) の並び
    private func dayMap() -> [(Date, DailyWeather)] {
        guard !selectedBlock.isEmpty,
              let dict = weather.data[selectedBlock] else { return [] }

        var arr: [(Date, DailyWeather)] = []
        arr.reserveCapacity(dict.count)
        for (k, v) in dict {
            if let d = yyyyMMdd.date(from: k) { arr.append((d, v)) }
        }

        // 年でフィルタ
        let filtered = arr.filter { Calendar.current.component(.year, from: $0.0) == selectedYear }
                          .sorted { $0.0 < $1.0 }

        // 期間トリム
        switch span {
        case .y1: return filtered
        case .m3: return dropToLastDays(filtered, days: 92)
        case .m1: return dropToLastDays(filtered, days: 31)
        }
    }

    private func tempMaxPoints() -> [Pt] { dayMap().map { Pt(d: $0.0, y: $0.1.tMax) } }
    private func tempMinPoints() -> [Pt] { dayMap().map { Pt(d: $0.0, y: $0.1.tMin) } }
    private func sunshineDailyPoints() -> [Pt] { dayMap().map { Pt(d: $0.0, y: $0.1.sunshineHours) } }
    private func precipPoints() -> [Pt] { dayMap().map { Pt(d: $0.0, y: $0.1.precipitationMm) } }

    // 有効積算温度：4/1以降、Tmax≥10 の日の Tmax を累積
    private func activeTempPoints() -> [Pt] {
        let dm = dayMap()
        guard let start = Calendar.current.date(from: DateComponents(year: selectedYear, month: 4, day: 1))
        else { return [] }
        var sum: Double = 0
        var out: [Pt] = []
        out.reserveCapacity(dm.count)
        for (d, w) in dm where d >= start {
            if let t = w.tMax, t >= 10 { sum += t }
            out.append(Pt(d: d, y: sum))
        }
        return out
    }

    // 品種別・満開以降の積算日照（表示範囲内で積算）
    private func cumulativeSunshineVarietySeries() -> [String: [Pt]] {
        let varietals = varietiesInYearBlock(year: selectedYear, block: selectedBlock)
        let dm = dayMap()
        guard !dm.isEmpty else { return [:] }

        var result: [String: [Pt]] = [:]
        for v in varietals {
            guard let bloom = bloomDate(year: selectedYear, block: selectedBlock, variety: v) else { continue }
            var sum: Double = 0
            var pts: [Pt] = []
            for (d, w) in dm where d >= bloom {
                if let s = w.sunshineHours { sum += s }
                pts.append(Pt(d: d, y: sum))
            }
            if !pts.isEmpty { result[v] = pts }
        }
        return result
    }

    // その年・区画に登場する品種名（重複除去・昇順）
    private func varietiesInYearBlock(year: Int, block: String) -> [String] {
        let cal = Calendar.current
        let names = store.entries.compactMap { e -> [String]? in
            guard e.block == block, cal.component(.year, from: e.date) == year else { return nil }
            return e.varieties.map { $0.varietyName }.filter { !$0.isEmpty }
        }.flatMap { $0 }
        return Array(Set(names)).sorted()
    }

    // 最初に満開（ステージコード23以上）になった日付
    private func bloomDate(year: Int, block: String, variety: String) -> Date? {
        let cal = Calendar.current
        let candidates = store.entries.compactMap { e -> Date? in
            guard e.block == block, cal.component(.year, from: e.date) == year else { return nil }
            for vs in e.varieties where vs.varietyName == variety {
                if let code = stageCode(from: vs.stage), code >= 23 {
                    return cal.startOfDay(for: e.date)
                }
            }
            return nil
        }
        return candidates.min()
    }

    private func stageCode(from stageText: String) -> Int? {
        let parts = stageText.split(separator: ":")
        if let first = parts.first, let v = Int(first.trimmingCharacters(in: .whitespaces)) { return v }
        return Int(stageText.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - ユーティリティ

    private func availableYears() -> [Int] {
        guard let dict = weather.data[selectedBlock], !dict.isEmpty else {
            let ys = store.entries
                .filter { $0.block == selectedBlock }
                .map { Calendar.current.component(.year, from: $0.date) }
            return Array(Set(ys + [Calendar.current.component(.year, from: Date())])).sorted()
        }
        var years = Set<Int>()
        years.reserveCapacity(dict.count)
        for k in dict.keys {
            if let d = yyyyMMdd.date(from: k) {
                years.insert(Calendar.current.component(.year, from: d))
            }
        }
        return Array(years).sorted()
    }

    private func valueOn(_ day: Date, from pts: [Pt]) -> Double? {
        let sd = Calendar.current.startOfDay(for: day)
        return pts.first(where: { Calendar.current.isDate($0.d, inSameDayAs: sd) })?.y
    }

    private func xToDate(_ pt: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) -> Date? {
        let frame = geo[proxy.plotAreaFrame]
        let x = pt.x - frame.origin.x
        return proxy.value(atX: x)
    }

    private func dropToLastDays(_ input: [(Date, DailyWeather)], days: Int) -> [(Date, DailyWeather)] {
        guard let last = input.last?.0 else { return input }
        let start = Calendar.current.date(byAdding: .day, value: -days+1, to: last) ?? last
        return input.filter { $0.0 >= start }
    }

    private func dateLabel(_ d: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy/MM/dd"
        return df.string(from: d)
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
    }
}

// yyyy-MM-dd（DailyWeather のキー）
fileprivate let yyyyMMdd: DateFormatter = {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd"
    return df
}()

// 吹き出し
@ViewBuilder
fileprivate func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.thinMaterial)
                .shadow(radius: 4)
        )
        .padding(8)
}

// eGDD View
/*
private struct GDDSection_iOS: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore
    
    let selectedYear: Int
    let selectedBlock: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                GDDPanel(selectedYear: selectedYear, selectedBlock: selectedBlock)
                    .environmentObject(store)
                    .environmentObject(weather)
            }
        }
    }
}
 */
#endif
