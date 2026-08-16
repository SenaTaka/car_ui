//
//  TelemetryRecorderTests.swift
//  car_uiTests
//
//  記録・CSV エクスポート(無料版行数制限含む)のテスト(監査 REL-014 対応)。
//

import XCTest
@testable import car_ui

final class TelemetryRecorderTests: XCTestCase {

    /// CSV は表示中の単位系に追従する(監査 A-1)。テストホストの地域が US だと
    /// 値が mph に換算されて期待値と食い違うため、単位系を明示的に固定する。
    private var savedUnitPreference: UnitSystemPreference = .automatic

    @MainActor
    override func setUp() {
        super.setUp()
        savedUnitPreference = UnitSettings.shared.preference
        UnitSettings.shared.preference = .metric
    }

    @MainActor
    override func tearDown() {
        UnitSettings.shared.preference = savedUnitPreference
        super.tearDown()
    }

    private func makeRecorder() -> TelemetryRecorder {
        // 前のテスト・過去実行の永続化ファイルを消して決定的にする
        try? FileManager.default.removeItem(at: TelemetryRecorder.persistURL)
        let recorder = TestRetention.retain(TelemetryRecorder())
        recorder.clear() // ディスク復元分を排除して決定的にする
        return recorder
    }

    /// persistToDisk はバックグラウンド書き込みのため、ファイルが現れるまで待つ
    /// (固定スリープはマシン負荷が高いときに書き込みへ追い越されて不安定だった)。
    private func waitForPersistFile() async throws {
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: TelemetryRecorder.persistURL.path) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("永続化ファイルが時間内に書き込まれなかった")
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
        // 復元は既定で直近 30 分に限定されるため、現在時刻で記録する
        let t0 = Date()
        recorder.record("obd.0C", value: 800, at: t0)
        recorder.record("gps.speed", value: 42.5, at: t0)

        recorder.persistToDisk()
        try await waitForPersistFile()

        let restored = TestRetention.retain(TelemetryRecorder())
        XCTAssertEqual(restored.latest("obd.0C"), 800)
        XCTAssertEqual(restored.latest("gps.speed"), 42.5)
        XCTAssertEqual(restored.channelIDs, ["gps.speed", "obd.0C"])
    }

    func testRestoreDropsSamplesOutsideDefaultWindow() async throws {
        let recorder = makeRecorder()
        // 既定の復元範囲(30 分)より古いサンプルは起動時に読み込まれない
        recorder.record("obd.0C", value: 1, at: Date(timeIntervalSinceNow: -3600))
        recorder.record("obd.0D", value: 2, at: Date())

        recorder.persistToDisk()
        try await waitForPersistFile()

        let restored = TestRetention.retain(TelemetryRecorder())
        XCTAssertNil(restored.latest("obd.0C"))
        XCTAssertEqual(restored.latest("obd.0D"), 2)
        XCTAssertEqual(restored.channelIDs, ["obd.0D"])
    }
}
