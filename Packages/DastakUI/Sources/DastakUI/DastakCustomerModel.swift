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
    @Published var discoveryRadiusKilometres = 10
    @Published var searchText = ""
    @Published var cart = DastakCart()
    @Published var errorMessage: String?
    @Published private(set) var catalogueRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var accountRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var ordersRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var parcelsRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var sessionExpired = false

    let parcelClient: any ParcelDeliveryClient

    private let catalogueClient: any CatalogueClient
    private let orderClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient
    private let deviceTokenClient: SupabaseDastakDeviceTokenClient?
    private let checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)?

    init(
        catalogueClient: any CatalogueClient,
        orderClient: any MerchantOrderClient,
        parcelClient: any ParcelDeliveryClient,
        checkoutClient: any DastakCheckoutClient,
        deviceTokenClient: SupabaseDastakDeviceTokenClient? = nil,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil
    ) {
        self.catalogueClient = catalogueClient
        self.orderClient = orderClient
        self.parcelClient = parcelClient
        self.checkoutClient = checkoutClient
        self.deviceTokenClient = deviceTokenClient
        self.checkoutCustomerProvider = checkoutCustomerProvider
        selectedLocation = Self.savedDeliveryLocation()
        discoveryRadiusKilometres = Self.savedDiscoveryRadius()
    }

    convenience init(
        functions: any FunctionClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil
    ) {
        self.init(
            catalogueClient: SupabaseCatalogueClient(functions: functions),
            orderClient: SupabaseMerchantOrderClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: functions),
            deviceTokenClient: SupabaseDastakDeviceTokenClient(functions: functions),
            checkoutCustomerProvider: checkoutCustomerProvider
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
        selectedLocation?.isReadyForDelivery == true
    }

    var ordersAndParcelsRefreshFailure: DastakCustomerRefreshFailure? {
        let failures = [ordersRefreshFailure, parcelsRefreshFailure].compactMap { $0 }
        return failures.first(where: { $0 == .sessionExpired }) ?? failures.first
    }

    func bootstrap() async {
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

    private func registerDeviceTokenIfAvailable() async {
        guard let token = UserDefaults.standard.string(forKey: "dastak.apns.deviceToken"),
              !token.isEmpty,
              let deviceTokenClient else { return }
        try? await deviceTokenClient.register(token: token, idempotencyKey: makeKey())
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

    func setLocation(_ location: DastakDeliveryLocation) async {
        selectedLocation = location
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
        guard let storeID = cart.storeID,
              let selectedLocation,
              selectedLocation.isReadyForDelivery,
              !cart.entries.isEmpty else { return }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            quote = try await orderClient.quote(
                storeID: storeID,
                lines: cart.orderLines,
                dropoff: selectedLocation.point,
                idempotencyKey: makeKey()
            )
            errorMessage = nil
        } catch {
            presentError(for: error, fallback: "The final price could not be calculated.")
        }
    }

    func createOrderAndCheckout() async -> MerchantOrderSnapshot? {
        guard hasCompleteDeliveryAddress, let quote, !isCheckingOut else { return nil }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            let order = try await orderClient.create(
                quoteID: quote.quoteID,
                idempotencyKey: makeKey()
            )
            checkoutSession = try await checkoutClient.createMerchantOrderCheckout(
                orderID: order.orderID,
                idempotencyKey: makeKey()
            )
            cart.removeAll()
            self.quote = nil
            await refreshOrders()
            errorMessage = nil
            return order
        } catch {
            presentError(for: error, fallback: "Checkout could not be started.")
            return nil
        }
    }

    func cancel(_ order: MerchantOrderSnapshot) async {
        do {
            _ = try await orderClient.customerCancel(
                orderID: order.orderID,
                reason: "Cancelled by customer",
                idempotencyKey: makeKey()
            )
            await refreshOrders()
        } catch {
            presentError(for: error, fallback: "This order could not be cancelled.")
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
            errorMessage = nil
        } catch {
            presentError(for: error, fallback: "Payment could not be started.")
        }
    }

    func retryPayment(for parcel: CustomerParcelDelivery) async {
        guard parcel.audience == .sender,
              parcel.parcel.paymentStatus == .pending,
              !isCheckingOut else { return }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            checkoutSession = try await checkoutClient.createParcelCheckout(
                parcelID: parcel.parcel.parcelID,
                idempotencyKey: makeKey()
            )
            errorMessage = nil
        } catch {
            presentError(for: error, fallback: "Payment could not be started.")
        }
    }

    func cancel(_ parcel: CustomerParcelDelivery) async {
        guard parcel.audience == .sender, canCancel(parcel.parcel.status) else { return }
        do {
            let updated = try await parcelClient.cancelParcel(
                parcelID: parcel.parcel.parcelID,
                reason: "Cancelled by customer",
                idempotencyKey: makeKey()
            )
            if updated.paymentStatus == .refundPending {
                _ = try await checkoutClient.processParcelRefund(
                    parcelID: updated.parcelID,
                    idempotencyKey: makeKey()
                )
            }
            await refreshParcels()
            errorMessage = nil
        } catch {
            presentError(for: error, fallback: "This parcel delivery could not be cancelled.")
        }
    }

    func clearCart() {
        cart.removeAll()
        quote = nil
    }

    func resetParcelQuote() {
        parcelQuote = nil
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
            errorMessage = nil
        } catch {
            presentError(for: error, fallback: "The parcel fare could not be calculated.")
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
                idempotencyKey: makeKey()
            )
            checkoutSession = try await checkoutClient.createParcelCheckout(
                parcelID: parcel.parcelID,
                idempotencyKey: makeKey()
            )
            let customerParcel = CustomerParcelDelivery(parcel: parcel, audience: .sender)
            parcels = [customerParcel] + parcels.filter { $0.parcel.parcelID != parcel.parcelID }
            self.parcelQuote = nil
            errorMessage = nil
            return parcel
        } catch {
            presentError(for: error, fallback: "Parcel checkout could not be started.")
            return nil
        }
    }

    private func makeKey() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private func persistDiscoveryPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(discoveryRadiusKilometres, forKey: "dastak.customer.discoveryRadiusKilometres")
        if let selectedLocation,
           let data = try? JSONEncoder().encode(selectedLocation) {
            defaults.set(data, forKey: "dastak.customer.deliveryLocation")
        }
    }

    private static func savedDeliveryLocation() -> DastakDeliveryLocation? {
        guard let data = UserDefaults.standard.data(forKey: "dastak.customer.deliveryLocation") else {
            return nil
        }
        return try? JSONDecoder().decode(DastakDeliveryLocation.self, from: data)
    }

    private static func savedDiscoveryRadius() -> Int {
        let value = UserDefaults.standard.integer(forKey: "dastak.customer.discoveryRadiusKilometres")
        return (10...30).contains(value) ? value : 10
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
