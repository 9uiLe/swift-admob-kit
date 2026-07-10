import AppMacros
import DesignSystem
import Domain

// concurrency-exception: SDK の Sendable 未準拠に対する @preconcurrency import (AdsKit 内部限定)。
@preconcurrency import GoogleMobileAds
import SwiftUI
import Tasking
import UIKit

/// バナースロット (Presentation) に注入される実バナー。
/// ロード前はプレースホルダを表示し、ロード完了時にフレーム内でクロスフェードする
/// (スロット側が高さを予約しているためレイアウトは一切動かない)。
/// `repository` は composition root で一度だけ注入される安定参照 (`final class`) のため
/// `@SkipEquatable` で比較対象外にする (不変条件: 実行中に差し替えない)。`@State` はマクロが
/// 自動除外するので比較対象は `placement` のみ。これで親由来の再評価を diff narrowing で抑えつつ、
/// `@State` 駆動の更新 (バナーのロード完了クロスフェード) は従来どおり保持する。
@Equatable
struct GameplayBannerContainer: EquatableBodyView {
    let placement: AdPlacementID
    @SkipEquatable let repository: AdMobServingRepository
    @State private var adUnitID: String?
    @State private var isLoaded = false
    @State private var loadedAdSize: CGSize?

    var equatableBody: some View {
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
            }
        }
        .animation(DesignAnimation.adFade, value: isLoaded) // animation-exception: AdsKit 隔離層は ScopedAnimation に依存不可のため直接指定
        .task {
            await repository.waitUntilReady()
            guard repository.isReady else {
                return
            }
            adUnitID = repository.bannerAdUnitID(for: placement)
        }
    }
}

private struct AdMobBannerView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    @Binding var isLoaded: Bool
    @Binding var loadedAdSize: CGSize?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded, loadedAdSize: $loadedAdSize)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        // 予約高さ (DesignAdMetrics.bannerReservedHeight) の外に実バナーがはみ出さないよう、
        // Auto Layout で container の実寸に強制一致させたうえで念のためクリップする
        // (adSize は上限指定にすぎず、実際に配信される広告の実寸を保証しないため)。
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
        context.coordinator.loadIfNeeded(width: width)
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        private static let resetLoadStateAction: ActionID = "adsKit.banner.resetLoadState"
        private static let loadBannerAction: ActionID = "adsKit.banner.load"
        var banner: BannerView?
        private var isLoaded: Binding<Bool>
        private var loadedAdSize: Binding<CGSize?>
        private var loadedWidth: CGFloat = 0
        private let taskStore = ViewTaskStore()

        init(isLoaded: Binding<Bool>, loadedAdSize: Binding<CGSize?>) {
            self.isLoaded = isLoaded
            self.loadedAdSize = loadedAdSize
        }

        func loadIfNeeded(width: CGFloat) {
            guard let banner, width > 0, abs(width - loadedWidth) > 1 else {
                return
            }
            loadedWidth = width
            // updateUIView (view update 中) からの @State 書き換えは未定義動作になるため、
            // binding への書き込みは次のメインアクタターンに遅延させる。
            taskStore.start(id: Self.resetLoadStateAction, lifetime: .screenBound, policy: .cancelExisting) { _ in
                self.isLoaded.wrappedValue = false
                self.loadedAdSize.wrappedValue = nil
            }
            // view update 中の同期 load はメインスレッドを塞ぐため、次のメインアクタターンへ遅延する。
            let requestWidth = width
            taskStore.start(id: Self.loadBannerAction, lifetime: .screenBound, policy: .cancelExisting) { _ in
                guard let banner = self.banner else {
                    return
                }
                banner.adSize = inlineAdaptiveBanner(
                    width: requestWidth,
                    maxHeight: DesignAdMetrics.bannerReservedHeight,
                )
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
                // 失敗時はプレースホルダのまま (ゲーム進行を止めない)。
                AdsKitLog.logger.error(
                    "failed to load banner ad: \(String(describing: error), privacy: .public)",
                )
                self.loadedAdSize.wrappedValue = nil
                self.isLoaded.wrappedValue = false
            }
        }
    }
}
