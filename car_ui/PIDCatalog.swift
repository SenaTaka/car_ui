//
//  PIDCatalog.swift
//  car_ui
//
//  OBD-II Mode 01 PID の定義カタログ。
//  対応 PID を自動検出して全件表示するためのメタデータ+デコード式を持つ。
//

import SwiftUI

struct PIDDefinition: Identifiable {
    let pid: UInt8
    let name: String
    let unit: String
    let icon: String
    let tint: Color
    let gaugeRange: ClosedRange<Double>
    let fractionDigits: Int
    let decode: ([UInt8]) -> Double?

    var id: UInt8 { pid }
    var channelID: String { String(format: "obd.%02X", pid) }
    var command: String { String(format: "01%02X", pid) }
}

enum PIDCatalog {
    // 毎サイクル取得する高速系(応答性重視)
    static let fastPIDs: [UInt8] = [0x0C, 0x0D, 0x11, 0x04]

    static func definition(for pid: UInt8) -> PIDDefinition? {
        byPID[pid]
    }

    static func definition(forChannel channelID: String) -> PIDDefinition? {
        guard channelID.hasPrefix("obd."),
              let pid = UInt8(channelID.dropFirst(4), radix: 16) else {
            return nil
        }
        return byPID[pid]
    }

    static let byPID: [UInt8: PIDDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.pid, $0) })
    }()

    private static func byteA(_ b: [UInt8]) -> Double? {
        b.first.map(Double.init)
    }

    private static func wordAB(_ b: [UInt8]) -> Double? {
        guard b.count >= 2 else { return nil }
        return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
    }

    private static func percentA(_ b: [UInt8]) -> Double? {
        byteA(b).map { $0 * 100 / 255 }
    }

    private static func tempA(_ b: [UInt8]) -> Double? {
        byteA(b).map { $0 - 40 }
    }

    private static func fuelTrim(_ b: [UInt8]) -> Double? {
        byteA(b).map { $0 * 100 / 128 - 100 }
    }

    private static func o2Voltage(_ b: [UInt8]) -> Double? {
        byteA(b).map { $0 * 0.005 }
    }

    private static func catalystTemp(_ b: [UInt8]) -> Double? {
        wordAB(b).map { $0 / 10 - 40 }
    }

    static let all: [PIDDefinition] = [
        PIDDefinition(pid: 0x04, name: "エンジン負荷", unit: "%", icon: "engine.combustion", tint: .purple, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x05, name: "冷却水温", unit: "℃", icon: "thermometer.medium", tint: .red, gaugeRange: -40...140, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x06, name: "短期燃料補正 B1", unit: "%", icon: "drop", tint: .cyan, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x07, name: "長期燃料補正 B1", unit: "%", icon: "drop.fill", tint: .cyan, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x08, name: "短期燃料補正 B2", unit: "%", icon: "drop", tint: .teal, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x09, name: "長期燃料補正 B2", unit: "%", icon: "drop.fill", tint: .teal, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x0A, name: "燃圧", unit: "kPa", icon: "gauge.low", tint: .orange, gaugeRange: 0...765, fractionDigits: 0, decode: { byteA($0).map { $0 * 3 } }),
        PIDDefinition(pid: 0x0B, name: "吸気圧 (MAP)", unit: "kPa", icon: "barometer", tint: .indigo, gaugeRange: 0...255, fractionDigits: 0, decode: byteA),
        PIDDefinition(pid: 0x0C, name: "エンジン回転数", unit: "rpm", icon: "tachometer", tint: .orange, gaugeRange: 0...8000, fractionDigits: 0, decode: { wordAB($0).map { $0 / 4 } }),
        PIDDefinition(pid: 0x0D, name: "車速 (OBD)", unit: "km/h", icon: "speedometer", tint: .blue, gaugeRange: 0...240, fractionDigits: 0, decode: byteA),
        PIDDefinition(pid: 0x0E, name: "点火時期", unit: "°", icon: "sparkles", tint: .yellow, gaugeRange: -64...64, fractionDigits: 1, decode: { byteA($0).map { $0 / 2 - 64 } }),
        PIDDefinition(pid: 0x0F, name: "吸気温", unit: "℃", icon: "wind", tint: .teal, gaugeRange: -40...120, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x10, name: "吸入空気量 (MAF)", unit: "g/s", icon: "waveform.path.ecg", tint: .indigo, gaugeRange: 0...300, fractionDigits: 1, decode: { wordAB($0).map { $0 / 100 } }),
        PIDDefinition(pid: 0x11, name: "スロットル開度", unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x14, name: "O2 センサー B1S1", unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x15, name: "O2 センサー B1S2", unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x16, name: "O2 センサー B1S3", unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x17, name: "O2 センサー B1S4", unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x18, name: "O2 センサー B2S1", unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x19, name: "O2 センサー B2S2", unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x1A, name: "O2 センサー B2S3", unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x1B, name: "O2 センサー B2S4", unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x1F, name: "エンジン稼働時間", unit: "秒", icon: "clock", tint: .gray, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
        PIDDefinition(pid: 0x21, name: "MIL 点灯後走行距離", unit: "km", icon: "exclamationmark.triangle", tint: .orange, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
        PIDDefinition(pid: 0x22, name: "燃圧 (マニホールド比)", unit: "kPa", icon: "gauge.low", tint: .orange, gaugeRange: 0...5178, fractionDigits: 1, decode: { wordAB($0).map { $0 * 0.079 } }),
        PIDDefinition(pid: 0x23, name: "燃圧 (直噴レール)", unit: "kPa", icon: "gauge.high", tint: .orange, gaugeRange: 0...655350, fractionDigits: 0, decode: { wordAB($0).map { $0 * 10 } }),
        PIDDefinition(pid: 0x2C, name: "EGR 指令値", unit: "%", icon: "arrow.triangle.2.circlepath", tint: .brown, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x2D, name: "EGR 誤差", unit: "%", icon: "arrow.triangle.2.circlepath", tint: .brown, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x2E, name: "パージ制御", unit: "%", icon: "aqi.medium", tint: .gray, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x2F, name: "燃料残量", unit: "%", icon: "fuelpump", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x31, name: "DTC クリア後走行距離", unit: "km", icon: "road.lanes", tint: .gray, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
        PIDDefinition(pid: 0x33, name: "大気圧", unit: "kPa", icon: "barometer", tint: .blue, gaugeRange: 0...255, fractionDigits: 0, decode: byteA),
        PIDDefinition(pid: 0x3C, name: "触媒温度 B1S1", unit: "℃", icon: "flame", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x3D, name: "触媒温度 B2S1", unit: "℃", icon: "flame", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x3E, name: "触媒温度 B1S2", unit: "℃", icon: "flame.fill", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x3F, name: "触媒温度 B2S2", unit: "℃", icon: "flame.fill", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x42, name: "ECU 電圧", unit: "V", icon: "bolt", tint: .yellow, gaugeRange: 0...20, fractionDigits: 2, decode: { wordAB($0).map { $0 / 1000 } }),
        PIDDefinition(pid: 0x43, name: "絶対負荷", unit: "%", icon: "engine.combustion.badge.exclamationmark", tint: .purple, gaugeRange: 0...100, fractionDigits: 1, decode: { wordAB($0).map { $0 * 100 / 255 } }),
        PIDDefinition(pid: 0x44, name: "目標空燃比 (λ)", unit: "", icon: "scalemass", tint: .mint, gaugeRange: 0...2, fractionDigits: 3, decode: { wordAB($0).map { $0 / 32768 } }),
        PIDDefinition(pid: 0x45, name: "相対スロットル", unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x46, name: "外気温", unit: "℃", icon: "thermometer.sun", tint: .cyan, gaugeRange: -40...60, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x47, name: "スロットル絶対 B", unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x49, name: "アクセルペダル D", unit: "%", icon: "shoeprints.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x4A, name: "アクセルペダル E", unit: "%", icon: "shoeprints.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x4C, name: "スロットル指令値", unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x52, name: "エタノール比率", unit: "%", icon: "leaf", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x5A, name: "相対アクセルペダル", unit: "%", icon: "shoeprints.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x5C, name: "エンジン油温", unit: "℃", icon: "oilcan", tint: .brown, gaugeRange: -40...160, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x5E, name: "燃料流量", unit: "L/h", icon: "fuelpump.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 2, decode: { wordAB($0).map { $0 / 20 } }),
        PIDDefinition(pid: 0x61, name: "要求トルク", unit: "%", icon: "gearshape.arrow.triangle.2.circlepath", tint: .purple, gaugeRange: -125...130, fractionDigits: 0, decode: { byteA($0).map { $0 - 125 } }),
        PIDDefinition(pid: 0x62, name: "実トルク", unit: "%", icon: "gearshape.2", tint: .purple, gaugeRange: -125...130, fractionDigits: 0, decode: { byteA($0).map { $0 - 125 } }),
        PIDDefinition(pid: 0x63, name: "基準トルク", unit: "Nm", icon: "gearshape", tint: .purple, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
    ]
}
