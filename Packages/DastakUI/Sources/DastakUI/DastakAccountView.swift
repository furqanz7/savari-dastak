import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakAccountView: View {
    let customer: MarketplaceCheckoutCustomer?
    let location: DastakDeliveryLocation?
    let discoveryRadiusKilometres: Int
    let refreshFailure: DastakCustomerRefreshFailure?
    let chooseLocation: () -> Void
    let retryAccount: () -> Void

    @Environment(\.marketplaceSignOut) private var signOut

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                profileCard
                if let refreshFailure {
                    DastakRefreshNotice(failure: refreshFailure, action: retryAccount)
                }
                deliverySection
                supportSection
                signOutButton
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Account")
    }

    private var profileCard: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(customer?.displayName ?? "Your account")
                    .font(.headline)
                Text(customer?.phoneNumber ?? "Phone number unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let email = customer?.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var deliverySection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Delivery")
                .font(MarketplaceTypography.sectionTitle)

            Button(action: chooseLocation) {
                VStack(spacing: MarketplaceSpacing.medium) {
                    HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location?.displayName ?? "Add delivery address")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(location?.displayAddress ?? "Add a house, flat or landmark")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        Spacer(minLength: MarketplaceSpacing.small)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    HStack {
                        Label("Delivery range", systemImage: "scope")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(discoveryRadiusKilometres) km")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
                .padding(MarketplaceSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .marketplaceFlatSurface()
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Support")
                .font(MarketplaceTypography.sectionTitle)
            Link(destination: URL(string: "tel:112")!) {
                Label("Emergency assistance", systemImage: "sos")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MarketplaceSpacing.medium)
            }
            .foregroundStyle(MarketplaceColors.destructive.color)
            .marketplaceFlatSurface()
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            Task { await signOut() }
        } label: {
            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(MarketplaceColors.destructive.color)
        .padding(.vertical, MarketplaceSpacing.small)
    }
}
