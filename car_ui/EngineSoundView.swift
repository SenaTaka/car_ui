import SwiftUI
import UIKit

/// エンジン音タブ: OBD2 の実測回転数に合わせて enjine-sim 由来の合成エンジン音を鳴らす。
/// 画面は enjine-sim を踏襲(暗いグラデ背景 + ツインダイヤル)。ペダル・ギアは実車が
/// 担うため置かない。バナー広告は全タブ共通で ContentView 側に置く。
struct EngineSoundView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var sound: EngineSoundController

    @State private var rewardedAds = RewardedAdManager()
    @State private var rewardStore = RewardStore()
    @State private var rewardPrompt: RewardStore.Item?
    @State private var showingAdLoadingToast = false
    @State private var showingPresets = false

    @AppStorage("engineSoundPresetName") private var savedPresetName = ""
    @AppStorage("engineSoundPopsEnabled") private var popsEnabled = true

    var body: some View {
        ZStack {
            background

            VStack(spacing: 10) {
                headerView

                // ツインダイヤル: 左タコ・右スピード(enjine-sim と同じ JDM 風)
                HStack(spacing: 8) {
                    RPMGaugeView(
                        currentRpm: sound.displayRpm,
                        maxRpm: sound.preset.parameters.maxRpm,
                        redlineRpm: sound.preset.parameters.redlineRpm,
                        idleRpm: sound.preset.parameters.idleRpm,
                        size: 172
                    )

                    SpeedometerView(
                        currentSpeed: sound.displaySpeed,
                        topSpeed: 260,
                        size: 172
                    )
                }

                infoDisplay
                statusRow
                controlButtons
                popsToggleRow

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onAppear {
            restorePresetAndSync()
            rewardedAds.preload()
        }
        .onChange(of: popsEnabled) { _, newValue in
            sound.popsEnabled = newValue
        }
        // alert はこの View に 1 つだけ(同一 View に 2 つ重ねるとフリーズする既知の罠)
        .alert(
            Text("\(rewardPrompt?.title ?? "") を24時間アンロック"),
            isPresented: Binding(
                get: { rewardPrompt != nil },
                set: { if !$0 { rewardPrompt = nil } }
            ),
            presenting: rewardPrompt
        ) { item in
            Button("広告を見る") { presentRewardedAd(for: item) }
            Button("キャンセル", role: .cancel) {}
        } message: { item in
            Text("短い動画広告を見ると、\(item.title) を24時間自由に使えます。")
        }
        .overlay(alignment: .bottom) {
            if showingAdLoadingToast {
                Text("広告の在庫がありません — そのままアンロックしました!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingPresets) {
            presetSelectionView
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.09, green: 0.09, blue: 0.15), .black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var headerView: some View {
        VStack(spacing: 6) {
            Text("ENGINE SOUND")
                .font(.system(size: 18, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.white)

            // エンジン名がプリセットピッカーを兼ねる(enjine-sim と同じ導線)
            Button {
                showingPresets = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.9))
                    Text(sound.preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private var infoDisplay: some View {
        HStack(spacing: 0) {
            infoStat(value: "\(Int(obd.liveValues[0x0D] ?? 0))", unit: "KM/H", color: .white)
            divider
            infoStat(value: "\(Int(obd.liveValues[0x04] ?? 0))%", unit: "LOAD", color: .orange)
            divider
            infoStat(value: "\(sound.preset.parameters.cylinders)", unit: "CYLINDERS", color: .blue)
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 30)
    }

    private func infoStat(value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    /// OBD 接続状態。未接続でも開始でき、その場合はアイドル音の試聴になる。
    private var statusRow: some View {
        HStack(spacing: 8) {
            StatusPill(phase: obd.phase)
            if !isReceivingData {
                Text("未接続 — アイドル音を試聴できます")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var isReceivingData: Bool {
        if obd.isDemo { return true }
        if case .connected = obd.phase { return true }
        return false
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            Button {
                toggleSound()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sound.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 18))
                    Text(sound.isPlaying ? "サウンド停止" : "サウンド開始")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(sound.isPlaying ? Color.red : Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                showingPresets = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("ENGINE")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                }
                .foregroundColor(.white)
                .frame(width: 62, height: 46)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var popsToggleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13))
                .foregroundColor(.orange.opacity(0.9))

            Text("POPS & BANGS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.75))

            Spacer()

            Toggle("", isOn: $popsEnabled)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .orange))
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var presetSelectionView: some View {
        NavigationView {
            List(EnginePreset.presets) { preset in
                let rewardLocked = preset.isRewardLocked && !rewardStore.isUnlocked(.f1Engine)

                Button {
                    loadPreset(preset)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preset.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.primary)

                            Text(preset.description)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            HStack {
                                Label("\(preset.parameters.cylinders) cyl", systemImage: "engine.combustion")
                                Label("\(String(format: "%.1f", preset.parameters.displacement))L", systemImage: "gauge.medium")
                                Label("\(Int(preset.parameters.redlineRpm)) RPM", systemImage: "speedometer")
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 4)

                        if preset.name == sound.preset.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        if rewardLocked {
                            VStack(spacing: 3) {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.orange)
                                Text("Ad · 24h")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("広告を見て24時間アンロック")
                        } else if preset.isRewardLocked, let hours = rewardStore.remainingHours(.f1Engine) {
                            Text("残り\(hours)h")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("エンジンプリセット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        showingPresets = false
                    }
                }
            }
        }
        // リワードの alert はルート View 側のみ(シート側にも付けると二重提示でフリーズ)
    }

    // MARK: - 操作

    private func toggleSound() {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred()

        if sound.isPlaying {
            sound.stop()
        } else {
            sound.popsEnabled = popsEnabled
            sound.start()
        }
    }

    /// 起動時: 保存済みプリセットを復元(期限切れのロック対象は先頭へフォールバック)
    private func restorePresetAndSync() {
        sound.popsEnabled = popsEnabled

        var preset = EnginePreset.presets.first { $0.name == savedPresetName }
            ?? EnginePreset.presets[0]
        if preset.isRewardLocked && !rewardStore.isUnlocked(.f1Engine) {
            preset = EnginePreset.presets[0]
        }
        if sound.preset.name != preset.name {
            sound.setPreset(preset)
        }
    }

    private func loadPreset(_ preset: EnginePreset) {
        // ロック中プリセットは読み込まずリワード広告を提案。alert はルートに
        // あるため、シートを閉じてから遅延して出す。
        if preset.isRewardLocked && !rewardStore.isUnlocked(.f1Engine) {
            showingPresets = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                rewardPrompt = .f1Engine
            }
            return
        }

        sound.setPreset(preset)
        savedPresetName = preset.name
        showingPresets = false

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }

    private func presentRewardedAd(for item: RewardStore.Item) {
        let grant = {
            rewardStore.unlock(item)
            if item == .f1Engine,
               let f1 = EnginePreset.presets.first(where: { $0.isRewardLocked }) {
                sound.setPreset(f1)
                savedPresetName = f1.name
                showingPresets = false
            }
        }

        // 実車 RPM 駆動なので広告表示中も音は止めない(サスペンド配線なし)
        let presented = rewardedAds.show(onReward: grant)
        if !presented {
            // 在庫なし: ユーザーを待たせず即アンロック(審査・新規ユニットで頻発)
            grant()
            withAnimation(.easeOut(duration: 0.25)) {
                showingAdLoadingToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeIn(duration: 0.25)) {
                    showingAdLoadingToast = false
                }
            }
        }
    }
}

#Preview {
    EngineSoundView()
        .environmentObject(ELM327BluetoothModel())
        .environmentObject(EngineSoundController())
}
