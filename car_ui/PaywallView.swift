//
//  PaywallView.swift
//  car_ui
//
//  Pro プラン提案(年額サブスク既定・7日間無料トライアル/月額/買い切り Lifetime)。
//  Guideline 3.1.2 準拠: 価格・期間・自動更新の明記、EULA・プライバシーポリシー・復元を必ず出す。
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: ProPlan = .yearly
    // 復元中/成功/対象なしを一定時間視認できるようにするための一時状態
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    /// プライバシーポリシーの正本 URL。CLAUDE.md/store 配下にアプリ内既存の記載が見つからなかったため
    /// 会社サイトの想定パスを暫定使用(指揮官側で正しい URL に要確認)。
    private static let privacyPolicyURL = URL(string: "https://takasawadynamics.com/apps/obd2-scanner/privacy")!
    private static let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private struct ValueProp: Identifiable {
        let icon: String
        let text: Text
        var id: String { icon }
    }

    private var valueProps: [ValueProp] {
        [
            ValueProp(icon: "engine.combustion.fill", text: Text("全エンジン音 + 追加音")),
            ValueProp(icon: "clock.arrow.circlepath", text: Text("ドライブ履歴と記録")),
            ValueProp(icon: "checkmark.seal.fill", text: Text("広告なし・CSV 無制限"))
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    valuePropList
                    planCards
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
                await proStore.refreshTrialEligibility()
                if proStore.yearlyProduct == nil, proStore.lifetimeProduct != nil {
                    selectedPlan = .lifetime
                }
            }
            .onChange(of: proStore.isPro) { _, isPro in
                // 復元中は performRestore() 側で確認表示後にまとめて dismiss する
                if isPro && !isRestoring { dismiss() }
            }
        }
    }

    // MARK: - 見出し・価値訴求

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("Pro で、全部のエンジンを自分の車で")
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valuePropList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(valueProps) { prop in
                HStack(spacing: 10) {
                    Image(systemName: prop.icon)
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                        .frame(width: 22)
                    prop.text
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - プラン 3 択

    private var planCards: some View {
        VStack(spacing: 10) {
            planCard(
                plan: .yearly,
                title: Text("年額"),
                price: proStore.yearlyProduct?.displayPrice,
                subtitle: perMonthSubtitle,
                badgeText: proStore.isTrialEligible ? Text("7 日間無料") : nil
            )
            planCard(
                plan: .monthly,
                title: Text("月額"),
                price: proStore.monthlyProduct?.displayPrice,
                subtitle: nil,
                badgeText: nil
            )
            planCard(
                plan: .lifetime,
                title: Text("買い切り"),
                price: proStore.lifetimeProduct?.displayPrice,
                subtitle: Text("一度だけ支払い、ずっと使える"),
                badgeText: nil
            )
        }
    }

    private var perMonthSubtitle: Text? {
        guard let perMonthText = proStore.yearlyPricePerMonthText else { return nil }
        return Text("月あたり ") + Text(perMonthText)
    }

    private func planCard(plan: ProPlan, title: Text, price: String?, subtitle: Text?, badgeText: Text?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .indigo : Color(.systemFill))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        title
                            .font(.headline)
                        if let badgeText {
                            badgeText
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.orange, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    if let subtitle {
                        subtitle
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(price ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .indigo : .primary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.indigo : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 購入・脚注

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if let errorMessage = proStore.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await proStore.purchase(plan: selectedPlan) }
            } label: {
                HStack(spacing: 8) {
                    if proStore.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    ctaLabel
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .foregroundStyle(.white)
            .disabled(proStore.isPurchasing || selectedProduct == nil)

            VStack(spacing: 4) {
                Button("購入を復元") {
                    Task { await performRestore() }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(proStore.isPurchasing)

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            legalFooter
        }
        .frame(maxWidth: .infinity)
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("価格・期間は選択したプランにより異なります。サブスクリプションは期間終了の 24 時間前までに解約しない限り自動更新されます。設定 > Apple ID > サブスクリプションから管理・解約できます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Link("利用規約", destination: Self.eulaURL)
                Link("プライバシーポリシー", destination: Self.privacyPolicyURL)
            }
            .font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .yearly: return proStore.yearlyProduct
        case .monthly: return proStore.monthlyProduct
        case .lifetime: return proStore.lifetimeProduct
        case .none: return nil
        }
    }

    private var ctaLabel: Text {
        switch selectedPlan {
        case .yearly:
            if proStore.isTrialEligible {
                return Text("無料で 7 日間試す")
            } else if let product = proStore.yearlyProduct {
                return Text(product.displayPrice) + Text("/年で始める")
            }
            return Text("年額プランで始める")
        case .monthly:
            if let product = proStore.monthlyProduct {
                return Text(product.displayPrice) + Text("/月で始める")
            }
            return Text("月額プランで始める")
        case .lifetime:
            if let product = proStore.lifetimeProduct {
                return Text(product.displayPrice) + Text(" で買い切る")
            }
            return Text("買い切りで購入")
        case .none:
            return Text("購入する")
        }
    }

    /// 復元中/成功/対象なしの3状態を最低 0.8 秒視認できる形で表示してから dismiss する。
    private func performRestore() async {
        isRestoring = true
        restoreMessage = "復元中…"
        await proStore.restore()
        let succeeded = proStore.isPro || proStore.isAdFree
        restoreMessage = succeeded ? "購入を復元しました" : "復元できる購入が見つかりませんでした"
        try? await Task.sleep(nanoseconds: 800_000_000)
        isRestoring = false
        restoreMessage = nil
        if proStore.isPro {
            dismiss()
        }
    }
}

#Preview {
    PaywallView()
        .environment(ProStore.shared)
}
