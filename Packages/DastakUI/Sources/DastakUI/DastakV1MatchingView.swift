import Foundation
import MapKit
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DastakV1MatchingView: View {
    @ObservedObject var model: DastakCustomerModel
    let isPresentedModally: Bool
    let openCart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isReportingIssue = false
    @State private var issueCategory = DastakV1CustomerIssueCategory.wrongSKU
    @State private var issueLineID: UUID?
    @State private var issueDescription = ""
    @State private var issuePhotoItem: PhotosPickerItem?
    @State private var issueEvidenceData: Data?
    @State private var issueEvidenceContentType: String?
    @State private var issueEvidenceError: String?
    @State private var showingCancellationConfirmation = false
    @State private var showingReorderConfirmation = false
    @State private var showingLaunchPayment = false

    init(
        model: DastakCustomerModel,
        isPresentedModally: Bool = true,
        openCart: @escaping () -> Void = {}
    ) {
        self.model = model
        self.isPresentedModally = isPresentedModally
        self.openCart = openCart
    }

    var body: some View {
        Group {
            if isPresentedModally {
                NavigationStack {
                    content
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            } else {
                content
            }
        }
        .marketplacePage()
        .task { await pollWhileActive() }
        .confirmationDialog(
            "Cancel this order?",
            isPresented: $showingCancellationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel order", role: .destructive) {
                Task { await model.cancelActiveV1Order() }
            }
            Button("Keep order", role: .cancel) {}
        } message: {
            Text("Cancellation is available only before confirmation. Reserved items will be released.")
        }
        .confirmationDialog(
            "Replace your current basket?",
            isPresented: $showingReorderConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace basket and reorder") { reorderCurrentOrder() }
            Button("Keep current basket", role: .cancel) {}
        } message: {
            Text("Current basket items will be replaced. You can review current availability and prices before submitting.")
        }
        .dastakFullScreenCover(isPresented: $showingLaunchPayment) {
            if let order = model.activeV1Order {
                DastakLaunchPaymentView(model: model, order: order)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let order = model.activeV1Order {
                ScrollView {
                    VStack(spacing: MarketplaceSpacing.large) {
                        statusCard(order)
                        if [.paid, .preparing].contains(order.status) {
                            preparationETACard(order)
                        }
                        if let tracking = order.tracking {
                            DastakDeliveryTrackingView(tracking: tracking, destination: order.deliveryAddress.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                        }
                        if order.status == .outForDelivery,
                           let delivery = order.delivery {
                            if delivery.pinVerified != true {
                                deliveryCard(delivery)
                            }
                            launchCollectionCard(order)
                        }
                        orderSummary(order)
                        receiptCard(order)
                        deliveryDetails(order)
                        timelineCard(order)
                        if let support = order.support {
                            supportCard(support, order: order)
                        }
                        supportContactCard
                        if order.status == .awaitingPayment,
                           let launchPayment = order.launchPayment {
                            paymentCard(order: order, launchPayment: launchPayment)
                        }
                        if let message = model.v1OrderErrorMessage {
                            DastakActionNotice(message: message) {
                                model.v1OrderErrorMessage = nil
                            }
                        }
                        if order.status == .awaitingPayment,
                           order.launchPayment?.canCommit == true {
                            payButton(order)
                        }
                        if canCancel(order) { cancelButton }
                        if DastakV1OrderPresentation.canReorder(order.status) {
                            reorderButton(order)
                        }
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
        .dastakOpaqueNavigationBar()
    }

    private func statusCard(_ order: DastakV1OrderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MarketplaceColors.dastakAccentSoft.color)
                        .frame(width: 52, height: 52)
                    if isMatching(order.status) {
                        ProgressView().tint(MarketplaceColors.dastakAccent.color)
                    } else {
                        Image(systemName: DastakV1OrderPresentation.symbol(order.status))
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(DastakV1OrderPresentation.deliveredDuration(order) ??
                         DastakV1OrderPresentation.title(order.status))
                        .font(.title2.bold())
                    Text(DastakV1OrderPresentation.message(order.status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.compact) {
                Text(order.displayOrderNumber)
                    .font(.caption.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: MarketplaceSpacing.small)
                Text(DastakFormatting.money(order.price.total))
                    .font(.headline.monospacedDigit())
            }
            if let date = DastakV1OrderPresentation.date(order.submittedAt ?? order.createdAt) {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if DastakV1OrderPresentation.isActive(order.status) {
                DastakV1JourneyProgress(status: order.status)
            }

            Label(
                DastakV1OrderPresentation.assurance(order.status),
                systemImage: assuranceSymbol(order.status)
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .frame(maxWidth: .infinity)
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func deliveryCard(_ delivery: DastakV1DeliveryProgress) -> some View {
        if let code = delivery.deliveryCode,
           delivery.verificationStatus == .active,
           code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil {
            VStack(spacing: MarketplaceSpacing.medium) {
                HStack(spacing: MarketplaceSpacing.compact) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DELIVERY CODE")
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text("Share only after every package arrives")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(code)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(7)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MarketplaceSpacing.compact)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("A trusted recipient may use this in-app code without a Dastak account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Label("No SMS code is used", systemImage: "iphone.gen2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            .frame(maxWidth: .infinity)
            .padding(MarketplaceSpacing.large)
            .background(
                LinearGradient(
                    colors: [
                        MarketplaceColors.dastakAccentSoft.color,
                        MarketplaceColors.dastakAccentSoft.color.opacity(0.46),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(MarketplaceColors.dastakAccent.color.opacity(0.28), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Delivery code \(code). Share only after receiving every package.")
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

    @ViewBuilder
    private func launchCollectionCard(_ order: DastakV1OrderSnapshot) -> some View {
        if let launch = order.launchPayment, launch.state != .notApplicable {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                HStack(spacing: MarketplaceSpacing.compact) {
                    Image(systemName: launch.state == .paymentCollected
                          ? "checkmark.seal.fill" : "indianrupeesign.circle.fill")
                        .font(.title2)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(launch.state == .paymentCollected
                             ? "Payment collected" : "Payment due at delivery")
                            .font(.headline)
                        Text(DastakFormatting.money(launch.amount ?? order.price.total))
                            .font(.title3.bold().monospacedDigit())
                    }
                }
                Text(launchCollectionMessage(launch))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MarketplaceSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MarketplaceColors.dastakAccentSoft.color)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func paymentCard(
        order: DastakV1OrderSnapshot,
        launchPayment: DastakV1LaunchPayment
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FULL BASKET SECURED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(paymentTimeRemaining(launchPayment, at: context.date))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DastakFormatting.money(launchPayment.amount ?? order.price.total))
                        .font(.headline.monospacedDigit())
                }
            }

            Label("Confirm now; pay the delivery partner by UPI or cash at the doorstep. No charge now.", systemImage: "hand.raised.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.dastakAccentSoft.color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func payButton(_ order: DastakV1OrderSnapshot) -> some View {
        Button {
            showingLaunchPayment = true
        } label: {
            HStack {
                if model.isCheckingOut { ProgressView().tint(.white) }
                Text("Confirm Pay via UPI/Cash on Delivery")
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(MarketplaceColors.dastakAccent.color)
        .controlSize(.large)
        .disabled(model.isCheckingOut || order.launchPayment?.canCommit != true)
    }

    private func orderSummary(_ order: DastakV1OrderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ITEMS IN THIS ORDER")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text("\(DastakV1OrderPresentation.itemCount(order)) item\(DastakV1OrderPresentation.itemCount(order) == 1 ? "" : "s")")
                        .font(.headline)
                }
                Spacer()
                if let restaurant = order.restaurant {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(restaurant.name)
                            .font(.subheadline.weight(.semibold))
                        Text(restaurant.branchName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
            Divider()
            ForEach(order.lines) { line in
                HStack(alignment: .center, spacing: MarketplaceSpacing.compact) {
                    DastakProductArtwork(
                        imageKey: model.imageKey(for: line),
                        fallbackSymbol: line.lineType == "FOOD_MENU_ITEM" ? "fork.knife" : "basket"
                    )
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.subheadline.weight(.medium))
                        if let detail = DastakV1OrderPresentation.optionSummary(line) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(line.quantity) × \(DastakFormatting.money(Money(paise: line.unitPricePaise)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DastakFormatting.money(Money(paise: line.lineTotalPaise)))
                        .font(.subheadline.bold().monospacedDigit())
                }
                if line.id != order.lines.last?.id { Divider().padding(.leading, 70) }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    @ViewBuilder
    private func preparationETACard(_ order: DastakV1OrderSnapshot) -> some View {
        if let readyAt = DastakV1OrderPresentation.date(
            order.fulfilmentProgress?.estimatedReadyAt
        ) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let late = order.fulfilmentProgress?.runningLate == true || context.date > readyAt
                HStack(alignment: .center, spacing: MarketplaceSpacing.compact) {
                    Image(systemName: late ? "clock.badge.exclamationmark" : "clock.fill")
                        .font(.title3)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .frame(width: 42, height: 42)
                        .background(
                            MarketplaceColors.dastakAccentSoft.color,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(late ? "Taking a little longer" : "Preparation estimate")
                            .font(.headline)
                        Text(late
                             ? "Your order stays in preparation until it is genuinely ready."
                             : "Expected around \(readyAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(late ? "We’re watching" : preparationCountdown(readyAt, at: context.date))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(late ? Color.secondary : MarketplaceColors.dastakAccent.color)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    @ViewBuilder
    private func deliveryDetails(_ order: DastakV1OrderSnapshot) -> some View {
        if let address = order.deliveryAddress {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                Label(address.label ?? "Delivery address", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Text(DastakV1OrderPresentation.addressLine(address))
                    .font(.subheadline)
                if let recipient = order.recipient {
                    Divider()
                    Label(
                        "\(recipient.name) · \(DastakV1OrderPresentation.phoneNumber(recipient.phoneNumber))",
                        systemImage: "person.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let instructions = address.instructions, !instructions.isEmpty {
                    Label(instructions, systemImage: "text.bubble.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(MarketplaceSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marketplaceFlatSurface()
        }
    }

    private func receiptCard(_ order: DastakV1OrderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                Label(order.paidAt == nil ? "Order summary" : "Bill summary", systemImage: "receipt")
                    .font(.headline)
                Spacer()
                if order.paidAt != nil {
                    ShareLink(item: receiptText(order)) {
                        Label("Share receipt", systemImage: "square.and.arrow.up")
                            .font(.caption.bold())
                    }
                }
            }
            receiptRow("Items", paise: order.price.subtotalPaise)
            if order.price.deliveryFeePaise > 0 {
                receiptRow("Delivery", paise: order.price.deliveryFeePaise)
            }
            if order.price.platformFeePaise > 0 {
                receiptRow("Dastak platform fee", paise: order.price.platformFeePaise)
            }
            if order.price.taxPaise > 0 {
                receiptRow("Taxes", paise: order.price.taxPaise)
            }
            if order.price.discountPaise > 0 {
                receiptRow("Discount", paise: -order.price.discountPaise)
            }
            Divider()
            receiptRow(receiptTotalLabel(order), paise: order.price.totalPaise, emphasized: true)
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Text(customerPaymentTitle(order))
                    .font(.footnote.weight(.semibold))
                if let paidAt = DastakV1OrderPresentation.date(order.paidAt) {
                    Text(paidAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(order.launchPayment?.committedAt == nil
                         ? "Confirm the order; there is no charge now"
                         : "Pay the delivery partner by UPI or cash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: MarketplaceSpacing.compact) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Order number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(order.displayOrderNumber)
                        .font(.caption.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: MarketplaceSpacing.small)
                Button {
                    copyToPasteboard(order.displayOrderNumber)
                    model.ordersActionMessage = "Order number copied."
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("Copy order number \(order.displayOrderNumber)")
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .accessibilityElement(children: .contain)
    }

    private func receiptRow(
        _ label: String,
        paise: Int,
        emphasized: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .headline : .subheadline)
            Spacer()
            Text(DastakFormatting.money(Money(paise: paise)))
                .font(emphasized
                      ? .headline.monospacedDigit()
                      : .subheadline.monospacedDigit())
        }
    }

    private func timelineCard(_ order: DastakV1OrderSnapshot) -> some View {
        let entries: [(String, String?)] = [
            ("Order placed", order.submittedAt ?? order.createdAt),
            ("Basket secured", order.fullySecuredAt),
            ("Order confirmed", order.launchPayment?.committedAt),
            ("Payment collected", order.launchPayment?.collectedAt ??
             (order.launchPayment == nil ? order.paidAt : nil)),
            ("Out for delivery", order.delivery?.outForDeliveryAt),
            ("Delivered", order.deliveredAt ?? order.delivery?.deliveredAt),
        ]
        return VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Timeline")
                .font(.headline)
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                if let date = DastakV1OrderPresentation.date(entry.1) {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        Circle()
                            .fill(MarketplaceColors.dastakAccent.color)
                            .frame(width: 8, height: 8)
                        Text(entry.0)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let current = currentTimelineEntry(order.status) {
                HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.compact) {
                    Circle()
                        .strokeBorder(MarketplaceColors.dastakAccent.color, lineWidth: 2)
                        .frame(width: 9, height: 9)
                    Text(current.label)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: MarketplaceSpacing.small)
                    Text(current.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
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
                        Text("\(issueCategoryTitle(issue.category)) · \(DastakV1OrderPresentation.displayState(issue.status))")
                            .font(.subheadline.weight(.semibold))
                        Text(issue.resolution ?? "Operations is reviewing your report.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(support.returns) { customerReturn in
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                        Text("Return · \(DastakV1OrderPresentation.displayState(customerReturn.status))")
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
                        "Refund \(DastakV1OrderPresentation.displayState(refund.status).lowercased()) · \(DastakFormatting.money(refund.amount)) to original payment method",
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
            showingCancellationConfirmation = true
        } label: {
            Label("Cancel order", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .controlSize(.large)
    }

    private var supportContactCard: some View {
        Link(destination: URL(string: "https://dastak-customer.vercel.app/support")!) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: "message.fill")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Contact Dastak support")
                        .font(.subheadline.bold())
                    Text("Account, payment or delivery help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
            }
            .padding(MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
        .buttonStyle(.plain)
    }

    private func reorderButton(_ order: DastakV1OrderSnapshot) -> some View {
        Button {
            if model.cart.isEmpty { reorderCurrentOrder() }
            else { showingReorderConfirmation = true }
        } label: {
            Label("Order again", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MarketplacePrimaryButtonStyle())
        .accessibilityHint("Rebuilds this order using products currently available")
    }

    private func reorderCurrentOrder() {
        guard let order = model.activeV1Order else { return }
        if model.reorder(order).openedBasket {
            if isPresentedModally { dismiss() }
            openCart()
        }
    }

    private func receiptText(_ order: DastakV1OrderSnapshot) -> String {
        var lines = [
            "Dastak receipt",
            "Order \(order.displayOrderNumber)",
            "",
        ]
        lines.append(contentsOf: order.lines.map {
            "\($0.quantity) × \($0.name) — \(DastakFormatting.money(Money(paise: $0.lineTotalPaise)))"
        })
        lines.append(contentsOf: [
            "",
            "Items: \(DastakFormatting.money(Money(paise: order.price.subtotalPaise)))",
            "Delivery: \(DastakFormatting.money(Money(paise: order.price.deliveryFeePaise)))",
            "Dastak platform fee: \(DastakFormatting.money(Money(paise: order.price.platformFeePaise)))",
            "Taxes: \(DastakFormatting.money(Money(paise: order.price.taxPaise)))",
        ])
        if order.price.discountPaise > 0 {
            lines.append("Discount: −\(DastakFormatting.money(Money(paise: order.price.discountPaise)))")
        }
        lines.append("Total: \(DastakFormatting.money(order.price.total))")
        if let collectedAt = DastakV1OrderPresentation.date(order.launchPayment?.collectedAt) {
            let method = order.launchPayment?.collectionMethod?.rawValue ?? "at delivery"
            lines.append("Payment collected by \(method): \(collectedAt.formatted(date: .abbreviated, time: .shortened))")
        } else if let paidAt = DastakV1OrderPresentation.date(order.paidAt) {
            lines.append("Payment confirmed: \(paidAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let address = order.deliveryAddress {
            lines.append("Delivered to: \(DastakV1OrderPresentation.addressLine(address))")
        }
        return lines.joined(separator: "\n")
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
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

    private func paymentTimeRemaining(
        _ payment: DastakV1LaunchPayment,
        at date: Date
    ) -> String {
        guard let value = payment.reservationExpiresAt,
              let expiry = DastakV1OrderPresentation.date(value) else {
            return "Reservation active"
        }
        let remaining = max(0, Int(expiry.timeIntervalSince(date).rounded(.up)))
        return String(format: "%d:%02d to confirm · no charge now", remaining / 60, remaining % 60)
    }

    private func launchCollectionMessage(_ launch: DastakV1LaunchPayment) -> String {
        switch launch.state {
        case .paymentCollected:
            let method = launch.collectionMethod.map { $0 == .cash ? "cash" : "UPI" }
            return "Your delivery partner recorded the doorstep payment\(method.map { " by \($0)" } ?? ""). The verified delivery can now be completed."
        case .collectionRetryNeeded:
            return "The last collection was not completed. Your delivery partner can safely retry before delivery."
        default:
            return "When the rider arrives with every package, verify your delivery PIN first. The rider then records the package photo and collects payment by UPI or cash."
        }
    }

    private func customerPaymentTitle(_ order: DastakV1OrderSnapshot) -> String {
        guard let launch = order.launchPayment else {
            return order.paidAt == nil ? "Payment" : "Payment confirmed"
        }
        switch launch.state {
        case .paymentCollected:
            return "Payment collected at delivery"
        case .collectionRetryNeeded:
            return "Collection needs retry"
        case .paymentDueAtDelivery:
            return "Due at delivery"
        case .readyToConfirm:
            return "Confirm now · no charge now"
        case .reservationExpired:
            return "Reservation expired"
        case .notApplicable:
            return order.paidAt == nil ? "Payment" : "Payment confirmed"
        }
    }

    private func assuranceSymbol(_ status: DastakV1OrderStatus) -> String {
        switch status {
        case .fulfilmentFailure: "exclamationmark.shield.fill"
        case .unavailable, .paymentExpired, .cancelledPrepayment, .cancelled: "exclamationmark.circle.fill"
        default: "checkmark.shield.fill"
        }
    }

    private func openDestinationInMaps(_ address: DastakV1DeliveryAddressInput) {
        let coordinate = CLLocationCoordinate2D(
            latitude: address.latitude,
            longitude: address.longitude
        )
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = address.label ?? "Dastak delivery address"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
    }


    private func preparationCountdown(_ readyAt: Date, at now: Date) -> String {
        let minutes = max(1, Int((readyAt.timeIntervalSince(now) / 60.0).rounded(.up)))
        return minutes == 1 ? "About 1 min" : "About \(minutes) min"
    }

    private func receiptTotalLabel(_ order: DastakV1OrderSnapshot) -> String {
        if order.paidAt != nil { return "Total paid" }
        if order.launchPayment?.committedAt != nil { return "Due at delivery" }
        if [.fullySecured, .awaitingPayment].contains(order.status) { return "Order total" }
        return "Current basket total"
    }

    private func currentTimelineEntry(
        _ status: DastakV1OrderStatus
    ) -> (label: String, status: String)? {
        switch status {
        case .created, .matching: ("Finding every item", "In progress")
        case .fullySecured: ("Ready to confirm", "Secured")
        case .awaitingPayment: ("Ready to confirm", "Action needed")
        case .paid, .preparing: ("Preparing", "In progress")
        case .pickupInProgress: ("Picking up", "In progress")
        case .outForDelivery: ("On the way", "In progress")
        case .delivered, .unavailable, .paymentExpired,
             .cancelledPrepayment, .cancelled, .fulfilmentFailure: nil
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

}

private struct DastakLaunchPaymentView: View {
    @ObservedObject var model: DastakCustomerModel
    let order: DastakV1OrderSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                        Text("SECURED CHECKOUT")
                            .font(.caption.bold())
                            .tracking(1.2)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text("Confirm your order")
                            .font(.largeTitle.bold())
                        Text("Your full basket is reserved. There is no charge now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AUTHORITATIVE TOTAL")
                                .font(.caption2.bold())
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.68))
                            Text(DastakFormatting.money(order.launchPayment?.amount ?? order.price.total))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    }
                    .padding(MarketplaceSpacing.large)
                    .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    reservationCard

                    if let address = order.deliveryAddress {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("DELIVER TO")
                                    .font(.caption2.bold())
                                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                Text(DastakV1OrderPresentation.addressLine(address))
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        }
                        .padding(MarketplaceSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .marketplaceFlatSurface()
                    }

                    HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Pay via UPI/Cash on Delivery")
                                .font(.headline)
                            Text("Pay the delivery partner at your doorstep by UPI or cash. No charge now.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(MarketplaceSpacing.large)
                    .background(MarketplaceColors.dastakAccentSoft.color)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(MarketplaceColors.dastakAccent.color.opacity(0.55), lineWidth: 2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Selected option. Pay via UPI or cash on delivery. No charge now.")

                    Label(
                        "Confirmation starts preparation immediately. The assigned rider records the doorstep collection before delivery.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if let error = model.v1OrderErrorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(MarketplaceColors.destructive.color)
                            .padding(MarketplaceSpacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .marketplaceFlatSurface()
                    }

                    Button {
                        Task {
                            if await model.retryPayment(for: order) { dismiss() }
                        }
                    } label: {
                        HStack {
                            if model.isCheckingOut { ProgressView().tint(.white) }
                            Text(model.isCheckingOut ? "Confirming order…" : "Confirm order")
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(model.isCheckingOut || order.launchPayment?.canCommit != true || isExpired)

                    if isExpired {
                        Button("Reservation expired — refresh order") { dismiss() }
                            .buttonStyle(MarketplaceSecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: 620)
                .padding(MarketplaceSpacing.medium)
                .frame(maxWidth: .infinity)
            }
            .marketplacePage()
            .navigationTitle("Payment option")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(model.isCheckingOut)
                }
            }
            .interactiveDismissDisabled(model.isCheckingOut)
        }
    }

    private var reservationCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isExpired(at: context.date) ? "Reservation expired" : "Full basket secured")
                        .font(.headline)
                    Text(isExpired(at: context.date) ? "Close and refresh the order." : reservationText(at: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isExpired(at: context.date) ? "clock.badge.exclamationmark" : "shippingbox.fill")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            .padding(MarketplaceSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .marketplaceFlatSurface()
            .accessibilityElement(children: .combine)
        }
    }

    private var isExpired: Bool { isExpired(at: .now) }

    private func isExpired(at date: Date) -> Bool {
        guard order.launchPayment?.reservationState != .expired,
              let value = order.launchPayment?.reservationExpiresAt,
              let expiry = DastakV1OrderPresentation.date(value) else { return true }
        return expiry <= date
    }

    private func reservationText(at date: Date) -> String {
        guard let value = order.launchPayment?.reservationExpiresAt,
              let expiry = DastakV1OrderPresentation.date(value) else { return "Reservation active" }
        let seconds = max(0, Int(expiry.timeIntervalSince(date).rounded(.up)))
        return String(format: "%d:%02d remaining to confirm", seconds / 60, seconds % 60)
    }
}

private enum DastakIssuePhotoError: Error {
    case invalid
}
