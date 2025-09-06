import SwiftUI
import Charts

struct GDDPanel: View {
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var weather: DailyWeatherStore

    @Binding var selectedYear: Int       // ← 変更: Binding
    @Binding var selectedBlock: String   // ← 変更: Binding

    @State private var method: GDDMethod = .effective
    @State private var startRule: GDDStartRule = .autoBudbreakOrApril1

    @State private var daily: [GDDPoint] = []
    @State private var accum: [GDDPoint] = []
    @State private var message: String?

    // ホバー
    @State private var hoverDay: Date?
    @State private var hoverDailyValue: Double?
    @State private var hoverAccumValue: Double?

    private let dfDay: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "M/d(EEE)"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("有効積算温度 (GDD)")
                .font(.title3).bold()

            // 方式／起点／再計算
            HStack(spacing: 12) {
                Picker("方式", selection: $method) {
                    Text("10℃以上単純積算").tag(GDDMethod.classicBase10)
                    Text("10〜30℃ eGDD").tag(GDDMethod.effective)
                }
                .pickerStyle(.segmented)

                Picker("起点", selection: $startRule) {
                    Text("4/1固定").tag(GDDStartRule.fixedApril1)
                    Text("萌芽 or 4/1").tag(GDDStartRule.autoBudbreakOrApril1)
                }
                .pickerStyle(.segmented)

                Spacer()

            }

            if accum.isEmpty {
                Text(message ?? "GDDデータなし")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Chart {
                    // 日次（棒）
                    ForEach(daily, id: \.id) { p in
                        BarMark(
                            x: .value("日付", p.day),
                            y: .value("日次GDD", p.value)
                        )
                        .opacity(0.35)
                    }
                    // 累積（折線）
                    ForEach(accum, id: \.id) { p in
                        LineMark(
                            x: .value("日付", p.day),
                            y: .value("累積GDD", p.value)
                        )
                        .interpolationMethod(.monotone)
                    }
                    // ホバー縦線＆ポイント
                    if let d = hoverDay {
                        RuleMark(x: .value("日付", d))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        if let ad = hoverDailyValue {
                            PointMark(x: .value("日付", d), y: .value("日次GDD", ad))
                                .symbolSize(50)
                                .foregroundStyle(.secondary)
                        }
                        if let ac = hoverAccumValue {
                            PointMark(x: .value("日付", d), y: .value("累積GDD", ac))
                                .symbolSize(50)
                        }
                    }
                }
                .chartYScale(domain: niceYDomain())
                .frame(minHeight: 240)

                // 左上ホバーバルーン（他グラフと同じ位置＆見た目）
                .overlay(alignment: .topLeading) {
                    if let d = hoverDay,
                       let ad = hoverDailyValue,
                       let ac = hoverAccumValue {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dfDay.string(from: d))
                                .font(.caption).bold()
                            Text("日次 \(format1(ad)) / 累積 \(format0(ac))")
                                .font(.caption2)
                        }
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 8)
                        .padding(.leading, 8)
                    }
                }

                // 共通ホバー取得：macOS はカーソル移動、iOS はドラッグ
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotOrigin = geo[proxy.plotAreaFrame].origin
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            #if os(macOS)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    let xInPlot = loc.x - plotOrigin.x
                                    if let date: Date = proxy.value(atX: xInPlot) {
                                        updateHover(date: date)
                                    }
                                case .ended:
                                    clearHover()
                                }
                            }
                            #else
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let xInPlot = value.location.x - plotOrigin.x
                                        if let date: Date = proxy.value(atX: xInPlot) {
                                            updateHover(date: date)
                                        }
                                    }
                                    .onEnded { _ in clearHover() }
                            )
                            #endif
                    }
                }
            }
        }
        // 初期値は設定から引き継ぎ
        .onAppear {
            method = store.settings.gddMethod
            startRule = store.settings.gddStartRule
            // 追加：表示名→正式名に寄せる（先頭一致で拾う）
            let canon = canonicalBlockName(from: selectedBlock)
            if canon != selectedBlock { selectedBlock = canon }
            recompute()
        }
        // 方式/起点が変わったら設定に保存して即再計算
        .onChange(of: method) { new in
            store.settings.gddMethod = new
            store.saveSettings()
            recompute()
        }
        .onChange(of: startRule) { new in
            store.settings.gddStartRule = new
            store.saveSettings()
            recompute()
        }
        // 親から渡された年/区画が変わったら即再計算
        .onChange(of: selectedYear) { _ in
            recompute()
        }
        .onChange(of: selectedBlock) { _ in
            recompute()
        }
    }

    // MARK: - 計算
    @MainActor
    private func recompute() {
        message = nil
        guard selectedYear != 0 else {
            daily = []; accum = []
            message = "年の選択がありません。"
            return
        }

        // 表示名に標高等が付く場合でも、設定の name に寄せてから渡す
        let blockParam: String? = {
            let canonical = canonicalBlockName(from: selectedBlock)
            return canonical.isEmpty ? nil : canonical
        }()

        let dailySeries = GDDSeriesBuilder.dailySeries(
            store: store,
            weather: weather,
            year: selectedYear,
            block: blockParam,          // ← 選択ブロックをそのまま反映
            variety: nil,
            method: method,
            rule: startRule,
            base: 10.0
        )
        // test
        print("dailySeries year=\(selectedYear) block=\(blockParam ?? "<nil>") method=\(method) rule=\(startRule)")
        //
        
        let accumSeries = GDDSeriesBuilder.cumulativeSeries(from: dailySeries)

        if dailySeries.isEmpty || accumSeries.isEmpty {
            daily = []; accum = []
            message = "GDDデータなし（起点・収穫日や気象データの有無をご確認ください）"
        } else {
            daily = dailySeries
            accum = accumSeries
        }
        
#if DEBUG
print("[GDD] year=\(selectedYear) block=\(canonicalBlockName(from: selectedBlock)) method=\(method) rule=\(startRule)")
print("[GDD] daily=\(dailySeries.count) accum=\(accumSeries.count)")
#endif
    }

    // MARK: - ホバー
    private func updateHover(date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        hoverDay = day
        hoverDailyValue = valueForDay(in: daily, day: day)
        hoverAccumValue = valueForDay(in: accum, day: day)
    }

    private func clearHover() {
        hoverDay = nil
        hoverDailyValue = nil
        hoverAccumValue = nil
    }

    private func valueForDay(in series: [GDDPoint], day: Date) -> Double? {
        let cal = Calendar.current
        return series.first(where: { cal.isDate($0.day, inSameDayAs: day) })?.value
    }

    // MARK: - 補助
    private func niceYDomain() -> ClosedRange<Double> {
        let maxV = max(accum.map(\.value).max() ?? 0, daily.map(\.value).max() ?? 0)
        let pad = max(50, maxV * 0.05)
        return 0...(maxV + pad)
    }
    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format1(_ v: Double) -> String { String(format: "%.1f", v) }

    // 表示名（例 "深沢(630m)"）から正式キー（設定の name）へ寄せる
    private func canonicalBlockName(from display: String) -> String {
        guard !display.isEmpty else { return "" }
        if let hit = store.settings.blocks.first(where: { display.hasPrefix($0.name) }) {
            return hit.name
        }
        return display
    }
}
