//
//  Units.swift
//  car_ui
//
//  単位系(メートル法 / ヤード・ポンド法)とロケール対応の数値表示。
//
//  背景: 2026-08-17 の UX 監査 A-1/A-2。単位が PIDCatalog に "km/h" などの
//  生文字列で直書きされ変換層が無かったため、US・UK のユーザーはメーターも
//  HUD も数字が読めなかった(DL の最大市場が US)。数値も String(format:) 固定で
//  独仏西の小数点(,)に追従していなかった。
//
//  方針: PID カタログが持つ値は常に**メートル法が正**(canonical)。変換は表示の
//  直前だけで行い、記録・チャート・しきい値判定は canonical 値のまま扱う。
//

import Foundation
import Observation
import SwiftUI

// MARK: - 単位系

/// 解決済みの単位系(表示に使う実体)
enum ResolvedUnitSystem {
    case metric
    case imperial
}

/// ユーザー設定としての単位系。`.automatic` は端末のロケールから解決する。
enum UnitSystemPreference: String, CaseIterable, Identifiable {
    case automatic
    case metric
    case imperial

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .automatic: return "自動(地域に合わせる)"
        case .metric: return "メートル法 (km/h・°C)"
        case .imperial: return "ヤード・ポンド法 (mph・°F)"
        }
    }

    /// 端末ロケールから解決する。US / LR / MM は華氏・マイル圏。
    var resolved: ResolvedUnitSystem {
        switch self {
        case .metric: return .metric
        case .imperial: return .imperial
        case .automatic:
            return Locale.current.measurementSystem == .metric ? .metric : .imperial
        }
    }
}

/// 単位設定の保持。`@Observable` なので、body 内でこの値を読んだ View は
/// 設定変更時に自動で再描画される(表示ヘルパ経由の間接参照でも追跡される)。
@Observable
final class UnitSettings {
    static let shared = UnitSettings()

    private static let storageKey = "units.systemPreference"

    var preference: UnitSystemPreference {
        didSet {
            guard preference != oldValue else { return }
            UserDefaults.standard.set(preference.rawValue, forKey: Self.storageKey)
        }
    }

    /// 表示に使う単位系
    var system: ResolvedUnitSystem { preference.resolved }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        preference = UnitSystemPreference(rawValue: raw) ?? .automatic
    }
}

// MARK: - 物理量の種別

/// 物理量の種別。表示単位と換算式はここから導出する。
/// canonical(内部保持)は常にメートル法側の単位。
enum UnitKind {
    case speed          // canonical: km/h
    case temperature    // canonical: ℃
    case pressure       // canonical: kPa
    case distance       // canonical: km
    case massFlow       // canonical: g/s
    case volumeFlow     // canonical: L/h
    case volume         // canonical: L
    case fuelEconomy    // canonical: km/L
    case torque         // canonical: Nm
    case length         // canonical: m
    case voltage
    case percent
    case angle
    case rpm
    case duration
    case gForce
    case dimensionless

    /// カタログが持つ canonical 単位文字列から種別を決める。
    /// PIDDefinition と ChannelInfo の双方がここを通る(対応表は 1 箇所だけ)。
    init(canonicalSymbol: String) {
        switch canonicalSymbol {
        case "km/h": self = .speed
        case "℃", "°C": self = .temperature
        case "kPa": self = .pressure
        case "km": self = .distance
        case "m": self = .length
        case "g/s": self = .massFlow
        case "L/h": self = .volumeFlow
        case "L": self = .volume
        case "km/L": self = .fuelEconomy
        case "Nm": self = .torque
        case "V": self = .voltage
        case "%": self = .percent
        case "°": self = .angle
        case "rpm": self = .rpm
        case "秒": self = .duration
        case "G": self = .gForce
        default: self = .dimensionless
        }
    }

    /// 表示に使う単位記号。単位記号は慣例的に翻訳しない(kPa・V・rpm と同じ扱い)。
    func symbol(_ system: ResolvedUnitSystem) -> String {
        switch self {
        case .speed:        return system == .metric ? "km/h" : "mph"
        case .temperature:  return system == .metric ? "°C" : "°F"
        case .pressure:     return system == .metric ? "kPa" : "psi"
        case .distance:     return system == .metric ? "km" : "mi"
        case .volumeFlow:   return system == .metric ? "L/h" : "gal/h"
        case .volume:       return system == .metric ? "L" : "gal"
        case .fuelEconomy:  return system == .metric ? "km/L" : "mpg"
        case .torque:       return system == .metric ? "Nm" : "lb·ft"
        case .length:       return system == .metric ? "m" : "ft"
        // 吸入空気量は OBD ツールの慣例として両単位系とも g/s を使う
        case .massFlow:     return "g/s"
        case .voltage:      return "V"
        case .percent:      return "%"
        case .angle:        return "°"
        case .rpm:          return "rpm"
        case .duration:     return "s"
        case .gForce:       return "G"
        case .dimensionless: return ""
        }
    }

