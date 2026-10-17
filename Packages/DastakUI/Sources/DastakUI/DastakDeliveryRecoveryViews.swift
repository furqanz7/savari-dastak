import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import MarketplaceDesignSystem
import MarketplaceInfrastructure

struct DastakDeliveryRecoveryPanel: View {
    @ObservedObject var operations: DastakDeliveryOperations
    let refresh: () async -> Void
    var body: some View {
        if operations.message != nil || operations.pending != nil || !operations.restored {
        VStack(alignment: .leading, spacing: 12) {
            if let message = operations.message { Text(message).font(.footnote) }
            if let pending = operations.pending {
                Label("Saved action awaiting recovery", systemImage: "lock.shield").font(.headline)
                Text(pending.operation == .collection ? "Confirming doorstep payment" : "Confirming your delivery update")
                    .font(.caption)
                Text("Reconnecting automatically using your saved action. You can also retry now. Keep the packages secure until the result is confirmed.")
                    .font(.footnote)
                Button(operations.busy ? "Checking saved action…" : pending.acknowledged ? "Finish local recovery" : "Retry saved action") {
                    Task { await operations.retry(); await refresh() }
                }.disabled(operations.busy)
                    .accessibilityIdentifier("delivery.recovery.retry")
            } else if !operations.restored {
                Button("Retry recovery storage") { Task { await operations.restore() } }.disabled(operations.busy)
            }
        }.padding(14).marketplaceFlatSurface()
        }
    }
}

