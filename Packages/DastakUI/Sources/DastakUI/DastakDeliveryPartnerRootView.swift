import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct DastakDeliveryPartnerWorkspaceView: View {
    @StateObject private var model: DastakDeliveryPartnerModel
    @StateObject private var locationManager = DastakLocationManager()
    @State private var handoffCode = ""
    @State private var pendingOnlineRequest = false
    @Environment(\.scenePhase) private var scenePhase
    private let services: MarketplaceAuthenticatedServices

    init(services: MarketplaceAuthenticatedServices) {
        self.services = services
        _model = StateObject(wrappedValue: DastakDeliveryPartnerModel(functions: services.functions))
    }

    var body: some View {
        deliveryWorkspace
        .marketplacePage()
        .task {
            await model.bootstrap()
        }
        .task {
            await observeOrderChanges()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await model.refresh()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, model.isOnline else { continue }
                locationManager.requestLocation()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refresh() }
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

    private func observeOrderChanges() async {
        while !Task.isCancelled {
            do {
                let accountID = try await services.accountID()
                for try await _ in services.orderEvents.events(accountID: accountID) {
                    guard !Task.isCancelled else { return }
                    await model.refresh()
                }
            } catch is CancellationError {
                return
            } catch {
                // The fallback poll keeps assignments current while realtime reconnects.
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private var deliveryWorkspace: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    partnerHeader
                    deliveryContent
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.xxLarge)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Delivery Partner")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await model.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(MarketplaceIconButtonStyle())
                    .disabled(model.isRefreshing || model.isBusy)
                    .accessibilityLabel("Refresh delivery queue")
                }
            }
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
            if let earnings = model.earnings {
                DastakEarningsCard(earnings: earnings, title: "Earnings")
            }
            availability
            if let mission = model.v1Dispatch?.currentMission {
                DastakV1MissionCard(
                    mission: mission,
                    busy: model.isBusy,
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
                    }
                )
            }
            if let currentJob = model.courierDispatch?.currentJob { courierJob(currentJob) }
            if let currentJob = model.parcelDispatch?.currentJob { parcelJob(currentJob) }
            if let offer = model.courierDispatch?.offer { courierOffer(offer) }
            if let offer = model.parcelDispatch?.offer { parcelOffer(offer) }
            if let offer = model.v1Dispatch?.offer, model.v1Dispatch?.currentMission == nil {
                v1Offer(offer)
            }
            if hasNoAssignment {
                DastakEmptyState(
                    symbol: model.isOnline ? "dot.radiowaves.left.and.right" : "power",
                    title: model.isOnline ? "Waiting for assignments" : "You are offline",
                    message: model.isOnline
                        ? "Ready merchant orders and parcels nearby will appear here."
                        : "Go online when you are ready to deliver."
                )
                .frame(minHeight: 260)
            }
        }
    }

    private var partnerHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                DastakWordmark(size: 30)
                Text(model.partner?.deliveryMethod.map(DastakPartnerFormatting.method) ?? "Delivery Partner")
                    .font(MarketplaceTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
                    Text(model.isOnline ? "Online" : "Offline")
                        .font(MarketplaceTypography.itemTitle)
                    Text(availabilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "Online",
                    isOn: Binding(
                        get: { model.isOnline },
                        set: { online in changeAvailability(online) }
                    )
                )
                .labelsHidden()
                .tint(MarketplaceColors.success.color)
                .disabled(model.isBusy || (model.isOnline && model.hasActiveJob))
            }

            if model.isOnline {
                Label(
                    "Dastak automatically takes you offline after 15 minutes without activity.",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let locationError = locationManager.errorMessage {
                Text(locationError)
                    .font(.caption)
                    .foregroundStyle(MarketplaceColors.destructive.color)
            }
        }
        .padding(.vertical, MarketplaceSpacing.medium)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var availabilityMessage: String {
        if model.isOnline, let availableUntil = model.partner?.availability?.availableUntil {
            return "Available until \(DastakPartnerFormatting.time(availableUntil))"
        }
        return model.isOnline ? "Receiving nearby work" : "Not receiving assignments"
    }

    private var hasNoAssignment: Bool {
        model.courierDispatch?.offer == nil
            && model.courierDispatch?.currentJob == nil
            && model.parcelDispatch?.offer == nil
            && model.parcelDispatch?.currentJob == nil
            && model.v1Dispatch?.offer == nil
            && model.v1Dispatch?.currentMission == nil
    }

    private func changeAvailability(_ online: Bool) {
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
        DastakPartnerOfferCard(
            title: "Dastak · \(offer.pickupCount) pickup\(offer.pickupCount == 1 ? "" : "s")",
            subtitle: offer.displayOrderNumber,
            symbol: "shippingbox.and.arrow.backward",
            payout: nil,
            distanceMeters: offer.distanceMeters,
            respondBy: offer.respondBy,
            itemSummary: "Collect the complete secured order before final delivery.",
            busy: model.isBusy,
            accept: { Task { await model.respondToV1Offer(offer, accept: true) } },
            decline: { Task { await model.respondToV1Offer(offer, accept: false) } }
        )
    }

    private func captureV1Evidence(
        _ item: PhotosPickerItem,
        mission: DastakV1DeliveryMissionSnapshot
    ) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  !data.isEmpty, data.count <= 10 * 1_024 * 1_024
            else {
                model.errorMessage = "Choose a clear package photo up to 10 MB."
                return
            }
            let supported = item.supportedContentTypes
            let type: UTType = supported.contains(.png) ? .png :
                supported.contains(.heic) ? .heic : .jpeg
            let ext = type == .png ? "png" : type == .heic ? "heic" : "jpg"
            let accountID = try await services.accountID()
            let path = "rider-delivery/\(accountID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
            try await services.uploadObject(
                bucket: "dastak-evidence",
                path: path,
                data: data,
                contentType: type.preferredMIMEType ?? "image/jpeg"
            )
            await model.advanceV1Mission(
                "v1AddDeliveryEvidence",
                mission: mission,
                objectPath: path
            )
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
    let advance: (String, UUID?, Int?, String?, String?) -> Void
    let recordCollection: (
        DastakV1CollectionOutcome,
        DastakV1CollectionMethod,
        String?,
        String?
    ) -> Void
    let captureEvidence: (PhotosPickerItem) -> Void
    @State private var pickupCodes: [UUID: String] = [:]
    @State private var packageCounts: [UUID: Int] = [:]
    @State private var deliveryCode = ""
    @State private var collectionMethod = DastakV1CollectionMethod.cash
    @State private var collectionReference = ""
    @State private var failureReason = ""
    @State private var evidenceItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakPartnerJobHeader(
                title: "Active Dastak mission",
                status: missionStatus,
                payout: nil
            )
            Text(mission.displayOrderNumber)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)

            if mission.status == .assigned {
                Button("Start pickups") {
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

                if mission.canStartFinalDelivery {
                    Button("Start final delivery") {
                        advance("v1StartFinalDelivery", nil, nil, nil, nil)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy)
                }
                if mission.canArriveCustomer {
                    Button("I’ve arrived") {
                        advance("v1ArriveAtCustomer", nil, nil, nil, nil)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy)
                }

                if let collection = mission.launchCollection,
                   collection.state != .notRequired {
                    collectionCard(collection)
                }

                if collectionSatisfied,
                   mission.canCaptureDeliveryEvidence,
                   mission.finalVerification?.evidencePresent != true {
                    PhotosPicker(selection: $evidenceItem, matching: .images) {
                        Label("Capture package handoff photo", systemImage: "camera.fill")
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
                if mission.finalVerification?.evidencePresent == true {
                    Label("Package photo secured", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.success.color)
                }

                if collectionSatisfied, mission.canVerifyDelivery {
                    DastakHandoffCodeField(
                        title: "Customer delivery code",
                        length: 6,
                        code: $deliveryCode
                    )
                    Button("Verify delivery") {
                        advance("v1VerifyDelivery", nil, nil, deliveryCode, nil)
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy || deliveryCode.count != 6)
                } else if mission.status == .arrived, !collectionSatisfied {
                    Label(
                        "Record the doorstep collection before the photo and customer delivery code.",
                        systemImage: "lock.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            if mission.canCancelBeforePickup {
                Button("Release mission before pickup", role: .destructive) {
                    advance(
                        "v1CancelBeforePickup",
                        nil,
                        nil,
                        nil,
                        "Rider cannot continue before pickup"
                    )
                }
                .buttonStyle(MarketplaceSecondaryButtonStyle())
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
        .onChange(of: mission.status) { _, _ in
            deliveryCode = ""
            collectionReference = ""
            failureReason = ""
        }
        .accessibilityElement(children: .contain)
    }

    private var finalStage: Bool {
        [.allPackagesPickedUp, .outForDelivery, .arrived, .deliveryRecovery]
            .contains(mission.status)
    }

    private var collectionSatisfied: Bool {
        guard let collection = mission.launchCollection else { return true }
        return !collection.required || collection.state == .collected
    }

    private var missionStatus: String {
        switch mission.status {
        case .assigned: "Assigned"
        case .enRouteToPickups: "Heading to pickups"
        case .pickupInProgress: "Collecting packages"
        case .allPackagesPickedUp: "All packages in custody"
        case .outForDelivery: "On the way"
        case .arrived: "At the customer"
        case .deliveryRecovery: "Delivery recovery"
        }
    }

    @ViewBuilder
    private func pickupStop(_ stop: DastakV1MissionPickupStop) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            DastakPartnerStop(
                title: "Pickup \(stop.sequence) of \(mission.pickupCount)",
                name: stop.branch.displayName,
                address: stop.branch.address,
                symbol: stop.status == .completed ? "checkmark.circle.fill" : "storefront"
            )
            if stop.status == .pending, mission.status != .assigned {
                Button("I’ve arrived") {
                    advance("v1ArriveAtPickup", stop.id, nil, nil, nil)
                }
                .buttonStyle(MarketplaceSecondaryButtonStyle())
                .disabled(busy)
            }
            if stop.status == .arrived {
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
                Button("Verify pickup") {
                    advance(
                        "v1VerifyPickup",
                        stop.id,
                        packageCounts[stop.id] ?? stop.packageCount ?? 1,
                        pickupCodes[stop.id],
                        nil
                    )
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(busy || pickupCodes[stop.id]?.count != 6)
            }
        }
        .padding(MarketplaceSpacing.compact)
        .background(MarketplaceColors.dastakAccentSoft.color.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func collectionCard(_ collection: DastakV1LaunchCollection) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AUTHORITATIVE AMOUNT DUE")
                        .font(.caption2.bold())
                        .tracking(1)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(DastakFormatting.money(collection.amount ?? Money(paise: 0)))
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
                    "Payment collected\(method.map { " by \($0)" } ?? ""). Delivery verification is unlocked.",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.success.color)
            } else if mission.status != .arrived {
                Text("Collection unlocks after arrival with complete package custody.")
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
                Picker("Actual payment method", selection: $collectionMethod) {
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
                TextField("Reason if collection fails", text: $failureReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack(spacing: MarketplaceSpacing.compact) {
                    Button("Couldn’t collect") {
                        recordCollection(
                            .failed,
                            collectionMethod,
                            collectionReference.isEmpty ? nil : collectionReference,
                            failureReason.isEmpty ? nil : failureReason
                        )
                    }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                    .disabled(busy || failureReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    Button("Record collected") {
                        recordCollection(
                            .collected,
                            collectionMethod,
                            collectionReference.isEmpty ? nil : collectionReference,
                            nil
                        )
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy || !collection.canRecord)
                }
            }
        }
        .padding(MarketplaceSpacing.medium)
        .background(MarketplaceColors.dastakAccentSoft.color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MarketplaceColors.dastakAccent.color.opacity(0.35), lineWidth: 1)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(MarketplaceColors.dastakAccentSoft.color)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MarketplaceMetrics.compactCornerRadius,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("New offer")
                        .font(.caption.bold())
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(title)
                        .font(MarketplaceTypography.itemTitle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

            Text(itemSummary)
                .font(.subheadline)
                .lineLimit(3)

            HStack(spacing: MarketplaceSpacing.compact) {
                Button("Decline", role: .destructive, action: decline)
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
                Button("Accept", action: accept)
                    .buttonStyle(MarketplacePrimaryButtonStyle())
            }
            .disabled(busy)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }
}

private struct DastakOfferTimer: View {
    let respondBy: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(DastakPartnerFormatting.secondsRemaining(until: respondBy, now: context.date))s")
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                string: "https://maps.apple.com/?daddr=\(point.latitude),\(point.longitude)&dirflg=d"
            ) else { return }
            openURL(url)
        } label: {
            Label(label, systemImage: "arrow.triangle.turn.up.right.diamond")
        }
        .buttonStyle(MarketplaceSecondaryButtonStyle())
    }
}

private struct DastakHandoffCodeField: View {
    let title: String
    let length: Int
    @Binding var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(title)
                .font(.subheadline.bold())
            TextField(String(repeating: "0", count: length), text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(length))
                }
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
        }
    }
}

private enum DastakPartnerFormatting {
    static func method(_ method: DeliveryMethod) -> String {
        switch method {
        case .walking: "Walking"
        case .bicycle: "Bicycle"
        case .bike, .motorbike: "Motorbike"
        case .scooter: "Scooter"
        case .auto: "Auto"
        case .car: "Car"
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

    static func secondsRemaining(until value: String, now: Date) -> Int {
        guard let date = date(value) else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSince(now))))
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
