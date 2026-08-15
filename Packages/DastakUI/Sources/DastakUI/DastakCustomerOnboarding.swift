import Foundation
import MarketplaceDesignSystem
import SwiftUI

enum DastakCustomerOnboardingStep: String, Identifiable {
    case notifications

    var id: String { rawValue }

    static func next(hasCompleted: Bool) -> Self? {
        return hasCompleted ? nil : .notifications
    }
}

struct DastakNotificationOnboardingView: View {
    let enableNotifications: () async -> Void
    let continueWithoutNotifications: () -> Void

    @State private var isRequesting = false

    var body: some View {
        ZStack {
            MarketplaceColors.dastakBackground.color.ignoresSafeArea()

            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 64, height: 64)
                    .background(MarketplaceColors.dastakAccentSoft.color)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                    Text("Stay updated")
                        .font(.largeTitle.bold())
                    Text("Get order, parcel, payment and delivery updates even when Dastak is closed.")
                        .font(MarketplaceTypography.supporting)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    benefit("bell", "Status changes", "Know when a merchant accepts and when a partner is on the way.")
                    benefit("lock.shield", "Only useful alerts", "Notifications contain no payment credentials or private evidence.")
                }

                Spacer()

                VStack(spacing: MarketplaceSpacing.compact) {
                    Button {
                        isRequesting = true
                        Task {
                            await enableNotifications()
                            isRequesting = false
                        }
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .tint(MarketplaceColors.primaryActionForeground.color)
                        } else {
                            Text("Enable notifications")
                        }
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(isRequesting)

                    Button("Not now", action: continueWithoutNotifications)
                        .buttonStyle(MarketplaceSecondaryButtonStyle())
                        .disabled(isRequesting)
                }
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.large)
            .padding(.vertical, MarketplaceSpacing.xxLarge)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func benefit(_ symbol: String, _ title: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
