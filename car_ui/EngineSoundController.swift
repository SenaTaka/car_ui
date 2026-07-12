import AVFoundation
import Combine
import Foundation
import QuartzCore

/// OBD2 の実測値(回転数・スロットル・負荷・車速)でエンジン音合成を駆動するコントローラ。
/// enjine-sim の AudioEngine から物理シミュレータ依存を除去し、`ingest(_:)` で受け取った
/// 最新サンプルを CADisplayLink で補間しながら `HarmonicGenerator` に流し込む。
/// `HarmonicGenerator.update()` は main スレッド限定・`render()` はオーディオスレッド、
/// というロックレス契約を守るため、このクラス全体を MainActor に閉じる。
@MainActor
final class EngineSoundController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var preset: EnginePreset = EnginePreset.presets[0]
    /// ゲージ表示用の補間済み値(publish は閾値付きで間引く)
    @Published private(set) var displayRpm: Double = 0
    @Published private(set) var displaySpeed: Double = 0
    @Published private(set) var isOverrun = false

    /// View 側の @AppStorage と同期する
    var popsEnabled = true

    /// OBD 値が届いているか(false ならアイドル試聴モード)
    var hasLiveData: Bool { CACurrentMediaTime() - lastRpmSampleAt < Tune.staleTimeout }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let harmonicGenerator: HarmonicGenerator
    private var displayLink: CADisplayLink?

    private let sampleRate: Double = 44100
    private let channelCount: AVAudioChannelCount = 2

    // 最新 OBD サンプル(ingest が保存、tick が消費)
    private var latestRpm: Double?
    private var latestSpeed: Double?
    private var latestThrottle: Double?   // 0x11 絶対開度 %
    private var latestLoad: Double?       // 0x04 負荷 %
    private var lastRpmSampleAt: CFTimeInterval = -.greatestFiniteMagnitude

    // 補間状態
    private var smoothedRpm: Double = 0
    private var smoothedSpeed: Double = 0
    private var smoothedThrottle: Double = 0  // 正規化済み 0...1
    private var smoothedLoad: Double = 0
    private var rpmSlope: Double = 0          // rpm/s(低域通過済み)
    private var lastTickAt: CFTimeInterval = 0

    // スロットル床学習(0x11 はアイドルで 10〜20% を報告する車が多い)
    private var throttleFloor: Double = Tune.floorInitial

    // オーバーラン(DFCO)判定
    private var overrunSince: CFTimeInterval = 0

    // 内蔵スピーカー出力中のみ低域補正を有効化(BT/CarPlay はフラット)
    private var isOnBuiltInSpeaker = false
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    /// 割り込み(電話等)で停止した場合に自動復帰するためのフラグ
    private var wasInterrupted = false

    /// 実車チューニング前提の閾値はここに集約
    private enum Tune {
        static let staleTimeout: CFTimeInterval = 2.0   // RPM がこれ以上古ければアイドルへ
        static let rpmSmoothing = 0.20                  // OBD 更新間隔(約 200ms)相当
        static let throttleSmoothing = 0.12             // ポップ判定のキレ用にやや速め
        static let slopeSmoothing = 0.30
        static let floorInitial = 15.0
        static let floorDriftPerSec = 0.2               // 床のゆっくり上方ドリフト %/s
        static let floorMax = 25.0
        static let wotCeil = 88.0                       // WOT 報告値の想定上限 %
        static let overrunThrottleEnter = 0.05
        static let overrunThrottleExit = 0.12
        static let overrunEnterSlope = -250.0           // rpm/s
        static let overrunExitSlope = 50.0
        static let overrunMinRpmFloor = 2000.0
        static let overrunEnterRpmFactor = 2.5          // idle × 2.5 以上で進入
        static let overrunExitRpmFactor = 1.6
        static let overrunMinDuration: CFTimeInterval = 0.3
    }

    init() {
        self.harmonicGenerator = HarmonicGenerator(sampleRate: sampleRate)
        setupAudioEngine()

        refreshOutputRoute()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshOutputRoute() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:))
            MainActor.assumeIsolated { self?.handleInterruption(type: type, options: options) }
        }
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    // MARK: - 入力

    /// ELM327BluetoothModel.liveValues の変化ごとに呼ぶ(保存のみ、軽量)
    func ingest(_ liveValues: [UInt8: Double]) {
        if let rpm = liveValues[0x0C] {
            latestRpm = rpm
            lastRpmSampleAt = CACurrentMediaTime()
        }
        if let speed = liveValues[0x0D] { latestSpeed = speed }
        latestThrottle = liveValues[0x11]
        latestLoad = liveValues[0x04]
    }

    func setPreset(_ newPreset: EnginePreset) {
        preset = newPreset
    }

    // MARK: - 再生制御

    func start() {
        guard !isPlaying else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try? audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setActive(true)
        } catch {
            return
        }
        refreshOutputRoute()

        harmonicGenerator.reset()
        // 0 からのスイープを避けるため現在の目標値から開始
        let now = CACurrentMediaTime()
        smoothedRpm = targetRpm(now: now)
        smoothedSpeed = latestSpeed ?? 0
        smoothedThrottle = 0
        smoothedLoad = 0
        rpmSlope = 0
        lastTickAt = now
        harmonicGenerator.update(makeSoundState())

        do {
            try engine.start()
        } catch {
            try? audioSession.setActive(false)
            return
        }
        isPlaying = true
        wasInterrupted = false
        startDisplayLink()
    }

    func stop() {
        guard isPlaying || wasInterrupted else { return }
        isPlaying = false
        wasInterrupted = false
        stopDisplayLink()

        // シンセ側をフェードアウトさせてから停止
        var silent = EngineSoundState()
        silent.cylinders = preset.parameters.cylinders
        silent.redlineRpm = preset.parameters.redlineRpm
        harmonicGenerator.update(silent)

        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - オーディオ基盤

    private func setupAudioEngine() {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channelCount
        )!

        // Pull 型ソースノード: render はオーディオスレッドで走るため
        // MainActor の self ではなく generator を直接キャプチャする
        let generator = harmonicGenerator
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            generator.render(frameCount: Int(frameCount), bufferList: abl)
            return noErr
        }
        self.sourceNode = node

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    private func refreshOutputRoute() {
        isOnBuiltInSpeaker = AVAudioSession.sharedInstance().currentRoute.outputs
            .contains { $0.portType == .builtInSpeaker }
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType?,
                                    options: AVAudioSession.InterruptionOptions?) {
        switch type {
        case .began:
            guard isPlaying else { return }
            stop()
            wasInterrupted = true
        case .ended:
            guard wasInterrupted else { return }
            wasInterrupted = false
            if options?.contains(.shouldResume) == true {
                start()
            }
        default:
            break
        }
    }

    // MARK: - 制御ループ

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(0.001, now - lastTickAt))
        lastTickAt = now

        // 一次遅れ補間: 5Hz の OBD サンプルを滑らかなピッチ変化にする
        let previousRpm = smoothedRpm
        smoothedRpm += (targetRpm(now: now) - smoothedRpm) * min(1, dt / Tune.rpmSmoothing)
        smoothedThrottle += (targetThrottle(now: now, dt: dt) - smoothedThrottle) * min(1, dt / Tune.throttleSmoothing)
        smoothedLoad += (targetLoad(now: now) - smoothedLoad) * min(1, dt / Tune.rpmSmoothing)
        smoothedSpeed += (targetSpeed(now: now) - smoothedSpeed) * min(1, dt / Tune.rpmSmoothing)

        let instantSlope = (smoothedRpm - previousRpm) / dt
        rpmSlope += (instantSlope - rpmSlope) * min(1, dt / Tune.slopeSmoothing)

        updateOverrun(now: now)

        harmonicGenerator.update(makeSoundState())

        // ゲージ用 publish(無駄な再描画を間引く)
        if abs(displayRpm - smoothedRpm) > 5 { displayRpm = smoothedRpm }
        if abs(displaySpeed - smoothedSpeed) > 0.5 { displaySpeed = smoothedSpeed }
        if isOverrun != overrunActive { isOverrun = overrunActive }
    }

    // MARK: - OBD → 目標値

    private func targetRpm(now: CFTimeInterval) -> Double {
        guard now - lastRpmSampleAt < Tune.staleTimeout, let rpm = latestRpm else {
            // 未接続・信号喪失時はアイドルへ滑らかに降ろす(アイドル試聴モード)
            return preset.parameters.idleRpm
        }
        return rpm
    }

    private func targetThrottle(now: CFTimeInterval, dt: Double) -> Double {
        guard now - lastRpmSampleAt < Tune.staleTimeout else { return 0 }
        if let raw = latestThrottle {
            // アイドル床の自動学習: 最小値へ即時追従、上へはゆっくりドリフト
            if raw < throttleFloor {
                throttleFloor = raw
            } else {
                throttleFloor = min(throttleFloor + Tune.floorDriftPerSec * dt, Tune.floorMax)
            }
            let span = max(5.0, Tune.wotCeil - throttleFloor)
            return min(1, max(0, (raw - throttleFloor) / span))
        }
        if let load = latestLoad {
            return min(1, max(0, load / 100))
        }
        // 最後の手段: RPM 上昇率から推定(下降時は 0)
        return min(1, max(0, rpmSlope / 2000))
    }

    private func targetLoad(now: CFTimeInterval) -> Double {
        guard now - lastRpmSampleAt < Tune.staleTimeout else { return 0 }
        if let load = latestLoad { return min(1, max(0, load / 100)) }
        return smoothedThrottle
    }

    private func targetSpeed(now: CFTimeInterval) -> Double {
        guard now - lastRpmSampleAt < Tune.staleTimeout else { return 0 }
        return latestSpeed ?? 0
    }

    /// スロットル閉 + 高回転 + 回転下降 → DFCO(オーバーラン)。ヒステリシス+最短維持付き。
    private var overrunActive = false
    private func updateOverrun(now: CFTimeInterval) {
        let idle = preset.parameters.idleRpm
        if overrunActive {
            guard now - overrunSince >= Tune.overrunMinDuration else { return }
            if smoothedThrottle > Tune.overrunThrottleExit
                || smoothedRpm < idle * Tune.overrunExitRpmFactor
                || rpmSlope > Tune.overrunExitSlope {
                overrunActive = false
            }
        } else {
            if smoothedThrottle < Tune.overrunThrottleEnter
                && smoothedRpm > max(idle * Tune.overrunEnterRpmFactor, Tune.overrunMinRpmFloor)
                && rpmSlope < Tune.overrunEnterSlope {
                overrunActive = true
                overrunSince = now
            }
        }
    }

    // MARK: - EngineSoundState 組み立て

    private func makeSoundState() -> EngineSoundState {
        let p = preset.parameters

        var state = EngineSoundState()
        state.rpm = smoothedRpm
        state.throttle = smoothedThrottle
        state.load = smoothedLoad
        state.running = true
        state.decelFuelCut = overrunActive
        state.overrun = overrunActive
        state.popsEnabled = popsEnabled
        state.speed = smoothedSpeed
        state.cylinders = p.cylinders
        let bankInfo = p.exhaustBankInfo
        state.exhaustBankPattern = bankInfo.pattern
        state.exhaustBankCount = bankInfo.bankCount
        // 4分の1波長の排気管共鳴: 排気量が大きいほど管が長い(AudioEngine と同式)
        let tailpipeLength = min(1.2, max(0.5, 0.45 + 0.11 * p.displacement))
        state.tailpipeResonanceHz = 343.0 / (4.0 * tailpipeLength)
        state.idleRpm = p.idleRpm
        state.redlineRpm = p.redlineRpm
        state.harmonicCount = p.harmonicCount
        state.exhaustScavengingFactor = p.exhaustScavengingFactor
        state.intakeHarmonicFactor = p.intakeHarmonicFactor
        state.intakeEfficiency = p.intakeEfficiency
        state.exhaustEfficiency = p.exhaustEfficiency
        state.frictionFactor = p.frictionFactor
        state.vtecMode = p.vtecMode
        state.boxerMode = p.boxerMode
        state.turboMode = p.turboMode
        state.smallSpeaker = isOnBuiltInSpeaker
        return state
    }
}
