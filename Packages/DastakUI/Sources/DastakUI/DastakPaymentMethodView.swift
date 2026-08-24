import MarketplaceDesignSystem
import SwiftUI

struct DastakPaymentMethodView: View {
    @ObservedObject var model: DastakCustomerModel
    let continueAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let upiMethods: [DastakPaymentMethod] = [
        .upiID, .googlePay, .phonePe, .paytm, .cred, .pop,
        .superMoney, .jupiter, .jioFinance, .slice
    ]

    private let otherMethods: [DastakPaymentMethod] = [
        .card, .netbanking, .wallet, .payLater
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    paymentSection(
                        title: "UPI",
                        subtitle: "Choose an app. Razorpay securely opens it when available.",
                        methods: upiMethods
                    )
                    paymentSection(
                        title: "Other ways to pay",
                        subtitle: "Your bank and card details stay with Razorpay.",
                        methods: otherMethods
                    )
                    securityNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 112)
            }
            .background(DastakMatteBackground(style: .dark).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                continueButton
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(MarketplaceColors.dastakText.color)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Payment method")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(MarketplaceColors.dastakText.color)
            Text("Choose how you want to pay.")
                .font(.body)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
    }

    private func paymentSection(
        title: String,
        subtitle: String,
        methods: [DastakPaymentMethod]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
            }

            VStack(spacing: 0) {
                ForEach(methods) { method in
                    PaymentMethodRow(
                        method: method,
                        isSelected: model.selectedPaymentMethod == method
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.selectedPaymentMethod = method
                        }
                    }
                    if method.id != methods.last?.id {
                        Divider()
                            .overlay(MarketplaceColors.dastakSecondaryText.color.opacity(0.17))
                            .padding(.leading, 66)
                    }
                }
            }
            .background(MarketplaceColors.dastakSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Dastak never sees or stores your card, UPI PIN, or bank credentials.")
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(MarketplaceColors.dastakSurface.color.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var continueButton: some View {
        VStack(spacing: 0) {
            Divider().overlay(MarketplaceColors.dastakSecondaryText.color.opacity(0.2))
            Button(action: continueAction) {
                HStack(spacing: 10) {
                    Text("Continue with \(model.selectedPaymentMethod.title)")
                    Spacer()
                    Image(systemName: "arrow.right")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(MarketplaceColors.dastakBackground.color)
    }
}

private struct PaymentMethodRow: View {
    let method: DastakPaymentMethod
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: method.symbol)
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 30, height: 30)
                    .background(MarketplaceColors.dastakAccent.color.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(method.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakText.color)
                    Text(method.detail)
                        .font(.footnote)
                        .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        isSelected
                            ? MarketplaceColors.dastakAccent.color
                            : MarketplaceColors.dastakSecondaryText.color
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
