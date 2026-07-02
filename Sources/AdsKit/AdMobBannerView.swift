// concurrency-exception: SDK の Sendable 未準拠に対する @preconcurrency import (AdsKit 内部限定)。
@preconcurrency import GoogleMobileAds
import DesignSystem
import Domain
import SwiftUI
import UIKit

// バナースロット (Presentation) に注入される実バナー。
// ロード前はプレースホルダを表示し、ロード完了時にフレーム内でクロスフェードする
// (スロット側が高さを予約しているためレイアウトは一切動かない)。
struct GameplayBannerContainer: View {
    let placement: AdPlacementID
    @State private var adUnitID: String?
    @State private var isLoaded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignRadius.medium.rawValue, style: .continuous)
                .fill(DesignColor.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignRadius.medium.rawValue, style: .continuous)
                        .strokeBorder(DesignColor.border, lineWidth: 1)
                }
            if let adUnitID {
                GeometryReader { proxy in
                    AdMobBannerView(
                        adUnitID: adUnitID,
                        width: proxy.size.width,
                        isLoaded: $isLoaded
                    )
                }
                .opacity(isLoaded ? 1 : 0)
            }
        }
        .animation(DesignAnimation.adFade, value: isLoaded)
        .task {
            adUnitID = await AdUnitIDResolver.resolve().adUnitID(for: placement)
        }
    }
}

private struct AdMobBannerView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    @Binding var isLoaded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let banner = BannerView()
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        context.coordinator.banner = banner
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.loadIfNeeded(width: width)
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        var banner: BannerView?
        private var isLoaded: Binding<Bool>
        private var loadedWidth: CGFloat = 0

        init(isLoaded: Binding<Bool>) {
            self.isLoaded = isLoaded
        }

        func loadIfNeeded(width: CGFloat) {
            guard let banner, width > 0, abs(width - loadedWidth) > 1 else {
                return
            }
            loadedWidth = width
            // 予約高さ (DesignAdMetrics.bannerReservedHeight) を超えないよう
            // maxHeight 付きのインラインアダプティブサイズを使う (レイアウトシフト防止)。
            banner.adSize = inlineAdaptiveBanner(
                width: width,
                maxHeight: DesignAdMetrics.bannerReservedHeight
            )
            banner.rootViewController = ConsentCoordinator.topViewController()
            banner.load(Request())
        }

        nonisolated func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            Task { @MainActor in
                self.isLoaded.wrappedValue = true
            }
        }

        nonisolated func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            Task { @MainActor in
                // 失敗時はプレースホルダのまま (ゲーム進行を止めない)。
                self.isLoaded.wrappedValue = false
            }
        }
    }
}
