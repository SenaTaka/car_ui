//
//  TrackStoreTests.swift
//  car_uiTests
//
//  走行軌跡 TrackPoint の Codable 往復テスト(監査 REL-011/014 対応)。
//

import CoreLocation
import XCTest
@testable import car_ui

final class TrackStoreTests: XCTestCase {

    func testTrackPointCodableRoundTrip() throws {
        let points = [
            TrackPoint(
                id: 1,
                time: Date(timeIntervalSince1970: 1_000_000),
                coordinate: CLLocationCoordinate2D(latitude: 34.6851, longitude: 135.5010),
                speedKPH: 42.5,
                rpm: 1800
            ),
            TrackPoint(
                id: 2,
                time: Date(timeIntervalSince1970: 1_000_001),
                coordinate: CLLocationCoordinate2D(latitude: 34.6860, longitude: 135.5021),
                speedKPH: nil,
                rpm: nil
            ),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let data = try encoder.encode(points)
        let restored = try decoder.decode([TrackPoint].self, from: data)

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].id, 1)
        XCTAssertEqual(restored[0].coordinate.latitude, 34.6851, accuracy: 0.000001)
        XCTAssertEqual(restored[0].coordinate.longitude, 135.5010, accuracy: 0.000001)
        XCTAssertEqual(restored[0].speedKPH, 42.5)
        XCTAssertEqual(restored[0].rpm, 1800)
        XCTAssertNil(restored[1].speedKPH)
        XCTAssertNil(restored[1].rpm)
        XCTAssertEqual(restored[1].time, Date(timeIntervalSince1970: 1_000_001))
    }
}
