import GoogleMobileAds
import SwiftUI
import UIKit

/// AdMob configuration for the free, ad-supported model.
///
/// PRODUCTION identifiers (paired with GADApplicationIdentifier in the
/// root Info.plist). Simulators always receive test ads; register any
/// physical development device as a test device in AdMob before tapping ads.
enum AdConfig {
    /// Production banner unit (bottom, shared across all tabs).
    static let bannerUnitID = "ca-app-pub-3848493291218445/1160611372"
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
