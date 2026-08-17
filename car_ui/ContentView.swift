//
//  ContentView.swift
//  car_ui
//
//  Created by Sena Takasawa on 2026/2/20.
//

import SwiftUI
import StoreKit
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
    // レビュー依頼(ReviewPromptPolicy 参照)。運転中に出さないため接続終了後のみ判定する。
    @Environment(\.requestReview) private var requestReview
    @AppStorage("review.qualifyingSessionCount") private var reviewQualifyingSessionCount = 0
    @AppStorage("review.lastRequestedVersion") private var reviewLastRequestedVersion = ""
    @AppStorage("review.pendingCheck") private var reviewPendingCheck = false
    @State private var liveSessionStartedAt: Date?
    @State private var liveSessionWasDemo = false

    var body: some View {
        VStack(spacing: 0) {
            // 監査 B-2: 以前は走行タブにしか無く、Pro の中核価値である記録の
            // 開始・停止・実行状態がメーター/分析タブから見えも触れもしなかった。
            SessionBar()

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
            handleReviewPromptSessionChange(isConnected: isConnected, isDemo: obd.isDemo)
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
            switch newPhase {
            case .background:
                // フォアグラウンド専用(UIBackgroundModes なし)。背面ではサスペンドで
                // 音が途切れるため明示停止し、復帰時に自動再開する。
                engineSound.sceneDidEnterBackground()
                // 監査 REL-011: 背面移行時に記録と軌跡をディスクへ退避(強制終了に備える)
                recorder.persistToDisk()
                TrackStore.shared.persistToDisk()
            case .active:
                engineSound.sceneDidBecomeActive()
                attemptReviewPromptIfPossible()
            default:
                break
            }
        }
        .onChange(of: keepAwakeWhileConnected) { _, _ in
            updateScreenWake()
        }
        .onChange(of: selectedTab) { _, _ in
            attemptReviewPromptIfPossible()
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
    /// 監査 B-4: ただし HUD 表示中は例外。HUD は GPS 速度だけでも動くため、
    /// OBD 未接続でも点灯を維持しないと走行中に画面が消える。
    private func updateScreenWake() {
        guard scenePhase == .active else {
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        if ScreenWakeCoordinator.shared.hudIsPresented {
            UIApplication.shared.isIdleTimerDisabled = true
            return
        }
        UIApplication.shared.isIdleTimerDisabled =
            keepAwakeWhileConnected && obd.phase.isConnected
    }

    // MARK: - レビュー依頼(ReviewPromptPolicy)

    /// 接続の開始・終了を検知し、実接続(デモ除く)で3分以上ライブデータを受信した
    /// セッションだけを ReviewPromptPolicy に計上する。判定ロジック自体は Policy 側の純粋関数。
    private func handleReviewPromptSessionChange(isConnected: Bool, isDemo: Bool) {
        if isConnected {
            liveSessionStartedAt = Date()
            liveSessionWasDemo = isDemo
            return
        }
        guard let startedAt = liveSessionStartedAt else { return }
        liveSessionStartedAt = nil
        let duration = Date().timeIntervalSince(startedAt)
        let nextState = ReviewPromptPolicy.sessionEnded(
            isDemo: liveSessionWasDemo,
            liveDuration: duration,
            state: currentReviewState())
        persistReviewState(nextState)
        // 接続が切れた直後に前面かつ安全な画面ならその場で、そうでなければ
        // pendingCheck が立ったままになり、次のフォアグラウンド復帰・タブ切替時に再判定する。
        attemptReviewPromptIfPossible()
    }

    /// pendingCheck が立っていて、かつ運転中でない安全な文脈のときだけ requestReview を呼ぶ。
    /// 接続中・HUD 表示中・走行タブでは呼ばない(ReviewPromptPolicy.isSafeContext で保証)。
    private func attemptReviewPromptIfPossible() {
        let isSafe = ReviewPromptPolicy.isSafeContext(
            isConnected: obd.phase.isConnected,
            isHUDPresented: ScreenWakeCoordinator.shared.hudIsPresented,
            isOnDriveTab: selectedTab == 1,
            isForeground: scenePhase == .active)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let result = ReviewPromptPolicy.shouldRequestReview(
            state: currentReviewState(),
            currentVersion: currentVersion,
            isSafeContext: isSafe)
        persistReviewState(result.nextState)
        if result.shouldRequest {
            requestReview()
        }
    }

    private func currentReviewState() -> ReviewPromptPolicy.State {
        ReviewPromptPolicy.State(
            qualifyingSessionCount: reviewQualifyingSessionCount,
            lastRequestedVersion: reviewLastRequestedVersion.isEmpty ? nil : reviewLastRequestedVersion,
            pendingCheck: reviewPendingCheck)
    }

    private func persistReviewState(_ state: ReviewPromptPolicy.State) {
        reviewQualifyingSessionCount = state.qualifyingSessionCount
        reviewLastRequestedVersion = state.lastRequestedVersion ?? ""
        reviewPendingCheck = state.pendingCheck
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

    /// App Store スクショ撮影・UI 検証用フック。起動引数が無ければ何もしない(本番挙動は不変)。
    /// `-uiDemo 1` デモモード / `-uiTab N`(0〜4)初期タブ / `-uiIntroOffer 1` プラン提案シート /
    /// `-uiConnect 1` 接続シート / `-uiOnboarding 1` オンボーディング(`-uiOnboardingStep N` で開始位置)。
    /// スクショ撮影フック起動時はオンボーディングを出さない(`-uiOnboarding 1` で強制表示)。
    private var isUITestRun: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiDemo") || args.contains("-uiTab")
            || args.contains("-uiIntroOffer") || args.contains("-uiConnect")
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
        // 接続シートの検証用フック。シートを開く操作はタップでしか行えず、
        // simctl にタップ機能が無いため接続失敗時の表示を確認できなかった。
        if value(after: "-uiConnect") == "1" {
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                NotificationCenter.default.post(name: .carUIOpenConnectionSheet, object: nil)
            }
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
