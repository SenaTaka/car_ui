//
//  PaywallView.swift
//  car_ui
//
//  Pro(買い切り)ペイウォール。広告除去・DTC 消去・CSV 無制限・記録保存の
//  価値を提示し、購入 / 復元を行う。
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    benefitsList
                    purchaseSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("car_ui Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                await proStore.loadProducts()
            }
            .onChange(of: proStore.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .onChange(of: proStore.isAdFree) { _, isAdFree in
                if isAdFree { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("car_ui Pro")
                .font(.title2.weight(.bold))

            Text("買い切り一回払い。サブスクなし・広告なしで全機能を使えます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            benefitRow(icon: "rectangle.slash", title: "広告除去", detail: "全タブのバナー広告を非表示")
            benefitRow(icon: "stethoscope", title: "DTC 消去", detail: "故障コードをワンタップで消去")
            benefitRow(icon: "square.and.arrow.up", title: "CSV ログ無制限", detail: "記録データを制限なくエクスポート")
            benefitRow(icon: "internaldrive", title: "記録の保存", detail: "0-100 加速・G フォースの記録を保存")
        }
        .panelStyle()
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if let errorMessage = proStore.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await proStore.purchase() }
            } label: {
                HStack(spacing: 8) {
                    if proStore.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(purchaseButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .foregroundStyle(.white)
            .disabled(proStore.isPurchasing || proStore.proProduct == nil)

            // 広告だけ消したい人向けの単品(Pro は広告除去を含む上位互換)
            if !proStore.isAdFree {
                Button {
                    Task { await proStore.purchaseAdFree() }
                } label: {
                    Text(adFreeButtonTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(proStore.isPurchasing || proStore.adFreeProduct == nil)

                Text("広告除去のみの買い切りです。DTC 消去などの Pro 機能は含みません。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text("広告除去は購入済みです。Pro にすると残りの機能も使えます。")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button("購入を復元") {
                Task { await proStore.restore() }
            }
            .font(.subheadline.weight(.semibold))
            .disabled(proStore.isPurchasing)
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseButtonTitle: String {
        if let product = proStore.proProduct {
            return "\(product.displayPrice) で Pro を購入"
        }
        return proStore.isLoadingProducts ? "読み込み中…" : "Pro を購入"
    }

    private var adFreeButtonTitle: String {
        if let product = proStore.adFreeProduct {
            return "広告除去のみ \(product.displayPrice)"
        }
        return proStore.isLoadingProducts ? "読み込み中…" : "広告除去のみ"
    }
}

#Preview {
    PaywallView()
        .environment(ProStore.shared)
}
