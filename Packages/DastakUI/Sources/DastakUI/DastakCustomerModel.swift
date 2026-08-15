import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakCustomerRefreshFailure: Equatable {
    case offline
    case sessionExpired
    case accessUnavailable
    case unavailable

    var title: String {
        switch self {
        case .offline: return "You are offline"
        case .sessionExpired: return "Your session expired"
        case .accessUnavailable: return "Customer access unavailable"
        case .unavailable: return "Updates are unavailable"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "Reconnect to refresh your latest orders and deliveries."
        case .sessionExpired:
            "Sign in again to view your latest orders and deliveries."
        case .accessUnavailable:
            "This account cannot load customer updates right now. Sign in again if the issue continues."
        case .unavailable:
            "Dastak could not refresh this information. Please try again."
        }
    }

    var symbol: String {
        switch self {
        case .offline: return "wifi.exclamationmark"
        case .sessionExpired: return "person.crop.circle.badge.exclamationmark"
        case .accessUnavailable: return "lock.trianglebadge.exclamationmark"
        case .unavailable: return "arrow.clockwise"
        }
    }

    var actionTitle: String {
        self == .sessionExpired ? "Sign in again" : "Try again"
    }
}

@MainActor
final class DastakCustomerModel: ObservableObject {
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var orders: [MerchantOrderSnapshot] = []
    @Published private(set) var quote: MerchantOrderQuote?
    @Published private(set) var checkoutSession: DastakCheckoutSession?
    @Published private(set) var checkoutCustomer: MarketplaceCheckoutCustomer?
    @Published var selectedPaymentMethod: DastakPaymentMethod = .googlePay
    @Published private(set) var parcelQuote: ParcelQuote?
    @Published private(set) var parcels: [CustomerParcelDelivery] = []
    @Published private(set) var isLoadingCatalogue = false
    @Published private(set) var isLoadingOrders = false
    @Published private(set) var isLoadingParcels = false
    @Published private(set) var isCheckingOut = false
    @Published var selectedLocation: DastakDeliveryLocation?
    @Published private(set) var deliveryAddress: DastakDeliveryLocation?
    @Published var discoveryRadiusKilometres = 10
    @Published var searchText = ""
    @Published var cart = DastakCart()
    @Published var errorMessage: String?
    @Published var cartErrorMessage: String?
    @Published var parcelErrorMessage: String?
    @Published var ordersActionMessage: String?
    @Published private(set) var addressErrorMessage: String?
    @Published private(set) var catalogueRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var accountRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var ordersRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var parcelsRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var sessionExpired = false
    @Published private(set) var isDeliveryAddressConfirmed = false
    @Published private(set) var hasCompletedOnboarding = false

    let parcelClient: any ParcelDeliveryClient

