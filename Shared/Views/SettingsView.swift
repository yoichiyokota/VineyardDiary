import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SettingsRootView()
                .tabItem { Label("畑リスト", systemImage: "leaf") }
            StageSettingsView()
                .tabItem { Label("ステージ", systemImage: "chart.bar.doc.horizontal") }
            VarietySettingsView()
                .tabItem { Label("品種", systemImage: "square.grid.2x2") }
        }
        .frame(minWidth: 620, minHeight: 460)
        .padding()
    }
}
