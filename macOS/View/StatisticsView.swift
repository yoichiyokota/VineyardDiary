#if os(macOS)
import SwiftUI
import Charts

// 軽量データ点（Line/Bar共通）
fileprivate struct Point: Identifiable {
    let id = UUID()
    let date: Date
    let y: Double?
}

@MainActor
struct StatisticsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var selectedBlock: String = ""
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // 各グラフ用ホバー日付
    @State private var hoverDateTemp: Date? = nil
    @State private var hoverDateSun: Date? = nil
    @State private var hoverDateRain: Date? = nil
    @State private var hoverDateAT: Date? = nil
    @State private var hoverDateSunVar: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .onChange(of: store.settings.blocks) { _ in
                    initialSelects()
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    tempsSection()              // 1) 最高・最低（赤/青、中央値なし）
                    sunshineDailySection()      // 2) 日照（棒）＋ホバー
                    precipitationSection()      // 3) 降水（棒）＋ホバー
                    GDDPanel(
                        selectedYear: $selectedYear,
                        selectedBlock: $selectedBlock,
                        xDomain: xDomainApr1ToToday()
                    )          // 4) 積算温度
                        .environmentObject(store)
                        .environmentObject(weather)
                    sunshineVarietySection()    // 5) 積算日照（品種別・満開以降）＋ホバー
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .onAppear(perform: initialSelects)
        .onChange(of: weather.data) { _ in initialSelects() }  // ← これを追加

        
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

        .frame(minWidth: 1100, minHeight: 760)
    }
    
    

    // MARK: - Header（年は4桁、カンマ無し：verbatimで強制）
    private var header: some View {
        HStack(spacing: 16) {
            Text(verbatim: "\(selectedYear)年")
                .font(.title2).bold()
            Spacer()
            HStack(spacing: 8) {
                Text("年")
                Picker("", selection: $selectedYear) {
                    ForEach(availableYears(), id: \.self) { y in
                        Text(verbatim: "\(y)年").tag(y)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            HStack(spacing: 6) {
                Text("区画")
                Picker("", selection: $selectedBlock) {
                    Text("すべて").tag("") // 空は全区画
                    ForEach(store.settings.blocks, id: \.id) { b in
                        // 表示は b.name（中に "(630m)" を含んでいてもOK）
                        // ただし tag は “生の name” を渡す
                        Text(b.name).tag(b.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Sections

    // 1) 最高・最低気温（赤/青）
    private func tempsSection() -> some View {
        let maxPts = tempMaxPoints()
        let minPts = tempMinPoints()

        return SectionCard(title: "気温の推移（最高・最低）") {
            Chart {
                // 最高：赤
                ForEach(maxPts) { p in
                    if let y = p.y {
                        LineMark(
                            x: .value("日付", p.date, unit: .day),
                            y: .value("気温", y),
                            series: .value("種類", "最高")
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(.red)   // ← 明示指定
                    }
                }
                // 最低：青
                ForEach(minPts) { p in
                    if let y = p.y {
                        LineMark(
                            x: .value("日付", p.date, unit: .day),
                            y: .value("気温", y),
                            series: .value("種類", "最低")
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(.blue)  // ← 明示指定
                    }
                }

                // ホバー中のポイント表示
                if let hd = hoverDateTemp,
                   let tmax = valueOn(date: hd, from: maxPts),
                   let tmin = valueOn(date: hd, from: minPts) {
                    RuleMark(x: .value("日付", hd, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", hd, unit: .day),
                              y: .value("最高", tmax))
                        .foregroundStyle(.red)
                    PointMark(x: .value("日付", hd, unit: .day),
                              y: .value("最低", tmin))
                        .foregroundStyle(.blue)
                }
            }
            .chartXScale(domain: xDomainForYear(selectedYear)) // ★これを追加
            .chartLegend(.hidden) // 凡例は不要なら隠す
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
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let pos):
                                if let d = xToDate(pos: pos, proxy: proxy, geo: geo) {
                                    hoverDateTemp = startOfDay(d)
                                }
                            case .ended:
                                hoverDateTemp = nil
                            }
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hd = hoverDateTemp {
                    let tmax = valueOn(date: hd, from: maxPts)
                    let tmin = valueOn(date: hd, from: minPts)
                    bubble {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateLabel(hd)).font(.caption).bold()
                            if let v = tmax { Text("最高 \(String(format: "%.1f", v))℃").foregroundStyle(.red) }
                            if let v = tmin { Text("最低 \(String(format: "%.1f", v))℃").foregroundStyle(.blue) }
                        }
                    }
                }
            }
        }
    }

    // 2) 日照（日次・棒）
    private func sunshineDailySection() -> some View {
        let sunPts = sunshineDailyPoints()
        return SectionCard(title: "日照時間の推移（h/日）") {
            Chart {
                ForEach(sunPts) { p in
                    if let y = p.y {
                        BarMark(
                            x: .value("日付", p.date, unit: .day),
                            y: .value("日照時間", y)
                        )
                        .foregroundStyle(.yellow)
                    }
                }

                if let hd = hoverDateSun, let v = valueOn(date: hd, from: sunPts) {
                    RuleMark(x: .value("日付", hd, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", hd, unit: .day), y: .value("日照", v))
                        .foregroundStyle(.yellow)
                }
            }
            .chartXScale(domain: xDomainForYear(selectedYear)) // ★これを追加
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
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let pos):
                                if let d = xToDate(pos: pos, proxy: proxy, geo: geo) {
                                    hoverDateSun = startOfDay(d)
                                }
                            case .ended:
                                hoverDateSun = nil
                            }
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hd = hoverDateSun, let v = valueOn(date: hd, from: sunPts) {
                    bubble { Text("\(dateLabel(hd))  日照 \(String(format: "%.1f", v)) h").font(.caption) }
                }
            }
        }
    }

    // 3) 降水（日次・棒）
    private func precipitationSection() -> some View {
        let prPts = precipPoints()
        return SectionCard(title: "降水量の推移（mm/日）") {
            Chart {
                ForEach(prPts) { p in
                    if let y = p.y {
                        BarMark(
                            x: .value("日付", p.date, unit: .day),
                            y: .value("降水量", y)
                        )
                        .foregroundStyle(.teal)
                    }
                }
                if let hd = hoverDateRain, let v = valueOn(date: hd, from: prPts) {
                    RuleMark(x: .value("日付", hd, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                    PointMark(x: .value("日付", hd, unit: .day), y: .value("降水", v))
                        .foregroundStyle(.teal)
                }
            }
            .chartXScale(domain: xDomainForYear(selectedYear)) // ★これを追加
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
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let pos):
                                if let d = xToDate(pos: pos, proxy: proxy, geo: geo) {
                                    hoverDateRain = startOfDay(d)
                                }
                            case .ended:
                                hoverDateRain = nil
                            }
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hd = hoverDateRain, let v = valueOn(date: hd, from: prPts) {
                    bubble { Text("\(dateLabel(hd))  降水 \(String(format: "%.1f", v)) mm").font(.caption) }
                }
            }
        }
    }

    
    // 5) 積算日照（品種別・満開以降）
    private func sunshineVarietySection() -> some View {
        let series = cumulativeSunshineVarietySeries()
        let varietals = series.keys.sorted()

        return SectionCard(title: "積算日照時間（品種別・満開以降）") {
            Chart {
                ForEach(varietals, id: \.self) { varietal in
                    if let pts = series[varietal] {
                        ForEach(pts) { p in
                            if let y = p.y {
                                LineMark(
                                    x: .value("日付", p.date, unit: .day),
                                    y: .value("積算日照", y)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(by: .value("品種", varietal))
                                .symbol(by: .value("品種", varietal))
                            }
                        }
                    }
                }

                if let hd = hoverDateSunVar {
                    RuleMark(x: .value("日付", hd, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3,3]))
                }
            }
            .chartXScale(domain: xDomainApr1ToToday())
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
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let pos):
                                if let d = xToDate(pos: pos, proxy: proxy, geo: geo) {
                                    hoverDateSunVar = startOfDay(d)
                                }
                            case .ended:
                                hoverDateSunVar = nil
                            }
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hd = hoverDateSunVar {
                    let lines: [String] = varietals.compactMap { v in
                        if let pts = series[v], let y = valueOn(date: hd, from: pts) {
                            return "\(v): \(String(format: "%.1f", y)) h"
                        }
                        return nil
                    }
                    if !lines.isEmpty {
                        bubble {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dateLabel(hd)).font(.caption).bold()
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

    // MARK: - 初期セット/候補

    private func initialSelects() {
        let blocks = availableBlocks()
        if selectedBlock.isEmpty || !blocks.contains(selectedBlock) {
            // 設定順に並んだ available から先頭を採用
            selectedBlock = blocks.first ?? (store.settings.blocks.first?.name ?? "")
        }
        let years = availableYears()
        if !years.contains(selectedYear) {
            selectedYear = years.max() ?? Calendar.current.component(.year, from: Date())
        }
    }

    //private func availableBlocks() -> [String] {
    //    // 設定に存在かつ天気データにもある区画のみ
    //    let defined = Set(store.settings.blocks.map { $0.name })
    //    let fromWeather = Set(weather.data.keys)
    //    return Array(defined.intersection(fromWeather)).sorted()
    //}
    
    private func availableBlocks() -> [String] {
        store.settings.blocks.map { $0.name }   // ← 並び順そのまま
    }

    private func availableYears() -> [Int] {
        var years = Set<Int>()
        if let dict = weather.data[selectedBlock] {
            for key in dict.keys {
                if let d = yyyyMMddDF.date(from: key) {
                    years.insert(Calendar.current.component(.year, from: d))
                }
            }
        }
        if years.isEmpty {
            let ys = store.entries
                .filter { $0.block == selectedBlock }
                .map { Calendar.current.component(.year, from: $0.date) }
            years.formUnion(ys)
        }
        if years.isEmpty { years.insert(Calendar.current.component(.year, from: Date())) }
        return Array(years).sorted()
    }

    // MARK: - データ生成

    private func dayMap() -> [(Date, DailyWeather)] {
        guard let dict = weather.data[selectedBlock] else { return [] }
        let arr: [(Date, DailyWeather)] = dict.compactMap { (k, v) in
            if let d = yyyyMMddDF.date(from: k) { return (d, v) }
            return nil
        }
        let filtered = arr.filter { Calendar.current.component(.year, from: $0.0) == selectedYear }
        return filtered.sorted { $0.0 < $1.0 }
    }

    private func tempMaxPoints() -> [Point] { dayMap().map { Point(date: $0.0, y: $0.1.tMax) } }
    private func tempMinPoints() -> [Point] { dayMap().map { Point(date: $0.0, y: $0.1.tMin) } }
    private func sunshineDailyPoints() -> [Point] { dayMap().map { Point(date: $0.0, y: $0.1.sunshineHours) } }
    private func precipPoints() -> [Point] { dayMap().map { Point(date: $0.0, y: $0.1.precipitationMm) } }

    // 有効積算温度：4/1以降、Tmax≥10 の日の Tmax を累積
    private func activeTempPoints() -> [Point] {
        let all = dayMap()
        guard let start = Calendar.current.date(from: DateComponents(year: selectedYear, month: 4, day: 1)) else { return [] }
        var sum: Double = 0
        var pts: [Point] = []
        for (d, w) in all {
            guard d >= start else { continue }
            if let tmax = w.tMax, tmax >= 10.0 { sum += tmax }
            pts.append(Point(date: d, y: sum))
        }
        return pts
    }

    // 満開（ステージコード23以上）以降の積算日照（品種別）
    private func sunshineVarietySeriesSource() -> [(Date, DailyWeather)] { dayMap() }

    private func cumulativeSunshineVarietySeries() -> [String: [Point]] {
        let varietals = varietiesInYearBlock(year: selectedYear, block: selectedBlock)
        let dm = sunshineVarietySeriesSource()
        var result: [String: [Point]] = [:]
        for v in varietals {
            guard let bloom = bloomDate(year: selectedYear, block: selectedBlock, variety: v) else { continue }
            var sum: Double = 0
            var pts: [Point] = []
            for (d, w) in dm where d >= bloom {
                if let s = w.sunshineHours { sum += s }
                pts.append(Point(date: d, y: sum))
            }
            if !pts.isEmpty { result[v] = pts }
        }
        return result
    }

    private func varietiesInYearBlock(year: Int, block: String) -> [String] {
        let cal = Calendar.current
        let names = store.entries.compactMap { e -> [String]? in
            guard e.block == block, cal.component(.year, from: e.date) == year else { return nil }
            return e.varieties.map { $0.varietyName }.filter { !$0.isEmpty }
        }.flatMap { $0 }
        return Array(Set(names)).sorted()
    }

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

    // MARK: - 共有ユーティリティ

    private func valueOn(date: Date, from pts: [Point]) -> Double? {
        let day = startOfDay(date)
        return pts.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) })?.y
    }
    
    private func xDomainApr1ToToday() -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: selectedYear, month: 4, day: 1))!
        // その区画・年の最後のデータ日（無ければ start）と “今日” の早い方まで
        let lastData = dayMap().last?.0 ?? start
        let end = min(cal.startOfDay(for: Date()), lastData)
        return start...end
    }

    private func xToDate(pos: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        let frame = geo[proxy.plotAreaFrame]
        let x = pos.x - frame.origin.x
        return proxy.value(atX: x)
    }

    private func startOfDay(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d)
    }

    private func dateLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "M/d"
        return df.string(from: date)
    }
}

// 軽量カード
fileprivate struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

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

// 角丸の小バブル
@ViewBuilder
private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.thinMaterial)
                .shadow(radius: 6)
        )
        .padding(8)
}

// yyyy-MM-dd パーサ（重複定義を避けるためローカルに用意）
fileprivate let yyyyMMddDF: DateFormatter = {
    let df = DateFormatter()
    df.calendar = Calendar(identifier: .gregorian)
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd"
    return df
}()

// 年ごとの共通 xDomain を計算
private func xDomainForYear(_ year: Int) -> ClosedRange<Date> {
    let cal = Calendar.current
    let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
    let endOfYear = cal.date(from: DateComponents(year: year, month: 12, day: 31))!
    let end = min(Date(), endOfYear) // 今日を上限
    return start...end
}


#endif
