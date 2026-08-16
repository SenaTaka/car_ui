//
//  VehicleProfile.swift
//  car_ui
//
//  車両プロファイル(レッドライン・最高回転・燃料種別)。
//
//  背景: 2026-08-17 の UX 監査 A-3/B-5。
//  - タコメーターの上限 8000 / レッドライン 6000 rpm がダッシュボードと HUD に
//    ハードコードされており、ディーゼルや軽自動車では針が半分も動かなかった。
//    (皮肉なことにサウンドタブのゲージだけはプリセットの redline を見ていた)
//  - 燃費が全車ガソリン前提(AFR 14.7・密度 740 g/L)で、ディーゼル車では
//    MAF からの推定値が実態とずれていた。
//

import Foundation
import Observation
import SwiftUI

/// 燃料種別。MAF から燃料流量を推定するときの定数を持つ。
enum FuelType: String, CaseIterable, Identifiable {
    case gasoline
    case diesel

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .gasoline: return "ガソリン"
        case .diesel: return "ディーゼル"
        }
    }

    /// 理論空燃比
    var stoichiometricAFR: Double {
        switch self {
        case .gasoline: return 14.7
        case .diesel: return 14.5
        }
    }

    /// 燃料密度 g/L
    var densityGPerL: Double {
        switch self {
        case .gasoline: return 740
        case .diesel: return 835
        }
    }
}

/// 車両プロファイルの保持。`@Observable` なので body 内で参照した View は
/// 設定変更時に自動で再描画される。
@Observable
final class VehicleProfile {
    static let shared = VehicleProfile()

    private enum Key {
        static let redline = "vehicle.redlineRpm"
        static let maxRpm = "vehicle.maxRpm"
        static let fuel = "vehicle.fuelType"
    }

    /// タコメーターの目盛り上限
    var maxRpm: Double {
        didSet {
            guard maxRpm != oldValue else { return }
            UserDefaults.standard.set(maxRpm, forKey: Key.maxRpm)
        }
    }

    /// これを超えたら赤で警告する回転数
    var redlineRpm: Double {
        didSet {
            guard redlineRpm != oldValue else { return }
            UserDefaults.standard.set(redlineRpm, forKey: Key.redline)
        }
    }

    var fuelType: FuelType {
        didSet {
            guard fuelType != oldValue else { return }
            UserDefaults.standard.set(fuelType.rawValue, forKey: Key.fuel)
        }
    }

    /// 選べる上限値(一般的な乗用車・ディーゼル・高回転型をカバーする)
    static let selectableMaxRpm: [Double] = [5000, 6000, 7000, 8000, 9000, 10000]

    private init() {
        let defaults = UserDefaults.standard
        let storedMax = defaults.double(forKey: Key.maxRpm)
        let storedRedline = defaults.double(forKey: Key.redline)
        maxRpm = storedMax > 0 ? storedMax : 8000
        redlineRpm = storedRedline > 0 ? storedRedline : 6500
        fuelType = FuelType(rawValue: defaults.string(forKey: Key.fuel) ?? "") ?? .gasoline
    }

    /// レッドラインは上限を超えられない(超えると赤帯が描画されない)
    func clampRedline() {
        if redlineRpm > maxRpm { redlineRpm = maxRpm }
    }

    /// 指定回転数がレッドライン以上か(ゲージの色分けに使う)
    func isOverRedline(_ rpm: Double) -> Bool { rpm >= redlineRpm }

    /// 0...maxRpm に正規化した進捗(ゲージの塗り量)
    func progress(_ rpm: Double) -> Double {
        guard maxRpm > 0 else { return 0 }
        return min(max(rpm / maxRpm, 0), 1)
    }
}
