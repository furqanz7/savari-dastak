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
    case admin

    fileprivate var label: String? {
        switch self {
        case .customerAndPartner: nil
        case .customer: "Customer"
        case .merchant: "Merchant"
        case .deliveryPartner: "Delivery Partner"
        case .admin: "Admin"
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
        case .admin: "dastak.admin"
        }
    }

    fileprivate func nextVideoResource() -> String {
        let defaults = UserDefaults.standard
        let key = "\(videoCycleKey).launch-video-index.v1"
        let nextIndex = DastakLaunchSequence.nextIndex(
            after: defaults.object(forKey: key) as? Int,
            count: videoResources.count
        )
        defaults.set(nextIndex, forKey: key)
        return videoResources[nextIndex]
    }
}

enum DastakLaunchSequence {
    static func nextIndex(after storedIndex: Int?, count: Int) -> Int {
        guard count > 0 else { return 0 }
        guard let storedIndex, (0..<count).contains(storedIndex) else { return 0 }
        return (storedIndex + 1) % count
    }
}

private enum DastakLaunchMediaState: Equatable {
    case loading
    case ready
    case failed
}

/// A short branded transition while Dastak restores the account and prepares its first screen.
/// It is deliberately separate from the system launch screen, which must remain static on iOS.
public struct DastakLaunchView<Content: View>: View {
    private let variant: DastakLaunchVariant
    private let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var videoResource: String?
    @State private var mediaState = DastakLaunchMediaState.loading
    @State private var minimumDurationElapsed = false
    @State private var hasFinishedLaunch = false

    public init(
        variant: DastakLaunchVariant = .customer,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.variant = variant
        self.content = content
    }

    public var body: some View {
        ZStack {
            content()
                .opacity(hasFinishedLaunch ? 1 : 0)
                .accessibilityHidden(!hasFinishedLaunch)

            if !hasFinishedLaunch {
                launchScreen
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .task(id: reduceMotion) {
            if !reduceMotion, videoResource == nil {
                videoResource = variant.nextVideoResource()
            }
            let minimumDuration: Duration = reduceMotion ? .milliseconds(650) : .milliseconds(2_200)
            try? await Task.sleep(for: minimumDuration)
            guard !Task.isCancelled else { return }
            minimumDurationElapsed = true
            finishIfReady()
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(4_000))
            guard !Task.isCancelled else { return }
            finish()
        }
        .onChange(of: mediaState) {
            finishIfReady()
        }
    }

    private var launchScreen: some View {
        ZStack {
            MarketplaceColors.dastakBackground.color
                .ignoresSafeArea()

            if !reduceMotion, mediaState != .failed, let videoResource {
                LaunchVideo(
                    resourceName: videoResource,
                    onReady: { mediaState = .ready },
                    onFailure: { mediaState = .failed }
                )
                .opacity(mediaState == .ready ? 0.78 : 0)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .animation(.easeOut(duration: 0.32), value: mediaState)
            }

            Color.black.opacity(mediaState == .ready ? 0.28 : 0.12)
                .ignoresSafeArea()

            VStack(spacing: MarketplaceSpacing.compact) {
                DastakLaunchWordmark()
                    .foregroundStyle(MarketplaceColors.primaryActionForeground.color)

                if let label = variant.label {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(MarketplaceColors.primaryActionForeground.color.opacity(0.78))

                    Capsule()
                        .fill(MarketplaceColors.dastakAccent.color)
                        .frame(width: 34, height: 2)
                        .padding(.top, MarketplaceSpacing.xSmall)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, MarketplaceSpacing.large)
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening Dastak")
        .preferredColorScheme(.dark)
    }

    private func finishIfReady() {
        guard minimumDurationElapsed else { return }
        guard reduceMotion || mediaState != .loading else { return }
        finish()
    }

    private func finish() {
        guard !hasFinishedLaunch else { return }
        if reduceMotion {
            hasFinishedLaunch = true
        } else {
            withAnimation(.easeOut(duration: 0.28)) {
                hasFinishedLaunch = true
            }
        }
    }
}

private struct DastakLaunchWordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MarketplaceWordmark.dastakLatin.uppercased())
                .font(.custom("HelveticaNeue-UltraLight", fixedSize: 50))
                .offset(y: -2)

            Text(MarketplaceWordmark.dastakUrdu)
                .font(.system(size: 42, weight: .light))
                .environment(\.layoutDirection, .rightToLeft)
                .offset(y: 2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MarketplaceWordmark.dastakLatin)
    }
}

#if os(iOS)
private struct LaunchVideo: UIViewRepresentable {
    let resourceName: String
    let onReady: () -> Void
    let onFailure: () -> Void

    func makeUIView(context: Context) -> LaunchVideoPlayerView {
        LaunchVideoPlayerView(
            resourceName: resourceName,
            onReady: onReady,
            onFailure: onFailure
        )
    }

    func updateUIView(_ uiView: LaunchVideoPlayerView, context: Context) {
        uiView.update(
            resourceName: resourceName,
            onReady: onReady,
            onFailure: onFailure
        )
    }

    static func dismantleUIView(_ uiView: LaunchVideoPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

private final class LaunchVideoPlayerView: UIView {
    private var resourceName: String?
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var playbackEndedObserver: NSObjectProtocol?
    private var onReady: () -> Void
    private var onFailure: () -> Void
    private var didResolveMedia = false

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(
        resourceName: String,
        onReady: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        self.onReady = onReady
        self.onFailure = onFailure
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        update(resourceName: resourceName, onReady: onReady, onFailure: onFailure)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(
        resourceName: String,
        onReady: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        self.onReady = onReady
        self.onFailure = onFailure

        guard self.resourceName != resourceName else {
            player?.play()
            return
        }

        stop()
        self.resourceName = resourceName
        didResolveMedia = false

        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "mp4") else {
            reportFailure()
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false

        self.player = player
        playerLayer.player = player
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            DispatchQueue.main.async { [weak self] in
                self?.handle(status)
            }
        }
        player.play()
    }

    func stop() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }
        player?.pause()
        playerLayer.player = nil
        player = nil
    }

    private func handle(_ status: AVPlayerItem.Status) {
        guard !didResolveMedia else { return }
        switch status {
        case .readyToPlay:
            didResolveMedia = true
            player?.play()
            onReady()
        case .failed:
            reportFailure()
        case .unknown:
            break
        @unknown default:
            reportFailure()
        }
    }

    private func reportFailure() {
        guard !didResolveMedia else { return }
        didResolveMedia = true
        DispatchQueue.main.async { [weak self] in
            self?.onFailure()
        }
    }
}
#else
private struct LaunchVideo: View {
    let resourceName: String
    let onReady: () -> Void
    let onFailure: () -> Void

    var body: some View {
        Color.clear
            .onAppear(perform: onFailure)
    }
}
#endif
