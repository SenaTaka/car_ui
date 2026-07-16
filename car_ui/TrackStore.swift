//
//  TrackStore.swift
//  car_ui
//
//  GPS 走行軌跡の記録。各点に速度・RPM を紐付け、地図のコンター表示に使う。
//

import Combine
import CoreLocation
import Foundation

struct TrackPoint: Identifiable {
    let id: Int
    let time: Date
    let coordinate: CLLocationCoordinate2D
    /// OBD 車速を優先、なければ GPS 車速
    let speedKPH: Double?
    let rpm: Double?
}

@MainActor
final class TrackStore: ObservableObject {
    static let shared = TrackStore()

    @Published private(set) var points: [TrackPoint] = []

    private var nextID = 0
    private var lastRecordTime: Date?
    /// リングバッファ上限(1 秒間隔で約 2 時間ぶん)
    private let maxPoints = 7200
    /// この間隔より短い更新は間引く
    private let minInterval: TimeInterval = 1.0
    /// OBD 値はこの秒数以内のサンプルだけ採用(切断後の残存値を防ぐ)
    private let obdFreshWindow: TimeInterval = 5

    func record(location: CLLocation) {
        let now = location.timestamp
        if let lastRecordTime, now.timeIntervalSince(lastRecordTime) < minInterval {
            return
        }
        lastRecordTime = now

        let recorder = TelemetryRecorder.shared
        let obdSpeed = freshValue("obd.0D", at: now, from: recorder)
        let gpsSpeed = location.speed >= 0 ? location.speed * 3.6 : nil

        nextID += 1
        points.append(
            TrackPoint(
                id: nextID,
                time: now,
                coordinate: location.coordinate,
                speedKPH: obdSpeed ?? gpsSpeed,
                rpm: freshValue("obd.0C", at: now, from: recorder)
            )
        )

        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }

    func clear() {
        points = []
        lastRecordTime = nil
    }

    private func freshValue(_ channelID: String, at time: Date, from recorder: TelemetryRecorder) -> Double? {
        guard let sample = recorder.samples(channelID).last,
              abs(time.timeIntervalSince(sample.time)) <= obdFreshWindow else {
            return nil
        }
        return sample.value
    }
}
