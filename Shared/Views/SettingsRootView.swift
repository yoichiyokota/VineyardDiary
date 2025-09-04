import SwiftUI
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
import AudioToolbox
#endif


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
            text = ddToDMS(v)   // ← DMS.swift の関数を利用
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
        if let dd = dmsToDD(trimmed) {// ← DMS.swift の関数を利用
            value = dd
            text = ddToDMS(dd)       // 正規化して表示
        } else {
            playFeedback() // 入力が解釈できない場合
        }
    }
}

/// 10進度 (DD) → 度分秒文字列（例: 35°12'34.50" / -139°44'00.00"）
func ddToDMS(_ dd: Double) -> String {
    let sign = dd < 0 ? -1.0 : 1.0
    let absVal = abs(dd)
    let deg = Int(absVal.rounded(.down))
    let minFloat = (absVal - Double(deg)) * 60.0
    let min = Int(minFloat.rounded(.down))
    let sec = (minFloat - Double(min)) * 60.0
    let prefix = sign < 0 ? "-" : ""
    return String(format: "%@%d°%02d'%05.2f\"", prefix, deg, min, sec)
}

/// 度分秒文字列 → 10進度 (DD)
/// 受け入れ例: "35°12'34.5\"", "-139 44 0", "35d12m34.5s"
func dmsToDD(_ s: String) -> Double? {
    // 許容：度,分,秒 を区切る記号 / 空白 を広めに対応
    let pattern = #"^\s*([+-]?\d+)[°d\s]+(\d+)?['m\s]*([0-9.]+)?["s\s]*$"#
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
    let ns = s as NSString
    guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
    func group(_ i: Int) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }
    guard let degStr = group(1), let deg = Double(degStr) else { return nil }
    let min = Double(group(2) ?? "0") ?? 0
    let sec = Double(group(3) ?? "0") ?? 0
    let absVal = abs(deg) + min/60.0 + sec/3600.0
    return deg < 0 ? -absVal : absVal
}

func playFeedback() {
    #if os(macOS)
    // システム標準のビープでOK（または "Glass" など）
    NSSound.beep()
    #else
    if #available(iOS 10.0, *) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    } else {
        AudioServicesPlaySystemSound(1103) // 旧来のシステム音
    }
    #endif
}
