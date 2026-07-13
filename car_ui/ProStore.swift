//
//  ProStore.swift
//  car_ui
//
//  StoreKit 2 の買い切り Pro(非消費型)。広告除去・DTC 消去・CSV 無制限・
//  記録保存・F1 V10 恒久解錠をアンロックする単一プロダクト。
//

import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let proProductID = "Sena.car-ui.pro"

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    var proProduct: Product? {
        products.first { $0.id == Self.proProductID }
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
            products = try await Product.products(for: [Self.proProductID])
        } catch {
            errorMessage = "商品情報の取得に失敗しました。通信環境をご確認ください。"
        }
    }

    func purchase() async {
        guard let product = proProduct else {
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
                errorMessage = "購入は承認待ちです。承認され次第 Pro が有効になります。"
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
            if !isPro {
                errorMessage = "復元できる購入が見つかりませんでした。"
            }
        } catch {
            errorMessage = "復元に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 起動時・購入直後・復元後に呼び、現在の権利状態から isPro を再計算する。
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID && transaction.revocationDate == nil {
                active = true
            }
        }
        isPro = active
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            errorMessage = "購入の検証に失敗しました。"
            return
        }
        if transaction.productID == Self.proProductID {
            await transaction.finish()
        }
        await refreshEntitlements()
    }
}
