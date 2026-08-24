import Foundation
import MarketplaceDesignSystem
import SwiftUI

enum DastakCustomerOnboardingStep: String, Identifiable {
    case notifications

    var id: String { rawValue }

    static func next(
        hasCompleted: Bool,
        notificationState: DastakNotificationPermissionState
    ) -> Self? {
        guard !hasCompleted, notificationState == .notRequested else { return nil }
        return .notifications
    }
}

struct DastakNotificationOnboardingView: View {
    let enableNotifications: () async -> Void
    let continueWithoutNotifications: () -> Void

    @State private var isRequesting = false

    var body: some View {
        ZStack {
            notificationBackground.ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            DastakWordmark(size: 36)
                                .foregroundStyle(MarketplaceColors.dastakText.color)
                            Spacer()
                            Text("FINISH SETUP")
                                .font(.caption2.weight(.bold))
                                .tracking(1.35)
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 30)
                                .background(MarketplaceColors.dastakAccent.color.opacity(0.10))
                                .clipShape(Capsule())
                        }
                        .padding(.top, 18)

                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .frame(width: 58, height: 58)
                                .background(MarketplaceColors.dastakAccent.color.opacity(0.11))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(MarketplaceColors.dastakAccent.color.opacity(0.24))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            Text("Know the moment\nyour order moves.")
                                .font(MarketplaceTypography.instrumentSerif(size: 42))
                                .foregroundStyle(MarketplaceColors.dastakText.color)
                                .lineSpacing(-2)

                            Text("Turn on useful order alerts, from secured to delivered—even when Dastak is closed.")
                                .font(.system(size: 16))
                                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 42)

                        VStack(spacing: 0) {
                            notificationPreview(
                                symbol: "checkmark.seal.fill",
                                title: "Your order is secured",
                                message: "Everything is ready for payment."
                            )
                            Divider().overlay(MarketplaceColors.dividerDark.color)
                            notificationPreview(
                                symbol: "location.fill",
                                title: "Your order is on the way",
                                message: "Your delivery partner has every package."
                            )
                        }
                        .padding(.horizontal, 16)
                        .background(MarketplaceColors.dastakSurface.color.opacity(0.96))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.22), radius: 24, y: 16)
                        .padding(.top, 28)

                        Label(
                            "Alerts never include payment credentials, verification codes or private evidence.",
                            systemImage: "lock.shield.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)

                        Spacer(minLength: 34)

                        VStack(spacing: MarketplaceSpacing.compact) {
                            Button {
                                isRequesting = true
                                Task {
                                    await enableNotifications()
                                    isRequesting = false
                                }
                            } label: {
                                if isRequesting {
                                    HStack(spacing: 9) {
                                        ProgressView()
                                            .tint(MarketplaceColors.primaryActionForeground.color)
                                        Text("Opening notification settings…")
                                    }
                                    .accessibilityElement(children: .combine)
                                } else {
                                    Text("Enable order alerts")
                                }
                            }
                            .buttonStyle(MarketplacePrimaryButtonStyle())
                            .disabled(isRequesting)

                            Button("Not now", action: continueWithoutNotifications)
                                .buttonStyle(MarketplaceSecondaryButtonStyle())
                                .disabled(isRequesting)
                        }
                    }
                    .frame(
                        maxWidth: MarketplaceMetrics.contentMaxWidth,
                        minHeight: proxy.size.height,
                        alignment: .leading
                    )
                    .padding(.horizontal, MarketplaceSpacing.large)
                    .padding(.top, 20)
                    .padding(.bottom, MarketplaceSpacing.large)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private var notificationBackground: some View {
        ZStack {
            MarketplaceColors.dastakBackground.color
            RadialGradient(
                colors: [MarketplaceColors.dastakAccent.color.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 360
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    private func notificationPreview(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 38, height: 38)
                .background(MarketplaceColors.dastakAccent.color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("now")
                .font(.caption2)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }
}