    /// canonical 値を表示単位へ換算する
    func convert(_ value: Double, to system: ResolvedUnitSystem) -> Double {
        guard system == .imperial else { return value }
        switch self {
        case .speed, .distance: return value * 0.621_371_192_2   // km → mi
        case .temperature:      return value * 9 / 5 + 32        // ℃ → ℉
        case .pressure:         return value * 0.145_037_737_7   // kPa → psi
        case .volumeFlow, .volume: return value * 0.264_172_052_4 // L → US gal
        case .fuelEconomy:      return value * 2.352_145_833     // km/L → mpg (US)
        case .torque:           return value * 0.737_562_149_3   // Nm → lb·ft
        case .length:           return value * 3.280_839_895     // m → ft
        case .massFlow, .voltage, .percent, .angle, .rpm, .duration, .gForce, .dimensionless:
            return value
        }
    }

    /// 表示単位の値を canonical へ戻す。ユーザーが表示単位で入力する箇所
    /// (手動レンジのステッパー等)で、保存値を canonical に保つために使う。
    func convertBack(_ displayValue: Double, from system: ResolvedUnitSystem) -> Double {
        guard system == .imperial else { return displayValue }
        if case .temperature = self { return (displayValue - 32) * 5 / 9 }
        // それ以外は比例換算なので、1 単位ぶんの係数で割り戻せる
        let factor = convert(1, to: system)
        guard factor != 0 else { return displayValue }
        return displayValue / factor
    }

    /// ゲージの範囲を表示単位へ換算する(いずれの換算も単調なので端点変換でよい)
    func convert(_ range: ClosedRange<Double>, to system: ResolvedUnitSystem) -> ClosedRange<Double> {
        let lower = convert(range.lowerBound, to: system)
        let upper = convert(range.upperBound, to: system)
        return min(lower, upper)...max(lower, upper)
    }

    /// 換算で有効桁が変わる量だけ小数桁を補正する
    /// (例: 100 kPa = 14.5 psi。0 桁のままだと分解能が落ちすぎる)
    func fractionDigits(base: Int, in system: ResolvedUnitSystem) -> Int {
        guard system == .imperial else { return base }
        switch self {
        case .pressure: return base + 1
        default: return base
        }
    }
}

// MARK: - ロケール対応の数値フォーマット

/// 小数桁を指定してロケールの小数点・記号で整形する。
/// `String(format:)` は POSIX 固定で独仏西の `,` に追従しないため、その置き換え。
/// 桁区切りは付けない(従来の見た目と桁幅を維持するため)。
func formatNumber(_ value: Double, digits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
}

/// 欠損値は "--"。数値はロケール対応で整形する。
func metricText(_ value: Double?, digits: Int) -> String {
    guard let value else { return "--" }
    return formatNumber(value, digits: digits)
}

/// 「0-100 km/h」のような速度のしきい値を表示単位で書く(例: 0-62 mph)。
/// 計測そのものは canonical(km/h)のまま行い、表記だけを合わせる。
func speedTargetText(_ kph: Int, system: ResolvedUnitSystem = UnitSettings.shared.system) -> String {
    let converted = UnitKind.speed.convert(Double(kph), to: system)
    return "\(Int(converted.rounded())) \(UnitKind.speed.symbol(system))"
}

/// canonical 値を「換算 → 整形」までまとめて行う。
func unitText(_ value: Double?, kind: UnitKind, digits: Int,
              system: ResolvedUnitSystem = UnitSettings.shared.system) -> String {
    guard let value else { return "--" }
    return formatNumber(kind.convert(value, to: system),
                        digits: kind.fractionDigits(base: digits, in: system))
}

// MARK: - カタログへの橋渡し

/// canonical 単位文字列と小数桁を持つカタログ型に、表示用の換算を生やすための共通処理。
/// PIDDefinition と ChannelInfo が準拠する。
protocol UnitConvertible {
    /// canonical(メートル法)の単位記号
    var unit: String { get }
    /// canonical での小数桁
    var fractionDigits: Int { get }
}

extension UnitConvertible {
    var kind: UnitKind { UnitKind(canonicalSymbol: unit) }

    /// 現在の単位系での表示単位
    var displayUnit: String { kind.symbol(UnitSettings.shared.system) }

    /// 現在の単位系での小数桁
    var displayDigits: Int {
        kind.fractionDigits(base: fractionDigits, in: UnitSettings.shared.system)
    }

    /// 現在の単位系へ換算した値
    func displayValue(_ value: Double?) -> Double? {
        value.map { kind.convert($0, to: UnitSettings.shared.system) }
    }

    /// 換算+整形済みの表示文字列(欠損は "--")
    func displayText(_ value: Double?) -> String {
        unitText(value, kind: kind, digits: fractionDigits)
    }

    /// 指定の単位系での表示単位(CSV 書き出しなど、設定と切り離して指定したい場合)
    func displayUnit(in system: ResolvedUnitSystem) -> String { kind.symbol(system) }
}

extension PIDDefinition: UnitConvertible {
    /// 現在の単位系へ換算したゲージ範囲
    var displayRange: ClosedRange<Double> {
        kind.convert(gaugeRange, to: UnitSettings.shared.system)
    }
}

extension ChannelInfo: UnitConvertible {}
