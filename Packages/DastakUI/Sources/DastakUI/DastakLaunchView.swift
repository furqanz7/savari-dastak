import AVFoundation
import Foundation
import MarketplaceDesignSystem
import SwiftUI

#if os(iOS)
import UIKit
#endif

public enum DastakLaunchVariant: Sendable {
    case customerAndPartner
    case customer
    case merchant
    case deliveryPartner

    fileprivate var label: String? {
        switch self {
        case .customerAndPartner: nil
        case .customer: "Customer"
        case .merchant: "Merchant"
        case .deliveryPartner: "Delivery Partner"
        }
    }

    fileprivate var videoResources: [String] {
        ["DastakSplash1", "DastakSplash2", "DastakSplash3"]
    }

    fileprivate var videoCycleKey: String {
        switch self {
        case .customerAndPartner: "dastak.customer-and-partner"
        case .customer: "dastak.customer"
        case .merchant: "dastak.merchant"
        case .deliveryPartner: "dastak.delivery-partner"
        }
    }

    fileprivate func nextVideoResource() -> String {
        let defaults = UserDefaults.standard
        let key = "\(videoCycleKey).launch-video-index"
        let currentIndex = defaults.object(forKey: key) as? Int ?? -1
        let nextIndex = (currentIndex + 1) % videoResources.count
        defaults.set(nextIndex, forKey: key)
        return videoResources[nextIndex]
    }
}

/// A short branded transition while Dastak restores the account and prepares its first screen.
/// It is deliberately separate from the system launch screen, which must remain static on iOS.
public struct DastakLaunchView<Content: View>: View {
    private let variant: DastakLaunchVariant
    private let content: () -> Content
    @State private var videoResource: String
    @State private var hasFinishedLaunch = false

    public init(
        variant: DastakLaunchVariant = .customer,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.content = content
        _videoResource = State(initialValue: variant.nextVideoResource())
    }

    public var body: some View {
        ZStack {
            content()
                .opacity(hasFinishedLaunch ? 1 : 0)
                .accessibilityHidden(!hasFinishedLaunch)

            if !hasFinishedLaunch {
                launchScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.28), value: hasFinishedLaunch)
        .task {
            guard !hasFinishedLaunch else { return }
            try? await Task.sleep(for: .milliseconds(1_250))
            guard !Task.isCancelled else { return }
            hasFinishedLaunch = true
        }
    }

    private var launchScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LaunchVideo(resourceName: videoResource)
                .opacity(0.78)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: MarketplaceSpacing.compact) {
                Spacer()

                DastakWordmark(size: 44)
                    .foregroundStyle(MarketplaceColors.primaryActionForeground.color)

                if let label = variant.label {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.3)
                        .foregroundStyle(MarketplaceColors.primaryActionForeground.color.opacity(0.78))

                    Capsule()
                        .fill(MarketplaceColors.dastakAccent.color)
                        .frame(width: 34, height: 2)
                        .padding(.top, MarketplaceSpacing.xSmall)
                }

                Spacer()
                    .frame(height: MarketplaceSpacing.xxLarge)
            }
            .padding(.horizontal, MarketplaceSpacing.large)
        }
        .preferredColorScheme(.dark)
    }
}

#if os(iOS)
private struct LaunchVideo: UIViewRepresentable {
    let resourceName: String

    func makeUIView(context: Context) -> LaunchVideoPlayerView {
        LaunchVideoPlayerView(resourceName: resourceName)
    }

    func updateUIView(_ uiView: LaunchVideoPlayerView, context: Context) {
        uiView.update(resourceName: resourceName)
    }

    static func dismantleUIView(_ uiView: LaunchVideoPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

private final class LaunchVideoPlayerView: UIView {
    private var resourceName: String?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(resourceName: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        playerLayer.videoGravity = .resizeAspectFill
        update(resourceName: resourceName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(resourceName: String) {
        guard self.resourceName != resourceName else {
            player?.play()
            return
        }
        self.resourceName = resourceName

        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "mp4"
        ) else {
            playerLayer.player = nil
            return
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        player = queuePlayer
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        playerLayer.player = queuePlayer
        queuePlayer.play()
    }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        looper = nil
        player = nil
    }
}
#else
private struct LaunchVideo: View {
    let resourceName: String

    var body: some View {
        Color.black
    }
}
#endif
