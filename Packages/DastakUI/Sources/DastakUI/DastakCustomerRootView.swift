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
    @State private var showingParcel = false
    @State private var showingCheckout = false
    @State private var isConfirmingPayment = false
    @Environment(\.marketplaceSignOut) private var signOut
    private let isPreview: Bool
    private let deliveryPartnerAccess: DeliveryPartnerAccess
    private let isDeliveryPartnerAccessLoading: Bool
    private let becomeDeliveryPartner: () -> Void

    public init(
        functions: any FunctionClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil,
        deliveryPartnerAccess: DeliveryPartnerAccess = .unavailable,
        isDeliveryPartnerAccessLoading: Bool = false,
        becomeDeliveryPartner: @escaping () -> Void = {}
    ) {
        _model = StateObject(
            wrappedValue: DastakCustomerModel(
                functions: functions,
                checkoutCustomerProvider: checkoutCustomerProvider,
                accountIDProvider: accountIDProvider
            )
        )
        isPreview = false
        self.deliveryPartnerAccess = deliveryPartnerAccess
        self.isDeliveryPartnerAccessLoading = isDeliveryPartnerAccessLoading
        self.becomeDeliveryPartner = becomeDeliveryPartner
    }

    #if DEBUG
    public init(preview: Bool) {
        _model = StateObject(wrappedValue: DastakCustomerModel.preview())
        isPreview = preview
        deliveryPartnerAccess = .notApplied
        isDeliveryPartnerAccessLoading = false
        becomeDeliveryPartner = {}
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
                    discoveryRadiusKilometres: model.discoveryRadiusKilometres,
                    refreshFailure: model.accountRefreshFailure,
                    deliveryPartnerAccess: deliveryPartnerAccess,
                    isDeliveryPartnerAccessLoading: isDeliveryPartnerAccessLoading,
                    chooseLocation: { showingDeliveryAddressEditor = true },
                    openOrders: { selectedTab = .orders },
                    becomeDeliveryPartner: becomeDeliveryPartner,
                    retryAccount: { Task { await model.refreshCheckoutCustomer() } },
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
            DastakDeliveryAddressEditor(
                requiresCompletion: false,
                initialLocation: model.deliveryAddress ?? model.selectedLocation,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation,
                save: { location in
                    await model.setLocation(location)
                }
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
                requestCurrentLocation: locationManager.requestLocation
            )
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
                                model.errorMessage = "Payment was received. We are confirming it securely and will update your order shortly."
                            }
                        }
                    case let .failed(message):
                        model.clearCheckoutSession()
                        showingCheckout = false
                        selectedTab = .orders
                        model.ordersActionMessage = message.isEmpty
                            ? "Payment failed. You can try again from Orders."
                            : message
                    case .dismissed:
                        model.clearCheckoutSession()
                        showingCheckout = false
                        selectedTab = .orders
                        model.ordersActionMessage = "Payment was not completed. Your order is saved and you can retry here."
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
        ordersPath = [destination]
        Task { await model.refreshOrdersAndParcels() }
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