struct DastakReturnMissionCard: View {
    @Environment(\.marketplaceDemonstration) private var demonstration
    @ObservedObject var operations: DastakDeliveryOperations
    let mission: DastakV1ReturnMission
    let refresh: () async -> Void
    @EnvironmentObject private var tracker: DastakActiveDeliveryTracker
    @Environment(\.scenePhase) private var scenePhase
    @State private var code = ""
    @State private var confirmed = false
    @State private var photo: PhotosPickerItem?
    @State private var review: DastakDeliveryCommand.Operation?
    @State private var photoMessage: String?
    private var nextStop: DastakV1ReturnMission.Stop? {
        mission.stops.sorted { $0.sequence < $1.sequence }.first { $0.status != "COMPLETED" }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 16) {
                Label("Return mission", systemImage: "arrow.uturn.backward.circle.fill").font(.title2.bold())
                Text("Order ID: \(mission.orderId.uuidString)").font(.caption)
                Text(DastakMerchantReceiptPresentation.label(mission.status)).font(.headline)
                Text("\(mission.packageCount) packages · Keep every package secure until each merchant verifies receipt.")
                if !operations.fresh(at: context.date) {
                    Text("Return information needs refreshing. Controls remain locked.").font(.footnote).foregroundStyle(.orange)
                }
                if let message = tracker.statusMessage, tracker.trackingID == mission.id {
                    Label(message, systemImage: "location.circle").font(.footnote)
                }
                if mission.status == "ASSIGNED" || mission.status == "AT_CUSTOMER" {
                    Text(mission.customerDestination.address.display).font(.subheadline)
                    route(latitude: mission.customerDestination.address.latitude, longitude: mission.customerDestination.address.longitude)
                    if mission.status == "ASSIGNED" { action("Arrived at customer", .arriveCustomer, now: context.date) }
                    if mission.status == "AT_CUSTOMER" {
                        Text("1. Check all packages · 2. Take photo · 3. Ask for return PIN")
                            .font(.footnote.bold())
                        if demonstration {
                            Button("Use sample return photo") {
                                Task {
                                    await operations.submitReturn(.evidence, mission: mission,
                                        photo: Data([0x44, 0x45, 0x4d, 0x4f]), contentType: "image/jpeg")
                                    await refresh()
                                }
                            }.disabled(!operations.canReturn(.evidence, mission: mission) || operations.busy)
                        } else {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(mission.evidence.isEmpty ? "Add return package photo" : "Replace return package photo", systemImage: "camera")
                        }.disabled(!operations.canReturn(.evidence, mission: mission) || operations.busy)
                        }
                        if !mission.evidence.isEmpty { Label("Return evidence recorded", systemImage: "checkmark.shield") }
                        if let photoMessage { Text(photoMessage).font(.footnote) }
                        Toggle("All \(mission.packageCount) return packages are present and accounted for", isOn: $confirmed)
                        DastakHandoffCodeField(title: "Customer return PIN", length: 6, code: $code)
                        action("Verify return pickup", .pickup, now: context.date)
                    }
                } else if mission.status == "RETURNING_TO_MERCHANTS" {
                    ForEach(mission.stops.sorted { $0.sequence < $1.sequence }) { stop in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(stop.sequence). \(stop.branch.displayName)").font(.headline)
                            Text("\(stop.packageCount) packages · \(DastakMerchantReceiptPresentation.label(stop.status))")
                            Text(stop.branch.address.display).font(.footnote)
                            if stop.id == nextStop?.id {
                                route(latitude: stop.branch.location?.latitude, longitude: stop.branch.location?.longitude)
                                if stop.status == "PENDING" { action("Arrived at return branch", .arriveStop, now: context.date) }
                                if stop.status == "ARRIVED" {
                                    Toggle("All \(stop.packageCount) packages for this branch are present", isOn: $confirmed)
                                    DastakHandoffCodeField(title: "Merchant return receipt code", length: 6, code: $code)
                                    action("Verify merchant receipt", .receipt, now: context.date)
                                }
                                if stop.verificationStatus == "BLOCKED" { Text("Verification is blocked. Keep custody and contact Operations.").foregroundStyle(.orange) }
                            }
                        }.padding(12).marketplaceFlatSurface()
                    }
                } else { Text("Operations must review this return state. No handoff actions are available.") }
                if mission.pickupVerification.status == "BLOCKED" {
                    Text("Return PIN attempts are blocked. Keep packages secure and contact Operations.").foregroundStyle(.orange)
                }
                Button("Refresh return") { Task { await refresh() } }
            }.padding(18).marketplaceFlatSurface()
        }
        .disabled(scenePhase != .active)
        .confirmationDialog("Confirm return action?", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
            if let review {
                Button("Confirm") {
                    let stopID = [.arriveStop, .receipt].contains(review) ? nextStop?.id : nil
                    let savedCode = code; let savedConfirmation = confirmed
                    Task {
                        await operations.submitReturn(review, mission: mission, stopID: stopID,
                            confirmed: savedConfirmation, code: [.pickup, .receipt].contains(review) ? savedCode : nil)
                        code = ""; confirmed = false; await refresh()
                    }
                    self.review = nil
                }
            }
            Button("Cancel", role: .cancel) { review = nil }
        } message: { Text("Follow the shown branch, package count and PIN steps. Verification transfers custody; do not hand over partial packages.") }
        .onChange(of: mission.version) { _, _ in code = ""; confirmed = false; review = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { code = ""; confirmed = false; review = nil } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty, data.count <= 10 * 1_024 * 1_024,
                          let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                          let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String),
                          let mime = type.preferredMIMEType, ["image/jpeg", "image/png", "image/heic"].contains(mime) else {
                        photoMessage = "Choose a clear JPG, PNG or HEIC package photo up to 10 MB."; return
                    }
                    await operations.submitReturn(.evidence, mission: mission, photo: data, contentType: mime)
                    await refresh()
                } catch { photoMessage = "The photo could not be read. No handoff was completed." }
                photo = nil
            }
        }
    }
    private func action(_ title: String, _ operation: DastakDeliveryCommand.Operation, now: Date) -> some View {
        Button(title) { review = operation }.buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(!operations.canReturn(operation, mission: mission,
                stopID: [.arriveStop, .receipt].contains(operation) ? nextStop?.id : nil,
                confirmed: confirmed, code: code, now: now))
    }
    @ViewBuilder private func route(latitude: Double?, longitude: Double?) -> some View {
        if let latitude, let longitude, latitude.isFinite, longitude.isFinite,
           abs(latitude) <= 90, abs(longitude) <= 180,
           let url = URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=d") {
            Link("Navigate to this destination", destination: url).font(.subheadline.bold())
        } else { Text("Destination coordinates unavailable. Refresh or contact Operations.").font(.footnote) }
    }
}

