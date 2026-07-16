//
//  DriveRecordStoreTests.swift
//  car_uiTests
//
//  Pro 保存記録の保存・削除・再読込テスト(監査 REL-014 対応)。
//

import XCTest
@testable import car_ui

final class DriveRecordStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "driveRecords.v1")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "driveRecords.v1")
        super.tearDown()
    }

    private func splits(_ pairs: [(Int, Double)]) -> [AccelTestModel.Split] {
        pairs.map { AccelTestModel.Split(targetKPH: $0.0, seconds: $0.1) }
    }

    func testSaveAndReload() {
        let store = TestRetention.retain(DriveRecordStore())
        store.save(splits: splits([(20, 2.0), (100, 10.5)]), peakG: 0.8)

        // 別インスタンスで UserDefaults から再読込できる
        let reloaded = TestRetention.retain(DriveRecordStore())
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records[0].peakG, 0.8)
        XCTAssertEqual(reloaded.records[0].splits.map(\.targetKPH), [20, 100])
    }

    func testDeleteByOffsetsAndRecord() {
        let store = TestRetention.retain(DriveRecordStore())
        store.save(splits: splits([(100, 12.0)]), peakG: 0.5)
        store.save(splits: splits([(100, 9.0)]), peakG: 0.7)
        store.save(splits: splits([(100, 10.0)]), peakG: 0.6)
        XCTAssertEqual(store.records.count, 3)

        // 先頭(最新 = 10.0 秒)を削除
        store.delete(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.records[0].splits[0].seconds, 9.0)

        // レコード指定で削除
        store.delete(store.records[0])
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[0].splits[0].seconds, 12.0)
    }

    func testBestZeroToHundred() {
        let store = TestRetention.retain(DriveRecordStore())
        XCTAssertNil(store.bestZeroToHundred)

        store.save(splits: splits([(100, 12.0)]), peakG: 0.5)
        store.save(splits: splits([(100, 9.4)]), peakG: 0.7)
        store.save(splits: splits([(20, 2.0)]), peakG: 0.3) // 100 未到達は対象外

        XCTAssertEqual(store.bestZeroToHundred, 9.4)
    }

    func testNewestFirstOrdering() {
        let store = TestRetention.retain(DriveRecordStore())
        store.save(splits: splits([(100, 12.0)]), peakG: 0.5)
        store.save(splits: splits([(100, 9.0)]), peakG: 0.7)
        XCTAssertEqual(store.records[0].splits[0].seconds, 9.0, "最新の記録が先頭に来る")
    }
}
