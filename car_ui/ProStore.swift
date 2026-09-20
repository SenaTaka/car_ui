//
//  ProStore.swift
//  car_ui
//
//  StoreKit 2 課金。Pro は年額/月額サブスク + 買い切り Lifetime の併置。
//  - Lifetime(`Sena.car_ui.pro`): 既存の非消費型を値上げ流用。更新前の購入者はそのまま Pro。
//  - 年額/月額: 自動更新サブスク。年額に 7 日間無料トライアル。
//  - 広告除去(`Sena.car_ui.adfree`): 新規販売は停止済みだが、既購入者の権利判定は継続する。
//

import Foundation
import Observation
import StoreKit

/// 現在有効なプラン(表示用)。lifetime はサブスクの有無に関わらず最優先で表示する。
enum ProPlan: String, Codable {
    case none
    case monthly
    case yearly
    case lifetime
}

/// 権利判定を StoreKit から切り離した純粋関数群(ユニットテスト対象)。
enum ProEntitlement {
    /// `entitlements` は `Transaction.currentEntitlements` を検証済み・失効(revocationDate)除外
    /// 済みで渡す前提。expirationDate が nil の商品(非消費型)は無期限として扱う。
    static func resolve(
        _ entitlements: [(productID: String, expirationDate: Date?)],
        now: Date
    ) -> (isPro: Bool, isAdFree: Bool, plan: ProPlan) {
        var hasLifetime = false
        var hasAdFree = false
        var subscriptionPlan: ProPlan = .none

        for entitlement in entitlements {
            switch entitlement.productID {
            case ProStore.lifetimeProductID:
                hasLifetime = true
            case ProStore.adFreeProductID:
                hasAdFree = true
            case ProStore.yearlyProductID:
                if isActive(expirationDate: entitlement.expirationDate, now: now) {
                    subscriptionPlan = .yearly
                }
            case ProStore.monthlyProductID:
                if isActive(expirationDate: entitlement.expirationDate, now: now),
                   subscriptionPlan != .yearly {
                    subscriptionPlan = .monthly
                }
            default:
                break
            }
        }

        let plan: ProPlan = hasLifetime ? .lifetime : subscriptionPlan
        let isPro = hasLifetime || subscriptionPlan != .none
        return (isPro, hasAdFree, plan)
    }

    private static func isActive(expirationDate: Date?, now: Date) -> Bool {
        guard let expirationDate else { return true }
        return expirationDate > now
    }
}

