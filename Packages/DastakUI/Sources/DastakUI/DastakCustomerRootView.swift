import Combine
import DastakDomain
import Foundation
import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

private let dastakOrderNotificationOpened = Notification.Name("dastak.notification.orderOpened")
private let dastakDeviceTokenRegistered = Notification.Name("dastak.notification.deviceTokenRegistered")
private let dastakPendingEntityTypeKey = "dastak.notification.pendingEntityType"
private let dastakPendingEntityIDKey = "dastak.notification.pendingEntityID"
private let dastakLegacyPendingOrderIDKey = "dastak.notification.pendingOrderID"

public struct DastakCustomerRootView: View {
    private enum Tab: Hashable {
        case home
        case search
        case orders
        case account
    }

    @StateObject private var model: DastakCustomerModel
    @StateObject private var locationManager = DastakLocationManager()
    @State private var selectedTab: Tab = .home
    @State private var ordersPath: [DastakCustomerDestination] = []
    @State private var showingDeliveryAddressEditor = false
    @State private var showingDiscoveryLocationPicker = false
    @State private var onboardingStep: DastakCustomerOnboardingStep?
    @State private var showingCart = false
    @State private var showingV1Order = false
    @State private var showingParcel = false
    @State private var showingCheckout = false
    @State private var isConfirmingPayment = false
    @Environment(\.marketplaceSignOut) private var signOut
    @Environment(\.scenePhase) private var scenePhase
    private let isPreview: Bool
    private let deliveryPartnerAccess: DeliveryPartnerAccess
    private let isDeliveryPartnerAccessLoading: Bool
    private let becomeDeliveryPartner: () -> Void
    private let accountSessionClient: any AccountSessionClient
    private let orderEvents: any OrderEventClient
    private let accountIDProvider: (@Sendable () async throws -> UUID)?

