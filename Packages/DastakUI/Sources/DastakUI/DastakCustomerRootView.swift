import Combine
import Foundation
import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

private let dastakOrderNotificationOpened = Notification.Name("dastak.notification.orderOpened")
private let dastakPendingOrderIDKey = "dastak.notification.pendingOrderID"

public struct DastakCustomerRootView: View {
    private enum Tab: Hashable {
        case home
        case search
        case orders
        case account
    }

    private enum DeliveryAddressEditorMode: String, Identifiable {
        case onboarding
        case edit

        var id: String { rawValue }
        var requiresCompletion: Bool { self == .onboarding }
    }

    @StateObject private var model: DastakCustomerModel
    @StateObject private var locationManager = DastakLocationManager()
    @State private var selectedTab: Tab = .home
    @State private var deliveryAddressEditorMode: DeliveryAddressEditorMode?
    @State private var showingCart = false
    @State private var showingParcel = false
    @State private var showingCheckout = false
    @State private var isConfirmingPayment = false
    @Environment(\.marketplaceSignOut) private var signOut
    private let isPreview: Bool

    public init(
        functions: any FunctionClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil
    ) {
        _model = StateObject(
            wrappedValue: DastakCustomerModel(
                functions: functions,
                checkoutCustomerProvider: checkoutCustomerProvider
            )
        )
        isPreview = false
    }

    #if DEBUG
    public init(preview: Bool) {
        _model = StateObject(wrappedValue: DastakCustomerModel.preview())
        isPreview = preview
    }
    #endif

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DastakHomeView(
                    model: model,
                    chooseLocation: { deliveryAddressEditorMode = .edit },
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
                    openCart: { showingCart = true }
                )
            }
            .tag(Tab.search)
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                DastakOrdersView(model: model)
            }
            .tag(Tab.orders)
            .tabItem { Label("Orders", systemImage: "clock") }

            NavigationStack {
                DastakAccountView(
                    customer: model.checkoutCustomer,
                    location: model.selectedLocation,
                    discoveryRadiusKilometres: model.discoveryRadiusKilometres,
                    refreshFailure: model.accountRefreshFailure,
                    chooseLocation: { deliveryAddressEditorMode = .edit },
                    retryAccount: { Task { await model.refreshCheckoutCustomer() } }
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
            locationManager.requestLocation()
            await model.bootstrap()
            if !model.hasCompleteDeliveryAddress {
                deliveryAddressEditorMode = .onboarding
            }
            if consumePendingOrderID() != nil {
                selectedTab = .orders
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: dastakOrderNotificationOpened)) { _ in
            selectedTab = .orders
        }
        .sheet(item: $deliveryAddressEditorMode) { mode in
            DastakDeliveryAddressEditor(
                requiresCompletion: mode.requiresCompletion,
                initialLocation: model.selectedLocation,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation,
                save: { location in
                    await model.setLocation(location)
                }
            )
            .interactiveDismissDisabled(mode.requiresCompletion)
            .presentationDetents(mode.requiresCompletion ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
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
                        model.errorMessage = message.isEmpty ? "Payment failed. You can try again." : message
                    case .dismissed:
                        break
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

    private func consumePendingOrderID() -> String? {
        let orderID = UserDefaults.standard.string(forKey: dastakPendingOrderIDKey)
        UserDefaults.standard.removeObject(forKey: dastakPendingOrderIDKey)
        return orderID
    }
}

private struct DastakCustomerNotice: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text(message)
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.dastakText.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(MarketplaceSpacing.compact)
        .background(MarketplaceColors.dastakSurface.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MarketplaceColors.dividerDark.color, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    }
}

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
