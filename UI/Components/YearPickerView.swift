import SwiftUI

/// 年のセレクタ（4桁西暦）。デフォルトは当年から過去へ。
struct YearPickerView: View {
    @ObservedObject var state: YearBlockFilterState

    var body: some View {
        HStack(spacing: 6) {
            Text("年")
            Picker("年を選択", selection: $state.selectedYear) {
                ForEach(availableYears(), id: \.self) { y in
                    Text("\(y)").tag(y)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120)
        }
        .accessibilityLabel(Text("年を選択"))
    }

    private func availableYears() -> [Int] {
        // 最小年は必要に応じて調整。ここでは 2015〜当年。
        let thisYear = Calendar.current.component(.year, from: Date())
        let start = 2015
        return Array(start...thisYear).reversed()
    }
}
