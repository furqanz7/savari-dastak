import Foundation
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DastakV1MatchingView: View {
    @ObservedObject var model: DastakCustomerModel
    @Environment(\.dismiss) private var dismiss
    @State private var isReportingIssue = false
    @State private var issueCategory = DastakV1CustomerIssueCategory.wrongSKU
    @State private var issueLineID: UUID?
    @State private var issueDescription = ""
    @State private var issuePhotoItem: PhotosPickerItem?
    @State private var issueEvidenceData: Data?
    @State private var issueEvidenceContentType: String?
    @State private var issueEvidenceError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let order = model.activeV1Order {
                    ScrollView {
                        VStack(spacing: MarketplaceSpacing.large) {
                            statusCard(order)
                            if order.status == .outForDelivery,
                               let delivery = order.delivery {
                                deliveryCard(delivery)
                            }
                            orderSummary(order)
                            if let support = order.support {
                                supportCard(support, order: order)
                            }
                            if order.status == .awaitingPayment,
                               let payment = order.payment {
                                paymentCard(order: order, payment: payment)
                            }
                            if let message = model.v1OrderErrorMessage {
                                DastakActionNotice(message: message) {
                                    model.v1OrderErrorMessage = nil
                                }
                            }
                            if order.status == .awaitingPayment,
                               order.payment?.canAttempt == true {
                                payButton(order)
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
        .marketplacePage()
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

            Label(
                [.paid, .preparing, .pickupInProgress, .outForDelivery, .delivered]
                    .contains(order.status)
                    ? "Secure package custody is tracked by Dastak"
                    : "No charge until the complete basket is secured",
                systemImage: "checkmark.shield.fill"
            )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .frame(maxWidth: .infinity)
        .padding(MarketplaceSpacing.large)
        .marketplaceFlatSurface()
    }

    @ViewBuilder
    private func deliveryCard(_ delivery: DastakV1DeliveryProgress) -> some View {
        if let code = delivery.deliveryCode,
           delivery.verificationStatus == .active,
           code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil {
            VStack(spacing: MarketplaceSpacing.medium) {
                VStack(spacing: 5) {
                    Text("DELIVERY CODE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(code)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(5)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                Text("Share this in-app code only when every package is with you. A trusted recipient may use it without a Dastak account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Label("No SMS code is used", systemImage: "iphone.gen2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            .frame(maxWidth: .infinity)
            .padding(MarketplaceSpacing.large)
            .background(MarketplaceColors.dastakAccentSoft.color)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Delivery code (code). Share only after receiving every package.")
        } else if delivery.verificationStatus == .blocked {
            Label(
                "Delivery verification needs Operations support. Your rider must keep every package secure.",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(MarketplaceSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marketplaceFlatSurface()
        }
    }

    private func paymentCard(
        order: DastakV1OrderSnapshot,
        payment: DastakV1PaymentReservation
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RESERVED FOR PAYMENT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(paymentTimeRemaining(payment, at: context.date))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DastakFormatting.money(payment.amount))
                        .font(.headline.monospacedDigit())
                }
            }

            if payment.latestAttempt?.status == "FAILED" {
                Label(
                    "Your previous attempt failed. The same secured basket remains reserved.",
                    systemImage: "arrow.clockwise.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.dastakAccentSoft.color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func payButton(_ order: DastakV1OrderSnapshot) -> some View {
        Button {
            Task {
                if await model.retryPayment(for: order) {
                    dismiss()
                }
            }
        } label: {
            HStack {
                if model.isCheckingOut { ProgressView().tint(.white) }
                Text(model.isCheckingOut
                     ? "Opening secure payment…"
                     : "Pay \(DastakFormatting.money(order.payment?.amount ?? order.price.total))")
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MarketplaceColors.dastakAccent.color)
        .controlSize(.large)
        .disabled(model.isCheckingOut)
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

    @ViewBuilder
    private func supportCard(
        _ support: DastakV1OrderSupport,
        order: DastakV1OrderSnapshot
    ) -> some View {
        if !support.recovery.isEmpty || !support.issues.isEmpty ||
            !support.returns.isEmpty || !support.refunds.isEmpty ||
            support.canReportIssue {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                Label("Help and recovery", systemImage: "lifepreserver.fill")
                    .font(.headline)

                ForEach(support.recovery) { recovery in
                    Label(recovery.customerMessage, systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(support.issues) { issue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(issueCategoryTitle(issue.category)) · \(displayState(issue.status))")
                            .font(.subheadline.weight(.semibold))
                        Text(issue.resolution ?? "Operations is reviewing your report.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(support.returns) { customerReturn in
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                        Text("Return · \(displayState(customerReturn.status))")
                            .font(.subheadline.weight(.semibold))
                        Text("\(customerReturn.packageCount) package(s) · secure reverse custody")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let code = customerReturn.mission?.pickupCode {
                            VStack(spacing: 4) {
                                Text("RETURN PICKUP CODE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                Text(code)
                                    .font(.title2.bold().monospacedDigit())
                                    .tracking(4)
                                Text("Share only after the assigned rider photographs and accounts for every return package.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(MarketplaceSpacing.compact)
                            .background(MarketplaceColors.dastakAccentSoft.color)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                ForEach(support.refunds) { refund in
                    Label(
                        "Refund \(displayState(refund.status).lowercased()) · \(DastakFormatting.money(refund.amount)) to original payment method",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if isReportingIssue {
                    issueForm(order: order)
                } else if support.canReportIssue {
                    Button {
                        resetIssueForm()
                        isReportingIssue = true
                    } label: {
                        Label("Get help with this order", systemImage: "exclamationmark.bubble.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private func issueForm(order: DastakV1OrderSnapshot) -> some View {
        let hasEvidence = issueEvidenceData != nil
        return VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Picker("What went wrong?", selection: $issueCategory) {
                ForEach(DastakV1CustomerIssueCategory.allCases, id: \.self) { category in
                    Text(issueCategoryTitle(category)).tag(category)
                }
            }
            .pickerStyle(.menu)

            Picker("Product", selection: $issueLineID) {
                Text("Whole order").tag(Optional<UUID>.none)
                ForEach(order.lines) { line in
                    Text("\(line.quantity)× \(line.name)").tag(Optional(line.id))
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 5) {
                Text("Details").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $issueDescription)
                    .frame(minHeight: 88)
                    .padding(6)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Issue details")
            }

            PhotosPicker(selection: $issuePhotoItem, matching: .images) {
                Label(
                    hasEvidence ? "Evidence photo added" : "Add evidence photo",
                    systemImage: hasEvidence ? "checkmark.circle.fill" : "camera.fill"
                )
            }
            .onChange(of: issuePhotoItem) { _, item in
                Task { await loadIssueEvidence(item) }
            }

            Text(
                evidenceRequired
                    ? "A clear photo is required for item or package problems. JPG, PNG, or HEIC; up to 10 MB."
                    : "A photo is optional for this issue. JPG, PNG, or HEIC; up to 10 MB."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let issueEvidenceError {
                Text(issueEvidenceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Back") { resetIssueForm() }
                    .buttonStyle(.bordered)
                Button {
                    Task {
                        if await model.reportV1Issue(
                            category: issueCategory,
                            orderLineID: issueLineID,
                            description: issueDescription,
                            evidenceData: issueEvidenceData,
                            evidenceContentType: issueEvidenceContentType
                        ) {
                            resetIssueForm()
                        }
                    }
                } label: {
                    if model.isReportingV1Issue { ProgressView() }
                    else { Text("Send to support") }
                }
                .buttonStyle(.borderedProminent)
                .tint(MarketplaceColors.dastakAccent.color)
                .disabled(
                    model.isReportingV1Issue ||
                    issueDescription.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ||
                    (evidenceRequired && issueEvidenceData == nil)
                )
            }
        }
    }

    private var evidenceRequired: Bool {
        ![.deliveryProblem, .other].contains(issueCategory)
    }

    private func loadIssueEvidence(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  (1...(10 * 1_024 * 1_024)).contains(data.count),
                  let type = item.supportedContentTypes.first(where: {
                      $0.conforms(to: .jpeg) || $0.conforms(to: .png) || $0.conforms(to: .heic)
                  })
            else { throw DastakIssuePhotoError.invalid }
            let contentType: String
            if type.conforms(to: .png) { contentType = "image/png" }
            else if type.conforms(to: .heic) { contentType = "image/heic" }
            else { contentType = "image/jpeg" }
            issueEvidenceData = data
            issueEvidenceContentType = contentType
            issueEvidenceError = nil
        } catch {
            issuePhotoItem = nil
            issueEvidenceData = nil
            issueEvidenceContentType = nil
            issueEvidenceError = "Choose a JPG, PNG, or HEIC photo up to 10 MB."
        }
    }

    private func resetIssueForm() {
        isReportingIssue = false
        issueDescription = ""
        issuePhotoItem = nil
        issueEvidenceData = nil
        issueEvidenceContentType = nil
        issueEvidenceError = nil
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
            guard let order = model.activeV1Order, shouldPoll(order.status) else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await model.refreshActiveV1Order()
        }
    }

    private func shouldPoll(_ status: DastakV1OrderStatus) -> Bool {
        [.created, .matching, .fullySecured, .awaitingPayment, .paid, .preparing,
         .pickupInProgress, .outForDelivery].contains(status)
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
        case .pickupInProgress: "Picking up your order"
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
        case .paid, .preparing: "Payment is confirmed and your secured items are being prepared."
        case .pickupInProgress: "Your delivery partner is collecting your complete order."
        case .outForDelivery: "Every package has been collected and your delivery partner is heading to you."
        case .delivered: "Every package was securely handed over. Your order is complete."
        case .unavailable: "Dastak could not secure the complete basket. You were not charged."
        case .paymentExpired: "The reservation expired without payment."
        case .cancelledPrepayment: "This order was cancelled before payment."
        case .fulfilmentFailure: "Support is recovering this order."
        }
    }

    private func paymentTimeRemaining(
        _ payment: DastakV1PaymentReservation,
        at date: Date
    ) -> String {
        guard let expiry = ISO8601DateFormatter().date(from: payment.expiresAt) else {
            return "Reservation active"
        }
        let remaining = max(0, Int(expiry.timeIntervalSince(date).rounded(.up)))
        return String(format: "%d:%02d remaining", remaining / 60, remaining % 60)
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

    private func issueCategoryTitle(_ category: DastakV1CustomerIssueCategory) -> String {
        switch category {
        case .wrongSKU: "Wrong product"
        case .wrongQuantity: "Wrong quantity"
        case .damaged: "Damaged"
        case .defective: "Defective"
        case .expired: "Expired"
        case .tamperedOrBrokenSeal: "Seal or tampering"
        case .incorrectPackage: "Incorrect package"
        case .suspectedMerchantMisfulfilment: "Merchant fulfilment concern"
        case .deliveryProblem: "Delivery problem"
        case .other: "Other"
        }
    }

    private func displayState(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private enum DastakIssuePhotoError: Error {
    case invalid
}
