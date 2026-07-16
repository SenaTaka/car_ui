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
    // 初回接続成功後に一度だけ出すプラン提案(価値体験の直後が最も反発が少ない)
    @AppStorage("paywall.introOffered") private var introOffered = false
    // 監査 REL-012: スリープ防止は接続中のみ+設定で無効化可能
    @AppStorage("display.keepAwakeWhileConnected") private var keepAwakeWhileConnected = true
    @State private var showingIntroPaywall = false
    @State private var suppressIntroOffer = false

    var body: some View {
        VStack(spacing: 0) {
            tabs
            // 全タブ共通の最下部バナー(タブバーの下)。Pro / 広告除去購入者は非表示。
            // safeAreaInset だと iOS 26 のフローティングタブバーにバナーが被さるため
            // VStack で下に積む(バナーは未ロード時 高さ 0)。
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
        // この sheet は .environment(proStore) より外側に付くため、
        // シート内容へ明示的に環境を注入する(欠けると起動時クラッシュ)
        .sheet(isPresented: $showingIntroPaywall) {
            PaywallView()
                .environment(proStore)
        }
        .onChange(of: obd.phase.isConnected) { _, isConnected in
            updateScreenWake()
            guard isConnected, !introOffered, !suppressIntroOffer,
                  !proStore.isPro, !proStore.isAdFree else { return }
            introOffered = true
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showingIntroPaywall = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 監査 REL-012: スリープ防止は「前面 + OBD 接続中 + 設定オン」のときだけ
            updateScreenWake()
            // エンジン音は他アプリ表示中もバックグラウンド再生を継続する
            // (Info.plist の UIBackgroundModes=audio + .playback セッション)。
            // OBD も背面継続(bluetooth-central)。駐車中の電池消費は
            // モデル側の駐車検知オートオフで保護する。
            obd.setBackgrounded(newPhase == .background)
            // 監査 REL-011: 背面移行時に記録と軌跡をディスクへ退避(強制終了に備える)
            if newPhase == .background {
                recorder.persistToDisk()
                TrackStore.shared.persistToDisk()
            }
        }
        .onChange(of: keepAwakeWhileConnected) { _, _ in
            updateScreenWake()
        }
        .onAppear {
            motion.start()
            updateScreenWake()
            applyUITestLaunchArgumentsIfPresent()
        }
        // 監査 REL-007: 起動ごとに UMP 同意情報を更新し、必要な同意フォームを表示。
        // 同意が確定するまで広告 SDK は開始されない(広告除去購入者には不要)。
        .task {
            if !proStore.removesAds {
                await AdConsentManager.shared.gatherConsent()
            }
        }
    }

    private var tabs: some View {
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
    }

    /// 監査 REL-012: 画面スリープ防止は「前面 + OBD 接続中(デモ含む)+ 設定オン」に限定。
    private func updateScreenWake() {
        UIApplication.shared.isIdleTimerDisabled =
            keepAwakeWhileConnected && scenePhase == .active && obd.phase.isConnected
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
            // スクショ撮影を初回提案シートで汚さない
            suppressIntroOffer = true
            obd.startDemoMode()
        }
        if let tabString = value(after: "-uiTab"), let tab = Int(tabString), (0...4).contains(tab) {
            selectedTab = tab
        }
        // 初回提案シートの検証用フック(フラグ状態に関係なく強制表示)
        if value(after: "-uiIntroOffer") == "1" {
            showingIntroPaywall = true
        }
    }
}

#Preview {
    ContentView()
}
