import CoreGraphics

// concurrency-exception: Google Mobile Ads delegate callbacks are nonisolated and must hop to MainActor.
@preconcurrency import GoogleMobileAds
import SwiftUI
import UIKit

/// A host-style-neutral adaptive banner. Reserve its surrounding height in the host layout to avoid shifts.
public struct AdMobBanner: View {
    private let slot: AdSlot
    private let client: AdMobClient
    private let maximumHeight: CGFloat
    @State private var adUnitID: String?
    @State private var isLoaded = false
    @State private var loadedAdSize: CGSize?

    @MainActor
    public init(
        slot: AdSlot,
        client: AdMobClient,
        maximumHeight: CGFloat,
    ) {
        self.slot = slot
        self.client = client
        self.maximumHeight = maximumHeight
    }

    public var body: some View {
        Group {
            if let adUnitID {
                GeometryReader { proxy in
                    AdMobBannerRepresentable(
                        adUnitID: adUnitID,
                        width: proxy.size.width,
                        maximumHeight: maximumHeight,
                        isLoaded: $isLoaded,
                        loadedAdSize: $loadedAdSize,
                    )
                    .frame(
                        width: loadedAdSize?.width ?? proxy.size.width,
                        height: loadedAdSize?.height ?? proxy.size.height,
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                }
                .opacity(isLoaded ? 1 : 0)
            } else {
                Color.clear
            }
        }
        .task {
            await client.waitUntilReady()
            adUnitID = client.bannerAdUnitID(for: slot)
        }
    }
}

private struct AdMobBannerRepresentable: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    let maximumHeight: CGFloat
    @Binding var isLoaded: Bool
    @Binding var loadedAdSize: CGSize?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded, loadedAdSize: $loadedAdSize)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        let banner = BannerView()
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            banner.widthAnchor.constraint(equalTo: container.widthAnchor),
            banner.heightAnchor.constraint(equalTo: container.heightAnchor),
        ])
        context.coordinator.banner = banner
        return container
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.loadIfNeeded(width: width, maximumHeight: maximumHeight)
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        var banner: BannerView?
        private var isLoaded: Binding<Bool>
        private var loadedAdSize: Binding<CGSize?>
        private var loadedWidth: CGFloat = 0

        init(isLoaded: Binding<Bool>, loadedAdSize: Binding<CGSize?>) {
            self.isLoaded = isLoaded
            self.loadedAdSize = loadedAdSize
        }

        func loadIfNeeded(width: CGFloat, maximumHeight: CGFloat) {
            guard let banner, width > 0, abs(width - loadedWidth) > 1 else {
                return
            }
            loadedWidth = width
            Task { @MainActor in
                self.isLoaded.wrappedValue = false
                self.loadedAdSize.wrappedValue = nil
                banner.adSize = inlineAdaptiveBanner(width: width, maxHeight: maximumHeight)
                banner.rootViewController = ConsentCoordinator.topViewController()
                banner.load(Request())
            }
        }

        nonisolated func bannerViewDidReceiveAd(_: BannerView) {
            Task { @MainActor in
                self.loadedAdSize.wrappedValue = self.banner?.adSize.size
                self.isLoaded.wrappedValue = true
            }
        }

        nonisolated func bannerView(_: BannerView, didFailToReceiveAdWithError error: Error) {
            Task { @MainActor in
                AdMobKitLog.logger.error(
                    "failed to load banner ad: \(String(describing: error), privacy: .public)",
                )
                self.loadedAdSize.wrappedValue = nil
                self.isLoaded.wrappedValue = false
            }
        }
    }
}
