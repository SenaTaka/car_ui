//
//  LocationModel.swift
//  car_ui
//
//  GPS 連携: 速度・高度・方位・精度・積算距離を取得し、時系列レコーダへ送る。
//

@preconcurrency import CoreLocation
import Combine
import Foundation
import SwiftUI

/// GPS 精度の言語化(レビュー 9-4)。数値だけでなく品質を明示する。
enum GPSQuality {
    case unavailable  // 取得できていない
    case low          // 低精度(> 25m): 軌跡・加速計測に影響
    case normal       // 通常(10〜25m)
    case good         // 良好(< 10m)

    var label: LocalizedStringKey {
        switch self {
        case .unavailable: return "利用不可"
        case .low: return "低精度"
        case .normal: return "通常"
        case .good: return "良好"
        }
    }

    var color: Color {
        switch self {
        case .unavailable: return DS.Role.disabled
        case .low: return DS.Role.danger
        case .normal: return DS.Role.warn
        case .good: return DS.Role.ok
        }
    }

    /// この品質で 0-100 GPS 計測を許可してよいか(低精度・利用不可は不可)
    var allowsAccelTiming: Bool {
        self == .good || self == .normal
    }
}

final class LocationModel: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isDenied = false
    @Published private(set) var speedKPH: Double?
    @Published private(set) var altitudeM: Double?
    @Published private(set) var courseDegrees: Double?
    @Published private(set) var horizontalAccuracyM: Double?
    @Published private(set) var totalDistanceKm: Double = 0

    /// 水平精度から算出した GPS 品質(レビュー 9-4)
    var quality: GPSQuality {
        guard isActive, let accuracy = horizontalAccuracyM else { return .unavailable }
        switch accuracy {
        case ..<10: return .good
        case ..<25: return .normal
        default: return .low
        }
    }

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isDenied = true
        default:
            beginUpdates()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isActive = false
        lastLocation = nil
    }

    func resetDistance() {
        totalDistanceKm = 0
    }

    private func beginUpdates() {
        isDenied = false
        isActive = true
        manager.startUpdatingLocation()
    }

    private func apply(_ location: CLLocation) {
        horizontalAccuracyM = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        altitudeM = location.verticalAccuracy >= 0 ? location.altitude : nil
        speedKPH = location.speed >= 0 ? location.speed * 3.6 : nil
        courseDegrees = location.course >= 0 ? location.course : nil

        if let lastLocation, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 {
            let delta = location.distance(from: lastLocation)
            if delta > 1 {
                totalDistanceKm += delta / 1000
                self.lastLocation = location
            }
        } else {
            lastLocation = location
        }

        let recorder = TelemetryRecorder.shared
        recorder.record("gps.lat", value: location.coordinate.latitude, at: location.timestamp)
        recorder.record("gps.lon", value: location.coordinate.longitude, at: location.timestamp)
        if let speedKPH {
            recorder.record("gps.speed", value: speedKPH, at: location.timestamp)
        }
        if let altitudeM {
            recorder.record("gps.altitude", value: altitudeM, at: location.timestamp)
        }
        if let courseDegrees {
            recorder.record("gps.course", value: courseDegrees, at: location.timestamp)
        }
        recorder.record("gps.distance", value: totalDistanceKm, at: location.timestamp)

        // 走行軌跡(地図のコンター表示用)。精度の悪い点は軌跡を汚すので捨てる
        if location.horizontalAccuracy >= 0, location.horizontalAccuracy < 100 {
            TrackStore.shared.record(location: location)
        }
    }
}

extension LocationModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isActive || lastLocation == nil {
                beginUpdates()
            }
        case .denied, .restricted:
            isDenied = true
            isActive = false
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive else { return }
        locations.forEach(apply)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 一時的な取得失敗は無視(次の更新を待つ)
    }
}