struct DastakDeliveryProblemPanel: View {
    @ObservedObject var operations: DastakDeliveryOperations
    let mission: DastakV1DeliveryMissionSnapshot
    let current: DastakV1DeliveryMissionSnapshot?
    let fresh: Bool
    let refresh: () async -> Void
    @State private var reason = ""
    @State private var review: DastakDeliveryCommand.Operation?
    var body: some View {
        if mission.mustUseDeliveryRecovery {
            VStack(alignment: .leading, spacing: 12) {
                Text("Delivery problem").font(.headline)
                Text("Keep every package secure. Reporting asks Operations to help; it does not complete or refund this order.").font(.footnote)
                TextField("Explain what happened", text: $reason, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("Customer unreachable") { review = .unreachable }
                    .disabled(!(3...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count))
                Button("Report another problem") { review = .problem }
                    .disabled(!(3...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count))
            }.disabled(operations.blocksActions || !fresh)
                .padding(16).marketplaceFlatSurface()
                .confirmationDialog("Report this problem to Operations?", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
                    if let review {
                        Button("Send report") {
                            let savedReason = reason
                            Task { await operations.report(review, mission: mission, current: current, reason: savedReason, fresh: fresh); await refresh() }
                            self.review = nil
                        }
                    }
                    Button("Cancel", role: .cancel) { review = nil }
                }
        }
    }
}

struct DastakDeliveryHistoryView: View {
    @ObservedObject var operations: DastakDeliveryOperations
    let services: MarketplaceAuthenticatedServices
    var standalone = false
    @State private var expanded = false
    @State private var orderTarget: DastakDeliveryOrderTarget?
    var body: some View {
        Group {
            if standalone { records }
            else {
                DisclosureGroup("Recent work", isExpanded: $expanded) { records.padding(.top, 12) }
                    .padding(16).marketplaceFlatSurface()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: expanded) { _, value in if value { Task { await operations.refreshHistory() } } }
        .sheet(item: $orderTarget) { target in
            DastakDeliveryOrderDetailView(target: target, client: .init(functions: services.functions))
        }
    }
    private var records: some View {
        DastakDeliveryHistoryContent(items: operations.history, current: operations.historyCurrent,
            loading: operations.historyLoading,
            refresh: { Task { await operations.refreshHistory() } },
            open: { orderTarget = .init(kind: $0.kind, workID: $0.workId) })
    }
}

private enum DastakDeliveryHistoryPalette {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? MarketplaceColors.accent(for: scheme) : Color(red: 0.47, green: 0.34, blue: 0.15)
    }
    static func secondary(_ scheme: ColorScheme) -> Color {
        MarketplaceColors.primaryText(for: scheme).opacity(0.68)
    }
}

private struct DastakDeliveryHistoryContent: View {
    let items: [DastakDeliveryWorkHistory.Item]
    let current: Bool
    let loading: Bool
    let refresh: () -> Void
    let open: (DastakDeliveryWorkHistory.Item) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent activity").font(.title2.bold())
                    Text("Deliveries, returns & parcels")
                        .font(.subheadline).foregroundStyle(DastakDeliveryHistoryPalette.secondary(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: refresh) {
                    Group {
                        if loading { ProgressView() }
                        else { Image(systemName: "arrow.clockwise").font(.body.weight(.semibold)) }
                    }.frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.bordered).buttonBorderShape(.circle)
                .tint(DastakDeliveryHistoryPalette.accent(scheme))
                .disabled(loading)
                .accessibilityLabel(loading ? "Refreshing history" : "Refresh history")
                .accessibilityIdentifier("delivery.history.refresh")
            }

