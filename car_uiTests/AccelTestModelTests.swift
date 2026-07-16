//
//  AccelTestModelTests.swift
//  car_uiTests
//
//  0-100 km/h 計測の状態遷移テスト(監査 REL-014 対応)。
//

import XCTest
@testable import car_ui

final class AccelTestModelTests: XCTestCase {

    func testFullRunRecordsAllSplits() {
        let model = TestRetention.retain(AccelTestModel())
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        model.arm()
        XCTAssertEqual(model.state, .armed)

        // 停止中は armed のまま
        model.update(speedKPH: 0, at: t0)
        XCTAssertEqual(model.state, .armed)

        // 発進(>= 1 km/h)で running へ
        model.update(speedKPH: 5, at: t0.addingTimeInterval(0.1))
        guard case .running = model.state else {
            return XCTFail("発進後は running になるべき")
        }

        model.update(speedKPH: 25, at: t0.addingTimeInterval(2.0))
        model.update(speedKPH: 45, at: t0.addingTimeInterval(4.0))
        model.update(speedKPH: 65, at: t0.addingTimeInterval(6.0))
        model.update(speedKPH: 85, at: t0.addingTimeInterval(8.0))
        model.update(speedKPH: 105, at: t0.addingTimeInterval(10.0))

        XCTAssertEqual(model.state, .finished)
        XCTAssertEqual(model.splits.map(\.targetKPH), [20, 40, 60, 80, 100])
        // スプリット時間は発進時刻からの経過秒
        XCTAssertEqual(model.splits[0].seconds, 1.9, accuracy: 0.001)
        XCTAssertEqual(model.splits[4].seconds, 9.9, accuracy: 0.001)
    }

    func testOneSampleCrossingRecordsAllThresholds() {
        let model = TestRetention.retain(AccelTestModel())
        let t0 = Date(timeIntervalSince1970: 2_000_000)

        model.arm()
        model.update(speedKPH: 2, at: t0)
        model.update(speedKPH: 120, at: t0.addingTimeInterval(5))

        XCTAssertEqual(model.state, .finished)
        XCTAssertEqual(model.splits.count, 5)
        // 全スプリットが同一サンプル時刻になる(補間なしの現仕様)
        XCTAssertTrue(model.splits.allSatisfy { abs($0.seconds - 5) < 0.001 })
    }

    func testCancelResetsState() {
        let model = TestRetention.retain(AccelTestModel())
        model.arm()
        model.update(speedKPH: 50, at: Date())
        model.cancel()

        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.splits.isEmpty)
        XCTAssertEqual(model.elapsed, 0)
    }

    func testUpdateIgnoredWhenIdle() {
        let model = TestRetention.retain(AccelTestModel())
        model.update(speedKPH: 100, at: Date())
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.splits.isEmpty)
    }
}
