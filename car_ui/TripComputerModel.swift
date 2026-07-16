//
//  TripComputerModel.swift
//  car_ui
//
//  トリップコンピュータ: OBD ライブ値から走行距離・平均速度・燃費を積算する。
//  燃料流量は 0x5E(直接)が無ければ MAF 0x10 から推定(ガソリン AFR 14.7 前提)。
//

import Combine
import Foundation

@MainActor
final class TripComputerModel: ObservableObject {
    @Published private(set) var distanceKM: Double = 0
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var fuelUsedLiters: Double = 0
    /// 瞬間燃費 km/L(走行中のみ。停車中は nil)
    @Published private(set) var instantKPL: Double?
    /// 瞬間燃料流量 L/h(停車中のアイドル消費表示用)
    @Published private(set) var instantLPH: Double?
    /// 燃料流量が MAF からの推定値か(0x5E 非対応車)
    @Published private(set) var isFuelEstimated = false

    private var lastSampleDate: Date?
    private var smoothedLPH: Double?

    /// これ以上サンプル間隔が空いたら積算しない(BG 復帰・切断のギャップ対策)
    private static let maxGapSeconds: TimeInterval = 2
    /// 理論空燃比(ガソリン)
    private static let stoichiometricAFR = 14.7
    /// ガソリン密度 g/L
    private static let fuelDensityGPerL = 740.0
    /// 瞬間値の平滑化係数(指数移動平均)
    private static let smoothingFactor = 0.15
    /// この車速未満は「停車」扱いで km/L を出さない(発散回避)
    private static let movingSpeedKPH = 3.0

    var averageSpeedKPH: Double? {
        guard elapsedSeconds > 0 else { return nil }
        return distanceKM / (elapsedSeconds / 3600)
    }

    var averageKPL: Double? {
        guard fuelUsedLiters > 0.001, distanceKM > 0.01 else { return nil }
        return distanceKM / fuelUsedLiters
    }

    var hasData: Bool {
        elapsedSeconds > 0
    }

    func ingest(_ values: [UInt8: Double]) {
        let now = Date()
        defer { lastSampleDate = now }

        guard let last = lastSampleDate else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt <= Self.maxGapSeconds else { return }

        guard let speed = values[0x0D] else { return }

        distanceKM += speed * dt / 3600
        elapsedSeconds += dt

        guard let lph = fuelLPH(from: values) else {
            instantKPL = nil
            instantLPH = nil
            smoothedLPH = nil
            return
        }

        fuelUsedLiters += lph * dt / 3600

        let smoothed = (smoothedLPH ?? lph) * (1 - Self.smoothingFactor) + lph * Self.smoothingFactor
        smoothedLPH = smoothed

        if speed >= Self.movingSpeedKPH, smoothed > 0.01 {
            instantKPL = speed / smoothed
            instantLPH = nil
        } else {
            instantKPL = nil
            instantLPH = smoothed
        }
    }

    func reset() {
        distanceKM = 0
        elapsedSeconds = 0
        fuelUsedLiters = 0
        instantKPL = nil
        instantLPH = nil
        smoothedLPH = nil
        lastSampleDate = nil
    }

    private func fuelLPH(from values: [UInt8: Double]) -> Double? {
        if let direct = values[0x5E] {
            isFuelEstimated = false
            return direct
        }
        if let maf = values[0x10] {
            isFuelEstimated = true
            return maf * 3600 / (Self.stoichiometricAFR * Self.fuelDensityGPerL)
        }
        return nil
    }
}