    public init(
        functions: any FunctionClient,
        orderEvents: any OrderEventClient = NoopOrderEventClient(),
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil,
        issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)? = nil,
        oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil,
        deliveryPartnerAccess: DeliveryPartnerAccess = .unavailable,
        isDeliveryPartnerAccessLoading: Bool = false,
        becomeDeliveryPartner: @escaping () -> Void = {}
    ) {
        _model = StateObject(
            wrappedValue: DastakCustomerModel(
                functions: functions,
                checkoutCustomerProvider: checkoutCustomerProvider,
                accountIDProvider: accountIDProvider,
                issueEvidenceUploader: issueEvidenceUploader,
                oauthIdentityLinker: oauthIdentityLinker
            )
        )
        isPreview = false
        self.deliveryPartnerAccess = deliveryPartnerAccess
        self.isDeliveryPartnerAccessLoading = isDeliveryPartnerAccessLoading
        self.becomeDeliveryPartner = becomeDeliveryPartner
        accountSessionClient = SupabaseAccountSessionClient(functions: functions)
        self.orderEvents = orderEvents
        self.accountIDProvider = accountIDProvider
    }

    #if DEBUG
    public init(preview: Bool) {
        _model = StateObject(wrappedValue: DastakCustomerModel.preview())
        isPreview = preview
        deliveryPartnerAccess = .notApplied
        isDeliveryPartnerAccessLoading = false
        becomeDeliveryPartner = {}
        accountSessionClient = DastakPreviewAccountSessionClient()
        orderEvents = NoopOrderEventClient()
        accountIDProvider = nil
    }
    #endif

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DastakHomeView(
                    model: model,
                    chooseLocation: { showingDiscoveryLocationPicker = true },
                    openSearch: { selectedTab = .search },
                    openCart: { showingCart = true },
                    sendParcel: { showingParcel = true }
                )
            }
            .tag(Tab.home)
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                DastakSearchView(
                    model: model,
                    chooseLocation: { showingDiscoveryLocationPicker = true },
                    openCart: { showingCart = true }
                )
            }
            .tag(Tab.search)
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack(path: $ordersPath) {
                DastakOrdersView(model: model)
            }
            .tag(Tab.orders)
            .tabItem { Label("Orders", systemImage: "clock") }

            NavigationStack {
                DastakAccountView(
                    customer: model.checkoutCustomer,
                    location: model.deliveryAddress,
                    savedAddressCount: model.savedAddresses.count,
                    accountSessionClient: accountSessionClient,
                    linkedIdentities: model.linkedIdentities,
                    isLinkingIdentity: model.isLinkingIdentity,
                    identityMessage: model.identityMessage,
                    discoveryRadiusKilometres: model.discoveryRadiusKilometres,
                    refreshFailure: model.accountRefreshFailure,
                    deliveryPartnerAccess: deliveryPartnerAccess,
                    isDeliveryPartnerAccessLoading: isDeliveryPartnerAccessLoading,
                    chooseLocation: { showingDeliveryAddressEditor = true },
                    openOrders: { selectedTab = .orders },
                    becomeDeliveryPartner: becomeDeliveryPartner,
                    retryAccount: { Task { await model.refreshCheckoutCustomer() } },
                    refreshIdentities: { Task { await model.refreshCustomerIdentities() } },
                    linkIdentity: { provider in Task { await model.linkIdentity(provider) } },
                    updateProfile: { displayName, phoneNumber in
                        try await model.updateAccountProfile(
                            displayName: displayName,
                            phoneNumber: phoneNumber
                        )
                    },
                    deleteAccount: {
                        try await model.deleteAccount()
                        await signOut()
                    }
                )
            }
            .tag(Tab.account)
            .tabItem { Label("Account", systemImage: "person") }
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .marketplacePage()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = model.errorMessage {
                DastakCustomerNotice(message: message) {
                    model.errorMessage = nil
                }
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.bottom, MarketplaceSpacing.small)
            }
        }
        .task {
            guard !isPreview else { return }
            await model.bootstrap()
            onboardingStep = DastakCustomerOnboardingStep.next(
                hasCompleted: model.hasCompletedOnboarding
            )
            if let destination = consumePendingDestination() {
                open(destination)
            } else {
                showingV1Order = model.activeV1Order != nil
            }
        }
        .task {
            guard !isPreview else { return }
            await observeOrderChanges()
        }
        .task {
            guard !isPreview else { return }
            await pollOrderChanges()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isPreview, phase == .active else { return }
            Task {
                await model.refreshOrdersAndParcels()
                await model.refreshCustomerIdentities()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: dastakOrderNotificationOpened)) { notification in
            guard let destination = DastakCustomerDestination(
                notificationPayload: notification.userInfo ?? [:]
            ) else { return }
            open(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: dastakDeviceTokenRegistered)) { _ in
            Task { await model.registerDeviceTokenIfAvailable() }
        }
        .sheet(isPresented: $showingDeliveryAddressEditor) {
            DastakAddressBookView(
                model: model,
                requiresCompletion: false,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDiscoveryLocationPicker) {
            DastakLocationPicker(
                title: "Browse near",
                currentLocation: locationManager.location,
                useLocation: { location in
                    Task { await model.selectDiscoveryLocation(location) }
                },
                requestCurrentLocation: locationManager.requestLocation
            )
        }
        .dastakOnboardingCover(item: $onboardingStep) { step in
            switch step {
            case .notifications:
                DastakNotificationOnboardingView(
                    enableNotifications: {
                        _ = await DastakNotificationPreferences.request()
                        await model.registerDeviceTokenIfAvailable()
                        model.completeOnboarding()
                        onboardingStep = nil
                    },
                    continueWithoutNotifications: {
                        model.completeOnboarding()
                        onboardingStep = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showingCart) {
            DastakCartView(
                model: model,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation,
                orderSubmitted: { showingV1Order = true }
            )
        }
        .sheet(isPresented: $showingV1Order) {
            DastakV1MatchingView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingParcel) {
            DastakParcelComposerView(
                model: model,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation
            )
        }
        .sheet(isPresented: $showingCheckout) {
            if let session = model.checkoutSession {
                DastakRazorpayCheckoutView(
                    session: session,
                    customerName: model.checkoutCustomer?.displayName,
                    customerEmail: model.checkoutCustomer?.email,
                    customerPhone: model.checkoutCustomer?.phoneNumber,
                    paymentMethod: model.selectedPaymentMethod
                ) { result in
                    switch result {
                    case .succeeded:
                        model.clearCheckoutSession()
                        showingCheckout = false
                        selectedTab = .orders
                        isConfirmingPayment = true
                        Task {
                            let confirmed = await model.waitForPaymentConfirmation(session: session)
                            isConfirmingPayment = false
                            if !confirmed {
                                if session.entityType == .dastakV1Order {
                                    model.v1OrderErrorMessage = "Payment was received. Dastak is still confirming it securely."
                                } else {
                                    model.errorMessage = "Payment was received. We are confirming it securely and will update your order shortly."
                                }
                            }
                            if session.entityType == .dastakV1Order { showingV1Order = true }
                        }
                    case let .failed(message):
                        model.clearCheckoutSession()
                        showingCheckout = false
                        selectedTab = .orders
                        if session.entityType == .dastakV1Order {
                            Task {
                                await model.reportV1CheckoutFailure(
                                    session: session,
                                    failureCode: .checkoutFailed
                                )
                                model.v1OrderErrorMessage = message.isEmpty
                                    ? "Payment failed. Your secured basket is still reserved—try again before the timer ends."
                                    : message
                                showingV1Order = true
                            }
                        } else {
                            model.ordersActionMessage = message.isEmpty
                                ? "Payment failed. You can try again from Orders."
                                : message
                        }
                    case .dismissed:
                        model.clearCheckoutSession()
                        showingCheckout = false
                        selectedTab = .orders
                        if session.entityType == .dastakV1Order {
                            Task {
                                await model.reportV1CheckoutFailure(
                                    session: session,
                                    failureCode: .checkoutDismissed
                                )
                                model.v1OrderErrorMessage = "Payment was not completed. Your reservation is unchanged and you can retry."
                                showingV1Order = true
                            }
                        } else {
                            model.ordersActionMessage = "Payment was not completed. Your order is saved and you can retry here."
                        }
                    }
                }
            }
        }
        .onChange(of: model.checkoutSession) { _, session in
            showingCheckout = session != nil
        }
        .overlay {
            ZStack {
                if isConfirmingPayment {
                    DastakPaymentConfirmationView()
                }
                if model.sessionExpired {
                    DastakSessionExpiredView {
                        Task { await signOut() }
                    }
                }
            }
        }
    }

    private func open(_ destination: DastakCustomerDestination) {
        selectedTab = .orders
        switch destination {
        case let .dastakV1Order(orderID):
            ordersPath = []
            Task {
                if await model.focusV1Order(id: orderID) {
                    showingV1Order = true
                }
            }
        case .merchantOrder, .parcel:
            ordersPath = [destination]
            Task { await model.refreshOrdersAndParcels() }
        }
    }

    private func consumePendingDestination() -> DastakCustomerDestination? {
        let defaults = UserDefaults.standard
        defer {
            defaults.removeObject(forKey: dastakPendingEntityTypeKey)
            defaults.removeObject(forKey: dastakPendingEntityIDKey)
            defaults.removeObject(forKey: dastakLegacyPendingOrderIDKey)
        }

        if let entityType = defaults.string(forKey: dastakPendingEntityTypeKey),
           let entityID = defaults.string(forKey: dastakPendingEntityIDKey) {
            return DastakCustomerDestination(
                notificationPayload: ["entityType": entityType, "entityId": entityID]
            )
        }
        guard let orderID = defaults.string(forKey: dastakLegacyPendingOrderIDKey) else {
            return nil
        }
        return DastakCustomerDestination(notificationPayload: ["orderId": orderID])
    }

    private func observeOrderChanges() async {
        guard let accountIDProvider else { return }
        while !Task.isCancelled {
            do {
                let accountID = try await accountIDProvider()
                for try await _ in orderEvents.events(accountID: accountID) {
                    guard !Task.isCancelled else { return }
                    await model.refreshOrdersAndParcels()
                }
            } catch is CancellationError {
                return
            } catch {
                // The fallback poll keeps orders current while realtime reconnects.
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func pollOrderChanges() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await model.refreshOrdersAndParcels()
        }
    }
}

private extension View {
    @ViewBuilder
    func dastakOnboardingCover<Content: View>(
        item: Binding<DastakCustomerOnboardingStep?>,
        @ViewBuilder content: @escaping (DastakCustomerOnboardingStep) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

private typealias DastakCustomerNotice = DastakActionNotice

private struct DastakSessionExpiredView: View {
    let signInAgain: () -> Void

    var body: some View {
        ZStack {
            MarketplaceColors.dastakBackground.color
                .ignoresSafeArea()

            DastakEmptyState(
                symbol: "person.crop.circle.badge.exclamationmark",
                title: "Your session expired",
                message: "Sign in again to continue securely.",
                actionTitle: "Sign in again",
                action: signInAgain
            )
            .padding(MarketplaceSpacing.large)
        }
    }
}

private struct DastakPaymentConfirmationView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(MarketplaceColors.dastakAccent.color.opacity(0.14))
                        .frame(width: 58, height: 58)
                    ProgressView()
                        .tint(MarketplaceColors.dastakAccent.color)
                }

                VStack(spacing: 6) {
                    Text("Confirming payment")
                        .font(.headline)
                        .foregroundStyle(MarketplaceColors.dastakText.color)
                    Text("Securing your order with Dastak")
                        .font(.footnote)
                        .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                }
            }
            .padding(28)
            .background(MarketplaceColors.dastakSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Confirming payment")
        }
        .transition(.opacity)
    }
}
