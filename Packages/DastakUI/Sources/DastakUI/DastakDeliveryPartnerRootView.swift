import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct DastakDeliveryPartnerWorkspaceView: View {
    @ObservedObject private var model: DastakDeliveryPartnerModel
    @ObservedObject private var operations: DastakDeliveryOperations
    @StateObject private var locationManager = DastakLocationManager()
    @State private var handoffCode = ""
    @State private var pendingOnlineRequest = false
    @State private var orderTarget: DastakDeliveryOrderTarget?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var activeTracker: DastakActiveDeliveryTracker
    @Environment(\.colorScheme) private var colorScheme
    private let services: MarketplaceAuthenticatedServices
    private let refreshToken: Int

    init(services: MarketplaceAuthenticatedServices, model: DastakDeliveryPartnerModel, operations: DastakDeliveryOperations, refreshToken: Int = 0) {
        self.services = services
        self.refreshToken = refreshToken
        self.operations = operations
        self.model = model
    }

    var body: some View {
        deliveryWorkspace
        .sheet(item: $orderTarget) { target in
            DastakDeliveryOrderDetailView(target: target, client: .init(functions: DastakDeliveryFunctionClient(base: services.functions)))
        }
        .marketplacePage()
        .task(id: refreshToken) {
            guard refreshToken > 0 else { return }
            await model.recoverDesk()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, !services.isDemonstration, model.isOnline, scenePhase == .active else { continue }
                locationManager.requestLocation()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { handoffCode = "" }
            guard phase == .active else { return }
            Task { await model.recoverDesk(force: false) }
        }
        .onReceive(locationManager.$location) { location in
            guard let location else { return }
            if pendingOnlineRequest {
                pendingOnlineRequest = false
                Task { await model.setAvailability(online: true, location: location) }
            } else if model.isOnline {
                Task { await model.publishLocation(location) }
            }
        }
        .onReceive(activeTracker.$returnMission) { operations.adoptTracked($0) }
        .onReceive(activeTracker.$mission) { model.adoptTrackedMission($0) }
        .onReceive(operations.$confirmedSnapshot) { model.applyConfirmedAction($0) }
        .onReceive(operations.$busy) { activeTracker.actionInFlight = $0 }
        .onDisappear { activeTracker.actionInFlight = false }
        .onReceive(locationManager.$errorMessage) { error in
            if error != nil { pendingOnlineRequest = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.notification.orderOpened"))) { event in
            if event.userInfo?["entityType"] as? String == "delivery" { Task { await model.refresh() } }
        }
        .alert(
            "Dastak",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var deliveryWorkspace: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    partnerHeader
                    deliveryContent
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.recoverDesk() }
            .navigationTitle("Deliveries")
            .dastakInlineNavigationTitle()
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var deliveryContent: some View {
        if model.isLoading {
            DastakLoadingOverlay(title: "Loading delivery queue")
                .frame(maxWidth: .infinity)
                .padding(.top, MarketplaceSpacing.xxLarge)
        } else {
            if let notice = model.noticeMessage {
                DastakPartnerNotice(message: notice) {
                    model.noticeMessage = nil
                }
            }
            if let failure = model.refreshFailure {
                Label(failure, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .padding(16)
                    .marketplaceFlatSurface()
            }
            availability
            DastakAppNotificationStatus()
            DastakDeliveryRecoveryPanel(operations: operations, refresh: { await model.actionFinished() })
            if let destination = model.nextDestination {
                DastakDeliveryDestinationMap(destination: destination, current: model.refreshFailure == nil && model.v1Current)
            }
            if let mission = operations.returnMission {
                fullOrderButton(kind: "RETURN", id: mission.id)
                DastakReturnMissionCard(operations: operations, mission: mission, refresh: { await model.refresh() })
                    .id(mission.id)
            }
            if let mission = model.v1Dispatch?.currentMission, model.v1Dispatch?.returnMission == nil, operations.returnMission == nil {
                fullOrderButton(kind: "V1_DELIVERY", id: mission.id)
                DastakDeliveryTrackingNotice(missionID: mission.id)
                DastakV1MissionCard(
                    mission: mission,
                    busy: model.isBusy,
                    submitting: operations.busy || model.busyOperation != nil,
                    advance: { operation, stopID, packageCount, code, reason in
                        Task {
                            await model.advanceV1Mission(
                                operation,
                                mission: mission,
                                stopID: stopID,
                                packageCount: packageCount,
                                verificationCode: code,
                                reason: reason
                            )
                        }
                    },
                    recordCollection: { outcome, method, reference, reason in
                        Task {
                            await model.recordV1Collection(
                                mission: mission,
                                outcome: outcome,
                                method: method,
                                reference: reference,
                                failureReason: reason
                            )
                        }
                    },
                    captureEvidence: { item in
                        Task { await captureV1Evidence(item, mission: mission) }
                    },
                    captureSampleEvidence: {
                        Task {
                            await operations.submitDelivery(.deliveryEvidence, mission: mission,
                                photo: Data([0x44, 0x45, 0x4d, 0x4f]), contentType: "image/jpeg")
                            await model.actionFinished()
                        }
                    }
                )
                .id(mission.id)
                DastakDeliveryProblemPanel(operations: operations, mission: mission,
                    current: model.v1Dispatch?.currentMission, fresh: model.v1Current,
                    refresh: { await model.refresh() })
            }
            if let currentJob = model.courierDispatch?.currentJob {
                fullOrderButton(kind: "LEGACY_DELIVERY", id: currentJob.assignmentID)
                courierJob(currentJob)
            }
            if let currentJob = model.parcelDispatch?.currentJob {
                fullOrderButton(kind: "PARCEL", id: currentJob.assignmentID)
                parcelJob(currentJob)
            }
            if let offer = model.courierDispatch?.offer, !model.hasActiveJob { courierOffer(offer) }
            if let offer = model.parcelDispatch?.offer, !model.hasActiveJob { parcelOffer(offer) }
            if let offer = model.v1Dispatch?.offer, !model.hasActiveJob {
                v1Offer(offer)
            }
            if hasNoAssignment {
                if let completed = model.v1Dispatch?.completedMission, model.v1Dispatch?.completedLaneCurrent == true {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Delivery completed", systemImage: "checkmark.seal.fill").font(.headline)
                        Text("\(completed.packageCount) packages handed over securely")
                        Text(DastakMerchantReceiptPresentation.date(completed.deliveredAt)).font(.caption).foregroundStyle(.secondary)
                        fullOrderButton(kind: "V1_DELIVERY", id: completed.id)
                    }.padding(16).marketplaceFlatSurface()
                }
                DastakEmptyState(
                    symbol: model.isOnline ? "dot.radiowaves.left.and.right" : "power",
                    title: model.isOnline ? "Ready for your next delivery" : "Your next delivery starts here",
                    message: model.isOnline
                        ? "Nearby offers appear automatically. Keep location and delivery alerts on."
                        : "Go online when you’re ready. Review the pickup and load details before accepting."
                )
                .frame(minHeight: 260)
            }
        }
    }

    private func fullOrderButton(kind: String, id: UUID) -> some View {
        Button { orderTarget = .init(kind: kind, workID: id) } label: {
            Label("View full order", systemImage: "list.bullet.rectangle")
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).marketplaceFlatSurface()
    }

    private var partnerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR DELIVERY DESK")
                    .font(.caption.weight(.bold)).tracking(2)
                    .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                Spacer()
                Text(model.partner?.deliveryMethod.map(DastakPartnerFormatting.method) ?? "Delivery Partner")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(model.hasActiveJob ? "Let’s get it delivered." : "Ready when you are.")
                .font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle().fill(model.refreshFailure == nil ? MarketplaceColors.success.color : MarketplaceColors.warning.color)
                    .frame(width: 6, height: 6)
                Text(model.refreshFailure == nil ? "Updates automatically" : "Reconnecting")
                Spacer()
                Button { Task { await model.recoverDesk() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Refresh delivery and recover saved action")
                .accessibilityIdentifier("delivery.refresh")
                if model.hasActiveJob ? model.criticalReadRunning : model.isRefreshing {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("Syncing")
                    }
                } else {
                    Text(model.refreshFailure == nil ? "Live sync on" : "Retrying")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, MarketplaceSpacing.compact)
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: model.isOnline ? "location.fill" : "location.slash")
                    .font(.title3)
                    .foregroundStyle(
                        model.isOnline
                            ? MarketplaceColors.success.color
                            : Color.secondary
                    )
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pendingOnlineRequest ? "Finding your location…" : model.hasActiveJob ? "Delivery in progress" : model.isOnline ? "You’re online" : "You’re offline")
                        .font(MarketplaceTypography.itemTitle)
                    Text(availabilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if pendingOnlineRequest { ProgressView() }
                Toggle(
                    "Online",
                    isOn: Binding(
                        get: { model.isOnline },
                        set: { online in changeAvailability(online) }
                    )
                )
                .labelsHidden()
                .tint(MarketplaceColors.success.color)
                .disabled(pendingOnlineRequest || model.isBusy || (model.isOnline && model.hasActiveJob))
            }

            if model.hasActiveJob {
                Label("Your current delivery stays available even when new assignments are paused.", systemImage: "shippingbox")
                    .font(.caption).foregroundStyle(.secondary)
                Label("The screen stays awake during active work. You can still lock it manually.", systemImage: "iphone")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.isOnline {
                Label(
                    "Dastak automatically takes you offline after 15 minutes without activity.",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Renew online availability") { changeAvailability(true) }
                    .disabled(model.isBusy || pendingOnlineRequest)
            } else if let locationError = locationManager.errorMessage {
                Text(locationError.replacingOccurrences(of: "Search for a delivery address instead.", with: "Allow location access in iOS Settings to receive nearby delivery offers."))
                    .font(.caption)
                    .foregroundStyle(MarketplaceColors.destructive.color)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var availabilityMessage: String {
        if model.hasActiveJob { return model.isOnline ? "Online · Completing your delivery" : "New assignments paused · Continue this delivery" }
        if model.isOnline, let availableUntil = model.partner?.availability?.availableUntil {
            return "Available until \(DastakPartnerFormatting.time(availableUntil))"
        }
        return model.isOnline ? "Receiving nearby work" : "Not receiving assignments"
    }

    private var hasNoAssignment: Bool {
        model.canShowEmptyDesk && model.courierDispatch?.offer == nil
            && model.courierDispatch?.currentJob == nil
            && model.parcelDispatch?.offer == nil
            && model.parcelDispatch?.currentJob == nil
            && model.v1Dispatch?.offer == nil
            && model.v1Dispatch?.currentMission == nil
            && model.v1Dispatch?.returnMission == nil
    }

    private func changeAvailability(_ online: Bool) {
        if services.isDemonstration {
            Task { await model.setAvailability(online: online, location: .init(address: "Sample Garden Street", point: .init(latitude: 12.6819, longitude: 78.6201))) }
            return
        }
        if online, locationManager.location == nil {
            pendingOnlineRequest = true
            locationManager.requestLocation()
            return
        }
        Task {
            await model.setAvailability(online: online, location: locationManager.location)
        }
    }

    private func courierOffer(_ offer: CourierAssignment) -> some View {
        DastakPartnerOfferCard(
            title: offer.store.name,
            subtitle: offer.store.address,
            symbol: "bag",
            payout: offer.courierPayout.paise,
            distanceMeters: offer.distanceMeters,
            respondBy: offer.respondBy,
            itemSummary: offer.items.map { "\($0.quantity) × \($0.name)" }.joined(separator: ", "),
            busy: model.isBusy,
            accept: {
                Task { await model.perform(.accept, assignment: offer) }
            },
            decline: {
                Task { await model.perform(.decline, assignment: offer) }
            }
        )
    }

    private func parcelOffer(_ offer: ParcelAssignment) -> some View {
        DastakPartnerOfferCard(
            title: "Parcel delivery",
            subtitle: offer.parcel.pickup.address,
            symbol: "shippingbox",
            payout: offer.parcel.courierPayout.paise,
            distanceMeters: offer.distanceMeters,
            respondBy: offer.respondBy,
            itemSummary: offer.parcel.declaredContents,
            busy: model.isBusy,
            accept: {
                Task { await model.perform(.accept, assignment: offer) }
            },
            decline: {
                Task { await model.perform(.decline, assignment: offer) }
            }
        )
    }

    private func v1Offer(_ offer: DastakV1RiderOffer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
        DastakPartnerOfferCard(
            title: "Dastak · \(offer.pickupCount) pickup\(offer.pickupCount == 1 ? "" : "s")",
            subtitle: offer.displayOrderNumber,
            symbol: "shippingbox.and.arrow.backward",
            payout: nil,
            distanceMeters: offer.distanceMeters,
            respondBy: offer.respondBy,
            itemSummary: "\(offer.transportType.replacingOccurrences(of: "_", with: " ").capitalized) · Verify every package at pickup, then deliver to the customer.",
            busy: model.isBusy || offer.orderLoad == nil || offer.pickupStops?.count != offer.pickupCount,
            accept: { Task { await model.respondToV1Offer(offer, accept: true) } },
            decline: { Task { await model.respondToV1Offer(offer, accept: false) } }
        )
            if offer.orderLoad == nil || offer.pickupStops?.count != offer.pickupCount {
                Text("Pickup or load details are unavailable. Refresh before responding to this offer.").font(.footnote).foregroundStyle(.secondary)
            }
            if let load = offer.orderLoad {
                Label("\(Double(load.totalWeightGrams) / 1000, specifier: "%.1f") kg · \(load.containsBulky ? "Bulky items" : "Standard load")", systemImage: "shippingbox")
                    .font(.subheadline)
                Text("Longest side: \(Double(load.longestSideMillimetres) / 10, specifier: "%.0f") cm")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach((offer.pickupStops ?? []).sorted { $0.sequence < $1.sequence }) { stop in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stop.sequence). \(stop.branch.displayName)").font(.headline)
                    Text(stop.branch.address.display).font(.caption).foregroundStyle(.secondary)
                    if let count = stop.packageCount { Text("\(count) packages").font(.caption) }
                }
            }
        }
    }

    private func captureV1Evidence(
        _ item: PhotosPickerItem,
        mission: DastakV1DeliveryMissionSnapshot
    ) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  !data.isEmpty, data.count <= 10 * 1_024 * 1_024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                  let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String),
                  let mime = type.preferredMIMEType, ["image/jpeg", "image/png", "image/heic"].contains(mime)
            else {
                model.errorMessage = "Choose a clear package photo up to 10 MB."
                return
            }
            await model.submitV1Evidence(mission: mission, data: data, contentType: mime)
        } catch {
            model.errorMessage = "The package photo could not be secured. Try again before handoff."
        }
    }

    private func courierJob(_ assignment: CourierAssignment) -> some View {
        DastakCourierJobView(
            assignment: assignment,
            handoffCode: $handoffCode,
            busy: model.isBusy
        ) { action, code in
            Task {
                await model.perform(action, assignment: assignment, verificationCode: code)
                handoffCode = ""
            }
        }
    }

    private func parcelJob(_ assignment: ParcelAssignment) -> some View {
        DastakParcelJobView(
            assignment: assignment,
            handoffCode: $handoffCode,
            busy: model.isBusy
        ) { action, code in
            Task {
                await model.perform(action, assignment: assignment, verificationCode: code)
                handoffCode = ""
            }
        }
    }
}