    private let catalogueClient: any CatalogueClient
    private let orderClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient
    private let addressClient: any CustomerAddressClient
    private let accountProfileClient: any AccountProfileClient
    private let deviceTokenClient: SupabaseDastakDeviceTokenClient?
    private let checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)?
    private let accountIDProvider: (@Sendable () async throws -> UUID)?
    private var preferenceScope = "default"
    private var orderPlacementAttempt = DastakOrderPlacementAttempt()
    private var parcelPlacementAttempt = DastakOrderPlacementAttempt()

    init(
        catalogueClient: any CatalogueClient,
        orderClient: any MerchantOrderClient,
        parcelClient: any ParcelDeliveryClient,
        checkoutClient: any DastakCheckoutClient,
        addressClient: any CustomerAddressClient,
        accountProfileClient: any AccountProfileClient,
        deviceTokenClient: SupabaseDastakDeviceTokenClient? = nil,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil
    ) {
        self.catalogueClient = catalogueClient
        self.orderClient = orderClient
        self.parcelClient = parcelClient
        self.checkoutClient = checkoutClient
        self.addressClient = addressClient
        self.accountProfileClient = accountProfileClient
        self.deviceTokenClient = deviceTokenClient
        self.checkoutCustomerProvider = checkoutCustomerProvider
        self.accountIDProvider = accountIDProvider
    }

    convenience init(
        functions: any FunctionClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil
    ) {
        self.init(
            catalogueClient: SupabaseCatalogueClient(functions: functions),
            orderClient: SupabaseMerchantOrderClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: functions),
            addressClient: SupabaseCustomerAddressClient(functions: functions),
            accountProfileClient: SupabaseAccountProfileClient(functions: functions),
            deviceTokenClient: SupabaseDastakDeviceTokenClient(functions: functions),
            checkoutCustomerProvider: checkoutCustomerProvider,
            accountIDProvider: accountIDProvider
        )
    }

    var activeProducts: [CatalogueProduct] {
        guard let products = catalogue?.products else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var hasCompleteDeliveryAddress: Bool {
        guard isDeliveryAddressConfirmed,
              let deliveryAddress,
              deliveryAddress.isReadyForDelivery else { return false }
        return true
    }

    var ordersAndParcelsRefreshFailure: DastakCustomerRefreshFailure? {
        let failures = [ordersRefreshFailure, parcelsRefreshFailure].compactMap { $0 }
        return failures.first(where: { $0 == .sessionExpired }) ?? failures.first
    }

    func bootstrap() async {
        await restorePreferencesAndAddress()
        async let orders: Void = refreshOrders()
        async let parcels: Void = refreshParcels()
        async let deviceToken: Void = registerDeviceTokenIfAvailable()
        async let checkoutCustomer: Void = refreshCheckoutCustomer()
        if selectedLocation != nil {
            async let catalogue: Void = refreshCatalogue()
            _ = await (orders, parcels, catalogue, deviceToken, checkoutCustomer)
        } else {
            _ = await (orders, parcels, deviceToken, checkoutCustomer)
        }
    }

    func registerDeviceTokenIfAvailable() async {
        guard let token = UserDefaults.standard.string(forKey: "dastak.apns.deviceToken"),
              !token.isEmpty,
              let deviceTokenClient else { return }
        _ = try? await deviceTokenClient.register(token: token, idempotencyKey: makeKey())
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: preferenceKey("onboardingCompleted"))
    }

    func refreshCheckoutCustomer() async {
        guard let checkoutCustomerProvider else { return }
        do {
            checkoutCustomer = try await checkoutCustomerProvider()
            accountRefreshFailure = nil
        } catch {
            accountRefreshFailure = refreshFailure(for: error)
        }
    }

    func updateAccountProfile(displayName: String, phoneNumber: String) async throws {
        let profile = try await accountProfileClient.update(
            displayName: displayName,
            phoneNumber: phoneNumber,
            idempotencyKey: makeKey()
        )
        checkoutCustomer = MarketplaceCheckoutCustomer(
            displayName: profile.displayName,
            email: checkoutCustomer?.email,
            phoneNumber: profile.phoneNumber
        )
        accountRefreshFailure = nil
    }

    func deleteAccount() async throws {
        try await accountProfileClient.deleteAccount(idempotencyKey: makeKey())
    }

    func setLocation(_ location: DastakDeliveryLocation) async -> Bool {
        guard let label = location.label, let details = location.details else {
            addressErrorMessage = "Add a label and doorstep details before saving."
            return false
        }
        do {
            let response = try await addressClient.saveDefault(
                label: label,
                address: location.address,
                details: details,
                location: location.point,
                idempotencyKey: makeKey()
            )
            let savedAddress = response.addresses.first(where: \.isDefault)
                .map(Self.deliveryLocation) ?? location
            deliveryAddress = savedAddress
            isDeliveryAddressConfirmed = true
            addressErrorMessage = nil
            return true
        } catch {
            addressErrorMessage = message(
                for: error,
                fallback: "The address could not be saved. Check your connection and try again."
            )
            return false
        }
    }

    func selectDiscoveryLocation(_ location: DastakDeliveryLocation) async {
        selectedLocation = Self.discoveryLocation(from: location)
        quote = nil
        orderPlacementAttempt.reset()
        cartErrorMessage = nil
        persistDiscoveryPreferences()
        await refreshCatalogue()
    }

    func setDiscoveryRadius(_ kilometres: Int) async {
        guard (10...30).contains(kilometres) else { return }
        discoveryRadiusKilometres = kilometres
        persistDiscoveryPreferences()
        await refreshCatalogue()
    }

    func refreshCatalogue() async {
        guard let selectedLocation, !isLoadingCatalogue else { return }
        isLoadingCatalogue = true
        defer { isLoadingCatalogue = false }
        do {
            catalogue = try await catalogueClient.browse(
                at: selectedLocation.point,
                discoveryRadiusKilometres: discoveryRadiusKilometres,
                idempotencyKey: makeKey()
            )
            catalogueRefreshFailure = nil
        } catch {
            catalogueRefreshFailure = refreshFailure(for: error)
        }
    }

    func refreshOrders() async {
        guard !isLoadingOrders else { return }
        isLoadingOrders = true
        defer { isLoadingOrders = false }
        do {
            orders = try await orderClient.customerSnapshot(
                idempotencyKey: makeKey()
            ).orders
            .sorted { $0.updatedAt > $1.updatedAt }
            ordersRefreshFailure = nil
        } catch {
            ordersRefreshFailure = refreshFailure(for: error)
        }
    }

    func refreshParcels() async {
        guard !isLoadingParcels else { return }
        isLoadingParcels = true
        defer { isLoadingParcels = false }
        do {
            parcels = try await parcelClient.customerSnapshot(
                idempotencyKey: makeKey()
            )
            .sorted {
                ($0.parcel.updatedAt ?? $0.parcel.createdAt ?? "") >
                    ($1.parcel.updatedAt ?? $1.parcel.createdAt ?? "")
            }
            parcelsRefreshFailure = nil
        } catch {
            parcelsRefreshFailure = refreshFailure(for: error)
        }
    }

    func refreshOrdersAndParcels() async {
        async let orders: Void = refreshOrders()
        async let parcels: Void = refreshParcels()
        _ = await (orders, parcels)
    }

    /// Checkout completion is not payment authority. Wait briefly for the
    /// signed Razorpay webhook to update this customer's server-side order.
    func waitForPaymentConfirmation(session: DastakCheckoutSession) async -> Bool {
        for attempt in 0..<6 {
            switch session.entityType {
            case .merchantOrder:
                await refreshOrders()
                if let order = orders.first(where: { $0.orderID == session.orderID }), order.paymentState == .paid {
                    return true
                }
            case .parcel:
                await refreshParcels()
                if let parcel = parcels.first(where: { $0.parcel.parcelID == session.orderID }),
                   parcel.parcel.paymentStatus == .paid {
                    return true
                }
            }
            guard attempt < 5 else { break }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return false
    }

    func prepareQuote() async {
        guard hasCompleteDeliveryAddress,
              let storeID = cart.storeID,
              let deliveryAddress,
              !cart.entries.isEmpty else { return }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            quote = try await orderClient.quote(
                storeID: storeID,
                lines: cart.orderLines,
                dropoff: deliveryAddress.point,
                idempotencyKey: makeKey()
            )
            orderPlacementAttempt.reset()
            cartErrorMessage = nil
        } catch {
            cartErrorMessage = message(for: error, fallback: "The final price could not be calculated.")
        }
    }

    func createOrderAndCheckout() async -> MerchantOrderSnapshot? {
        guard hasCompleteDeliveryAddress, let quote, !isCheckingOut else { return nil }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            let order = try await orderClient.create(
                quoteID: quote.quoteID,
                idempotencyKey: orderPlacementAttempt.key(for: quote.quoteID, makeKey: makeKey)
            )
            orders = [order] + orders.filter { $0.orderID != order.orderID }
            cart.removeAll()
            self.quote = nil
            orderPlacementAttempt.reset()
            cartErrorMessage = nil
            do {
                checkoutSession = try await checkoutClient.createMerchantOrderCheckout(
                    orderID: order.orderID,
                    idempotencyKey: makeKey()
                )
            } catch {
                ordersActionMessage = "Your order is saved. Payment could not start, so you can retry from Orders."
            }
            return order
        } catch {
            cartErrorMessage = message(for: error, fallback: "The order could not be placed. Try again without changing your basket.")
            return nil
        }
    }

    func cancel(_ order: MerchantOrderSnapshot, reason: String = "Cancelled by customer") async {
        do {
            let updated = try await orderClient.customerCancel(
                orderID: order.orderID,
                reason: reason,
                idempotencyKey: makeKey()
            )
            orders = [updated] + orders.filter { $0.orderID != updated.orderID }
            if updated.paymentState == .refundPending,
               updated.refundDecision?.decisionStatus == .eligible {
                do {
                    _ = try await checkoutClient.processMerchantOrderRefund(
                        orderID: updated.orderID,
                        idempotencyKey: makeKey()
                    )
                    ordersActionMessage = "Cancellation confirmed. Your refund is processing."
                } catch {
                    ordersActionMessage = "Cancellation confirmed. Your refund is queued and will update here."
                }
            } else if updated.refundDecision?.decisionStatus == .reviewRequired {
                ordersActionMessage = "Your cancellation request is under review. Dastak will show the refund decision here."
            } else {
                ordersActionMessage = "Order cancelled. You were not charged."
            }
            await refreshOrders()
        } catch {
            ordersActionMessage = message(for: error, fallback: "This order could not be cancelled.")
        }
    }

    func clearCheckoutSession() {
        checkoutSession = nil
    }

    func retryPayment(for order: MerchantOrderSnapshot) async {
        guard order.paymentState == .paymentPending, !isCheckingOut else { return }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            checkoutSession = try await checkoutClient.createMerchantOrderCheckout(
                orderID: order.orderID,
                idempotencyKey: makeKey()
            )
            ordersActionMessage = nil
        } catch {
            ordersActionMessage = message(for: error, fallback: "Payment could not be started.")
        }
    }

    func retryPayment(for parcel: CustomerParcelDelivery) async {
        guard parcel.audience == .sender,
              parcel.parcel.paymentStatus == .pending || parcel.parcel.paymentStatus == .failed,
              !isCheckingOut else { return }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            checkoutSession = try await checkoutClient.createParcelCheckout(
                parcelID: parcel.parcel.parcelID,
                idempotencyKey: makeKey()
            )
            ordersActionMessage = nil
        } catch {
            ordersActionMessage = message(for: error, fallback: "Payment could not be started.")
        }
    }

    func cancel(_ parcel: CustomerParcelDelivery, reason: String = "Cancelled by customer") async {
        guard parcel.audience == .sender, canCancel(parcel.parcel.status) else { return }
        do {
            let updated = try await parcelClient.cancelParcel(
                parcelID: parcel.parcel.parcelID,
                reason: reason,
                idempotencyKey: makeKey()
            )
            if updated.paymentStatus == .refundPending {
                do {
                    _ = try await checkoutClient.processParcelRefund(
                        parcelID: updated.parcelID,
                        idempotencyKey: makeKey()
                    )
                    ordersActionMessage = "Delivery cancelled. Your refund is processing."
                } catch {
                    ordersActionMessage = "Delivery cancelled. Your refund is queued and will update here."
                }
            } else {
                ordersActionMessage = "Delivery cancelled. You were not charged."
            }
            await refreshParcels()
        } catch {
            ordersActionMessage = message(for: error, fallback: "This parcel delivery could not be cancelled.")
        }
    }

    func clearCart() {
        cart.removeAll()
        quote = nil
        orderPlacementAttempt.reset()
    }

    func resetParcelQuote() {
        parcelQuote = nil
        parcelPlacementAttempt.reset()
    }

    func prepareParcelQuote(
        deliveryMethod: DeliveryMethod,
        pickup: DastakDeliveryLocation,
        dropoff: DastakDeliveryLocation
    ) async {
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            parcelQuote = try await parcelClient.quote(
                deliveryMethod: deliveryMethod,
                pickup: AddressedGeoPoint(
                    latitude: pickup.point.latitude,
                    longitude: pickup.point.longitude,
                    address: pickup.address
                ),
                dropoff: AddressedGeoPoint(
                    latitude: dropoff.point.latitude,
                    longitude: dropoff.point.longitude,
                    address: dropoff.address
                ),
                idempotencyKey: makeKey()
            )
            parcelPlacementAttempt.reset()
            parcelErrorMessage = nil
        } catch {
            parcelErrorMessage = message(for: error, fallback: "The parcel fare could not be calculated.")
        }
    }

    func createParcelAndCheckout(
        recipientName: String,
        recipientPhoneNumber: String,
        declaredContents: String,
        declaredValuePaise: Int
    ) async -> ParcelDelivery? {
        guard let parcelQuote, !isCheckingOut else { return nil }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            let parcel = try await parcelClient.createParcel(
                quoteID: parcelQuote.quoteID,
                recipientName: recipientName,
                recipientPhoneNumber: recipientPhoneNumber,
                declaredContents: declaredContents,
                declaredValuePaise: declaredValuePaise,
                idempotencyKey: parcelPlacementAttempt.key(for: parcelQuote.quoteID, makeKey: makeKey)
            )
            let customerParcel = CustomerParcelDelivery(parcel: parcel, audience: .sender)
            parcels = [customerParcel] + parcels.filter { $0.parcel.parcelID != parcel.parcelID }
            self.parcelQuote = nil
            parcelPlacementAttempt.reset()
            parcelErrorMessage = nil
            do {
                checkoutSession = try await checkoutClient.createParcelCheckout(
                    parcelID: parcel.parcelID,
                    idempotencyKey: makeKey()
                )
            } catch {
                ordersActionMessage = "Your delivery is saved. Payment could not start, so you can retry from Orders."
            }
            return parcel
        } catch {
            parcelErrorMessage = message(for: error, fallback: "The delivery could not be created. Try again without changing its details.")
            return nil
        }
    }

    private func makeKey() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private func restorePreferencesAndAddress() async {
        isDeliveryAddressConfirmed = false
        if let accountIDProvider, let accountID = try? await accountIDProvider() {
            preferenceScope = accountID.uuidString.lowercased()
        }
        selectedLocation = Self.savedDiscoveryLocation(scope: preferenceScope)
        discoveryRadiusKilometres = Self.savedDiscoveryRadius(scope: preferenceScope)
        hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: preferenceKey("onboardingCompleted")
        )

        do {
            let response = try await addressClient.snapshot(idempotencyKey: makeKey())
            if let saved = response.addresses.first(where: \.isDefault) {
                deliveryAddress = Self.deliveryLocation(saved)
                if selectedLocation == nil {
                    selectedLocation = Self.discoveryLocation(from: Self.deliveryLocation(saved))
                }
                isDeliveryAddressConfirmed = true
                persistDiscoveryPreferences()
            } else {
                deliveryAddress = nil
                isDeliveryAddressConfirmed = false
            }
            addressErrorMessage = nil
        } catch {
            addressErrorMessage = message(
                for: error,
                fallback: "Saved addresses are unavailable. Try again before ordering."
            )
        }
    }

    private func persistDiscoveryPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(discoveryRadiusKilometres, forKey: preferenceKey("discoveryRadiusKilometres"))
        if let selectedLocation,
           let data = try? JSONEncoder().encode(selectedLocation) {
            defaults.set(data, forKey: preferenceKey("discoveryLocation"))
        }
        defaults.removeObject(forKey: preferenceKey("deliveryLocation"))
    }

    private func preferenceKey(_ name: String) -> String {
        "dastak.customer.\(preferenceScope).\(name)"
    }

    private static func savedDiscoveryLocation(scope: String) -> DastakDeliveryLocation? {
        let defaults = UserDefaults.standard
        let keyPrefix = "dastak.customer.\(scope)."
        guard let data = defaults.data(forKey: keyPrefix + "discoveryLocation")
            ?? defaults.data(forKey: keyPrefix + "deliveryLocation") else {
            return nil
        }
        guard let saved = try? JSONDecoder().decode(DastakDeliveryLocation.self, from: data) else {
            return nil
        }
        return discoveryLocation(from: saved)
    }

    private static func savedDiscoveryRadius(scope: String) -> Int {
        let value = UserDefaults.standard.integer(forKey: "dastak.customer.\(scope).discoveryRadiusKilometres")
        return (10...30).contains(value) ? value : 10
    }

    private static func deliveryLocation(_ address: CustomerDeliveryAddress) -> DastakDeliveryLocation {
        DastakDeliveryLocation(
            address: address.address,
            point: address.location,
            label: address.label,
            details: address.details
        )
    }

    nonisolated static func discoveryLocation(
        from location: DastakDeliveryLocation
    ) -> DastakDeliveryLocation {
        DastakDeliveryLocation(address: location.address, point: location.point)
    }

    private func canCancel(_ status: ParcelDeliveryStatus) -> Bool {
        return switch status {
        case .paymentPending, .paid, .assigned, .enRouteToPickup:
            true
        case .pickedUp, .inTransit, .delivered, .cancelled:
            false
        }
    }

    private func message(for error: Error, fallback: String) -> String {
        guard case let FunctionClientError.api(_, _, message) = error else {
            return fallback
        }
        return message
    }

    private func presentError(for error: Error, fallback: String) {
        if refreshFailure(for: error) == .sessionExpired {
            errorMessage = nil
            return
        }
        errorMessage = message(for: error, fallback: fallback)
    }

    private func refreshFailure(for error: Error) -> DastakCustomerRefreshFailure {
        let failure: DastakCustomerRefreshFailure
        if let servicesError = error as? MarketplaceAuthenticatedServicesError,
                  servicesError == .authenticationRequired {
            failure = .sessionExpired
        } else if let functionError = error as? FunctionClientError {
            switch functionError {
            case .authenticationRequired:
                failure = .sessionExpired
            case let .api(statusCode, _, _):
                switch statusCode {
                case 401:
                    failure = .sessionExpired
                case 403:
                    failure = .accessUnavailable
                default:
                    failure = .unavailable
                }
            case .invalidResponse, .malformedErrorResponse:
                failure = .unavailable
            }
        } else if let urlError = error as? URLError,
                  [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut].contains(urlError.code) {
            failure = .offline
        } else {
            failure = .unavailable
        }

        if failure == .sessionExpired {
            sessionExpired = true
        }
        return failure
    }
}

