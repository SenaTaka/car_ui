//
//  TrackContourTests.swift
//  car_uiTests
//
//  コンター配色・レンジ解決・進行方位のロジックテスト(走行マップ改善)。
//

import CoreLocation
import SwiftUI
import XCTest
@testable import car_ui

final class TrackContourTests: XCTestCase {

    private func point(_ lat: Double, _ lon: Double, t: TimeInterval, speed: Double? = nil, rpm: Double? = nil) -> TrackPoint {
        TrackPoint(
            id: Int(t),
            time: Date(timeIntervalSince1970: 1_000_000 + t),
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            speedKPH: speed,
            rpm: rpm
        )
    }

    // MARK: - jet カラーマップ

    func testJetEndpointsAndMonotonicHue() {
        // 0 は濃青、1 は濃赤(端点)
        XCTAssertEqual(TrackContour.color(forNormalized: 0.0), Color(red: 0, green: 0, blue: 0.5))
        XCTAssertEqual(TrackContour.color(forNormalized: 1.0), Color(red: 0.5, green: 0, blue: 0))
        // クランプ: 範囲外でも端点色に収束
        XCTAssertEqual(TrackContour.color(forNormalized: -1), TrackContour.color(forNormalized: 0))
        XCTAssertEqual(TrackContour.color(forNormalized: 2), TrackContour.color(forNormalized: 1))
        // 中央付近は緑寄り(jet の中心)
        XCTAssertNotEqual(TrackContour.color(forNormalized: 0.5), TrackContour.color(forNormalized: 0.0))
    }

    // MARK: - バケット(手動レンジのクランプ)

    func testBucketClampsToManualRange() {
        let range = 0.0...100.0
        // レンジ下限
        XCTAssertEqual(TrackContour.bucket(for: point(0, 0, t: 0, speed: 0), source: .speed, range: range), 0)
        // レンジ上限(bucketCount-1 に収まる)
        XCTAssertEqual(TrackContour.bucket(for: point(0, 0, t: 0, speed: 100), source: .speed, range: range), TrackContour.bucketCount - 1)
        // レンジ超過もクランプ
        XCTAssertEqual(TrackContour.bucket(for: point(0, 0, t: 0, speed: 999), source: .speed, range: range), TrackContour.bucketCount - 1)
        // 値なしは nil
        XCTAssertNil(TrackContour.bucket(for: point(0, 0, t: 0, speed: nil), source: .speed, range: range))
    }

    // MARK: - 実効レンジ(自動 / 手動)

    func testEffectiveRangeAutoUsesMeasuredMinMax() {
        let pts = [point(0, 0, t: 0, speed: 20), point(0, 0, t: 1, speed: 80)]
        let range = TrackRangeResolver.effectiveRange(
            points: pts, source: .speed, auto: true,
            speedMin: 0, speedMax: 120, rpmMin: 0, rpmMax: 8000
        )
        XCTAssertEqual(range?.lowerBound, 20)
        XCTAssertEqual(range?.upperBound, 80)
    }

    func testEffectiveRangeManualUsesConfiguredMinMax() {
        let pts = [point(0, 0, t: 0, speed: 20), point(0, 0, t: 1, speed: 80)]
        let range = TrackRangeResolver.effectiveRange(
            points: pts, source: .speed, auto: false,
            speedMin: 0, speedMax: 60, rpmMin: 0, rpmMax: 8000
        )
        XCTAssertEqual(range?.lowerBound, 0)
        XCTAssertEqual(range?.upperBound, 60)
    }

    func testEffectiveRangeManualPerSource() {
        let pts = [point(0, 0, t: 0, rpm: 1000), point(0, 0, t: 1, rpm: 6000)]
        let range = TrackRangeResolver.effectiveRange(
            points: pts, source: .rpm, auto: false,
            speedMin: 0, speedMax: 60, rpmMin: 500, rpmMax: 7000
        )
        XCTAssertEqual(range?.lowerBound, 500)
        XCTAssertEqual(range?.upperBound, 7000)
    }

    // MARK: - 進行方位

    func testBearingOfTravelDueNorth() {
        // 南から北へ移動 → 方位 ≈ 0°
        let pts = [point(34.6800, 135.5, t: 0), point(34.6900, 135.5, t: 5)]
        let bearing = try? XCTUnwrap(TrackContour.bearingOfTravel(pts, minDistance: 10))
        XCTAssertNotNil(bearing)
        XCTAssertEqual(bearing ?? -1, 0, accuracy: 1.0)
    }

    func testBearingOfTravelDueEast() {
        // 西から東へ移動 → 方位 ≈ 90°
        let pts = [point(34.68, 135.500, t: 0), point(34.68, 135.520, t: 5)]
        let bearing = try? XCTUnwrap(TrackContour.bearingOfTravel(pts, minDistance: 10))
        XCTAssertEqual(bearing ?? -1, 90, accuracy: 1.0)
    }

    func testBearingNilWhenStationary() {
        // 動いていない(移動距離が閾値未満) → nil
        let pts = [point(34.68, 135.5, t: 0), point(34.680001, 135.5, t: 5)]
        XCTAssertNil(TrackContour.bearingOfTravel(pts, minDistance: 15))
    }
}
