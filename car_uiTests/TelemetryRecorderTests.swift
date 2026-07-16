//
//  TelemetryRecorderTests.swift
//  car_uiTests
//
//  記録・CSV エクスポート(無料版行数制限含む)のテスト(監査 REL-014 対応)。
//

import XCTest
@testable import car_ui

final class TelemetryRecorderTests: XCTestCase {

    private func makeRecorder() -> TelemetryRecorder {
        let recorder = TestRetention.retain(TelemetryRecorder())
        recorder.clear() // ディスク復元分を排除して決定的にする
        return recorder
    }

    func testRecordAndLatest() {
        let recorder = makeRecorder()
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        recorder.record("obd.0C", value: 800, at: t0)
        recorder.record("obd.0C", value: 1200, at: t0.addingTimeInterval(1))

        XCTAssertEqual(recorder.latest("obd.0C"), 1200)
        XCTAssertEqual(recorder.samples("obd.0C").count, 2)
        XCTAssertEqual(recorder.channelIDs, ["obd.0C"])
    }

    func testNonFiniteValuesAreRejected() {
        let recorder = makeRecorder()
        recorder.record("obd.0C", value: .nan)
        recorder.record("obd.0C", value: .infinity)
        XCTAssertTrue(recorder.samples("obd.0C").isEmpty)
    }

    func testSamplesSinceFiltersByTime() {
        let recorder = makeRecorder()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<10 {
            recorder.record("obd.0D", value: Double(i), at: t0.addingTimeInterval(Double(i)))
        }
        let recent = recorder.samples("obd.0D", since: t0.addingTimeInterval(5))
        XCTAssertEqual(recent.count, 5)
        XCTAssertEqual(recent.first?.value, 5)
    }

    func testCSVFreeRowLimit() {
        let recorder = makeRecorder()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<600 {
            recorder.record("obd.0D", value: Double(i), at: t0.addingTimeInterval(Double(i)))
        }

        let free = String(decoding: recorder.csvData(for: ["obd.0D"], rowLimit: 500), as: UTF8.self)
        let freeRows = free.split(separator: "\n").count - 1 // ヘッダを除く
        XCTAssertEqual(freeRows, 500)

        let pro = String(decoding: recorder.csvData(for: ["obd.0D"], rowLimit: nil), as: UTF8.self)
        let proRows = pro.split(separator: "\n").count - 1
        XCTAssertEqual(proRows, 600)

        // 無料版は「直近」500 件(先頭 100 件が切り捨てられる)
        XCTAssertFalse(free.contains(",99\n"))
        XCTAssertTrue(free.contains(",100\n"))
    }

    func testCSVWideHeaderAndRows() {
        let recorder = makeRecorder()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        recorder.record("obd.0C", value: 800, at: t0)
        recorder.record("obd.0D", value: 40, at: t0)

        let csv = String(decoding: recorder.csvWideData(for: ["obd.0C", "obd.0D"]), as: UTF8.self)
        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[0].hasPrefix("time,"))
        XCTAssertEqual(lines[0].split(separator: ",").count, 3) // time + 2ch
        XCTAssertGreaterThanOrEqual(lines.count, 2)
    }

    func testPersistRoundTrip() async throws {
        let recorder = makeRecorder()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        recorder.record("obd.0C", value: 800, at: t0)
        recorder.record("gps.speed", value: 42.5, at: t0)

        recorder.persistToDisk()
        // persistToDisk はバックグラウンド書き込みのため完了を待つ
        try await Task.sleep(nanoseconds: 500_000_000)

        let restored = TestRetention.retain(TelemetryRecorder())
        XCTAssertEqual(restored.latest("obd.0C"), 800)
        XCTAssertEqual(restored.latest("gps.speed"), 42.5)
        XCTAssertEqual(restored.channelIDs, ["gps.speed", "obd.0C"])
    }
}
