//
//  ProStore.swift
//  car_ui
//
//  StoreKit 2 の買い切り課金(非消費型 2 商品)。
//  - Pro: 広告除去・DTC 消去・CSV 無制限・記録保存をまとめてアンロック
//  - 広告除去: 広告非表示のみの安価な単品(Pro は上位互換)
//

import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let proProductID = "Sena.car_ui.pro"
    static let adFreeProductID = "Sena.car_ui.adfree"
    private static let allProductIDs = [proProductID, adFreeProductID]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    /// 広告除去単品の購入状態。広告非表示の判定には `removesAds` を使うこと。
    private(set) var isAdFree = false
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    /// 広告を非表示にすべきか(Pro は広告除去を含む上位互換)。
    var removesAds: Bool {
        isPro || isAdFree
    }

    var proProduct: Product? {
        products.first { $0.id == Self.proProductID }
    }

    var adFreeProduct: Product? {
        products.first { $0.id == Self.adFreeProductID }
    }

    private init() {
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

    func purchase() async {
        await purchase(productID: Self.proProductID)
    }

    func purchaseAdFree() async {
        await purchase(productID: Self.adFreeProductID)
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
        var proActive = false
        var adFreeActive = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.proProductID:
                proActive = true
            case Self.adFreeProductID:
                adFreeActive = true
            default:
                break
            }
        }
        isPro = proActive
        isAdFree = adFreeActive
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
