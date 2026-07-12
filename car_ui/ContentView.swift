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
    @StateObject private var engineSound = EngineSoundController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("ダッシュボード", systemImage: "gauge.with.dots.needle.67percent")
                    }

                DataView()
                    .tabItem {
                        Label("データ", systemImage: "chart.bar.xaxis")
                    }

                DriveView()
                    .tabItem {
                        Label("ドライブ", systemImage: "steeringwheel")
                    }

                EngineSoundView()
                    .tabItem {
                        Label("エンジン音", systemImage: "engine.combustion.fill")
                    }

                ToolsView()
                    .tabItem {
                        Label("ツール", systemImage: "wrench.and.screwdriver")
                    }
            }

            // 全タブ共通の最下部バナー(タブバーの下)
            AdBannerView()
        }
        .environmentObject(obd)
        .environmentObject(location)
        .environmentObject(motion)
        .environmentObject(recorder)
        .environmentObject(engineSound)
        // ルートで購読することで、エンジン音タブを離れても再生が続く
        .onReceive(obd.$liveValues) { values in
            engineSound.ingest(values)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // バックグラウンド再生は v1 スコープ外(BLE も止まり RPM が届かないため)
            if newPhase == .background {
                engineSound.stop()
            }
        }
        .onAppear {
            motion.start()
        }
    }
}

#Preview {
    ContentView()
}
