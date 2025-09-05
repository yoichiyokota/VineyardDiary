//
//  InteractionProbeView.swift
//  Vineyard Diary
//
//  Created by yoichi_yokota on 2025/09/05.
//


import SwiftUI

struct InteractionProbeView: View {
    @State private var count = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Interaction Probe").font(.title2).bold()

                Button {
                    count += 1
                    print("✅ Button tapped. count=\(count)")
                } label: {
                    Text("Count: \(count)")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(10)
                }

                Text("Tap me")
                    .padding(12)
                    .background(.yellow.opacity(0.6))
                    .cornerRadius(8)
                    .onTapGesture { print("✅ Text tapped") }

                List {
                    Button("Row Button") { print("✅ Row button tapped") }
                        .buttonStyle(.plain)
                }
                .frame(height: 180)
                .listStyle(.plain)

                Spacer()
            }
            .padding()
            .navigationTitle("Probe")
        }
    }
}