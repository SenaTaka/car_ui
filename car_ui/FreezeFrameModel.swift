//
//  FreezeFrameModel.swift
//  car_ui
//
//  Mode 02 フリーズフレーム(DTC 確定時に ECU が保存する車両状態スナップショット)。
//

import Foundation

struct FreezeFrameSnapshot {
    struct Entry: Identifiable {
        let pid: UInt8
        let value: Double

        var id: UInt8 { pid }
    }

    /// フリーズフレームを確定させた DTC(Mode 02 PID 0x02)
    let triggeringDTC: String?
    /// アプリで読み取った時刻(ECU 側の発生時刻は取得不可)
    let capturedAt: Date
    let entries: [Entry]

    /// デモモード用: P0301(1番シリンダー失火)発生時の現実的なスナップショット
    static let demo = FreezeFrameSnapshot(
        triggeringDTC: "P0301",
        capturedAt: Date(),
        entries: [
            Entry(pid: 0x0C, value: 3180),  // RPM
            Entry(pid: 0x0D, value: 62),    // 車速
            Entry(pid: 0x04, value: 47),    // エンジン負荷
            Entry(pid: 0x05, value: 88),    // 水温
            Entry(pid: 0x0B, value: 54),    // 吸気圧
            Entry(pid: 0x11, value: 32),    // スロットル
            Entry(pid: 0x0F, value: 31),    // 吸気温
            Entry(pid: 0x06, value: 2.3),   // 短期燃料補正
            Entry(pid: 0x07, value: 1.6)    // 長期燃料補正
        ]
    )
}
