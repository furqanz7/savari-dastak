import Combine
import DastakDomain
import Foundation
import MarketplaceDesignSystem
import MarketplaceFoundation
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
    private let merchantOnboardingState: MerchantOnboardingState?
    private let isMerchantAccessLoading: Bool
    private let deliveryPartnerAccess: DeliveryPartnerAccess
    private let isDeliveryPartnerAccessLoading: Bool
    private let becomeMerchant: () -> Void
    private let becomeDeliveryPartner: () -> Void
    private let accountSessionClient: any AccountSessionClient
    private let orderEvents: any OrderEventClient
    private let accountIDProvider: (@Sendable () async throws -> UUID)?
    private let oauthReauthenticator: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)?

    public init(
        functions: any FunctionClient,
        orderEvents: any OrderEventClient = NoopOrderEventClient(),
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil,
        issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)? = nil,
        oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil,
        oauthReauthenticator: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil,
        merchantOnboardingState: MerchantOnboardingState? = nil,
        isMerchantAccessLoading: Bool = false,
        deliveryPartnerAccess: DeliveryPartnerAccess = .unavailable,
        isDeliveryPartnerAccessLoading: Bool = false,
        becomeMerchant: @escaping () -> Void = {},
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
        self.merchantOnboardingState = merchantOnboardingState
        self.isMerchantAccessLoading = isMerchantAccessLoading
        self.deliveryPartnerAccess = deliveryPartnerAccess
        self.isDeliveryPartnerAccessLoading = isDeliveryPartnerAccessLoading
        self.becomeMerchant = becomeMerchant
        self.becomeDeliveryPartner = becomeDeliveryPartner
        accountSessionClient = SupabaseAccountSessionClient(functions: functions)
        self.orderEvents = orderEvents
        self.accountIDProvider = accountIDProvider
        self.oauthReauthenticator = oauthReauthenticator
    }

    #if DEBUG
    public init(preview: Bool) {
        _model = StateObject(wrappedValue: DastakCustomerModel.preview())
        isPreview = preview
        merchantOnboardingState = .notApplied
        isMerchantAccessLoading = false
        deliveryPartnerAccess = .notApplied
        isDeliveryPartnerAccessLoading = false
        becomeMerchant = {}
        becomeDeliveryPartner = {}
        accountSessionClient = DastakPreviewAccountSessionClient()
        orderEvents = NoopOrderEventClient()
        accountIDProvider = nil
        oauthReauthenticator = nil
    }
    #endif

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DastakHomeView(
                    model: model,
                    chooseLocation: { showingDiscoveryLocationPicker = true },
                    openCart: { showingCart = true },
                    sendParcel: { showingParcel = true }
                )
            }
            .tag(Tab.home)
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack(path: $ordersPath) {
                DastakOrdersView(
                    model: model,
                    openCart: { showingCart = true },
                    openDestination: { ordersPath.append($0) }
                )
            }
            .tag(Tab.orders)
            .tabItem { Label("Orders", systemImage: "clock") }

            NavigationStack {
                DastakAccountView(
                    customerModel: model,
                    customer: model.checkoutCustomer,
                    location: model.deliveryAddress,
                    savedAddressCount: model.savedAddresses.count,
                    accountSessionClient: accountSessionClient,
                    linkedIdentities: model.linkedIdentities,
                    isLinkingIdentity: model.isLinkingIdentity,
                    identityMessage: model.identityMessage,
                    identityMessageIsSuccess: model.identityMessageIsSuccess,
                    hasActiveOrders: model.hasActiveOrders,
                    refreshFailure: model.accountRefreshFailure,
                    merchantOnboardingState: merchantOnboardingState,
                    isMerchantAccessLoading: isMerchantAccessLoading,
                    deliveryPartnerAccess: deliveryPartnerAccess,
                    isDeliveryPartnerAccessLoading: isDeliveryPartnerAccessLoading,
                    chooseLocation: { showingDeliveryAddressEditor = true },
                    openOrders: { selectedTab = .orders },
                    becomeMerchant: becomeMerchant,
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
                    },
                    reauthenticate: { provider in
                        guard let oauthReauthenticator else {
                            throw MarketplaceAuthenticatedServicesError.authenticationRequired
                        }
                        try await oauthReauthenticator(provider)
                    },
                    exportAccount: { try await model.exportAccount() }
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
            do {
                _ = try await accountSessionClient.snapshot(
                    device: dastakAccountSessionDevice(applicationName: "Dastak"),
                    idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!
                )
            } catch FunctionClientError.authenticationRequired {
                await signOut()
                return
            } catch let FunctionClientError.api(statusCode, _, _) where statusCode == 401 {
                await signOut()
                return
            } catch {
                // Account content can still load during a temporary session-registry outage.
            }
            await model.bootstrap()
            let notificationState = await DastakNotificationPreferences.status()
            if notificationState != .notRequested {
                model.completeOnboarding()
                if notificationState == .enabled {
                    await model.registerDeviceTokenIfAvailable()
                }
            }
            onboardingStep = DastakCustomerOnboardingStep.next(
                hasCompleted: model.hasCompletedOnboarding,
                notificationState: notificationState
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
        .dastakFullScreenCover(isPresented: $showingV1Order) {
            DastakV1MatchingView(model: model)
        }
        .sheet(isPresented: $showingParcel) {
            DastakParcelComposerView(
                model: model,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation
            )
        }
        .dastakFullScreenCover(isPresented: $showingCheckout) {
            if let session = model.checkoutSession {
                DastakRazorpayCheckoutView(
                    session: session,
                    customerName: model.checkoutCustomer?.displayName,
                    customerEmail: model.checkoutCustomer?.email,
                    customerPhone: model.checkoutCustomer?.phoneNumber
                ) { result in
                    switch result {
                    case let .succeeded(completion):
                        Task {
                            if session.entityType == .dastakV1Order {
                                do {
                                    _ = try await model.completeV1CustomCheckout(
                                        session: session,
                                        providerOrderID: completion.orderID,
                                        providerPaymentID: completion.paymentID,
                                        providerSignature: completion.signature
                                    )
                                } catch {
                                    model.clearCheckoutSession()
                                    showingCheckout = false
                                    selectedTab = .orders
                                    model.v1OrderErrorMessage = "We're still checking your payment. No second charge will be attempted."
                                    showingV1Order = true
                                    return
                                }
                            }

                            model.clearCheckoutSession()
                            showingCheckout = false
                            selectedTab = .orders
                            isConfirmingPayment = true
                            let confirmed = await model.waitForPaymentConfirmation(session: session)
                            isConfirmingPayment = false
                            if !confirmed {
                                if session.entityType == .dastakV1Order {
                                    model.v1OrderErrorMessage = "We're waiting for payment confirmation. This usually takes a few seconds."
                                } else {
                                    model.errorMessage = "Authorization returned successfully. We are waiting for secure payment confirmation."
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
            DastakMatteBackground(style: .dark)
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
