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
    static let bannerUnitID = "ca-app-pub-3848493291218445/2711542365"
}

private enum AdLoadState: Equatable {
    case pending  // load() 発行済み・結果待ち — レイアウトスペースは確保しておく
    case loaded
    case failed
}

/// Bottom banner slot: a standard 320x50 AdMob banner.
/// `load()` 呼び出し時点で高さが 0 だと SDK が "Invalid ad width or height" で
/// クライアント側失敗するため、結果が判明するまでは 50pt を確保しておく。
/// 失敗が確定した場合のみ高さ 0 に畳んで空白帯を消す。
struct AdBannerView: View {
    @State private var state: AdLoadState = .pending

    var body: some View {
        // 起動引数 -uiFakeBanner: 広告ロードに依存せずバナー込みレイアウトを検証する
        // シミュレータ用フック(本番挙動には影響しない)
        if ProcessInfo.processInfo.arguments.contains("-uiFakeBanner") {
            Color.orange.frame(maxWidth: .infinity).frame(height: 50)
        } else if AdConsentManager.shared.canShowAds {
            // 監査 REL-007: UMP 同意が確定(canRequestAds)するまで広告をリクエストしない
            BannerAdRepresentable(state: $state)
                .frame(maxWidth: .infinity)
                .frame(height: state == .failed ? 0 : 50)
                .clipped()
                .background(Color(.systemBackground))
        }
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    @Binding var state: AdLoadState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state)
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
        @Binding var state: AdLoadState

        init(state: Binding<AdLoadState>) {
            _state = state
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            state = .loaded
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            state = .failed
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
