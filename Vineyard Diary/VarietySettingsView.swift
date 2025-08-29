import SwiftUI

struct VarietySettingsView: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Column header
            HStack {
                Text("品種名").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 40)
            }.padding(.horizontal, 6)

            List {
                ForEach($store.settings.varieties) { $v in
                    HStack {
                        TextField("品種名", text: $v.name)
                        Button(role: .destructive) {
                            if let idx = store.settings.varieties.firstIndex(where: { $0.id == v.id }) {
                                store.settings.varieties.remove(at: idx)
                                store.save()
                            }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Button {
                    // Allow adding blank row, user may fill later
                    store.settings.varieties.append(.init(name: ""))
                    store.save()
                } label: { Label("行を追加", systemImage: "plus.circle") }
                Spacer()
            }
        }.padding()
    }
}
