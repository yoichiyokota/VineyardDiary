import SwiftUI

struct StageSettingsView: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ステージ").font(.headline)
                Spacer()
                Button {
                    store.settings.stages.append(.init(code: 0, label: ""))
                    store.saveSettings()
                } label: { Label("追加", systemImage: "plus") }
            }

            List {
                ForEach(store.settings.stages) { s in
                    HStack(spacing: 8) {
                        // コード（Int）を数値ステッパーで
                        Stepper(value: bindingForCode(s), in: 0...999) {
                            Text("No.\(bindingForCode(s).wrappedValue)")
                                .frame(width: 72, alignment: .leading)
                        }
                        TextField("説明", text: bindingForLabel(s))
                            .textFieldStyle(.roundedBorder)
                        Spacer()
                        Button(role: .destructive) {
                            if let i = store.settings.stages.firstIndex(where: { $0.id == s.id }) {
                                store.settings.stages.remove(at: i)
                                store.saveSettings()
                            }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func bindingForCode(_ s: StageSetting) -> Binding<Int> {
        Binding(
            get: { s.code },
            set: { new in
                if let i = store.settings.stages.firstIndex(where: { $0.id == s.id }) {
                    store.settings.stages[i].code = new
                    store.saveSettings()
                }
            }
        )
    }

    private func bindingForLabel(_ s: StageSetting) -> Binding<String> {
        Binding(
            get: { s.label },
            set: { new in
                if let i = store.settings.stages.firstIndex(where: { $0.id == s.id }) {
                    store.settings.stages[i].label = new
                    store.saveSettings()
                }
            }
        )
    }
}
