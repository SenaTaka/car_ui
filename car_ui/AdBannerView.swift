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

/// Bottom banner slot: a standard 320x50 AdMob banner.
/// 広告がロードされるまでは高さ 0 に畳む(未ロード時にタブバーの下へ
/// 白い空白帯が出るのを防ぐ)。ロード完了時のみ 50pt を確保する。
struct AdBannerView: View {
    @State private var isLoaded = false

    var body: some View {
        // 起動引数 -uiFakeBanner: 広告ロードに依存せずバナー込みレイアウトを検証する
        // シミュレータ用フック(本番挙動には影響しない)
        if ProcessInfo.processInfo.arguments.contains("-uiFakeBanner") {
            Color.orange.frame(maxWidth: .infinity).frame(height: 50)
        } else if AdConsentManager.shared.canShowAds {
            // 監査 REL-007: UMP 同意が確定(canRequestAds)するまで広告をリクエストしない
            BannerAdRepresentable(isLoaded: $isLoaded)
                .frame(maxWidth: .infinity)
                .frame(height: isLoaded ? 50 : 0)
                .clipped()
                .background(Color(.systemBackground))
        }
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    @Binding var isLoaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var isLoaded: Bool

        init(isLoaded: Binding<Bool>) {
            _isLoaded = isLoaded
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            isLoaded = true
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            isLoaded = false
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AdBannerView()
            .padding()
    }
}
