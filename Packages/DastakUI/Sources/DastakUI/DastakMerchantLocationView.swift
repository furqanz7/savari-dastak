import SwiftUI
import MarketplaceDesignSystem

struct DastakMerchantLocationView: View {
    @ObservedObject var model: DastakMerchantModel
    var presentation: DastakMerchantStoreHeading.Presentation = .compact
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DastakMerchantStoreHeading(
                name: model.selectedLocation?.name ?? (model.locationsInitialized || model.locationMessage != nil ? "Store unavailable" : "Checking your store…"),
                service: model.selectedLocation?.service,
                symbol: model.selectedLocation?.symbol ?? "storefront",
                presentation: presentation,
                refreshing: model.isRefreshingLocations || model.isRefreshingCatalogue || model.isRefreshingRestaurant,
                refreshDisabled: model.locationSwitchDisabled || model.isRefreshingCatalogue || model.isRefreshingRestaurant
            ) {
                Task { await model.refreshLocations(); await model.refreshSelectedStore() }
            }
            if model.hasPendingCanonicalSelections {
                Text("Save or discard your product selections before refreshing your store.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.locationMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityIdentifier("merchant.location.context")
    }
}

/// One unboxed page heading; compact identity is used inside category browsing.
/// It lives in normal page flow and never supplies an overlay or a fixed height.
struct DastakMerchantStoreHeading: View {
    enum Presentation: CaseIterable {
        case orders, catalogue, menu, compact
        var eyebrow: String {
            switch self {
            case .orders: "THE ORDER DESK"
            case .catalogue: "YOUR STOREFRONT"
            case .menu: "FROM YOUR KITCHEN"
            case .compact: ""
            }
        }
        var subtitle: String {
            switch self {
            case .orders: "Every request. Every handoff. All in view."
            case .catalogue: "Your products, stock and everyday essentials."
            case .menu: "Your dishes, photos and little extras."
            case .compact: ""
            }
        }
    }

    let name: String
    let service: String?
    let symbol: String
    var presentation: Presentation = .compact
    var refreshing = false
    var refreshDisabled = false
    let refresh: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { MarketplaceColors.accent(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: presentation == .compact ? 0 : 8) {
            if presentation == .compact {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        serviceLabel
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    refreshButton
                }
            } else {
                HStack(spacing: 12) {
                    Text(presentation.eyebrow).font(.caption2.weight(.bold)).tracking(1.8)
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    refreshButton
                }
                Text(name).font(MarketplaceTypography.instrumentSerif(size: 36))
                    .foregroundStyle(MarketplaceColors.primaryText(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.subtitle).font(.subheadline)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                serviceLabel.padding(.top, 4)
                Rectangle().fill(LinearGradient(colors: [accent.opacity(0.45), accent.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1).padding(.top, 10).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, presentation == .compact ? 0 : 4)
    }

    @ViewBuilder private var serviceLabel: some View {
        if let service {
            Label(service, systemImage: symbol).font(.caption)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            ZStack {
                Circle().fill(accent.opacity(0.07))
                Circle().strokeBorder(accent.opacity(0.18), lineWidth: 0.75)
                if refreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .medium)) }
            }.foregroundStyle(accent).frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(refreshing ? "Refreshing store" : "Refresh store")
        .disabled(refreshDisabled || refreshing)
        .accessibilityIdentifier("merchant.store.refresh")
    }
}
