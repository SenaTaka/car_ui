//
//  PIDCatalogTests.swift
//  car_uiTests
//
//  PID デコード式の境界値テスト(監査 REL-014 対応)。
//

import XCTest
@testable import car_ui

final class PIDCatalogTests: XCTestCase {

    func testRPMDecode() throws {
        let rpm = try XCTUnwrap(PIDCatalog.byPID[0x0C])
        // ((A*256)+B)/4
        XCTAssertEqual(rpm.decode([0x00, 0x00]), 0)
        XCTAssertEqual(rpm.decode([0x0B, 0xB8]), 750)      // 3000/4
        XCTAssertEqual(rpm.decode([0xFF, 0xFF]), 16383.75) // 上限
        XCTAssertNil(rpm.decode([0x0B]))                   // バイト不足
        XCTAssertNil(rpm.decode([]))
    }

    func testSpeedDecode() throws {
        let speed = try XCTUnwrap(PIDCatalog.byPID[0x0D])
        XCTAssertEqual(speed.decode([0x00]), 0)
        XCTAssertEqual(speed.decode([0x64]), 100)
        XCTAssertEqual(speed.decode([0xFF]), 255)
        XCTAssertNil(speed.decode([]))
    }

    func testCoolantTempDecode() throws {
        let temp = try XCTUnwrap(PIDCatalog.byPID[0x05])
        // A - 40
        XCTAssertEqual(temp.decode([0x00]), -40)
        XCTAssertEqual(temp.decode([0x28]), 0)
        XCTAssertEqual(temp.decode([0xFF]), 215)
    }

    func testEngineLoadDecode() throws {
        let load = try XCTUnwrap(PIDCatalog.byPID[0x04])
        // A * 100 / 255
        XCTAssertEqual(try XCTUnwrap(load.decode([0x00])), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(load.decode([0xFF])), 100, accuracy: 0.01)
    }

    func testFuelTrimDecode() throws {
        let trim = try XCTUnwrap(PIDCatalog.byPID[0x06])
        // (A - 128) * 100 / 128
        XCTAssertEqual(try XCTUnwrap(trim.decode([0x80])), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(trim.decode([0x00])), -100, accuracy: 0.01)
    }

    func testChannelLookup() {
        XCTAssertNotNil(PIDCatalog.definition(forChannel: "obd.0C"))
        XCTAssertNil(PIDCatalog.definition(forChannel: "gps.speed"))
    }
}
