import Foundation
import Observation

/// 24-hour unlocks earned by watching rewarded ads. Expiry timestamps live in
/// UserDefaults so an unlock survives relaunches but quietly lapses a day
/// later — watch another ad to renew.
@MainActor
@Observable
final class RewardStore {
    enum Item: String, CaseIterable, Identifiable {
        case f1Engine = "reward.f1v10"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .f1Engine: return String(localized: "F1 V10 Legend")
            }
        }
    }

    static let unlockDuration: TimeInterval = 24 * 60 * 60

    private var expiries: [Item: Date] = [:]

    init() {
        for item in Item.allCases {
            if let date = UserDefaults.standard.object(forKey: item.rawValue) as? Date {
                expiries[item] = date
            }
        }
    }

    func isUnlocked(_ item: Item) -> Bool {
        guard let expiry = expiries[item] else { return false }
        return expiry > Date()
    }

    /// Whole hours left on the unlock (rounded up), nil when locked.
    func remainingHours(_ item: Item) -> Int? {
        guard let expiry = expiries[item], expiry > Date() else { return nil }
        return max(1, Int((expiry.timeIntervalSinceNow / 3600).rounded(.up)))
    }

    func unlock(_ item: Item) {
        let expiry = Date().addingTimeInterval(Self.unlockDuration)
        expiries[item] = expiry
        UserDefaults.standard.set(expiry, forKey: item.rawValue)
    }
}
