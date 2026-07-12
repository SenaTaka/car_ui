import GoogleMobileAds
import os
import UIKit

/// Rewarded ads for the 24-hour unlock (F1 V10 Legend preset).
///
/// If no fill has arrived when the user consents, the CALLER grants the
/// reward immediately (fail-open) — never make the user wait for an ad that
/// may not exist. The next fill is preloaded in the background for next time.
@MainActor
final class RewardedAdManager: NSObject, FullScreenContentDelegate {
    private static let log = Logger(subsystem: "Sena.car-ui", category: "ads")

    private var ad: RewardedAd?
    private var isLoading = false
    private var retryDelay: TimeInterval = 4

    /// Called just before the ad covers the screen.
    var onAdWillPresent: (() -> Void)?
    /// Called when the ad goes away, whether or not the reward was earned.
    var onAdDismissed: (() -> Void)?

    var isReady: Bool { ad != nil }

    func preload() {
        guard ad == nil, !isLoading else { return }
        isLoading = true
        RewardedAd.load(with: AdConfig.rewardedUnitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            self.isLoading = false
            guard let ad else {
                Self.log.error("rewarded load failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                let delay = self.retryDelay
                self.retryDelay = min(delay * 2, 60)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.preload()
                }
                return
            }
            ad.fullScreenContentDelegate = self
            self.ad = ad
            self.retryDelay = 4
        }
    }

    /// Present the ad; `onReward` fires only if the user earned the reward.
    /// Returns false when no fill is ready — the caller should grant the
    /// reward immediately (a no-fill, common in App Review and on brand-new
    /// units, must never make the user wait or read as a broken feature).
    @discardableResult
    func show(onReward: @escaping () -> Void) -> Bool {
        if let readyAd = ad {
            present(readyAd, onReward: onReward)
            return true
        }
        Self.log.warning("rewarded not ready at consent — caller grants without an ad")
        preload()
        return false
    }

    private func present(_ readyAd: RewardedAd, onReward: @escaping () -> Void) {
        guard let top = Self.topViewController() else { return }
        onAdWillPresent?()
        readyAd.present(from: top) {
            onReward()
        }
        ad = nil
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onAdDismissed?()
        preload()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Self.log.error("rewarded present failed: \(error.localizedDescription, privacy: .public)")
        onAdDismissed?()
        preload()
    }

    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    }

    /// The topmost presented controller — full-screen ads must be presented
    /// from here so they also work above sheets and alerts.
    static func topViewController() -> UIViewController? {
        var top = rootViewController()
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
