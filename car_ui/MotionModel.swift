//
//  MotionModel.swift
//  car_ui
//
//  加速度計連携: 重力ベクトルで水平面に射影した G(横 / 前後)を算出する。
//  端末の取り付け角度に依存せず、車両の加減速・旋回 G を表示できる。
//

import Combine
import CoreMotion
import Foundation

final class MotionModel: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isAvailable = true
    @Published private(set) var lateralG: Double = 0
    @Published private(set) var longitudinalG: Double = 0
    @Published private(set) var magnitudeG: Double = 0
    @Published private(set) var peakG: Double = 0

    private let manager = CMMotionManager()
    private var recordCounter = 0

    func start() {
        guard manager.isDeviceMotionAvailable else {
            isAvailable = false
            return
        }
        guard !isActive else { return }

        isActive = true
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.apply(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isActive = false
        lateralG = 0
        longitudinalG = 0
        magnitudeG = 0
    }

    func resetPeak() {
        peakG = 0
    }

    private func apply(_ motion: CMDeviceMotion) {
        let a = motion.userAcceleration
        let g = motion.gravity

        // 重力方向を法線とする水平面へ加速度を射影
        let gLength = max(sqrt(g.x * g.x + g.y * g.y + g.z * g.z), 0.0001)
        let gn = (x: g.x / gLength, y: g.y / gLength, z: g.z / gLength)
        let dot = a.x * gn.x + a.y * gn.y + a.z * gn.z
        let h = (x: a.x - dot * gn.x, y: a.y - dot * gn.y, z: a.z - dot * gn.z)

        // 水平面内の基底: e1 = 端末 X 軸の水平成分(横方向)、e2 = ĝ × e1(前後方向)
        let xDot = gn.x
        var e1 = (x: 1 - xDot * gn.x, y: -xDot * gn.y, z: -xDot * gn.z)
        let e1Length = max(sqrt(e1.x * e1.x + e1.y * e1.y + e1.z * e1.z), 0.0001)
        e1 = (x: e1.x / e1Length, y: e1.y / e1Length, z: e1.z / e1Length)
        let e2 = (
            x: gn.y * e1.z - gn.z * e1.y,
            y: gn.z * e1.x - gn.x * e1.z,
            z: gn.x * e1.y - gn.y * e1.x
        )

        lateralG = h.x * e1.x + h.y * e1.y + h.z * e1.z
        longitudinalG = h.x * e2.x + h.y * e2.y + h.z * e2.z
        magnitudeG = sqrt(h.x * h.x + h.y * h.y + h.z * h.z)
        peakG = max(peakG, magnitudeG)

        // 記録は 2 Hz に間引き(リングバッファを長時間持たせる)
        recordCounter += 1
        if recordCounter.isMultiple(of: 5) {
            let recorder = TelemetryRecorder.shared
            recorder.record("motion.gx", value: lateralG)
            recorder.record("motion.gy", value: longitudinalG)
            recorder.record("motion.gmag", value: magnitudeG)
        }
    }
}

// MARK: - 0-100 km/h 加速計測(OBD 車速または GPS 車速を入力に使う)

final class AccelTestModel: ObservableObject {
    enum State: Equatable {
        case idle
        case armed          // 停止状態で発進待ち
        case running(Date)  // 発進時刻
        case finished
    }

    struct Split: Identifiable {
        let targetKPH: Int
        let seconds: Double

        var id: Int { targetKPH }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var splits: [Split] = []
    @Published private(set) var elapsed: Double = 0
    /// 自動計測モード(レビュー 9-3: 完全停止で自動待機→発進で自動開始)。
    /// 走行直前のタップを運転者に要求しないための安全機能。
    @Published var autoStart = true

    private let targets = [20, 40, 60, 80, 100]
    /// この速度未満を「停止」とみなす
    private let stopThreshold: Double = 1

    var isMeasuring: Bool {
        if case .running = state { return true }
        return state == .armed
    }

    func arm() {
        state = .armed
        splits = []
        elapsed = 0
    }

    func setAutoStart(_ enabled: Bool) {
        autoStart = enabled
        // 手動へ切り替えたら待機状態はリセット(誤発進を防ぐ)
        if !enabled, state == .armed {
            state = .idle
        }
    }

    func cancel() {
        state = .idle
        splits = []
        elapsed = 0
    }

    func update(speedKPH: Double, at time: Date = Date()) {
        switch state {
        case .idle:
            // 自動モード: 停止を検出したら発進待ちへ(手動時は arm() を待つ)
            if autoStart, speedKPH < stopThreshold {
                state = .armed
                splits = []
                elapsed = 0
            }
        case .finished:
            // 自動モード: 完了後に再び停止したら次の計測へ自動リセット
            if autoStart, speedKPH < stopThreshold {
                state = .armed
                splits = []
                elapsed = 0
            }
        case .armed:
            if speedKPH >= stopThreshold {
                state = .running(time)
            }
        case .running(let startTime):
            elapsed = time.timeIntervalSince(startTime)
            for target in targets where speedKPH >= Double(target) && !splits.contains(where: { $0.targetKPH == target }) {
                splits.append(Split(targetKPH: target, seconds: elapsed))
            }
            if splits.contains(where: { $0.targetKPH == targets.last }) {
                state = .finished
            }
        }
    }
}
