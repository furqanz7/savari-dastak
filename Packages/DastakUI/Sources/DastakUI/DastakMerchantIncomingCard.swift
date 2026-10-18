import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakMerchantLineList: View {
    let lines: [DastakV1MerchantLine]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines) { line in
                DastakMerchantAdaptiveRow {
                  HStack(alignment: .top, spacing: 12) {
                    Text("\(line.quantity)×").font(.subheadline.bold().monospacedDigit())
                        .frame(minWidth: 30, minHeight: 30)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.name).font(.subheadline.weight(.medium))
                        let detail = [line.variant, line.packSize].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                        if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        if let options = line.selection?.options, !options.isEmpty {
                            Text(options.map { "\($0.groupName): \($0.name)" }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                  }.frame(maxWidth: .infinity, alignment: .leading)
                    if let subtotal = line.lineSubtotalPaise {
                        Text(DastakFormatting.money(Money(paise: subtotal)))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary).fixedSize(horizontal: true, vertical: true)
                    }
                }
            }
        }.padding(.vertical, 4)
    }
}

/// Confirmation cards retain every line. Only already-accepted work uses this
/// compact summary; all hidden lines remain reachable without a network read.
struct DastakMerchantLineSummary: View {
    let lines: [DastakV1MerchantLine]
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DastakMerchantLineList(lines: expanded ? lines : Array(lines.prefix(3)))
            if lines.count > 3 {
                MarketplaceFeedbackButton(expanded ? "Show fewer items" : "Show all \(lines.count) items", haptic: .selection) { expanded.toggle() }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            }
        }
    }
}

struct DastakMerchantIncomingCard: View {
    let number: String
    let branch: String
    let lines: [DastakV1MerchantLine]
    let productSubtotalPaise: Int?
    let expiresAt: String?
    let prepOptions: [Int]
    let isFood: Bool
    let subset: Bool
    let busy: Bool
    let canRespond: Bool
    var revision: Int = 0
    var openDetail: (() -> Void)? = nil
    let respond: (Bool, Int, String?) -> Void
    @State private var confirmedItems = false
    @State private var prepMinutes = 15
    @State private var showingDecline = false
    @State private var declineReason = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = DastakMerchantOrderClock.isExpired(expiresAt, now: context.date)
            VStack(alignment: .leading, spacing: 16) {
                DastakMerchantAdaptiveRow {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(isFood ? "NEW FOOD ORDER" : "NEW REQUEST", systemImage: isFood ? "fork.knife" : "bell.badge")
                            .font(.caption.weight(.bold)).tracking(1)
                            .foregroundStyle(MarketplaceColors.accent(for: scheme))
                        Text(number).font(.title3.weight(.bold))
                        Text(branch).font(.caption).foregroundStyle(.secondary)
                    }
                    if let expiresAt {
                        Text(expired ? "Expired" : DastakMerchantOrderClock.remaining(expiresAt, now: context.date))
                            .font(.subheadline.bold().monospacedDigit())
                            .padding(9).background(.orange.opacity(0.12), in: Capsule())
                            .accessibilityLabel(expired ? "Request expired" : "Response time remaining")
                    }
                }
                if subset {
                    Label("Confirm only the items listed below.", systemImage: "square.stack.3d.up")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DastakMerchantLineList(lines: lines)
                if let productSubtotalPaise {
                    HStack {
                        Text("Product value")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(DastakFormatting.money(Money(paise: productSubtotalPaise)))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Product value \(DastakFormatting.money(Money(paise: productSubtotalPaise))). Delivery and platform fees are not shown to the merchant.")
                }
                Divider()
                Toggle(isFood ? "I can prepare this exact selection" : "I have physically checked every item", isOn: $confirmedItems)
                    .font(.subheadline.weight(.medium))
                    .tint(MarketplaceColors.accent(for: scheme))
                DastakMerchantAdaptiveRow {
                    Label("Preparation time", systemImage: "timer").font(.subheadline)
                    Picker("Preparation time", selection: $prepMinutes) {
                        ForEach(options, id: \.self) { Text("\($0) min").tag($0) }
                    }.pickerStyle(.menu).frame(minHeight: 44)
                }
                DastakMerchantAdaptiveRow {
                    MarketplaceFeedbackButton {
                        respond(true, prepMinutes, nil)
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text("Accept order")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DastakMerchantActionStyle(primary: true))
                    .disabled(busy || expired || !canRespond || !confirmedItems)
                    MarketplaceFeedbackButton("Decline", role: .destructive) { showingDecline = true }
                        .buttonStyle(DastakMerchantActionStyle())
                        .disabled(busy || expired || !canRespond)
                }
                Text("Acceptance holds the items. Start packing when the order moves to Preparing.")
                    .font(.caption).foregroundStyle(.secondary)
                if let openDetail { Divider(); DastakMerchantDetailLink(action: openDetail) }
            }
            .padding(20).marketplaceFlatSurface()
            .overlay(RoundedRectangle(cornerRadius: MarketplaceMetrics.compactCornerRadius).strokeBorder(MarketplaceColors.accent(for: scheme).opacity(0.35), lineWidth: 1))
        }
        .onAppear { prepMinutes = options.contains(15) ? 15 : options.first ?? 15 }
        .onChange(of: revision) { _, _ in
            confirmedItems = false
            showingDecline = false
            if !options.contains(prepMinutes) { prepMinutes = options.first ?? 15 }
        }
        .alert("Decline this request?", isPresented: $showingDecline) {
            if isFood { TextField("Reason", text: $declineReason) }
            Button("Keep request", role: .cancel) {}
            Button("Decline request", role: .destructive) {
                respond(false, prepMinutes, declineReason.trimmingCharacters(in: .whitespacesAndNewlines))
            }.disabled(isFood && declineReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        } message: {
            Text(isFood ? "Tell us why you cannot prepare this order." : "The system will continue looking for another available merchant.")
        }
    }

    private var options: [Int] {
        let valid = prepOptions.filter { (1...240).contains($0) }
        return valid.isEmpty ? [10, 15, 20, 30] : Array(Set(valid)).sorted()
    }
}

enum DastakMerchantOrderClock {
    static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func isExpired(_ value: String?, now: Date) -> Bool {
        guard let value, let expiry = date(value) else { return false }
        return expiry <= now
    }
    static func remaining(_ value: String, now: Date) -> String {
        guard let expiry = date(value) else { return "Awaiting update" }
        let seconds = max(0, Int(ceil(expiry.timeIntervalSince(now))))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
