import Combine
import DastakDomain
import Foundation
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

private let dastakOrderNotificationOpened = Notification.Name("dastak.notification.orderOpened")
private let dastakPendingEntityTypeKey = "dastak.notification.pendingEntityType"
private let dastakPendingEntityIDKey = "dastak.notification.pendingEntityID"
private let dastakLegacyPendingOrderIDKey = "dastak.notification.pendingOrderID"

public struct DastakCustomerRootView: View {
    @StateObject private var model: DastakCustomerModel
    @StateObject private var locationManager = DastakLocationManager()
    @StateObject private var haptics = MarketplaceHapticScope()
    @State private var navigation = DastakCustomerNavigation(service:
        DastakCustomerService(rawValue: UserDefaults.standard.string(forKey: "dastak.customer.lastService") ?? "") ?? .grocery)
    @State private var isReadyForAppAction = false
    @State private var appActionTask: Task<Void, Never>?
    @State private var ordersPath: [DastakCustomerDestination] = []
    @State private var showingDeliveryAddressEditor = false
    @State private var showingDiscoveryLocationPicker = false
    @State private var onboardingStep: DastakCustomerOnboardingStep?
    @State private var showingCart = false
    @State private var showingV1Order = false
    @State private var showingParcel = false
    @State private var showingCheckout = false
    @State private var isConfirmingPayment = false
    @State private var riderCallURL: URL?
    @State private var showingRiderCall = false
    @Environment(\.openURL) private var openURL
    @Environment(\.marketplaceSignOut) private var signOut
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
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
    public init(preview: Bool, shoppingFixtures: Bool = false) {
        _model = StateObject(wrappedValue: DastakCustomerModel.preview(panelFixtures: true, shoppingFixtures: shoppingFixtures))
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
        GeometryReader { geometry in
            let layout = DastakCustomerLayout(width: geometry.size.width, height: geometry.size.height,
                                              largerText: dynamicTypeSize >= .xxxLarge)
            VStack(spacing: 10) {
                Group {
                    if layout.usesCompactControls {
                        customerChrome(width: geometry.size.width, compact: true)
                    } else {
                        ScrollView { customerChrome(width: geometry.size.width, compact: false) }
                            .scrollIndicators(.hidden)
                            .frame(height: layout.inlineChromeHeight)
                    }
                }
                .opacity(showingCart ? 0 : 1)
                .allowsHitTesting(!showingCart)
                .accessibilityHidden(showingCart)

                ZStack {
                    // Retain exploration and scroll state independently for each service.
                    homePanel(.grocery)
                        .customerSectionVisible(navigation.section == .home && navigation.service == .grocery)
                    homePanel(.food)
                        .customerSectionVisible(navigation.section == .home && navigation.service == .food)
                    NavigationStack(path: $ordersPath) {
                        DastakOrdersView(model: model, openCart: { showingCart = true },
                                         openDestination: { ordersPath.append($0) })
                    }
                    .customerSectionVisible(navigation.section == .orders)
                    NavigationStack { accountPanel(.profile) }
                        .customerSectionVisible(navigation.section == .profile)
                    NavigationStack { accountPanel(.settings) }
                        .customerSectionVisible(navigation.section == .settings)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .modifier(DastakMainPanelLiquidGlass())
                .padding(.horizontal, layout.panelHorizontalInset)
                .padding(.top, layout.panelDownshift)
                .opacity(showingCart ? 0 : 1)
                .allowsHitTesting(!showingCart)
                .accessibilityHidden(showingCart)
                contextualBars
                    .opacity(showingCart ? 0 : 1)
                    .allowsHitTesting(!showingCart)
                    .accessibilityHidden(showingCart)
            }
        }
        .dastakBasketExperience(model: model, service: navigation.service.basketService, showsDock: false,
                               openCart: { openCart(navigation.service.basketService) })
        .allowsHitTesting(!showingCart)
        .accessibilityHidden(showingCart)
        .tint(MarketplaceColors.accent(for: colorScheme))
        .onAppear {
            haptics.isActive = scenePhase == .active
            model.hapticFeedback = { [weak haptics] event in haptics?.play(event) }
        }
        .onChange(of: scenePhase) { _, phase in haptics.isActive = phase == .active }
        .onChange(of: model.v1Orders) { _, _ in
            guard !isPreview else { return }
            Task { await model.syncOrderLiveTracking() }
        }
        .onChange(of: model.activeV1Order) { _, _ in
            guard !isPreview else { return }
            Task { await model.syncOrderLiveTracking() }
        }
        .environment(\.dastakOpenCart, DastakOpenCartAction { service in openCart(service) })
        .background {
            DastakNativeEnvironment(place: .customer(service:navigation.service,
                cartPresented:showingCart, basketService:model.cartService))
        }
        .environment(\.marketplaceImmersiveEnvironment, true)
        .onChange(of: model.cartService) { _, service in
            let destination: DastakCustomerService = service == .food ? .food : .grocery
            if navigation.service != destination { navigation.selectService(destination) }
        }
        .onChange(of: navigation.section) { _, section in
            guard !isPreview else { return }
            Task {
                switch section {
                case .home:
                    await model.refreshV1Catalogue()
                case .orders:
                    await model.refreshOrdersAndParcels()
                case .profile, .settings:
                    async let customer: Void = model.refreshCheckoutCustomer()
                    async let identities: Bool = model.refreshCustomerIdentities()
                    _ = await (customer, identities)
                }
            }
        }
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
            await prepareCustomer()
        }
        .task {
            guard !isPreview else { return }
            await observeOrderChanges()
        }
        #if DEBUG
        .task {
            // Explicit opt-in, synthetic integration checks when simulator taps
            // are unavailable. Never mounted by the authenticated Release root.
            let args = ProcessInfo.processInfo.arguments
            guard isPreview, args.contains("-DastakUIPreviewShopping"),
                  let index = args.firstIndex(of: "-DastakUIPreviewEnvironmentStep"),
                  args.indices.contains(index + 1) else { return }
            let step = args[index + 1]
            guard ["grocery-cart", "food-home", "food-added", "food-cart", "billing-switch", "cycle", "reorder-review", "notice-review"].contains(step) else { return }
            if step == "billing-switch" {
                navigation.selectService(.food)
                openCart(.food)
                // Finite, local-only renderer regression check; no commerce action.
                do {
                    try await Task.sleep(for: .seconds(6))
                    for service: DastakBasketService in [.grocery,.food,.grocery,.food] {
                        model.cartService = service
                        try await Task.sleep(for: .seconds(3))
                    }
                } catch { return }
                return
            }
            if step == "notice-review" {
                if let milk = model.knownCatalogueProducts.first(where: { $0.packSize == "1 litre" }) {
                    model.addToCart(milk)
                }
                navigation.navigate(.orders)
                model.ordersActionMessage = "Added 1 item to your Grocery basket. Review prices and availability before placing your order."
                return
            }
            if step == "reorder-review" {
                // Nonempty independent baskets make replacement consent and
                // cancellation visible. Only the synthetic shopping root runs this.
                if let milk = model.knownCatalogueProducts.first(where: { $0.packSize == "1 litre" }) {
                    model.addToCart(milk)
                    model.addToCart(milk)
                }
                if let restaurant = model.v1Restaurants.first,
                   let item = restaurant.categories.first?.items.first {
                    model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [])
                    model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [])
                }
                model.cartService = .grocery
                navigation.navigate(.orders)
                return
            }
            if step == "grocery-cart" || step == "cycle" {
                if let product = model.v1Catalogue?.skus.first { model.addToCart(product) }
                showingCart = true
            } else {
                navigation.selectService(.food)
                if step != "food-home", let restaurant = model.v1Restaurants.first,
                   let item = restaurant.categories.first?.items.first {
                    model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [])
                }
                showingCart = step == "food-cart"
            }
            guard step == "cycle" else { return }
            // Exercise sheet dismissal and service changes within one mounted
            // Customer root. Finite and cancellable; no order/account writes.
            do {
                try await Task.sleep(for: .seconds(12))
                showingCart = false
                navigation.selectService(.food)
                model.cartService = .food
                try await Task.sleep(for: .seconds(12))
                if let restaurant = model.v1Restaurants.first,
                   let item = restaurant.categories.first?.items.first {
                    model.addFoodToCart(restaurant: restaurant, item: item, optionIDs: [])
                }
                showingCart = true
                try await Task.sleep(for: .seconds(12))
                showingCart = false
                model.clearCart()
            } catch { return }
        }
        #endif
        .task {
            guard !isPreview else { return }
            await pollOrderChanges()
        }
        .task(id: scenePhase) {
            guard !isPreview, scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.refreshAreaAvailability(force: true)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isPreview, phase == .active else { return }
            Task {
                await model.refreshAreaAvailability(force: true)
                await model.refreshOrdersAndParcels()
                await model.syncOrderLiveTracking()
                await model.refreshCustomerIdentities()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: dastakOrderNotificationOpened)) { notification in
            guard let destination = DastakCustomerDestination(
                notificationPayload: notification.userInfo ?? [:]
            ) else { return }
            open(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: DastakAppActionInbox.opened)) { _ in
            consumeAppAction()
        }
        .onChange(of: navigation.service) { _, service in
            UserDefaults.standard.set(service.rawValue, forKey: "dastak.customer.lastService")
        }
        .onDisappear { appActionTask?.cancel() }
        .sheet(isPresented: $showingDeliveryAddressEditor) {
            DastakAddressBookView(
                model: model,
                requiresCompletion: false,
                currentLocation: locationManager.location,
                requestCurrentLocation: locationManager.requestLocation,
                currentLocationError: locationManager.errorMessage
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDiscoveryLocationPicker) {
            DastakLocationPicker(
                title: "Browse near",
                initialLocation: model.selectedLocation,
                currentLocation: locationManager.location,
                currentLocationError: locationManager.errorMessage,
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
                orderSubmitted: { showingV1Order = true },
                currentLocationError: locationManager.errorMessage
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.marketplaceImmersiveEnvironment, true)
            .presentationDetents(dynamicTypeSize >= .xxxLarge ? [.large] : [.fraction(0.75), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            // Keep both checkouts visible without changing scrims during a basket switch.
            // Shopping chrome/panels remain non-interactive while showingCart is true.
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.75)))
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
                    customerPhone: model.checkoutCustomer?.phoneNumber,
                    prepareTestRehearsal: { outcome in
                        try await model.prepareV1TestRehearsal(session: session, outcome: outcome)
                    }
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
                                    navigation.navigate(.orders)
                                    model.v1OrderErrorMessage = "We're still checking your payment. No second charge will be attempted."
                                    showingV1Order = true
                                    return
                                }
                            }

                            model.clearCheckoutSession()
                            showingCheckout = false
                            navigation.navigate(.orders)
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
                        navigation.navigate(.orders)
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
                        navigation.navigate(.orders)
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
        .alert(riderCallURL == nil ? "Calling unavailable" : "Call your delivery partner?", isPresented: $showingRiderCall) {
            if let url = riderCallURL {
                Button("Call") { openURL(url) }
            }
            Button("Cancel", role: .cancel) { riderCallURL = nil }
        } message: {
            Text(riderCallURL == nil ? "We couldn’t confirm an available delivery partner. Check the order and try again." : "This will open the phone app to call the partner currently assigned to this order.")
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
        // Outside all presentation modifiers so sheets/covers inherit the same
        // action scope. Full-screen details must not disable their own feedback.
        .environment(\.marketplaceHapticScope, haptics)
    }

    // Keep asynchronous startup outside the large SwiftUI result-builder chain
    // so both simulator architectures can type-check it on the CI toolchain.
    private func prepareCustomer() async {
        guard !isPreview else {
            isReadyForAppAction = true
            consumeAppAction()
            return
        }
        // The shared auth shell verifies the session before mounting this view.
        await model.bootstrap()
        let notificationState = await DastakNotificationPreferences.status()
        if notificationState != .notRequested {
            model.completeOnboarding()
        }
        onboardingStep = DastakCustomerOnboardingStep.next(
            hasCompleted: model.hasCompletedOnboarding,
            notificationState: notificationState
        )
        isReadyForAppAction = true
        if DastakAppActionInbox().peek() != nil {
            consumeAppAction()
        } else if let destination = consumePendingDestination() {
            open(destination)
        } else {
            showingV1Order = model.activeV1Order != nil
        }
    }

    private func consumeAppAction() {
        guard isReadyForAppAction, let action = DastakAppActionInbox().consume() else { return }
        appActionTask?.cancel()
        showingCart = false
        showingV1Order = false
        showingParcel = false
        showingCheckout = false
        showingDeliveryAddressEditor = false
        showingDiscoveryLocationPicker = false
        ordersPath = []
        let presentation = navigation.apply(action,
            basketHasItems: model.baskets[navigation.service.basketService].itemCount > 0)
        model.cartService = navigation.service.basketService
        if action == .grocery || action == .food || action == .search { model.searchText = "" }
        // Allow an existing sheet to dismiss before presenting the new destination.
        appActionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            switch presentation {
            case .home: break
            case .basket: openCart(navigation.service.basketService)
            case .emptyBasket: model.errorMessage = "Your basket is empty. Add an item before opening your cart."
            case .tracking: showingV1Order = model.activeV1Order != nil
            }
        }
    }

    private func open(_ destination: DastakCustomerDestination) {
        navigation.navigate(.orders)
        switch destination {
        case let .dastakV1Order(orderID):
            ordersPath = []
            let callKey = "dastak.liveActivity.pendingCallOrder"
            let shouldCall = UserDefaults.standard.string(forKey: callKey).flatMap(UUID.init(uuidString:)) == orderID
            UserDefaults.standard.removeObject(forKey: callKey)
            Task {
                if shouldCall {
                    riderCallURL = await model.liveActivityRiderCallURL(orderID: orderID)
                    showingRiderCall = true
                    return
                }
                if await model.focusV1Order(id: orderID) {
                    showingV1Order = true
                }
            }
        case .merchantOrder, .parcel:
            ordersPath = [destination]
            Task { await model.refreshOrdersAndParcels() }
        }
    }

    private func selectService(_ service: DastakCustomerService) {
        let resetsHome = navigation.service == service
        guard navigation.selectService(service) else { return }
        if resetsHome { model.searchText = "" }
        model.cartService = service.basketService
    }

    private func openCart(_ service: DastakBasketService) {
        // Select before presentation: a remembered basket must not choose the first
        // billing frame when the customer opens the basket from another service.
        model.cartService = service
        showingCart = true
    }

    private func customerChrome(width: CGFloat, compact: Bool) -> some View {
        DastakCustomerChrome(
            navigation: navigation,
            locationLabel: model.deliveryAddress?.label ?? "Choose your location",
            map: model.v1BrowseMap,
            selectSection: { section in
                navigation.navigate(section)
                if section == .home { model.searchText = "" }
            },
            selectService: selectService,
            chooseLocation: { showingDeliveryAddressEditor = true },
            openDirectory: openDirectory,
            availableWidth: width, compact: compact
        )
    }

    private func openDirectory(_ key: String) {
        let keys = Set((model.v1BrowseMap?.nodes ?? []).filter { $0.kind == "DESTINATION" }.map(\.key))
        _ = navigation.openDirectory(key, allowedKeys: keys)
    }

    private func homePanel(_ service: DastakCustomerService) -> some View {
        NavigationStack {
            DastakHomeView(model: model,
                chooseLocation: { showingDeliveryAddressEditor = true },
                openCart: { openCart(service.basketService) }, sendParcel: { showingParcel = true },
                shellService: service,
                homeRevision: service == .grocery ? navigation.groceryHomeRevision : navigation.foodHomeRevision,
                startsWithSearch: navigation.startsWithSearch && navigation.service == service,
                directoryKey: navigation.directoryKey, directoryRevision: navigation.directoryRevision,
                isActive: navigation.section == .home && navigation.service == service,
                onBrowseDestinationChanged: { key in
                    guard service == .grocery else { return }
                    let keys = Set((model.v1BrowseMap?.nodes ?? []).filter { $0.kind == "DESTINATION" }.map(\.key))
                    navigation.updateDirectoryHighlight(key, allowedKeys: keys)
                })
                // Recreate exploration/scroll state on an explicit Home reset, never the basket model.
                .id(service == .grocery ? navigation.groceryHomeRevision : navigation.foodHomeRevision)
        }
    }

    private func accountPanel(_ panel: DastakCustomerAccountPanel) -> some View {
        DastakAccountView(
            customerModel: model, customer: model.checkoutCustomer,
            location: model.defaultDeliveryAddress, savedAddressCount: model.savedAddresses.count,
            accountSessionClient: accountSessionClient, linkedIdentities: model.linkedIdentities,
            isLinkingIdentity: model.isLinkingIdentity, identityMessage: model.identityMessage,
            identityMessageIsSuccess: model.identityMessageIsSuccess, hasActiveOrders: model.hasActiveOrders,
            refreshFailure: model.accountRefreshFailure,
            merchantOnboardingState: merchantOnboardingState, isMerchantAccessLoading: isMerchantAccessLoading,
            deliveryPartnerAccess: deliveryPartnerAccess, isDeliveryPartnerAccessLoading: isDeliveryPartnerAccessLoading,
            chooseLocation: { showingDeliveryAddressEditor = true },
            openOrders: { navigation.navigate(.orders) },
            becomeMerchant: becomeMerchant, becomeDeliveryPartner: becomeDeliveryPartner,
            retryAccount: { Task { await model.refreshCheckoutCustomer() } },
            refreshIdentities: { Task { await model.refreshCustomerIdentities() } },
            linkIdentity: { provider in Task { await model.linkIdentity(provider) } },
            updateProfile: { try await model.updateAccountProfile(displayName: $0, phoneNumber: $1) },
            deleteAccount: { try await model.deleteAccount(); await signOut() },
            reauthenticate: { provider in
                guard let oauthReauthenticator else { throw MarketplaceAuthenticatedServicesError.authenticationRequired }
                try await oauthReauthenticator(provider)
            },
            exportAccount: { try await model.exportAccount() }, panel: panel,
            isActive: panel == .profile ? navigation.section == .profile : navigation.section == .settings
        )
    }

    private var contextualBars: some View {
        VStack(spacing: 6) {
            DastakBasketDock(model: model, service: navigation.service.basketService,
                             openCart: { openCart(navigation.service.basketService) })
            if let order = model.activeV1Order, DastakCustomerModel.isActiveV1Order(order.status) {
                MarketplaceFeedbackButton { showingV1Order = true } label: {
                    HStack {
                        Image(systemName: "circle.fill").font(.system(size: 7))
                        Text(DastakV1OrderPresentation.title(order.status, trackingPhase: order.tracking?.phase,
                                                            fulfilmentState: order.fulfilmentProgress?.state)).font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .marketplaceGlass(cornerRadius: 16)
                .accessibilityIdentifier("dastak.active-order")
            }
        }
        .padding(.horizontal, 12)
    }

    private var bucketSummary: String {
        let basket = model.baskets[navigation.service.basketService]
        return "\(basket.itemCount) \(basket.itemCount == 1 ? "item" : "items") · \(DastakFormatting.money(basket.subtotal)) estimated"
    }

    private func consumePendingDestination() -> DastakCustomerDestination? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dastakPendingEntityTypeKey) != "delivery" else { return nil }
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
                for try await event in orderEvents.events(accountID: accountID) {
                    guard !Task.isCancelled else { return }
                    switch event.entityKind {
                    case .parcel:
                        if model.customerParcel(withID: event.entityID) != nil {
                            await model.refreshParcelDetail(parcelID: event.entityID)
                        } else {
                            await model.refreshParcels()
                        }
                    case .merchantOrder:
                        if model.activeV1Order?.id == event.entityID {
                            await model.refreshActiveV1Order()
                        } else if model.v1Orders.contains(where: { $0.id == event.entityID }) {
                            await model.refreshV1Orders()
                        } else if model.order(withID: event.entityID) != nil {
                            await model.refreshOrderDetail(orderID: event.entityID)
                        } else {
                            // The first event for a newly-created order is
                            // ambiguous across the legacy and V1 contracts.
                            async let legacy: Void = model.refreshOrders()
                            async let v1: Void = model.refreshV1Orders()
                            _ = await (legacy, v1)
                        }
                    }
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
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            await model.refreshOrdersAndParcels()
        }
    }
}

private extension View {
    func customerSectionVisible(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
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

private struct DastakMainPanelLiquidGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        if #available(iOS 26.0, macOS 26.0, *),
           DastakPanelReadability.surface(isDark: colorScheme == .dark, supportsNativeGlass: true,
                reduceTransparency: reduceTransparency,
                increasedContrast: contrast == .increased) != .opaque {
            // Keep one structural content branch. iOS can change appearance
            // while snapshotting a backgrounded app; swapping branches discards
            // the category and product presentation state owned by its children.
            content
                .clipShape(shape)
                .glassEffect(colorScheme == .dark ? .regular
                    : .clear.tint(.white.opacity(DastakPanelReadability.lightGlassTintOpacity)), in: shape)
        } else {
            fallback(content, shape: shape)
        }
    }

    private func fallback(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(MarketplaceColors.surface(for: colorScheme), in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(.primary.opacity(0.1), lineWidth: 1))
    }
}

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