/// 更新前からの無料利用者は、アップデート後もエンジン音のロックを免除する(grandfather)。
/// 判定は初回起動時の一度きり。以後は再評価しない。
enum LegacyPolicy {
    static func decide(onboardingCompleted: Bool, alreadyDecided: Bool, previous: Bool) -> Bool {
        if alreadyDecided { return previous }
        return onboardingCompleted
    }
}

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let yearlyProductID = "Sena.car_ui.pro.yearly"
    static let monthlyProductID = "Sena.car_ui.pro.monthly"
    /// Lifetime。既存の非消費型 `Sena.car_ui.pro`(旧・買い切り Pro)をそのまま流用する。
    static let lifetimeProductID = "Sena.car_ui.pro"
    static let adFreeProductID = "Sena.car_ui.adfree"
    private static let allProductIDs = [yearlyProductID, monthlyProductID, lifetimeProductID, adFreeProductID]

    private static let legacyDecidedKey = "pro.legacyDecided"
    private static let legacyFreeSoundKey = "pro.legacyFreeSound"
    /// ContentView の `@AppStorage("onboarding.completed")` と同じキー。
    private static let onboardingCompletedKey = "onboarding.completed"

    private(set) var products: [Product] = []
    private(set) var isPro = false
    /// 広告除去単品の購入状態。広告非表示の判定には `removesAds` を使うこと。
    private(set) var isAdFree = false
    private(set) var activePlan: ProPlan = .none
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    /// 年額サブスクの無料トライアル対象か(`Product.SubscriptionInfo.isEligibleForIntroOffer`)。
    private(set) var isTrialEligible = false
    var errorMessage: String?

    /// 更新前からの無料利用者はエンジン音ロックを免除(grandfather)。ProStore 初期化時に一度だけ判定。
    private(set) var legacyFreeSound: Bool

    private var updatesTask: Task<Void, Never>?

    /// 広告を非表示にすべきか(Pro は広告除去を含む上位互換)。
    var removesAds: Bool {
        isPro || isAdFree
    }

    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductID }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeProductID }
    }

    var adFreeProduct: Product? {
        products.first { $0.id == Self.adFreeProductID }
    }

    /// 年額を 12 で割った「月あたり」表示(年額商品の通貨・ロケールで整形)。取得前は nil。
    var yearlyPricePerMonthText: String? {
        guard let product = yearlyProduct else { return nil }
        let perMonth = product.price / 12
        return product.priceFormatStyle.format(perMonth)
    }

    private init() {
        legacyFreeSound = Self.evaluateLegacyFreeSound(defaults: .standard)

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    /// 初回起動時に一度だけ grandfather を判定し、以後は再評価しないよう UserDefaults に確定値を書く。
    private static func evaluateLegacyFreeSound(defaults: UserDefaults) -> Bool {
        let alreadyDecided = defaults.bool(forKey: legacyDecidedKey)
        let previous = defaults.bool(forKey: legacyFreeSoundKey)
        let onboardingCompleted = defaults.bool(forKey: onboardingCompletedKey)
        let decided = LegacyPolicy.decide(
            onboardingCompleted: onboardingCompleted,
            alreadyDecided: alreadyDecided,
            previous: previous)
        if !alreadyDecided {
            defaults.set(true, forKey: legacyDecidedKey)
            defaults.set(decided, forKey: legacyFreeSoundKey)
        }
        return decided
    }

    /// 商品情報のロード(価格表示用)。失敗してもクラッシュはさせない。
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: Self.allProductIDs)
        } catch {
            errorMessage = "商品情報の取得に失敗しました。通信環境をご確認ください。"
        }
    }

    /// 年額のトライアル対象判定は非同期 API のため、商品ロード後に別途更新する。
    func refreshTrialEligibility() async {
        guard let subscription = yearlyProduct?.subscription else {
            isTrialEligible = false
            return
        }
        isTrialEligible = await subscription.isEligibleForIntroOffer
    }

    func purchase(plan: ProPlan) async {
        let productID: String
        switch plan {
        case .yearly: productID = Self.yearlyProductID
        case .monthly: productID = Self.monthlyProductID
        case .lifetime: productID = Self.lifetimeProductID
        case .none: return
        }
        await purchase(productID: productID)
    }

    private func purchase(productID: String) async {
        guard let product = products.first(where: { $0.id == productID }) else {
            errorMessage = "商品情報がまだ読み込まれていません。もう一度お試しください。"
            await loadProducts()
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .userCancelled:
                break
            case .pending:
                errorMessage = "購入は承認待ちです。承認され次第有効になります。"
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro && !isAdFree {
                errorMessage = "復元できる購入が見つかりませんでした。"
            }
        } catch {
            errorMessage = "復元に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 起動時・購入直後・復元後に呼び、現在の権利状態から購入フラグを再計算する。
    func refreshEntitlements() async {
        var entitlements: [(productID: String, expirationDate: Date?)] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            entitlements.append((transaction.productID, transaction.expirationDate))
        }
        let resolved = ProEntitlement.resolve(entitlements, now: Date())
        isPro = resolved.isPro
        isAdFree = resolved.isAdFree
        activePlan = resolved.plan
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            errorMessage = "購入の検証に失敗しました。"
            return
        }
        if Self.allProductIDs.contains(transaction.productID) {
            await transaction.finish()
        }
        await refreshEntitlements()
    }
}
