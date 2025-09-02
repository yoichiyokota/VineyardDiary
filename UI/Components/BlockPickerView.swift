import SwiftUI

/// 区画セレクタ。先頭 "" を「すべて」として扱う。
struct BlockPickerView: View {
    @ObservedObject var state: YearBlockFilterState

    var body: some View {
        HStack(spacing: 6) {
            Text("区画")
            Picker("区画を選択", selection: $state.selectedBlock) {
                Text("すべて").tag("")
                ForEach(state.blocks, id: \.self) { name in
                    if !name.isEmpty { Text(name).tag(name) }
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 160)
        }
        .accessibilityLabel(Text("区画を選択"))
    }
}