private struct DastakV1MissionCard: View {
    let mission: DastakV1DeliveryMissionSnapshot
    let busy: Bool
    let submitting: Bool
    let advance: (String, UUID?, Int?, String?, String?) -> Void
    let recordCollection: (
        DastakV1CollectionOutcome,
        DastakV1CollectionMethod,
        String?,
        String?
    ) -> Void
    let captureEvidence: (PhotosPickerItem) -> Void
    var captureSampleEvidence: (() -> Void)? = nil
    @Environment(\.marketplaceDemonstration) private var demonstration
    @State private var pickupCodes: [UUID: String] = [:]
    @State private var packageCounts: [UUID: Int] = [:]
    @State private var deliveryCode = ""
    @State private var collectionMethod = DastakV1CollectionMethod.cash
    @State private var collectionReference = ""
    @State private var failureReason = ""
    @State private var evidenceItem: PhotosPickerItem?
    @State private var confirmRelease = false
    @State private var confirmCollection = false
    @State private var showingCollectionFailure = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakPartnerJobHeader(
                title: "CURRENT DELIVERY",
                status: DastakDeliveryPresentation.title(mission.status),
                payout: nil
            )
            Text(mission.displayOrderNumber)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            if let step = DastakDeliveryPresentation.step(mission.status) {
                HStack(spacing: 8) {
                    ForEach(Array(["Pickup", "Route", "Handoff"].enumerated()), id: \.offset) { index, label in
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(index <= step ? MarketplaceColors.accent(for: colorScheme) : Color.secondary.opacity(0.15))
                                .frame(height: 4)
                            Label(label, systemImage: index < step ? "checkmark.circle.fill" : "\(index + 1).circle")
                                .font(.caption.weight(index == step ? .bold : .regular))
                                .foregroundStyle(index == step ? Color.primary : Color.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of 3. \(DastakDeliveryPresentation.title(mission.status))")
            }
            Text(DastakDeliveryPresentation.instruction(mission.status))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if submitting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating delivery…").font(.footnote.weight(.medium))
                }
                .accessibilityElement(children: .combine)
            }
            Divider()

            if mission.status == .assigned {
                MarketplaceFeedbackButton("Start pickups") {
                    advance("v1StartPickups", nil, nil, nil, nil)
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy)
            }

            if !finalStage {
                ForEach(mission.pickupStops) { stop in
                    pickupStop(stop)
                }
            }

            if finalStage, let destination = mission.customerDestination {
                DastakPartnerStop(
                    title: "Customer destination",
                    name: destination.recipient?.name ?? "Recipient",
                    address: destination.address.displayLine,
                    symbol: "mappin.and.ellipse"
                )
                DastakMapRouteButton(
                    point: GeoPoint(
                        latitude: destination.address.latitude,
                        longitude: destination.address.longitude
                    ),
                    label: "Open customer route"
                )
                if let number = destination.recipient?.phoneNumber,
                   let url = DastakDeliveryPresentation.callURL(number) {
                    Link(destination: url) { Label("Call customer", systemImage: "phone.fill") }
                }

                if mission.canStartFinalDelivery {
                    MarketplaceFeedbackButton("Start final delivery") {
                        advance("v1StartFinalDelivery", nil, nil, nil, nil)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy)
                }
                if mission.canArriveCustomer {
                    DastakTrackedArrivalButton(
                        missionID: mission.id,
                        stopID: nil,
                        fallback: mission.customerArrival,
                        busy: busy
                    ) {
                        advance("v1ArriveAtCustomer", nil, nil, nil, nil)
                    }
                }

                if mission.status == .arrived {
                    Text("HANDOFF · PIN → PHOTO → PAYMENT → COMPLETE")
                        .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                if mission.canVerifyCustomerPIN == true {
                    DastakHandoffCodeField(title: "Customer delivery PIN", length: 6, code: $deliveryCode)
                    MarketplaceFeedbackButton("Verify customer PIN") {
                        advance("v1VerifyCustomerPIN", nil, nil, deliveryCode, nil)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy || deliveryCode.count != 6)
                }
                if mission.finalVerification?.pinVerified == true {
                    Label("Customer PIN verified", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(MarketplaceColors.success.color)
                }
                if mission.canCaptureDeliveryEvidence,
                   mission.finalVerification?.evidencePresent != true {
                    if demonstration {
                        Button("Use sample package photo") { captureSampleEvidence?() }
                            .buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(busy)
                    } else {
                    PhotosPicker(selection: $evidenceItem, matching: .images) {
                        Label("Add package handoff photo", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                    .disabled(busy)
                    .onChange(of: evidenceItem) { _, item in
                        guard let item else { return }
                        captureEvidence(item)
                        evidenceItem = nil
                    }
                    }
                }
                if mission.finalVerification?.evidencePresent == true {
                    Label("Package photo secured", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.success.color)
                }

                if let collection = mission.launchCollection, collection.state != .notRequired {
                    collectionCard(collection)
                }
                if mission.status == .arrived {
                    MarketplaceFeedbackButton("Complete delivery") {
                        advance("v1CompleteDelivery", nil, nil, nil, nil)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy || mission.canCompleteDelivery != true)
                }
            }

            if mission.canCancelBeforePickup {
                Button("Can’t continue this delivery?", role: .destructive) { confirmRelease = true }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(busy)
            }
            if mission.mustUseDeliveryRecovery {
                Label(
                    "Keep every package secure and contact Operations for recovery.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.warning.color)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .confirmationDialog("Release this delivery?", isPresented: $confirmRelease, titleVisibility: .visible) {
            Button("Release delivery", role: .destructive) {
                advance("v1CancelBeforePickup", nil, nil, nil, "Rider cannot continue before pickup")
            }
            Button("Keep delivery", role: .cancel) {}
        } message: {
            Text("Only release before collecting any packages. The delivery will return for reassignment.")
        }
        .confirmationDialog("Confirm payment received", isPresented: $confirmCollection, titleVisibility: .visible) {
            Button("Payment received") {
                guard !busy, mission.launchCollection?.canRecord == true else { return }
                recordCollection(.collected, collectionMethod, collectionReference.isEmpty ? nil : collectionReference, nil)
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Confirm you actually received the full amount by \(collectionMethod == .cash ? "cash" : "UPI"). Do not confirm a pending payment.")
        }
        .onChange(of: DastakDeliveryPresentation.handoffRevision(mission)) { _, _ in clearHandoffInputs() }
        .onChange(of: mission.status) { _, _ in clearHandoffInputs() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clearHandoffInputs() } }
        .accessibilityElement(children: .contain)
    }

    private var finalStage: Bool {
        [.allPackagesPickedUp, .outForDelivery, .arrived, .deliveryRecovery]
            .contains(mission.status)
    }

    private func clearHandoffInputs() {
        pickupCodes = [:]; packageCounts = [:]; deliveryCode = ""; collectionReference = ""
        failureReason = ""; showingCollectionFailure = false; confirmCollection = false; confirmRelease = false
    }

    @ViewBuilder
    private func pickupStop(_ stop: DastakV1MissionPickupStop) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            DastakPartnerStop(
                title: "Pickup \(stop.sequence) of \(mission.pickupCount)",
                name: stop.branch.displayName,
                address: stop.branch.address.displayLine,
                symbol: stop.status == .completed ? "checkmark.circle.fill" : "storefront"
            )
            Label(
                stop.status == .completed ? "Pickup verified" : stop.ready ? "Packages ready" : stop.runningLate ? "Merchant is running late" : "Merchant is preparing",
                systemImage: stop.status == .completed ? "checkmark.seal.fill" : stop.ready ? "shippingbox.fill" : "clock"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(stop.ready || stop.status == .completed ? MarketplaceColors.success.color : Color.secondary)
            if stop.status != .completed {
                DastakMapRouteButton(point: GeoPoint(latitude: stop.branch.address.latitude,
                    longitude: stop.branch.address.longitude), label: "Open merchant route")
            }
            if stop.status == .pending, mission.status != .assigned {
                DastakTrackedArrivalButton(
                    missionID: mission.id,
                    stopID: stop.id,
                    fallback: stop.arrival,
                    busy: busy
                ) {
                    advance("v1ArriveAtPickup", stop.id, nil, nil, nil)
                }
            }
            if stop.status == .arrived {
                if !stop.ready {
                    Text("Wait for the merchant to mark all packages ready before verifying pickup.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Stepper(
                    "Packages accounted: \(packageCounts[stop.id] ?? stop.packageCount ?? 1)",
                    value: Binding(
                        get: { packageCounts[stop.id] ?? stop.packageCount ?? 1 },
                        set: { packageCounts[stop.id] = $0 }
                    ),
                    in: 1...1_000
                )
                DastakHandoffCodeField(
                    title: "Merchant pickup code",
                    length: 6,
                    code: Binding(
                        get: { pickupCodes[stop.id] ?? "" },
                        set: { pickupCodes[stop.id] = $0 }
                    )
                )
                MarketplaceFeedbackButton("Verify pickup") {
                    advance(
                        "v1VerifyPickup",
                        stop.id,
                        packageCounts[stop.id] ?? stop.packageCount ?? 1,
                        pickupCodes[stop.id],
                        nil
                    )
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy || !stop.ready || pickupCodes[stop.id]?.count != 6)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func collectionCard(_ collection: DastakV1LaunchCollection) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.state == .collected ? "PAYMENT RECEIVED" : "COLLECT AT THE DOOR")
                        .font(.caption2.bold())
                        .tracking(1)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(collection.amount.map(DastakFormatting.money) ?? "Amount unavailable")
                        .font(.title2.bold().monospacedDigit())
                }
                Spacer()
                Text(collection.state == .collected ? "COLLECTED" : "PAY AT DELIVERY")
                    .font(.caption2.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            if collection.state == .collected {
                let method = collection.lastMethod.map { $0 == .cash ? "cash" : "UPI" }
                Label(
                    "Payment collected\(method.map { " by \($0)" } ?? ""). You can complete delivery.",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.success.color)
            } else if !collection.canRecord {
                Text("Collection unlocks after arrival, customer PIN verification and the package photo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                if collection.state == .retryNeeded {
                    Label(
                        collection.failureReason.map { "Last attempt failed: \($0)" } ??
                            "The last attempt failed. Retry before delivery.",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.warning.color)
                }
                Text("Confirm payment only after receiving the full amount.")
                    .font(.footnote).foregroundStyle(.secondary)
                Picker("Received by", selection: $collectionMethod) {
                    ForEach(collection.methods, id: \.self) { method in
                        Text(method == .cash ? "Cash" : "UPI").tag(method)
                    }
                }
                .pickerStyle(.segmented)
                if collectionMethod == .upi {
                    TextField("UPI reference (optional)", text: $collectionReference)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Button("Confirm payment received") { confirmCollection = true }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy || !collection.canRecord || collection.amount == nil || !collection.methods.contains(collectionMethod))
                DisclosureGroup("Having trouble collecting?", isExpanded: $showingCollectionFailure) {
                    TextField("What went wrong?", text: $failureReason, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .padding(.vertical, 8)
                    Button("Couldn’t collect") {
                        recordCollection(
                            .failed,
                            collectionMethod,
                            collectionReference.isEmpty ? nil : collectionReference,
                            failureReason.isEmpty ? nil : failureReason
                        )
                    }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                    .disabled(busy || !collection.canRecord || failureReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MarketplaceColors.dastakAccent.color.opacity(0.35), lineWidth: 1)
        }
    }
}

/// Synchronizes workspace state into the process-owned background tracker
/// without making the entire delivery screen observe every GPS response.
struct DastakDeliveryTrackerBridge: View {
    @EnvironmentObject private var tracker: DastakActiveDeliveryTracker
    let dispatch: DastakV1DeliveryDispatchSnapshot?
    let isAuthoritative: Bool

    private var revision: String {
        guard isAuthoritative else { return "loading" }
        if let returned = dispatch?.returnMission { return "return:\(returned.id):\(returned.version):\(returned.status)" }
        let mission = dispatch?.currentMission
        guard let mission else { return "none" }
        return "\(mission.id.uuidString):\(mission.version):\(mission.status.rawValue)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: revision) {
                guard isAuthoritative else { return }
                if let dispatch { tracker.adopt(dispatch) }
            }
            .accessibilityHidden(true)
    }
}

private struct DastakDeliveryTrackingNotice: View {
    @EnvironmentObject private var tracker: DastakActiveDeliveryTracker
    let missionID: UUID

    var body: some View {
        if tracker.mission?.id == missionID {
            if let message = tracker.statusMessage {
                Label(message, systemImage: "location.circle").font(.footnote).foregroundStyle(.secondary)
            }
            if let failure = tracker.heartbeatFailure {
                Label(failure, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

/// Only this compact control observes the high-frequency tracking snapshot.
/// The rest of the mission card stays stable while GPS eligibility changes.
private struct DastakTrackedArrivalButton: View {
    @EnvironmentObject private var tracker: DastakActiveDeliveryTracker
    let missionID: UUID
    let stopID: UUID?
    let fallback: DastakArrivalEligibility?
    let busy: Bool
    let action: () -> Void

    private var eligibility: DastakArrivalEligibility? {
        guard let mission = tracker.mission, mission.id == missionID else { return fallback }
        if let stopID {
            return mission.pickupStops.first(where: { $0.id == stopID })?.arrival ?? fallback
        }
        return mission.customerArrival ?? fallback
    }

    var body: some View {
        DastakArrivalButton(eligibility: eligibility, busy: busy, action: action)
    }
}

private struct DastakPartnerNotice: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(MarketplaceColors.success.color)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(MarketplaceIconButtonStyle())
            .accessibilityLabel("Dismiss confirmation")
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }
}

private struct DastakPartnerOfferCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let payout: Int?
    let distanceMeters: Double
    let respondBy: String
    let itemSummary: String
    let busy: Bool
    let accept: () -> Void
    let decline: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expired = DastakDeliveryPresentation.secondsRemaining(until: respondBy, now: context.date) == 0
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                    .frame(width: 48, height: 48)
                    .background(MarketplaceColors.accent(for: colorScheme).opacity(0.12))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MarketplaceMetrics.compactCornerRadius,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(expired ? "OFFER ENDED" : "NEW DELIVERY")
                        .font(.caption.bold())
                        .tracking(1)
                        .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
                    Text(title)
                        .font(MarketplaceTypography.itemTitle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                DastakOfferTimer(respondBy: respondBy)
            }

            HStack(alignment: .firstTextBaseline) {
                if let payout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You earn")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(DastakFormatting.money(.init(paise: payout)))
                            .font(.title2.bold().monospacedDigit())
                    }
                }
                Spacer()
                Label(
                    DastakPartnerFormatting.distance(distanceMeters),
                    systemImage: "location"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Divider()
            Text(expired ? "This offer has expired. Your next available offer will appear automatically." : itemSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: MarketplaceSpacing.compact) {
                Button("Decline", role: .destructive, action: decline)
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                Button(expired ? "Offer expired" : "Accept delivery", action: accept)
                    .buttonStyle(MarketplacePrimaryButtonStyle())
            }
            .disabled(busy || expired)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .overlay {
            RoundedRectangle(cornerRadius: 24).stroke(MarketplaceColors.accent(for: colorScheme).opacity(0.30), lineWidth: 1)
        }
        }
    }
}

private struct DastakOfferTimer: View {
    let respondBy: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(DastakDeliveryPresentation.secondsRemaining(until: respondBy, now: context.date))s")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(MarketplaceColors.warning.color)
                .frame(minWidth: 38, minHeight: 30)
                .background(MarketplaceColors.warning.color.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

private struct DastakCourierJobView: View {
    let assignment: CourierAssignment
    @Binding var handoffCode: String
    let busy: Bool
    let perform: (DastakCourierAction, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakPartnerJobHeader(
                title: "Active delivery",
                status: DastakPartnerFormatting.orderStatus(assignment.orderStatus),
                payout: assignment.courierPayout.paise
            )

            DastakPartnerStop(
                title: "Pickup",
                name: assignment.store.name,
                address: assignment.store.address,
                symbol: "storefront"
            )
            DastakPartnerStop(
                title: "Drop-off",
                name: "Customer",
                address: "Open the route for the exact destination.",
                symbol: "mappin"
            )

            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                ForEach(assignment.items, id: \.productID) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(item.quantity) ×")
                            .font(.subheadline.bold().monospacedDigit())
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(item.unitLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, MarketplaceSpacing.small)

            DastakMapRouteButton(
                point: destination,
                label: headingToCustomer ? "Open drop-off route" : "Open pickup route"
            )

            if assignment.orderStatus == .returningToMerchant {
                Label(
                    "Return the items to the merchant. The merchant will close this delivery.",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.subheadline)
                .foregroundStyle(MarketplaceColors.warning.color)
            }

            if let action {
                if action.codeLength > 0 {
                    DastakHandoffCodeField(
                        title: assignment.orderStatus == .atStore
                            ? "Merchant pickup code"
                            : "Customer delivery code",
                        length: action.codeLength,
                        code: $handoffCode
                    )
                }

                Button(action.title) {
                    perform(action.action, action.codeLength > 0 ? handoffCode : nil)
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy || (action.codeLength > 0 && handoffCode.count != action.codeLength))
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var headingToCustomer: Bool {
        assignment.orderStatus == .pickedUp || assignment.orderStatus == .inTransit
    }

    private var destination: GeoPoint {
        headingToCustomer ? assignment.dropoff : assignment.store.pickup
    }

    private var action: (action: DastakCourierAction, title: String, codeLength: Int)? {
        switch assignment.orderStatus {
        case .assigned: (.startToStore, "Start to store", 0)
        case .enRouteToPickup: (.arriveAtStore, "Arrived at store", 0)
        case .atStore: (.confirmPickup, "Confirm pickup", 4)
        case .pickedUp: (.startDelivery, "Start delivery", 0)
        case .inTransit: (.completeDelivery, "Complete delivery", 4)
        default: nil
        }
    }
}

private struct DastakParcelJobView: View {
    let assignment: ParcelAssignment
    @Binding var handoffCode: String
    let busy: Bool
    let perform: (DastakParcelPartnerAction, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakPartnerJobHeader(
                title: "Active parcel",
                status: DastakPartnerFormatting.parcelStatus(assignment.parcel.status),
                payout: assignment.parcel.courierPayout.paise
            )

            DastakPartnerStop(
                title: "Pickup",
                name: "Sender",
                address: assignment.parcel.pickup.address,
                symbol: "shippingbox"
            )
            DastakPartnerStop(
                title: "Drop-off",
                name: assignment.parcel.recipient.name,
                address: assignment.parcel.dropoff.address,
                symbol: "mappin"
            )

            LabeledContent("Contents", value: assignment.parcel.declaredContents)

            DastakMapRouteButton(
                point: destination,
                label: headingToRecipient ? "Open drop-off route" : "Open pickup route"
            )

            if let action {
                if action.codeLength > 0 {
                    DastakHandoffCodeField(
                        title: assignment.parcel.status == .enRouteToPickup
                            ? "Sender pickup code"
                            : "Recipient delivery code",
                        length: action.codeLength,
                        code: $handoffCode
                    )
                }

                Button(action.title) {
                    perform(action.action, action.codeLength > 0 ? handoffCode : nil)
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy || (action.codeLength > 0 && handoffCode.count != action.codeLength))
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var headingToRecipient: Bool {
        assignment.parcel.status == .pickedUp || assignment.parcel.status == .inTransit
    }

    private var destination: GeoPoint {
        let location = headingToRecipient ? assignment.parcel.dropoff : assignment.parcel.pickup
        return GeoPoint(latitude: location.latitude, longitude: location.longitude)
    }

    private var action: (action: DastakParcelPartnerAction, title: String, codeLength: Int)? {
        switch assignment.parcel.status {
        case .assigned: (.startToPickup, "Start to pickup", 0)
        case .enRouteToPickup: (.confirmPickup, "Confirm pickup", 6)
        case .pickedUp: (.startDelivery, "Start delivery", 0)
        case .inTransit: (.completeDelivery, "Complete delivery", 6)
        default: nil
        }
    }
}

private struct DastakPartnerJobHeader: View {
    let title: String
    let status: String
    let payout: Int?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Text(status)
                    .font(MarketplaceTypography.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let payout {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Earnings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DastakFormatting.money(.init(paise: payout)))
                        .font(.headline.monospacedDigit())
                }
            }
        }
    }
}

private struct DastakPartnerStop: View {
    let title: String
    let name: String
    let address: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.subheadline.bold())
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DastakMapRouteButton: View {
    let point: GeoPoint
    let label: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let url = URL(
                string: "https://maps.apple.com/?daddr=\(point.latitude),\(point.longitude)"
            ) else { return }
            openURL(url)
        } label: {
            Label(label, systemImage: "arrow.triangle.turn.up.right.diamond")
        }
        .buttonStyle(MarketplaceSecondaryButtonStyle())
    }
}

struct DastakHandoffCodeField: View {
    let title: String
    let length: Int
    @Binding var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(title)
                .font(.subheadline.bold())
            TextField("\(length)-digit code", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .onChange(of: code) { _, value in
                    code = DastakDeliveryPresentation.code(value, length: length)
                }
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .accessibilityLabel(title)
            Text("Ask for this code only when the packages are ready for handoff.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum DastakPartnerFormatting {
    static func method(_ method: DeliveryMethod) -> String {
        switch method {
        case .retired: "Retired delivery method"
        case .walking: "Walking"
        case .bicycle: "Bicycle"
        case .bike, .motorbike: "Motorbike"
        case .scooter: "Scooter"
        case .auto: "Auto"
        case .goodsVehicle: "Tempo / goods vehicle"
        }
    }

    static func orderStatus(_ status: MerchantOrderStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .merchantAccepted: "Merchant accepted"
        case .ready: "Ready"
        case .assigned: "Assigned"
        case .enRouteToPickup: "Heading to store"
        case .atStore: "At store"
        case .pickedUp: "Picked up"
        case .inTransit: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        case .returningToMerchant: "Return to merchant"
        }
    }

    static func parcelStatus(_ status: ParcelDeliveryStatus) -> String {
        switch status {
        case .paymentPending: "Payment pending"
        case .paid: "Paid"
        case .assigned: "Assigned"
        case .enRouteToPickup: "Heading to sender"
        case .pickedUp: "Picked up"
        case .inTransit: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    static func distance(_ meters: Double) -> String {
        meters < 1_000
            ? "\(Int(meters.rounded())) m to pickup"
            : String(format: "%.1f km to pickup", meters / 1_000)
    }

    static func time(_ value: String) -> String {
        guard let date = date(value) else { return "soon" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
