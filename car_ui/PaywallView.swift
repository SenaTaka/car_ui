//
//  PaywallView.swift
//  car_ui
//
//  プラン提案ペイウォール。無料 / 広告除去(¥300)/ Pro(¥730)の3列比較で
//  価値を提示し、購入 / 復元を行う。買い切り・サブスクなしを全面に。
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss

    private struct BenefitRow: Identifiable {
        let name: String
        let detail: String
        let inAdFree: Bool

        var id: String { name }
    }

    private let benefits: [BenefitRow] = [
        BenefitRow(name: "広告なし", detail: "全タブのバナー広告を非表示", inAdFree: true),
        // 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化したため特典から除外
        // BenefitRow(name: "DTC 消去", detail: "故障コードをワンタップで消去", inAdFree: false),
        BenefitRow(name: "CSV 無制限", detail: "横持ち/縦持ちエクスポートを制限なく", inAdFree: false),
        BenefitRow(name: "記録の保存", detail: "0-100 加速・G フォースの記録を保存", inAdFree: false)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    comparisonTable
                    purchaseSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("プラン")
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

            Text("買い切り、一回だけ。")
                .font(.title2.weight(.bold))

            Text("サブスクはありません。一度買えばずっと使えます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 無料 / 広告除去 / Pro の比較表

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // ヘッダ行
            HStack(spacing: 0) {
                Text("機能")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                planHeader("無料", price: nil, highlighted: false)
                planHeader("広告除去", price: proStore.adFreeProduct?.displayPrice, highlighted: false)
                planHeader("Pro", price: proStore.proProduct?.displayPrice, highlighted: true)
            }
            .padding(.vertical, 10)

            Divider()

            ForEach(benefits) { benefit in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(benefit.name)
                            .font(.subheadline.weight(.semibold))
                        Text(benefit.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    checkCell(false, highlighted: false)
                    checkCell(benefit.inAdFree, highlighted: false)
                    checkCell(true, highlighted: true)
                }
                .padding(.vertical, 10)

                if benefit.id != benefits.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Text("おすすめ")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.indigo, in: Capsule())
                .foregroundStyle(.white)
                .offset(x: -8, y: -10)
        }
    }

    private func planHeader(_ name: String, price: String?, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption.weight(highlighted ? .bold : .semibold))
                .foregroundStyle(highlighted ? .indigo : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(price ?? (name == "無料" ? "¥0" : "—"))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(highlighted ? .indigo : .secondary)
        }
        .frame(width: 64)
    }

    private func checkCell(_ included: Bool, highlighted: Bool) -> some View {
        Image(systemName: included ? "checkmark.circle.fill" : "minus")
            .font(.subheadline)
            .foregroundStyle(included ? (highlighted ? .indigo : .green) : Color(.systemFill))
            .frame(width: 64)
    }

    // MARK: - 購入

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
                    VStack(spacing: 1) {
                        Text(purchaseButtonTitle)
                            .font(.headline)
                        Text("全機能・買い切り")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
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

            Text("お支払いは一度だけ。自動更新や定期課金は一切ありません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
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
