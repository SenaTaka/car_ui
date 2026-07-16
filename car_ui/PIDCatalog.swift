//
//  PIDCatalog.swift
//  car_ui
//
//  OBD-II Mode 01 PID の定義カタログ。
//  対応 PID を自動検出して全件表示するためのメタデータ+デコード式を持つ。
//

import SwiftUI

/// チャンネル分類(レビュー 6章・8章: チャンネル選択のカテゴリ化)
enum PIDCategory: String, CaseIterable, Identifiable {
    case driving   // 走行
    case engine    // エンジン
    case fuel      // 燃料
    case intake    // 吸排気
    case temperature // 温度
    case diagnostics // 診断
    case other     // その他

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .driving: return "走行"
        case .engine: return "エンジン"
        case .fuel: return "燃料"
        case .intake: return "吸排気"
        case .temperature: return "温度"
        case .diagnostics: return "診断"
        case .other: return "その他"
        }
    }
}

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

    /// PID から分類を決定(レビュー 6章・8章)
    var category: PIDCategory {
        switch pid {
        case 0x0C, 0x0D, 0x11, 0x45, 0x49, 0x4A, 0x4C, 0x31, 0x62, 0x63, 0x64:
            return .driving          // 回転数・車速・スロットル・トルク・距離
        case 0x04, 0x05, 0x0E, 0x1F, 0x43, 0x52, 0x5C, 0x42:
            return .engine           // 負荷・点火・稼働時間・エタノール・油温・ECU電圧
        case 0x06, 0x07, 0x08, 0x09, 0x0A, 0x22, 0x23, 0x2F, 0x5E, 0x51, 0x44:
            return .fuel             // 燃料補正・燃圧・残量・流量・λ
        case 0x0B, 0x0F, 0x10, 0x33, 0x46, 0x47, 0x48, 0x2C, 0x2D:
            return .intake           // 吸気圧・吸気温・MAF・大気圧・EGR/パージ
        case 0x3C, 0x3D, 0x3E, 0x3F:
            return .temperature      // 触媒温度
        case 0x14...0x1B:
            return .fuel             // O2 センサー(燃料系)
        default:
            return .other
        }
    }
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
        PIDDefinition(pid: 0x04, name: String(localized: "エンジン負荷"), unit: "%", icon: "engine.combustion", tint: .purple, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x05, name: String(localized: "冷却水温"), unit: "℃", icon: "thermometer.medium", tint: .red, gaugeRange: -40...140, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x06, name: String(localized: "短期燃料補正 B1"), unit: "%", icon: "drop", tint: .cyan, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x07, name: String(localized: "長期燃料補正 B1"), unit: "%", icon: "drop.fill", tint: .cyan, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x08, name: String(localized: "短期燃料補正 B2"), unit: "%", icon: "drop", tint: .teal, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x09, name: String(localized: "長期燃料補正 B2"), unit: "%", icon: "drop.fill", tint: .teal, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x0A, name: String(localized: "燃圧"), unit: "kPa", icon: "gauge.low", tint: .orange, gaugeRange: 0...765, fractionDigits: 0, decode: { byteA($0).map { $0 * 3 } }),
        PIDDefinition(pid: 0x0B, name: String(localized: "吸気圧 (MAP)"), unit: "kPa", icon: "barometer", tint: .indigo, gaugeRange: 0...255, fractionDigits: 0, decode: byteA),
        PIDDefinition(pid: 0x0C, name: String(localized: "エンジン回転数"), unit: "rpm", icon: "tachometer", tint: .orange, gaugeRange: 0...8000, fractionDigits: 0, decode: { wordAB($0).map { $0 / 4 } }),
        PIDDefinition(pid: 0x0D, name: String(localized: "車速 (OBD)"), unit: "km/h", icon: "speedometer", tint: .blue, gaugeRange: 0...240, fractionDigits: 0, decode: byteA),
        PIDDefinition(pid: 0x0E, name: String(localized: "点火時期"), unit: "°", icon: "sparkles", tint: .yellow, gaugeRange: -64...64, fractionDigits: 1, decode: { byteA($0).map { $0 / 2 - 64 } }),
        PIDDefinition(pid: 0x0F, name: String(localized: "吸気温"), unit: "℃", icon: "wind", tint: .teal, gaugeRange: -40...120, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x10, name: String(localized: "吸入空気量 (MAF)"), unit: "g/s", icon: "waveform.path.ecg", tint: .indigo, gaugeRange: 0...300, fractionDigits: 1, decode: { wordAB($0).map { $0 / 100 } }),
        PIDDefinition(pid: 0x11, name: String(localized: "スロットル開度"), unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x14, name: String(localized: "O2 センサー B1S1"), unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x15, name: String(localized: "O2 センサー B1S2"), unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x16, name: String(localized: "O2 センサー B1S3"), unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x17, name: String(localized: "O2 センサー B1S4"), unit: "V", icon: "circle.hexagongrid", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x18, name: String(localized: "O2 センサー B2S1"), unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x19, name: String(localized: "O2 センサー B2S2"), unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x1A, name: String(localized: "O2 センサー B2S3"), unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x1B, name: String(localized: "O2 センサー B2S4"), unit: "V", icon: "circle.hexagongrid.fill", tint: .mint, gaugeRange: 0...1.275, fractionDigits: 3, decode: o2Voltage),
        PIDDefinition(pid: 0x1F, name: String(localized: "エンジン稼働時間"), unit: "秒", icon: "clock", tint: .gray, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
        PIDDefinition(pid: 0x21, name: String(localized: "MIL 点灯後走行距離"), unit: "km", icon: "exclamationmark.triangle", tint: .orange, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
        PIDDefinition(pid: 0x22, name: String(localized: "燃圧 (マニホールド比)"), unit: "kPa", icon: "gauge.low", tint: .orange, gaugeRange: 0...5178, fractionDigits: 1, decode: { wordAB($0).map { $0 * 0.079 } }),
        PIDDefinition(pid: 0x23, name: String(localized: "燃圧 (直噴レール)"), unit: "kPa", icon: "gauge.high", tint: .orange, gaugeRange: 0...655350, fractionDigits: 0, decode: { wordAB($0).map { $0 * 10 } }),
        PIDDefinition(pid: 0x2C, name: String(localized: "EGR 指令値"), unit: "%", icon: "arrow.triangle.2.circlepath", tint: .brown, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x2D, name: String(localized: "EGR 誤差"), unit: "%", icon: "arrow.triangle.2.circlepath", tint: .brown, gaugeRange: -100...100, fractionDigits: 1, decode: fuelTrim),
        PIDDefinition(pid: 0x2E, name: String(localized: "パージ制御"), unit: "%", icon: "aqi.medium", tint: .gray, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x2F, name: String(localized: "燃料残量"), unit: "%", icon: "fuelpump", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x31, name: String(localized: "DTC クリア後走行距離"), unit: "km", icon: "road.lanes", tint: .gray, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
        PIDDefinition(pid: 0x33, name: String(localized: "大気圧"), unit: "kPa", icon: "barometer", tint: .blue, gaugeRange: 0...255, fractionDigits: 0, decode: byteA),
        PIDDefinition(pid: 0x3C, name: String(localized: "触媒温度 B1S1"), unit: "℃", icon: "flame", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x3D, name: String(localized: "触媒温度 B2S1"), unit: "℃", icon: "flame", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x3E, name: String(localized: "触媒温度 B1S2"), unit: "℃", icon: "flame.fill", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x3F, name: String(localized: "触媒温度 B2S2"), unit: "℃", icon: "flame.fill", tint: .red, gaugeRange: -40...1200, fractionDigits: 0, decode: catalystTemp),
        PIDDefinition(pid: 0x42, name: String(localized: "ECU 電圧"), unit: "V", icon: "bolt", tint: .yellow, gaugeRange: 0...20, fractionDigits: 2, decode: { wordAB($0).map { $0 / 1000 } }),
        PIDDefinition(pid: 0x43, name: String(localized: "絶対負荷"), unit: "%", icon: "engine.combustion.badge.exclamationmark", tint: .purple, gaugeRange: 0...100, fractionDigits: 1, decode: { wordAB($0).map { $0 * 100 / 255 } }),
        PIDDefinition(pid: 0x44, name: String(localized: "目標空燃比 (λ)"), unit: "", icon: "scalemass", tint: .mint, gaugeRange: 0...2, fractionDigits: 3, decode: { wordAB($0).map { $0 / 32768 } }),
        PIDDefinition(pid: 0x45, name: String(localized: "相対スロットル"), unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x46, name: String(localized: "外気温"), unit: "℃", icon: "thermometer.sun", tint: .cyan, gaugeRange: -40...60, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x47, name: String(localized: "スロットル絶対 B"), unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x49, name: String(localized: "アクセルペダル D"), unit: "%", icon: "shoeprints.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x4A, name: String(localized: "アクセルペダル E"), unit: "%", icon: "shoeprints.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x4C, name: String(localized: "スロットル指令値"), unit: "%", icon: "pedal.accelerator", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x52, name: String(localized: "エタノール比率"), unit: "%", icon: "leaf", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x5A, name: String(localized: "相対アクセルペダル"), unit: "%", icon: "shoeprints.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 1, decode: percentA),
        PIDDefinition(pid: 0x5C, name: String(localized: "エンジン油温"), unit: "℃", icon: "oilcan", tint: .brown, gaugeRange: -40...160, fractionDigits: 0, decode: tempA),
        PIDDefinition(pid: 0x5E, name: String(localized: "燃料流量"), unit: "L/h", icon: "fuelpump.fill", tint: .green, gaugeRange: 0...100, fractionDigits: 2, decode: { wordAB($0).map { $0 / 20 } }),
        PIDDefinition(pid: 0x61, name: String(localized: "要求トルク"), unit: "%", icon: "gearshape.arrow.triangle.2.circlepath", tint: .purple, gaugeRange: -125...130, fractionDigits: 0, decode: { byteA($0).map { $0 - 125 } }),
        PIDDefinition(pid: 0x62, name: String(localized: "実トルク"), unit: "%", icon: "gearshape.2", tint: .purple, gaugeRange: -125...130, fractionDigits: 0, decode: { byteA($0).map { $0 - 125 } }),
        PIDDefinition(pid: 0x63, name: String(localized: "基準トルク"), unit: "Nm", icon: "gearshape", tint: .purple, gaugeRange: 0...65535, fractionDigits: 0, decode: wordAB),
    ]
}