            if !current && !loading {
                Label(items.isEmpty ? "Couldn't load history. Tap refresh to try again."
                      : "Couldn't refresh. Showing your last saved activity.", systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(DastakDeliveryHistoryPalette.accent(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("delivery.history.unavailable")
            }

            if items.isEmpty {
                if loading {
                    HStack(spacing: 12) { ProgressView(); Text("Loading recent activity…") }
                        .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 36)
                } else if current {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").font(.largeTitle)
                            .foregroundStyle(DastakDeliveryHistoryPalette.accent(scheme)).accessibilityHidden(true)
                        Text("A fresh start").font(.headline)
                        Text("Your completed deliveries and other recent work will appear here.")
                            .font(.subheadline).foregroundStyle(DastakDeliveryHistoryPalette.secondary(scheme))
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(28)
                        .accessibilityIdentifier("delivery.history.empty")
                }
            } else {
                ForEach(items) { item in
                    DastakDeliveryHistoryCard(item: item, open: { open(item) })
                }
            }

            Label("Up to 30 recent records. For balances and payouts, open Earnings.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(DastakDeliveryHistoryPalette.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.top, 2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DastakDeliveryHistoryCard: View {
    let item: DastakDeliveryWorkHistory.Item
    let open: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { DastakDeliveryHistoryPalette.accent(scheme) }
    private var statusColor: Color {
        switch DastakDeliveryHistoryPresentation.tone(item.outcome) {
        case .success: scheme == .dark ? Color(red: 0.66, green: 0.83, blue: 0.72) : Color(red: 0.23, green: 0.39, blue: 0.29)
        case .cancelled: scheme == .dark ? Color(red: 0.90, green: 0.66, blue: 0.58) : Color(red: 0.56, green: 0.25, blue: 0.19)
        case .neutral: accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { kind; Spacer(minLength: 16); status }
                VStack(alignment: .leading, spacing: 12) { kind; status }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.reference).font(.subheadline.weight(.semibold).monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(DastakMerchantReceiptPresentation.date(item.endedAt))
                    .font(.caption).foregroundStyle(DastakDeliveryHistoryPalette.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let packages = DastakDeliveryHistoryPresentation.packages(item.packageCount) {
                Label(packages, systemImage: "shippingbox")
                    .font(.subheadline).foregroundStyle(DastakDeliveryHistoryPalette.secondary(scheme))
            }
            if let payout = DastakDeliveryHistoryPresentation.payout(item.payoutPaise) {
                Text(payout).font(.subheadline.weight(.medium)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(MarketplaceColors.divider(for: scheme)).frame(height: 1)
                .accessibilityHidden(true)
            Button(action: open) {
                HStack(spacing: 12) {
                    Text("View order").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(accent)
                .accessibilityLabel("View full order \(item.reference)")
                .accessibilityIdentifier("delivery.history.order.\(item.id)")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(MarketplaceColors.surface(for: scheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(MarketplaceColors.divider(for: scheme), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private var kind: some View {
        HStack(spacing: 10) {
            Image(systemName: DastakDeliveryHistoryPresentation.symbol(item.kind))
                .font(.body.weight(.medium)).foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            Text(DastakDeliveryHistoryPresentation.kind(item.kind)).font(.headline)
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Image(systemName: DastakDeliveryHistoryPresentation.tone(item.outcome) == .success ? "checkmark.circle.fill"
                  : DastakDeliveryHistoryPresentation.tone(item.outcome) == .cancelled ? "xmark.circle.fill" : "circle.fill")
                .accessibilityHidden(true)
            Text(DastakDeliveryHistoryPresentation.outcome(item.outcome))
        }.font(.caption.weight(.semibold)).foregroundStyle(statusColor)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(statusColor.opacity(0.10), in: Capsule())
            .fixedSize(horizontal: true, vertical: true)
    }
}

#if DEBUG
/// Isolated history render: no authentication, requests, order actions or real data.
public struct DastakDeliveryHistoryPreview: View {
    public init() {}
    public var body: some View {
        TabView(selection: .constant(1)) {
            Color.clear.tabItem { Label("Deliveries", systemImage: "shippingbox") }.tag(0)
            NavigationStack {
                ScrollView {
                    DastakDeliveryHistoryContent(items: Self.items, current: true, loading: false,
                        refresh: {}, open: { _ in })
                        .padding(16).padding(.bottom, 24)
                }
                .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-DastakHistoryFooterPreview") ? .bottom : .top)
                .navigationTitle("History").dastakInlineNavigationTitle().marketplacePage()
            }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(1)
            Color.clear.tabItem { Label("Earnings", systemImage: "indianrupeesign.circle") }.tag(2)
            Color.clear.tabItem { Label("Account", systemImage: "person") }.tag(3)
        }.tint(MarketplaceColors.dastakAccent.color)
    }
    private static var items: [DastakDeliveryWorkHistory.Item] {
        let data = Data("""
        {"items":[
          {"kind":"V1_DELIVERY","workId":"00000000-0000-0000-0000-000000000001","reference":"DSK-261015-00000111","status":"COMPLETED","startedAt":"2026-10-15T19:30:00Z","endedAt":"2026-10-15T19:58:00Z","packageCount":1,"outcome":"COMPLETED"},
          {"kind":"V1_DELIVERY","workId":"00000000-0000-0000-0000-000000000002","reference":"DSK-261015-00000110","status":"CANCELLED","startedAt":"2026-10-15T19:00:00Z","endedAt":"2026-10-15T19:55:00Z","packageCount":1,"outcome":"CANCELLED"},
          {"kind":"RETURN","workId":"00000000-0000-0000-0000-000000000003","reference":"DSK-261015-00000109","status":"COMPLETED","startedAt":"2026-10-15T18:00:00Z","endedAt":"2026-10-15T18:55:00Z","packageCount":2,"payoutPaise":1500,"outcome":"RETURNED"}
        ]}
        """.utf8)
        return (try? JSONDecoder().decode(DastakDeliveryWorkHistory.self, from: data).items) ?? []
    }
}
#endif
