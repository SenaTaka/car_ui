//
//  ReadinessStatus.swift
//  car_ui
//
//  Mode 01 PID 0x01(モニタステータス)のパース結果。
//  車検・排ガス検査前のレディネスチェックに使う。
//

import Foundation

struct ReadinessStatus {
    struct Monitor: Identifiable {
        let name: String
        let supported: Bool
        /// 未完了ビットが 0 のとき Ready
        let ready: Bool

        var id: String { name }
    }

    /// MIL(エンジン警告灯)点灯中か
    let milOn: Bool
    /// 確定 DTC 数
    let dtcCount: Int
    /// true = 圧縮着火(ディーゼル)。バイト C/D のモニタ名称が変わる
    let isCompressionIgnition: Bool
    let monitors: [Monitor]

    var notReadyCount: Int {
        monitors.filter { $0.supported && !$0.ready }.count
    }

    /// 0101 応答のデータ 4 バイト(A B C D)から生成する。
    /// A: bit7=MIL, bit0-6=DTC数 / B: bit0-2=常時モニタ support, bit3=点火方式, bit4-6=未完了
    /// C: 非常時モニタ support / D: 同・未完了(1=Not Ready)
    static func parse(_ bytes: [UInt8]) -> ReadinessStatus? {
        guard bytes.count >= 4 else { return nil }

        let a = bytes[0]
        let b = bytes[1]
        let c = bytes[2]
        let d = bytes[3]

        let isDiesel = b & 0x08 != 0

        var monitors: [Monitor] = []

        let continuousNames = ["失火", "燃料系統", "包括コンポーネント"]
        for (bit, name) in continuousNames.enumerated() {
            let supported = b & (1 << bit) != 0
            let incomplete = b & (1 << (bit + 4)) != 0
            monitors.append(Monitor(name: name, supported: supported, ready: !incomplete))
        }

        // (bit, ガソリン名, ディーゼル名)。bit2/4 はガソリンのみ、ディーゼルでは予約
        let nonContinuous: [(Int, String?, String?)] = [
            (0, "触媒", "NMHC 触媒"),
            (1, "加熱触媒", "NOx/SCR"),
            (2, "EVAP(蒸発ガス)", nil),
            (3, "二次空気", "ブースト圧"),
            (5, "O2 センサー", "排ガスセンサー"),
            (6, "O2 ヒーター", "PM フィルター"),
            (7, "EGR/VVT", "EGR/VVT")
        ]
        for (bit, petrolName, dieselName) in nonContinuous {
            guard let name = isDiesel ? dieselName : petrolName else { continue }
            let supported = c & (1 << bit) != 0
            let incomplete = d & (1 << bit) != 0
            monitors.append(Monitor(name: name, supported: supported, ready: !incomplete))
        }

        return ReadinessStatus(
            milOn: a & 0x80 != 0,
            dtcCount: Int(a & 0x7F),
            isCompressionIgnition: isDiesel,
            monitors: monitors
        )
    }

    /// デモモード用: MIL 消灯・DTC 0 件・EVAP のみ Not Ready(バッテリー交換後によくある状態)
    static let demo: ReadinessStatus = {
        // A=0x00, B=0x07(常時3種 support・全完了), C=0xE7(EVAP等 support), D=0x04(EVAP のみ未完了)
        parse([0x00, 0x07, 0xE7, 0x04])!
    }()
}
