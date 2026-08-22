import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakV1MatchingView: View {
    @ObservedObject var model: DastakCustomerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let order = model.activeV1Order {
                    ScrollView {
                        VStack(spacing: MarketplaceSpacing.large) {
                            statusCard(order)
                            orderSummary(order)
                            if let message = model.v1OrderErrorMessage {
                                DastakActionNotice(message: message) {
                                    model.v1OrderErrorMessage = nil
                                }
                            }
                            if canCancel(order) { cancelButton }
                        }
                        .padding(MarketplaceSpacing.medium)
                    }
                } else {
                    DastakEmptyState(
                        symbol: "clock",
                        title: "No active match",
                        message: "Your submitted Dastak order will appear here."
                    )
                }
            }
            .navigationTitle("Order status")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await pollWhileActive() }
    }

    private func statusCard(_ order: DastakV1OrderSnapshot) -> some View {
        VStack(spacing: MarketplaceSpacing.medium) {
            ZStack {
                Circle()
                    .fill(MarketplaceColors.dastakAccentSoft.color)
                    .frame(width: 86, height: 86)
                if isMatching(order.status) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(MarketplaceColors.dastakAccent.color)
                } else {
                    Image(systemName: statusSymbol(order.status))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
            }

            VStack(spacing: MarketplaceSpacing.small) {
                Text(statusTitle(order.status))
                    .font(MarketplaceTypography.instrumentSerif(fixedSize: 32))
                    .multilineTextAlignment(.center)
                Text(statusMessage(order.status))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Label("No charge until the complete basket is secured", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .frame(maxWidth: .infinity)
        .padding(MarketplaceSpacing.large)
        .marketplaceFlatSurface()
    }

    private func orderSummary(_ order: DastakV1OrderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ORDER")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(order.displayOrderNumber)
                        .font(.headline.monospaced())
                }
                Spacer()
                Text(DastakFormatting.money(order.price.total))
                    .font(.headline.monospacedDigit())
            }
            Divider()
            ForEach(order.lines) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(line.quantity)×")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(line.name)
                        .font(.subheadline)
                    Spacer()
                    Text(DastakFormatting.money(Money(paise: line.lineTotalPaise)))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            Task { await model.cancelActiveV1Order() }
        } label: {
            Text("Cancel before payment")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func pollWhileActive() async {
        while !Task.isCancelled {
            guard let order = model.activeV1Order, isMatching(order.status) else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await model.refreshActiveV1Order()
        }
    }

    private func isMatching(_ status: DastakV1OrderStatus) -> Bool {
        status == .created || status == .matching
    }

    private func canCancel(_ order: DastakV1OrderSnapshot) -> Bool {
        [.created, .matching, .fullySecured, .awaitingPayment].contains(order.status)
    }

    private func statusTitle(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .created, .matching: "Finding every item"
        case .fullySecured, .awaitingPayment: "Your basket is secured"
        case .paid, .preparing: "Preparing your order"
        case .pickupInProgress: "Pickup in progress"
        case .outForDelivery: "On the way"
        case .delivered: "Delivered"
        case .unavailable: "Basket unavailable"
        case .paymentExpired: "Payment window expired"
        case .cancelledPrepayment: "Order cancelled"
        case .fulfilmentFailure: "Order needs attention"
        }
    }

    private func statusMessage(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .created, .matching:
            "Dastak is matching the exact products in your basket. Retail merchant identities stay private."
        case .fullySecured, .awaitingPayment:
            "Every item has been reserved. Secure payment will be requested before preparation begins."
        case .paid, .preparing: "Your secured items are being prepared."
        case .pickupInProgress: "Your rider is collecting the declared packages."
        case .outForDelivery: "Your verified packages are heading to you."
        case .delivered: "Your delivery has been completed."
        case .unavailable: "Dastak could not secure the complete basket. You were not charged."
        case .paymentExpired: "The reservation expired without payment."
        case .cancelledPrepayment: "This order was cancelled before payment."
        case .fulfilmentFailure: "Support is recovering this order."
        }
    }

    private func statusSymbol(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .fullySecured, .awaitingPayment, .delivered: "checkmark.shield.fill"
        case .paid, .preparing: "shippingbox.fill"
        case .pickupInProgress, .outForDelivery: "scooter"
        case .cancelledPrepayment, .paymentExpired: "xmark.circle.fill"
        case .unavailable, .fulfilmentFailure: "exclamationmark.triangle.fill"
        case .created, .matching: "magnifyingglass"
        }
    }
}
