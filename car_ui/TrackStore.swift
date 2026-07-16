//
//  TrackStore.swift
//  car_ui
//
//  GPS 走行軌跡の記録。各点に速度・RPM を紐付け、地図のコンター表示に使う。
//

import Combine
import CoreLocation
import Foundation

// nonisolated: バックグラウンドでの JSON 符号化(persistToDisk)で使うため
nonisolated struct TrackPoint: Identifiable {
    let id: Int
    let time: Date
    let coordinate: CLLocationCoordinate2D
    /// OBD 車速を優先、なければ GPS 車速
    let speedKPH: Double?
    let rpm: Double?
}

// 監査 REL-011: 永続化のため Codable 対応(CLLocationCoordinate2D は緯度経度で符号化)
nonisolated extension TrackPoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, time, lat, lon, speedKPH, rpm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        time = try c.decode(Date.self, forKey: .time)
        coordinate = CLLocationCoordinate2D(
            latitude: try c.decode(Double.self, forKey: .lat),
            longitude: try c.decode(Double.self, forKey: .lon)
        )
        speedKPH = try c.decodeIfPresent(Double.self, forKey: .speedKPH)
        rpm = try c.decodeIfPresent(Double.self, forKey: .rpm)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(time, forKey: .time)
        try c.encode(coordinate.latitude, forKey: .lat)
        try c.encode(coordinate.longitude, forKey: .lon)
        try c.encodeIfPresent(speedKPH, forKey: .speedKPH)
        try c.encodeIfPresent(rpm, forKey: .rpm)
    }
}

@MainActor
final class TrackStore: ObservableObject {
    static let shared = TrackStore()

    @Published private(set) var points: [TrackPoint] = []

    private var nextID = 0
    private var lastRecordTime: Date?
    private var lastPersist = Date()
    /// 監査 REL-011: 記録中はこの間隔でディスクへ退避
    private let persistInterval: TimeInterval = 60

    private init() {
        restoreFromDisk()
    }
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

        if now.timeIntervalSince(lastPersist) > persistInterval {
            persistToDisk()
        }
    }

    func clear() {
        points = []
        lastRecordTime = nil
        persistToDisk()
    }

    // MARK: - 永続化(監査 REL-011: アプリ終了・クラッシュで軌跡が消えないように)

    nonisolated static var persistURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("car_ui", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("track.json")
    }

    /// スナップショットをバックグラウンドで JSON 保存する(呼び出し側は待たない)。
    func persistToDisk() {
        lastPersist = Date()
        let snapshot = points
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: Self.persistURL, options: .atomic)
        }
    }

    private func restoreFromDisk() {
        guard let data = try? Data(contentsOf: Self.persistURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let restored = try? decoder.decode([TrackPoint].self, from: data),
              !restored.isEmpty else { return }
        points = restored
        nextID = restored.map(\.id).max() ?? 0
    }

    private func freshValue(_ channelID: String, at time: Date, from recorder: TelemetryRecorder) -> Double? {
        guard let sample = recorder.samples(channelID).last,
              abs(time.timeIntervalSince(sample.time)) <= obdFreshWindow else {
            return nil
        }
        return sample.value
    }
}
