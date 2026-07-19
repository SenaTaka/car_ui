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
    // 初回起動オンボーディング(完了フラグは永続化、その他タブから再表示可)
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showingOnboarding = false

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
        // iPhone 16 等でタブバーが下端セーフエリアに寄って切れるため少し持ち上げる
        .padding(.bottom, 10)
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
        // セッションの走行距離を LocationModel の積算距離から更新
        .onReceive(location.$totalDistanceKm) { km in
            DriveSessionManager.shared.updateDistance(km)
        }
        // この sheet は .environment(proStore) より外側に付くため、
        // シート内容へ明示的に環境を注入する(欠けると起動時クラッシュ)
        .sheet(isPresented: $showingIntroPaywall) {
            PaywallView()
                .environment(proStore)
        }
        // 初回起動オンボーディング。閉じる操作では消せず、選択で完了する
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(initialStepIndex: uiOnboardingInitialStep) { outcome in
                completeOnboarding(with: outcome)
            }
            .environmentObject(obd)
        }
        // その他タブの「はじめかたをもう一度見る」から再表示
        .onReceive(NotificationCenter.default.publisher(for: .carUIShowOnboarding)) { _ in
            showingOnboarding = true
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
            // モーション権限は実際に使う画面(走行タブ等)の onAppear で要求する
            // (起動直後にダイアログを出さないため。DriveView.onAppear 参照)
            updateScreenWake()
            applyUITestLaunchArgumentsIfPresent()
            // 初回起動のみオンボーディングを表示(スクショ撮影フックの起動時は出さない)
            if !onboardingCompleted, !isUITestRun {
                showingOnboarding = true
            }
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
        // レビュー 1-1: 5タブを行動単位へ再定義(メーター/走行/分析/サウンド/その他)
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("メーター", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

            DriveView()
                .tabItem {
                    Label("走行", systemImage: "steeringwheel")
                }
                .tag(1)

            AnalysisView()
                .tabItem {
                    Label("分析", systemImage: "chart.xyaxis.line")
                }
                .tag(2)

            EngineSoundView()
                .tabItem {
                    Label("サウンド", systemImage: "engine.combustion.fill")
                }
                .tag(3)

            ToolsView()
                .tabItem {
                    Label("その他", systemImage: "ellipsis.circle")
                }
                .tag(4)
        }
    }

    /// 監査 REL-012: 画面スリープ防止は「前面 + OBD 接続中(デモ含む)+ 設定オン」に限定。
    private func updateScreenWake() {
        UIApplication.shared.isIdleTimerDisabled =
            keepAwakeWhileConnected && scenePhase == .active && obd.phase.isConnected
    }

    /// オンボーディング終了。選んだ入口に応じてデモ開始/接続シートへ誘導する。
    private func completeOnboarding(with outcome: OnboardingOutcome) {
        onboardingCompleted = true
        showingOnboarding = false

        switch outcome {
        case .demo:
            // オンボーディング直後にプラン提案を重ねない(体験を優先)
            suppressIntroOffer = true
            selectedTab = 0
            obd.startDemoMode()
        case .connect:
            selectedTab = 0
            // fullScreenCover が閉じてから接続シートを開く
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                NotificationCenter.default.post(name: .carUIOpenConnectionSheet, object: nil)
            }
        case .later:
            break
        }
    }

    /// App Store スクショ撮影用フック。起動引数が無ければ何もしない(本番挙動は不変)。
    /// `-uiDemo 1` でデモモード表示、`-uiTab N`(0〜4)で初期表示タブを指定する。
    /// スクショ撮影フック起動時はオンボーディングを出さない(`-uiOnboarding 1` で強制表示)。
    private var isUITestRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiDemo") || args.contains("-uiTab") || args.contains("-uiIntroOffer")
    }

    /// `-uiOnboardingStep N` で指定(未指定は 0 = 最初から)
    private var uiOnboardingInitialStep: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-uiOnboardingStep"), idx + 1 < args.count else { return 0 }
        return Int(args[idx + 1]) ?? 0
    }

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
        // オンボーディングの検証・スクショ用フック
        if value(after: "-uiOnboarding") == "1" {
            showingOnboarding = true
        }
    }
}

// MARK: - 画面間の軽量な通知(オンボーディング→接続シート等)

extension Notification.Name {
    /// メータータブの接続シートを開く(オンボーディングの「アダプタに接続する」)
    static let carUIOpenConnectionSheet = Notification.Name("carUIOpenConnectionSheet")
    /// オンボーディングを再表示(その他タブの「はじめかたをもう一度見る」)
    static let carUIShowOnboarding = Notification.Name("carUIShowOnboarding")
}

#Preview {
    ContentView()
}
