import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        TabView {
            BlocksPane()
                .tabItem { Label("畑", systemImage: "leaf") }

            VarietiesPane()
                .tabItem { Label("品種", systemImage: "leaf.circle") }

            StageSettingsView()
                .tabItem { Label("ステージ", systemImage: "list.number") }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - 畑（行ごとに削除ボタン）
private struct BlocksPane: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("畑リスト").font(.headline)
                Spacer()
                Button {
                    store.settings.blocks.append(.init(name: "", latitude: nil, longitude: nil))
                    store.saveSettings()
                } label: { Label("追加", systemImage: "plus") }
            }

            Table(store.settings.blocks) {
                TableColumn("名前") { b in
                    HStack {
                        TextField("名前", text: bindingForName(b))
                        Spacer()
                        Button(role: .destructive) {
                            if let i = index(of: b) {
                                store.settings.blocks.remove(at: i)
                                store.saveSettings()
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                TableColumn("緯度") { b in
                    TextField("緯度", text: bindingForLatString(b))
                }
                TableColumn("経度") { b in
                    TextField("経度", text: bindingForLonString(b))
                }
            }
        }
    }

    private func index(of b: BlockSetting) -> Int? {
        store.settings.blocks.firstIndex(where: { $0.id == b.id })
    }

    private func bindingForName(_ b: BlockSetting) -> Binding<String> {
        Binding(
            get: { b.name },
            set: { new in
                if let i = index(of: b) { store.settings.blocks[i].name = new; store.saveSettings() }
            }
        )
    }
    private func bindingForLatString(_ b: BlockSetting) -> Binding<String> {
        Binding(
            get: { b.latitude.map { String($0) } ?? "" },
            set: { new in
                if let i = index(of: b) { store.settings.blocks[i].latitude = Double(new); store.saveSettings() }
            }
        )
    }
    private func bindingForLonString(_ b: BlockSetting) -> Binding<String> {
        Binding(
            get: { b.longitude.map { String($0) } ?? "" },
            set: { new in
                if let i = index(of: b) { store.settings.blocks[i].longitude = Double(new); store.saveSettings() }
            }
        )
    }
}

// MARK: - 品種
private struct VarietiesPane: View {
    @EnvironmentObject var store: DiaryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("品種").font(.headline)
                Spacer()
                Button {
                    store.settings.varieties.append(.init(name: ""))
                    store.saveSettings()
                } label: { Label("追加", systemImage: "plus") }
            }

            List {
                ForEach(store.settings.varieties) { v in
                    HStack {
                        TextField("品種名", text: bindingForName(v))
                        Spacer()
                        Button(role: .destructive) {
                            if let i = store.settings.varieties.firstIndex(where: { $0.id == v.id }) {
                                store.settings.varieties.remove(at: i)
                                store.saveSettings()
                            }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func bindingForName(_ v: VarietySetting) -> Binding<String> {
        Binding(
            get: { v.name },
            set: { new in
                if let i = store.settings.varieties.firstIndex(where: { $0.id == v.id }) {
                    store.settings.varieties[i].name = new
                    store.saveSettings()
                }
            }
        )
    }
}
