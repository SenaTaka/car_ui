//
//  AdConsentManager.swift
//  car_ui
//
//  Google UMP による広告同意管理(監査 REL-007 対応)。
//  起動ごとに同意情報を更新し、必要な同意フォームを表示する。
//  同意状態が確定して canRequestAds が true になるまで
//  Mobile Ads SDK を開始せず、バナーもリクエストしない。
//

import GoogleMobileAds
import Observation
import UserMessagingPlatform

@MainActor
@Observable
final class AdConsentManager {
    static let shared = AdConsentManager()

    /// 同意状態が確定し、広告をリクエストしてよいか
    private(set) var canShowAds = false
    /// プライバシーオプション(同意の再設定)入口を表示すべきか
    private(set) var isPrivacyOptionsRequired = false

    private var adsStarted = false

    private init() {}

    /// 起動ごとに呼ぶ。同意情報を更新し、必要なら同意フォームを表示する。
    func gatherConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // 更新・表示に失敗しても、キャッシュ済みの canRequestAds が有効ならそれに従う
        }
        refreshState()
    }

    /// アプリ内からの同意再設定(UMP プライバシーオプションフォーム)
    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            // フォームを表示できない場合は状態だけ更新する
        }
        refreshState()
    }

    private func refreshState() {
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        if ConsentInformation.shared.canRequestAds {
            startAdsIfNeeded()
        } else {
            canShowAds = false
        }
    }

    private func startAdsIfNeeded() {
        if !adsStarted {
            adsStarted = true
            MobileAds.shared.start()
        }
        canShowAds = true
    }
}
