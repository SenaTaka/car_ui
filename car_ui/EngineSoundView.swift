import SwiftUI
import UIKit

/// エンジン音タブ: OBD2 の実測回転数に合わせて enjine-sim 由来の合成エンジン音を鳴らす。
/// 画面は enjine-sim を踏襲(暗いグラデ背景 + ツインダイヤル)。ペダル・ギアは実車が
/// 担うため置かない。バナー広告は全タブ共通で ContentView 側に置く。
struct EngineSoundView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var sound: EngineSoundController
    @Environment(ProStore.self) private var proStore

    @State private var showingPresets = false
    @State private var showingPaywall = false
    // ロック中プリセットの 20 秒試聴(T2)。期限が来たら直前の無料プリセットへ戻して Paywall を出す。
    @State private var previewTask: Task<Void, Never>?
    @State private var previewRemainingSeconds: Int?

    private var unitSystem: ResolvedUnitSystem { UnitSettings.shared.system }

    @AppStorage("engineSoundPresetName") private var savedPresetName = ""
    @AppStorage("engineSoundPopsEnabled") private var popsEnabled = true

    var body: some View {
        ZStack {
            background

            // 監査 REL-013: 固定 172pt ×2 は iPhone SE(論理幅 375pt)に収まらず、
            // 横画面では縦方向がはみ出す。メーターは画面幅から可変にし、
            // 全体をスクロール可能にして小型端末・横画面でも全操作へ到達できるようにする。
            GeometryReader { geometry in
                let gaugeSize = min(172, (geometry.size.width - 32 - 8) / 2)

                ScrollView {
                    VStack(spacing: 10) {
                        headerView

                        // ツインダイヤル: 左タコ・右スピード(enjine-sim と同じ JDM 風)
                        HStack(spacing: 8) {
                            RPMGaugeView(
                                currentRpm: sound.displayRpm,
                                maxRpm: sound.preset.parameters.maxRpm,
                                redlineRpm: sound.preset.parameters.redlineRpm,
                                idleRpm: sound.preset.parameters.idleRpm,
                                size: gaugeSize
                            )

                            // 監査 A-1: ダイヤルの数字ごと表示単位へ換算する
                            SpeedometerView(
                                currentSpeed: UnitKind.speed.convert(sound.displaySpeed, to: unitSystem),
                                topSpeed: UnitKind.speed.convert(260, to: unitSystem),
                                size: gaugeSize,
                                unitLabel: UnitKind.speed.symbol(unitSystem)
                            )
                        }

                        infoDisplay
                        statusRow
                        controlButtons
                        volumeRow
                        popsToggleRow
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            restorePresetAndSync()
            applyUITestLaunchArgumentsIfPresent()
        }
        .onChange(of: popsEnabled) { _, newValue in
            sound.popsEnabled = newValue
        }
        .sheet(isPresented: $showingPresets) {
            presetSelectionView
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
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

            if let remaining = previewRemainingSeconds {
                Text("試聴中… あと \(remaining) 秒")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }

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
            infoStat(value: unitText(obd.liveValues[0x0D] ?? 0, kind: .speed, digits: 0),
                     unit: UnitKind.speed.symbol(unitSystem), color: .white)
            divider
            infoStat(value: "\(Int(obd.liveValues[0x04] ?? 0))%", unit: "LOAD", color: .orange)
            divider
            infoStat(value: "\(sound.preset.parameters.cylinders)", unit: "CYL", color: .blue)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: DS.minTapTarget)
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
                .frame(maxWidth: .infinity, minHeight: DS.minTapTarget)
                .background(sound.isPlaying ? Color.red : Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                showingPresets = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "engine.combustion.fill")
                        .font(.system(size: 16, weight: .semibold))
                    // レビュー 11-2: 意味不明な「ENGINE」→「音源」(エンジン選択)
                    Text("音源")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(minWidth: 62, minHeight: DS.minTapTarget)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    /// レビュー 11-4: マスター音量スライダー(サウンド機能の基本操作)
    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))

            Slider(value: Binding(get: { Double(sound.masterVolume) },
                                  set: { sound.masterVolume = Float($0) }),
                   in: 0...1)
                .tint(.orange)
                .accessibilityLabel("音量")

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: DS.minTapTarget)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .frame(minHeight: DS.minTapTarget)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var presetSelectionView: some View {
        NavigationView {
            List(EnginePreset.presets) { preset in
                Button {
                    selectPreset(preset)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(preset.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.primary)

                                if !isUnlocked(preset) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                    Text("Pro")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                            }

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

    /// 起動時: 保存済みプリセットを復元。ロック対象になっていたら先頭の無料プリセットへフォールバック。
    private func restorePresetAndSync() {
        sound.popsEnabled = popsEnabled

        var preset = EnginePreset.presets.first { $0.name == savedPresetName }
            ?? EnginePreset.presets[0]
        if !isUnlocked(preset) {
            preset = EnginePreset.presets.first { $0.isFree } ?? EnginePreset.presets[0]
            savedPresetName = preset.name
        }
        if sound.preset.name != preset.name {
            sound.setPreset(preset)
        }
    }

    /// Pro / 広告除去以前からの無料利用者(grandfather)/ 無料プリセットのいずれかで解放されているか。
    private func isUnlocked(_ preset: EnginePreset) -> Bool {
        preset.isFree || proStore.isPro || proStore.legacyFreeSound
    }

    private func selectPreset(_ preset: EnginePreset) {
        if isUnlocked(preset) {
            loadPreset(preset)
        } else {
            previewLockedPreset(preset)
        }
    }

    private func loadPreset(_ preset: EnginePreset) {
        previewTask?.cancel()
        previewTask = nil
        previewRemainingSeconds = nil

        sound.setPreset(preset)
        savedPresetName = preset.name
        showingPresets = false

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }

    /// App Store スクショ撮影用フック(ContentView と同じ流儀)。`-uiEngineSoundPresets 1` で
    /// プリセット一覧シートを強制表示する(ロック表示のスクショに使う。本番挙動は不変)。
    private func applyUITestLaunchArgumentsIfPresent() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiEngineSoundPresets") {
            showingPresets = true
        }
    }

    /// T2: ロック中プリセットを 20 秒だけ試聴させ、期限が来たら直前の無料プリセットへ戻して Paywall を出す。
    private func previewLockedPreset(_ preset: EnginePreset) {
        previewTask?.cancel()

        let currentPreset = sound.preset
        let fallbackPreset = isUnlocked(currentPreset)
            ? currentPreset
            : (EnginePreset.presets.first { $0.isFree } ?? EnginePreset.presets[0])

        sound.setPreset(preset)
        showingPresets = false
        previewRemainingSeconds = 20

        previewTask = Task {
            for remaining in stride(from: 19, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                previewRemainingSeconds = remaining
            }
            guard !Task.isCancelled else { return }
            sound.setPreset(fallbackPreset)
            savedPresetName = fallbackPreset.name
            previewRemainingSeconds = nil
            showingPaywall = true
        }
    }
}

#Preview {
    EngineSoundView()
        .environmentObject(ELM327BluetoothModel())
        .environmentObject(EngineSoundController())
        .environment(ProStore.shared)
}
