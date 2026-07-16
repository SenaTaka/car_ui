//
//  ContentView.swift
//  car_ui
//
//  Created by Sena Takasawa on 2026/2/20.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var obd = ELM327BluetoothModel()
    @StateObject private var location = LocationModel()
    @StateObject private var motion = MotionModel()
    @StateObject private var recorder = TelemetryRecorder.shared
    @StateObject private var engineSound = EngineSoundController()
    @StateObject private var tripComputer = TripComputerModel()
    @State private var proStore = ProStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("ダッシュボード", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

            DataView()
                .tabItem {
                    Label("データ", systemImage: "chart.bar.xaxis")
                }
                .tag(1)

            DriveView()
                .tabItem {
                    Label("ドライブ", systemImage: "steeringwheel")
                }
                .tag(2)

            EngineSoundView()
                .tabItem {
                    Label("エンジン音", systemImage: "engine.combustion.fill")
                }
                .tag(3)

            ToolsView()
                .tabItem {
                    Label("ツール", systemImage: "wrench.and.screwdriver")
                }
                .tag(4)
        }
        // 全タブ共通の最下部バナー。safeAreaInset なのでタブバーはバナーの上に
        // 正しく持ち上がり、下端が切れない。Pro / 広告除去購入者は非表示。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !proStore.removesAds {
                AdBannerView()
            }
        }
        .environmentObject(obd)
        .environmentObject(location)
        .environmentObject(motion)
        .environmentObject(recorder)
        .environmentObject(engineSound)
        .environmentObject(tripComputer)
        .environment(proStore)
        // ルートで購読することで、エンジン音タブを離れても再生が続く
        .onReceive(obd.$liveValues) { values in
            engineSound.ingest(values)
            tripComputer.ingest(values)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 車載利用中は画面を暗転・スリープさせない(前面のときだけ有効化し、
            // 背面ではロックを解放して電池を無駄にしない)
            UIApplication.shared.isIdleTimerDisabled = (newPhase == .active)
            // エンジン音は他アプリ表示中もバックグラウンド再生を継続する
            // (Info.plist の UIBackgroundModes=audio + .playback セッション)。
            // OBD も背面継続(bluetooth-central)。駐車中の電池消費は
            // モデル側の駐車検知オートオフで保護する。
            obd.setBackgrounded(newPhase == .background)
        }
        .onAppear {
            motion.start()
            UIApplication.shared.isIdleTimerDisabled = true
            applyUITestLaunchArgumentsIfPresent()
        }
    }

    /// App Store スクショ撮影用フック。起動引数が無ければ何もしない(本番挙動は不変)。
    /// `-uiDemo 1` でデモモード表示、`-uiTab N`(0〜4)で初期表示タブを指定する。
    private func applyUITestLaunchArgumentsIfPresent() {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        if value(after: "-uiDemo") == "1" {
            obd.startDemoMode()
        }
        if let tabString = value(after: "-uiTab"), let tab = Int(tabString), (0...4).contains(tab) {
            selectedTab = tab
        }
    }
}

#Preview {
    ContentView()
}
