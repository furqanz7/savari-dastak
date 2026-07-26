import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

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
    @State private var showingLocationPicker = false
    @State private var showingCart = false
    @State private var showingParcel = false
    @State private var showingCheckout = false
    private let isPreview: Bool

    public init(functions: any FunctionClient) {
        _model = StateObject(wrappedValue: DastakCustomerModel(functions: functions))
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
                    chooseLocation: { showingLocationPicker = true },
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
                    location: model.selectedLocation,
                    discoveryRadiusKilometres: model.discoveryRadiusKilometres,
                    chooseLocation: { showingLocationPicker = true }
                )
            }
            .tag(Tab.account)
            .tabItem { Label("Account", systemImage: "person") }
        }
        .tint(MarketplaceColors.dastakAccent.color)
        .marketplacePage()
        .task {
            guard !isPreview else { return }
            locationManager.requestLocation()
            await model.bootstrap()
        }
        .onReceive(locationManager.$location.compactMap { $0 }) { location in
            guard model.selectedLocation == nil else { return }
            Task { await model.setLocation(location) }
        }
        .sheet(isPresented: $showingLocationPicker) {
            DastakLocationPicker(
                title: "Delivery location",
                currentLocation: locationManager.location,
                useLocation: { location in
                    Task { await model.setLocation(location) }
                },
                requestCurrentLocation: locationManager.requestLocation
            )
        }
        .sheet(isPresented: $showingCart) {
            DastakCartView(model: model)
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
                DastakCheckoutPlaceholderView(session: session) {
                    model.clearCheckoutSession()
                    showingCheckout = false
                    selectedTab = .orders
                }
            }
        }
        .onChange(of: model.checkoutSession) { _, session in
            showingCheckout = session != nil
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
}

private struct DastakCheckoutPlaceholderView: View {
    let session: DastakCheckoutSession
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)

                VStack(spacing: 8) {
                    Text("Secure payment")
                        .font(.title2.bold())
                    Text(DastakFormatting.money(.init(paise: session.amountPaise)))
                        .font(.largeTitle.bold().monospacedDigit())
                    Text("Razorpay checkout is ready.")
                        .foregroundStyle(.secondary)
                }

                Button("Continue") {
                    dismiss()
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
            }
            .padding(24)
            .navigationTitle("Payment")
            .dastakInlineNavigationTitle()
        }
        .presentationDetents([.medium])
    }
}
