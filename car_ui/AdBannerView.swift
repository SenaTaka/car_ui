import GoogleMobileAds
import SwiftUI
import UIKit

/// AdMob configuration for the free, ad-supported model.
///
/// Simulators always receive test ads; register any physical development
/// device as a test device in AdMob before tapping ads.
enum AdConfig {
    // TODO: car_ui 用の本番ユニット ID に差し替える(現在は Google 公式テスト ID)。
    // Info.plist の GADApplicationIdentifier も併せて差し替えること。

    /// Banner unit (bottom, shared across all tabs).
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    /// Rewarded unit — 24 h unlock (F1 V10 Legend).
    static let rewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
}

/// Bottom banner slot: a standard 320x50 AdMob banner with a fixed frame so
/// the layout never shifts whether an ad has loaded or not.
struct AdBannerView: View {
    var body: some View {
        BannerAdRepresentable()
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.systemBackground))
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AdBannerView()
            .padding()
    }
}
