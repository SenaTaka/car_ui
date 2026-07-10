//
//  ContentView.swift
//  car_ui
//
//  Created by Sena Takasawa on 2026/2/20.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var obd = ELM327BluetoothModel()
    @StateObject private var location = LocationModel()
    @StateObject private var motion = MotionModel()
    @StateObject private var recorder = TelemetryRecorder.shared

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("ダッシュボード", systemImage: "gauge.with.dots.needle.67percent")
                }

            SensorsView()
                .tabItem {
                    Label("センサー", systemImage: "square.grid.3x3")
                }

            ChartsView()
                .tabItem {
                    Label("チャート", systemImage: "chart.xyaxis.line")
                }

            DriveView()
                .tabItem {
                    Label("ドライブ", systemImage: "steeringwheel")
                }

            ToolsView()
                .tabItem {
                    Label("ツール", systemImage: "wrench.and.screwdriver")
                }
        }
        .environmentObject(obd)
        .environmentObject(location)
        .environmentObject(motion)
        .environmentObject(recorder)
        .onAppear {
            motion.start()
        }
    }
}

#Preview {
    ContentView()
}
