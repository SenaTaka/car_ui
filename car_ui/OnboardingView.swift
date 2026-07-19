//
//  OnboardingView.swift
//  car_ui
//
//  初回起動オンボーディング(HIG の Welcome スクリーン様式)。
//  1) 価値提示 → 2) つなぎかた → 3) 権限の事前説明(priming)→ 4) デモ/接続の選択。
//  権限ダイアログはここでは出さず、実際に使う機能の直前で要求する方針を説明する。
//

import SwiftUI

/// オンボーディング終了時にユーザーが選んだ入口
enum OnboardingOutcome {
    /// デモモードで即体験
    case demo
    /// アダプタに接続(メータータブで接続シートを開く)
    case connect
    /// あとで決める(そのままアプリへ)
    case later
}

struct OnboardingView: View {
    let onFinish: (OnboardingOutcome) -> Void

    /// スクショ・検証用に途中のステップから開始できる(0〜3)。本番は常に 0。
    init(initialStepIndex: Int = 0, onFinish: @escaping (OnboardingOutcome) -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: Step(rawValue: initialStepIndex) ?? .welcome)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Int, CaseIterable {
        case welcome, connect, permissions, start
    }

    @State private var step: Step
    /// 進行方向(戻る操作でスライド方向を反転させる)
    @State private var movesForward = true
    /// welcome の行を順番にフェードインさせるためのフラグ
    @State private var revealsFeatures = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(pageTransition)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(Color(.systemBackground))
        .sensoryFeedback(.selection, trigger: step)
        .onAppear {
            guard !reduceMotion else {
                revealsFeatures = true
                return
            }
            withAnimation(.spring(duration: 0.7).delay(0.35)) {
                revealsFeatures = true
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - 上部バー(戻る+進捗ドット)

    private var topBar: some View {
        ZStack {
            progressDots

            HStack {
                if step != .welcome {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                    }
                    .minTapTarget()
                    .accessibilityLabel("戻る")
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 52)
        .animation(.default, value: step)
    }

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? Color.accentColor : Color(.systemFill))
                    .frame(width: s == step ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.35), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ステップ \(step.rawValue + 1) / \(Step.allCases.count)"))
    }

    // MARK: - 各ステップの内容

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomePage
        case .connect: connectPage
        case .permissions: permissionsPage
        case .start: startPage
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroIcon("gauge.with.dots.needle.67percent", gradient: [.blue, .indigo])
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 28)

