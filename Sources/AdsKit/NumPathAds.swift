import Domain
import Presentation
import SwiftUI

/// AdsKit の公開ファサード。アプリターゲット (RootView) だけがこれを import する。
public enum NumPathAds {
    @MainActor
    public static func bannerProvider(repository: AdMobServingRepository) -> AnyAdBannerProvider {
        AnyAdBannerProvider { placement in
            GameplayBannerContainer(placement: placement, repository: repository)
        }
    }
}
