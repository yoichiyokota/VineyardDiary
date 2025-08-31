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

// MARK: - 畑設定（緯度・経度をDMS形式で表示／編集）
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
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }

                TableColumn("緯度（DMS）") { b in
                    DMSInputField(value: bindingForLat(b), isLat: true, placeholder: "36°46'01.7\"N")
                }

                TableColumn("経度（DMS）") { b in
                    DMSInputField(value: bindingForLon(b), isLat: false, placeholder: "138°20'13.2\"E")
                }
            }
        }
    }

    // MARK: - バインディング生成
    private func index(of b: BlockSetting) -> Int? {
        store.settings.blocks.firstIndex(where: { $0.id == b.id })
    }

    private func bindingForName(_ b: BlockSetting) -> Binding<String> {
        Binding(
            get: { b.name },
            set: { new in
                if let i = index(of: b) {
                    store.settings.blocks[i].name = new
                    store.saveSettings()
                }
            }
        )
    }

    private func bindingForLat(_ b: BlockSetting) -> Binding<Double?> {
        Binding(
            get: { b.latitude },
            set: { new in
                if let i = index(of: b) {
                    store.settings.blocks[i].latitude = new
                    store.saveSettings()
                }
            }
        )
    }

    private func bindingForLon(_ b: BlockSetting) -> Binding<Double?> {
        Binding(
            get: { b.longitude },
            set: { new in
                if let i = index(of: b) {
                    store.settings.blocks[i].longitude = new
                    store.saveSettings()
                }
            }
        )
    }
}

// MARK: - 品種設定（従来どおり）
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

// MARK: - DMS入力フィールド（Double? <-> DMS文字列）
private struct DMSInputField: View {
    @Binding var value: Double?
    let isLat: Bool
    var placeholder: String

    @State private var text: String = ""

    var body: some View {
        TextField(placeholder, text: $text, onCommit: commit)
            .textFieldStyle(.roundedBorder)
            .onAppear { syncFromModel() }
            .onChange(of: value) { _ in syncFromModel() }
            .onSubmit { commit() }
            .frame(maxWidth: .infinity)
            .help(isLat
                  ? "緯度（N/S）。例: 36°46'01.7\"N"
                  : "経度（E/W）。例: 138°20'13.2\"E")
    }

    private func syncFromModel() {
        if let v = value {
            text = ddToDMS(v, isLat: isLat)   // ← DMS.swift の関数を利用
        } else {
            text = ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            value = nil
            return
        }
        if let dd = dmsToDD(trimmed, isLat: isLat) { // ← DMS.swift の関数を利用
            value = dd
            text = ddToDMS(dd, isLat: isLat)        // 正規化して表示
        } else {
            NSSound.beep() // 入力が解釈できない場合
        }
    }
}
