import SwiftUI
import Charts

// ホバー中の選択点（全グラフで共通）
struct SelectedPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
    let series: String? // "最高"/"最低" や 品種名。単線のときは nil
}

struct StatisticsView: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedBlock: String = ""

    // グラフごとのホバー選択状態
    @State private var selTemp: SelectedPoint?
    @State private var selSun: SelectedPoint?
    @State private var selCumulTemp: SelectedPoint?
    @State private var selCumulSunVar: SelectedPoint?

    // バブルの表示位置（各グラフ用）
    @State private var posTemp: CGPoint?
    @State private var posSun: CGPoint?
    @State private var posCumulTemp: CGPoint?
    @State private var posCumulSunVar: CGPoint?

    // 「2,025」ではなく「2025」にするための整形
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
                    temperatureSection                 // 最高=赤 / 最低=青（ホバー）
                    sunshineSection                    // 日照（棒）（ホバー）
                    cumulativeTemperatureSection       // 有効積算温度（畑ごと1本）（ホバー）
                    cumulativeSunshineVarietySection   // 積算日照（品種別）（ホバー）
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .onAppear {
            // 設定に無い区画は選ばせない
            let valid = Set(store.settings.blocks.map { $0.name })
            if selectedBlock.isEmpty || !valid.contains(selectedBlock) {
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

    // MARK: - 型
    private enum SeriesKind { case tMax, tMin, sun }
    private struct Point: Identifiable { let id = UUID(); let date: Date; let value: Double? }
    private struct TempPoint: Identifiable { let id = UUID(); let date: Date; let value: Double; let series: String }
    private struct SeriesPoint: Identifiable { let id = UUID(); let date: Date; let value: Double?; let series: String }

    // MARK: - 気温（最高/最低：色分け + ホバー）
    private var temperatureSection: some View {
        let data = tempPoints()
        return Group {
            Text("気温の推移（最高・最低）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(data) { p in
                    LineMark(
                        x: .value("日付", p.date),
                        y: .value(p.series, p.value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("系列", p.series))
                }
            }
            .chartForegroundStyleScale(["最高": .red, "最低": .blue])
            .chartLegend(position: .top, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = proxy.plotAreaFrame
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard
                                    let date = xToDate(loc.x, proxy: proxy, geo: geo),
                                    let targetY = yToTempValue(loc.y, proxy: proxy, geo: geo)
                                else { return }

                                if let (d, v, s) = nearestTempPoint2D(toDate: date, targetY: targetY, in: data) {
                                    selTemp = SelectedPoint(date: d, value: v, series: s)
                                    posTemp = adjustBubblePoint(loc, in: geo[plot], bubbleWidth: 200, bubbleHeight: 34)
                                }
                            case .ended:
                                selTemp = nil
                                posTemp = nil
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let s = selTemp, let pt = posTemp {
                                InfoBubble(date: s.date, value: s.value, series: s.series)
                                    .position(x: pt.x, y: pt.y - 18)
                            }
                        }
                }
            }
            .frame(height: 340)
            .panelBackground()
        }
    }

    private func tempPoints() -> [TempPoint] {
        let seq = daySequence()
        var pts: [TempPoint] = []
        for (d, dw) in seq {
            if let tmax = dw.tMax { pts.append(TempPoint(date: d, value: tmax, series: "最高")) }
            if let tmin = dw.tMin { pts.append(TempPoint(date: d, value: tmin, series: "最低")) }
        }
        return pts
    }

    // MARK: - 日照（棒 + ホバー）
    private var sunshineSection: some View {
        let pts = points(kind: .sun)
        return Group {
            Text("日照時間の推移（棒グラフ）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(pts) { p in
                    if let v = p.value {
                        BarMark(
                            x: .value("日付", p.date),
                            y: .value("日照(h)", v)
                        )
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = proxy.plotAreaFrame
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let date = xToDate(loc.x, proxy: proxy, geo: geo) else { return }
                                if let (d, v) = nearestBarPoint(to: date, in: pts) {
                                    selSun = SelectedPoint(date: d, value: v, series: nil)
                                    posSun = adjustBubblePoint(loc, in: geo[plot], bubbleWidth: 180, bubbleHeight: 32)
                                }
                            case .ended:
                                selSun = nil
                                posSun = nil
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let s = selSun, let pt = posSun {
                                InfoBubble(date: s.date, value: s.value, series: s.series)
                                    .position(x: pt.x, y: pt.y - 18)
                            }
                        }
                }
            }
            .frame(height: 260)
            .panelBackground()
        }
    }

    // MARK: - 有効積算温度（畑ごと1本 + ホバー）
    private var cumulativeTemperatureSection: some View {
        let pts = cumulativeActiveTempPoints()
        return Group {
            Text("有効積算温度（4/1〜：最高気温が10℃以上の日の最高気温を加算）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(pts) { p in
                    if let v = p.value {
                        LineMark(
                            x: .value("日付", p.date),
                            y: .value("積算温度(℃)", v)
                        )
                        .interpolationMethod(.monotone)
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = proxy.plotAreaFrame
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let date = xToDate(loc.x, proxy: proxy, geo: geo) else { return }
                                if let (d, v) = nearestLinePoint(to: date, in: pts) {
                                    selCumulTemp = SelectedPoint(date: d, value: v, series: nil)
                                    posCumulTemp = adjustBubblePoint(loc, in: geo[plot], bubbleWidth: 200, bubbleHeight: 34)
                                }
                            case .ended:
                                selCumulTemp = nil
                                posCumulTemp = nil
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let s = selCumulTemp, let pt = posCumulTemp {
                                InfoBubble(date: s.date, value: s.value, series: s.series)
                                    .position(x: pt.x, y: pt.y - 18)
                            }
                        }
                }
            }
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

    // MARK: - 積算日照（品種別 + ホバー）
    private var cumulativeSunshineVarietySection: some View {
        let all = cumulativeSunshineVarietyPoints()
        return Group {
            Text("積算日照時間（品種別・満開=ステージNo.23以降を累積）")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(all) { p in
                    if let v = p.value {
                        LineMark(
                            x: .value("日付", p.date),
                            y: .value("積算日照(h)", v)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("品種", p.series))
                    }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = proxy.plotAreaFrame
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let date = xToDate(loc.x, proxy: proxy, geo: geo) else { return }
                                if let (d, v, s) = nearestSeriesPoint(to: date, in: all) {
                                    selCumulSunVar = SelectedPoint(date: d, value: v, series: s)
                                    posCumulSunVar = adjustBubblePoint(loc, in: geo[plot], bubbleWidth: 220, bubbleHeight: 34)
                                }
                            case .ended:
                                selCumulSunVar = nil
                                posCumulSunVar = nil
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let s = selCumulSunVar, let pt = posCumulSunVar {
                                InfoBubble(date: s.date, value: s.value, series: s.series)
                                    .position(x: pt.x, y: pt.y - 18)
                            }
                        }
                }
            }
            .frame(height: 320)
            .panelBackground()
        }
    }

    // —— ここから下は StatisticsView の内部に必ず置いてください ——

    // 品種別の積算日照ポイント
    private func cumulativeSunshineVarietyPoints() -> [SeriesPoint] {
        let seq = daySequence()
        guard !seq.isEmpty else { return [] }

        var all: [SeriesPoint] = []
        let varieties = varietiesInYearAndBlock()

        // 日付→日照時間の辞書
        let sunByDate: [Date: Double] = Dictionary(uniqueKeysWithValues:
            seq.map { (d, dw) in (d, dw.sunshineHours ?? 0.0) }
        )

        for variety in varieties {
            guard let bloom = bloomDate(block: selectedBlock, variety: variety, year: selectedYear) else {
                continue // 満開日が無ければ線を描かない
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

    // 当年の1年分の（選択区画の）日次データ
    private func daySequence() -> [(Date, DailyWeather)] {
        let valid = Set(store.settings.blocks.map { $0.name })
        guard !selectedBlock.isEmpty, valid.contains(selectedBlock),
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

    // 品種別の満開日（ステージNo.23以上の最初の日）
    private func bloomDate(block: String, variety: String, year: Int) -> Date? {
        let cal = Calendar.current
        let entries = store.entries
            .filter { $0.block == block && cal.component(.year, from: $0.date) == year }
            .sorted { $0.date < $1.date }

        for e in entries {
            if let item = e.varieties.first(where: { $0.varietyName == variety }) {
                if let no = leadingStageNumber(item.stage), no >= 23 {
                    return cal.startOfDay(for: e.date)
                }
            }
        }
        return nil
    }

    private func leadingStageNumber(_ s: String) -> Int? {
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }

    private func varietiesInYearAndBlock() -> [String] {
        let cal = Calendar.current
        let set = Set(
            store.entries
                .filter { $0.block == selectedBlock && cal.component(.year, from: $0.date) == selectedYear }
                .flatMap { $0.varieties.map { $0.varietyName } }
        )
        return Array(set).sorted()
    }

    // MARK: - ホバー座標→日付・温度、バブル位置の調整、最近傍点探索
    private func xToDate(_ x: CGFloat, proxy: ChartProxy, geo: GeometryProxy) -> Date? {
        let plot = proxy.plotAreaFrame
        let relX = x - geo[plot].origin.x
        let pxX = geo[plot].origin.x + relX
        return proxy.value(atX: pxX) as Date?
    }

    // 温度用：Y座標→値(Double)を逆算
    private func yToTempValue(_ y: CGFloat, proxy: ChartProxy, geo: GeometryProxy) -> Double? {
        let plot = proxy.plotAreaFrame
        let relY = y - geo[plot].origin.y
        let py = geo[plot].origin.y + relY
        return proxy.value(atY: py) as Double?
    }

    // バブルがプロットエリアからはみ出ないように中央基準で調整
    private func adjustBubblePoint(_ loc: CGPoint, in rect: CGRect,
                                   bubbleWidth: CGFloat = 180, bubbleHeight: CGFloat = 32,
                                   margin: CGFloat = 8) -> CGPoint {
        let halfW = bubbleWidth / 2
        let halfH = bubbleHeight / 2

        let minX = rect.minX + halfW + margin
        let maxX = rect.maxX - halfW - margin
        let minY = rect.minY + halfH + margin
        let maxY = rect.maxY - halfH - margin

        let x = min(max(loc.x, minX), maxX)
        let y = min(max(loc.y, minY), maxY)

        return CGPoint(x: x, y: y)
    }

    // 2D最近傍（同一日なら Y により「最高/最低」を正しく選ぶ）
    private func nearestTempPoint2D(
        toDate date: Date,
        targetY: Double,
        in data: [TempPoint]
    ) -> (Date, Double, String)? {
        guard !data.isEmpty else { return nil }
        let byDate = data.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }!
        let sameDay = data.filter { Calendar.current.isDate($0.date, inSameDayAs: byDate.date) }
        if sameDay.count >= 2 {
            let bestY = sameDay.min { abs($0.value - targetY) < abs($1.value - targetY) }!
            return (bestY.date, bestY.value, bestY.series)
        } else {
            return (byDate.date, byDate.value, byDate.series)
        }
    }

    private func nearestBarPoint(to date: Date, in pts: [Point]) -> (Date, Double)? {
        let cand = pts.compactMap { p -> (Date, Double)? in
            guard let v = p.value else { return nil }
            return (p.date, v)
        }
        guard !cand.isEmpty else { return nil }
        let best = cand.min { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }!
        return best
    }

    private func nearestLinePoint(to date: Date, in pts: [Point]) -> (Date, Double)? {
        let cand = pts.compactMap { p -> (Date, Double)? in
            guard let v = p.value else { return nil }
            return (p.date, v)
        }
        guard !cand.isEmpty else { return nil }
        let best = cand.min { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }!
        return best
    }

    private func nearestSeriesPoint(to date: Date, in pts: [SeriesPoint]) -> (Date, Double, String)? {
        let cand = pts.compactMap { p -> (Date, Double, String)? in
            guard let v = p.value else { return nil }
            return (p.date, v, p.series)
        }
        guard !cand.isEmpty else { return nil }
        let best = cand.min { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }!
        return best
    }
}

// MARK: - フロートUI（ホバーで表示）
private struct InfoBubble: View {
    let date: Date
    let value: Double
    let series: String?

    private var dateStr: String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy/MM/dd"
        return df.string(from: date)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(dateStr).font(.caption).foregroundStyle(.secondary)
            if let s = series, !s.isEmpty {
                Text(s).font(.caption).bold()
                Divider().frame(height: 12)
            }
            Text(String(format: "%.2f", value)).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
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