            Text("OBD2スキャナーへようこそ")
                .font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)

            Text("あなたの車を、走るデータに。")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 26) {
                featureRow(index: 0,
                           symbol: "gauge.open.with.lines.needle.33percent",
                           color: DS.Role.accent,
                           title: "リアルタイム計測",
                           detail: "速度・回転数・水温など、車が発する対応データを自動検出して表示します。")
                featureRow(index: 1,
                           symbol: "map.fill",
                           color: DS.Role.ok,
                           title: "走行の記録と分析",
                           detail: "走ったルートと速度を、あとから地図とチャートで振り返れます。")
                featureRow(index: 2,
                           symbol: "engine.combustion.fill",
                           color: DS.Role.engine,
                           title: "エンジンサウンド",
                           detail: "実測の回転数に連動して、往年の名機のサウンドを鳴らせます。")
            }
            .padding(.bottom, 32)

            privacyFootnote("計測したデータはすべてこの iPhone の中だけに保存されます。")
        }
    }

    private var connectPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroIcon("car.rear.road.lane", gradient: [.teal, .blue])
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 28)

            pageTitle("つなぎかたは 3 ステップ")

            Text("ELM327 対応の Bluetooth OBD2 アダプタを使います。")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 26) {
                numberedRow(1, title: "アダプタを挿す",
                            detail: "車の OBD2 ポート(多くは運転席の足元)にアダプタを差し込みます。")
                numberedRow(2, title: "エンジンをかける",
                            detail: "イグニッションを ON にするとアダプタに電源が入ります。")
                numberedRow(3, title: "アプリが自動検出",
                            detail: "接続すると、この車が対応するデータを自動で見つけて表示します。")
            }
            .padding(.bottom, 32)

            privacyFootnote("アダプタがなくても、デモモードで全機能を試せます。", symbol: "info.circle.fill")
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroIcon("hand.raised.fill", gradient: [.indigo, .purple])
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 28)

            pageTitle("使う機能だけ、その場で許可")

            Text("必要になった画面で、はじめて許可をお願いします。今は何も求めません。")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 26) {
                featureRow(index: 0,
                           symbol: "antenna.radiowaves.left.and.right",
                           color: DS.Role.accent,
                           title: "Bluetooth",
                           detail: "OBD2 アダプタと通信するために使います。")
                featureRow(index: 1,
                           symbol: "location.fill",
                           color: DS.Role.ok,
                           title: "位置情報",
                           detail: "GPS 速度の計測と、走行ルートの記録に使います。")
                featureRow(index: 2,
                           symbol: "move.3d",
                           color: DS.Role.motion,
                           title: "モーション",
                           detail: "G フォースと 0-100 km/h 加速の計測に使います。")
            }
            .padding(.bottom, 32)

            privacyFootnote("すべて端末内で処理され、外部に送信されることはありません。")
        }
    }

    private var startPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroIcon("flag.pattern.checkered", gradient: [.orange, .red])
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 28)

            pageTitle("準備完了")

            Text("アダプタをお持ちならすぐに接続。まずは雰囲気を見たいなら、デモですべての画面を体験できます。")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 36)

            VStack(alignment: .leading, spacing: 26) {
                featureRow(index: 0,
                           symbol: "play.rectangle.on.rectangle.fill",
                           color: DS.Role.accent,
                           title: "デモモード",
                           detail: "実走行を再現したデータで、メーターからエンジン音まで今すぐ動きます。")
                featureRow(index: 1,
                           symbol: "arrow.triangle.2.circlepath",
                           color: DS.Role.ok,
                           title: "いつでも切り替え",
                           detail: "メーター画面右上の接続ボタンから、本物のアダプタへいつでも移れます。")
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - 下部 CTA

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            if step == .start {
                Button {
                    onFinish(.demo)
                } label: {
                    Label("デモではじめる", systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onFinish(.connect)
                } label: {
                    Label("アダプタに接続する", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)

                Button("あとで決める") {
                    onFinish(.later)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .minTapTarget()
            } else {
                Button {
                    goForward()
                } label: {
                    Text("続ける")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 500)
        .animation(.default, value: step)
    }

    // MARK: - 部品

    private func heroIcon(_ symbol: String, gradient: [Color]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: gradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 92)
                .shadow(color: gradient[0].opacity(0.35), radius: 14, y: 6)

            Image(systemName: symbol)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .nonRepeating, value: step)
        }
        .accessibilityHidden(true)
    }

    private func pageTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title.weight(.bold))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 6)
    }

    /// Apple の Welcome スクリーン様式の機能行(アイコン+太字タイトル+説明)
    private func featureRow(index: Int, symbol: String, color: Color,
                            title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(revealsFeatures ? 1 : 0)
        .offset(y: revealsFeatures ? 0 : 14)
        .animation(reduceMotion ? nil : .spring(duration: 0.6).delay(0.35 + Double(index) * 0.12),
                   value: revealsFeatures)
        .accessibilityElement(children: .combine)
    }

    /// つなぎかたの番号付き行(番号バッジ+タイトル+説明)
    private func numberedRow(_ number: Int, title: LocalizedStringKey,
                             detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
                .padding(.horizontal, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func privacyFootnote(_ text: LocalizedStringKey,
                                 symbol: String = "lock.shield.fill") -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
    }

    // MARK: - 遷移

    private var pageTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: movesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func goForward() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        movesForward = true
        revealsFeatures = true
        withAnimation(.spring(duration: 0.45)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        movesForward = false
        withAnimation(.spring(duration: 0.45)) {
            step = previous
        }
    }
}

#Preview {
    OnboardingView { _ in }
}
