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

            #if os(macOS)
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
            #else
            List {
                ForEach(store.settings.blocks) { b in
                    HStack(spacing: 12) {
                        TextField("名前", text: bindingForName(b))
                        DMSInputField(value: bindingForLat(b), isLat: true,  placeholder: "36°46'01.7\"N")
                        DMSInputField(value: bindingForLon(b), isLat: false, placeholder: "138°20'13.2\"E")
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
            }
            #endif
        }
        .onChange(of: store.settings.blocks) { _ in
            store.saveSettings()
        }
    }

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

// MARK: - 品種設定
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

// MARK: - DMS入力フィールド（DD(Double?) <-> DMS文字列 with N/E/S/W）
// ※ ddToDMSWithHemisphere / dmsToDDWithHemisphere は DMS.swift に実装済み前提。
//   （このファイルでは再定義しないでください：重複を避けるため）
private struct DMSInputField: View {
    @Binding var value: Double?
    let isLat: Bool
    var placeholder: String

    @State private var text: String
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    init(value: Binding<Double?>, isLat: Bool, placeholder: String) {
        self._value = value
        self.isLat = isLat
        self.placeholder = placeholder
        if let v = value.wrappedValue {
            _text = State(initialValue: ddToDMSWithHemisphere(v, isLat: isLat))
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($focused)
                .onSubmit { validateAndCommit() }
                .onChange(of: focused) { isFocused in
                    if !isFocused { validateAndCommit() }
                }
                .onChange(of: value) { _ in
                    guard !focused else { return }
                    if let v = value {
                        text = ddToDMSWithHemisphere(v, isLat: isLat)
                    } else {
                        text = ""
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(error == nil ? Color.clear : Color.red.opacity(0.6), lineWidth: 1)
                )

            if let msg = error {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .help(isLat
              ? "例: 36°46'01.7\"N（北緯N/南緯Sも可）／-36°46'01.7\" も可"
              : "例: 138°20'13.2\"E（東経E/西経Wも可）／-138°20'13.2\" も可")
    }

    private func validateAndCommit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            value = nil
            error = nil
            return
        }
        switch dmsToDDWithHemisphere(trimmed, isLat: isLat) {
        case .success(let dd):
            if isLat && (dd < -90 || dd > 90) {
                error = "緯度は -90〜90 の範囲で入力してください。"
                playFeedbackError(); return
            }
            if !isLat && (dd < -180 || dd > 180) {
                error = "経度は -180〜180 の範囲で入力してください。"
                playFeedbackError(); return
            }
            value = dd
            text = ddToDMSWithHemisphere(dd, isLat: isLat) // 正規化表示
            error = nil
        case .failure(let err):
            error = err.localizedDescription
            playFeedbackError()
        }
    }
}

func playFeedbackError() {
    #if os(macOS)
    NSSound.beep()
    #else
    if #available(iOS 10.0, *) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    } else {
        AudioServicesPlaySystemSound(1053)
    }
    #endif
}