#if DEBUG
extension DastakCustomerModel {
    static func preview() -> DastakCustomerModel {
        let functions = DastakPreviewFunctionClient()
        let model = DastakCustomerModel(functions: functions)
        model.selectedLocation = DastakDeliveryLocation(
            address: "Gandhi Road, Vaniyambadi",
            point: GeoPoint(latitude: 12.6819, longitude: 78.6201)
        )
        model.deliveryAddress = DastakDeliveryLocation(
            address: "Gandhi Road, Vaniyambadi",
            point: GeoPoint(latitude: 12.6819, longitude: 78.6201),
            label: "Home",
            details: "12, Gandhi Road"
        )
        model.isDeliveryAddressConfirmed = true
        model.catalogue = try? JSONDecoder().decode(
            CatalogueSnapshot.self,
            from: Data(Self.previewCatalogueJSON.utf8)
        )
        return model
    }

    private static let previewCatalogueJSON = """
    {
      "serviceZoneId":"66666666-6666-4666-8666-666666666666",
      "discoveryRadiusMeters":10000,
      "stores":[{
        "storeId":"33333333-3333-4333-8333-333333333333",
        "name":"Namma Daily",
        "address":"Flower Bazaar, Vaniyambadi",
        "location":{"latitude":12.6824,"longitude":78.6211},
        "serviceZoneId":"66666666-6666-4666-8666-666666666666",
        "isPublished":true,
        "acceptingOrders":true
      }],
      "categories":[{
        "categoryId":"44444444-4444-4444-8444-444444444444",
        "storeId":"33333333-3333-4333-8333-333333333333",
        "name":"Everyday essentials",
        "displayOrder":1,
        "isActive":true
      }],
      "products":[
        {
          "productId":"11111111-1111-4111-8111-111111111111",
          "storeId":"33333333-3333-4333-8333-333333333333",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "name":"Fresh whole milk",
          "description":"Local dairy milk",
          "unitLabel":"1 litre",
          "price":{"paise":6800},
          "imageObjectPath":null,
          "availability":"in_stock",
          "catalogueKind":"general",
          "restrictedApprovalState":"not_applicable",
          "isActive":true
        },
        {
          "productId":"22222222-2222-4222-8222-222222222222",
          "storeId":"33333333-3333-4333-8333-333333333333",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "name":"Farm eggs",
          "description":"Six fresh eggs",
          "unitLabel":"6 pieces",
          "price":{"paise":7200},
          "imageObjectPath":null,
          "availability":"in_stock",
          "catalogueKind":"general",
          "restrictedApprovalState":"not_applicable",
          "isActive":true
        },
        {
          "productId":"77777777-7777-4777-8777-777777777777",
          "storeId":"33333333-3333-4333-8333-333333333333",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "name":"Pain relief tablets",
          "description":"10 tablet strip",
          "unitLabel":"10 tablets",
          "price":{"paise":4500},
          "imageObjectPath":null,
          "availability":"in_stock",
          "catalogueKind":"otc_medicine",
          "restrictedApprovalState":"not_applicable",
          "isActive":true
        },
        {
          "productId":"88888888-8888-4888-8888-888888888888",
          "storeId":"33333333-3333-4333-8333-333333333333",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "name":"Basmati rice",
          "description":"Long grain rice",
          "unitLabel":"1 kilogram",
          "price":{"paise":16500},
          "imageObjectPath":null,
          "availability":"in_stock",
          "catalogueKind":"general",
          "restrictedApprovalState":"not_applicable",
          "isActive":true
        }
      ]
    }
    """
}

private actor DastakPreviewFunctionClient: FunctionClient {
    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        throw FunctionClientError.invalidResponse
    }
}
#endif
