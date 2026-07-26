import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

@MainActor
final class DastakCustomerModel: ObservableObject {
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var orders: [MerchantOrderSnapshot] = []
    @Published private(set) var quote: MerchantOrderQuote?
    @Published private(set) var checkoutSession: DastakCheckoutSession?
    @Published private(set) var parcelQuote: ParcelQuote?
    @Published private(set) var createdParcel: ParcelDelivery?
    @Published private(set) var isLoadingCatalogue = false
    @Published private(set) var isLoadingOrders = false
    @Published private(set) var isCheckingOut = false
    @Published var selectedLocation: DastakDeliveryLocation?
    @Published var discoveryRadiusKilometres = 10
    @Published var searchText = ""
    @Published var cart = DastakCart()
    @Published var errorMessage: String?

    let parcelClient: any ParcelDeliveryClient

    private let catalogueClient: any CatalogueClient
    private let orderClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient

    init(
        catalogueClient: any CatalogueClient,
        orderClient: any MerchantOrderClient,
        parcelClient: any ParcelDeliveryClient,
        checkoutClient: any DastakCheckoutClient
    ) {
        self.catalogueClient = catalogueClient
        self.orderClient = orderClient
        self.parcelClient = parcelClient
        self.checkoutClient = checkoutClient
    }

    convenience init(functions: any FunctionClient) {
        self.init(
            catalogueClient: SupabaseCatalogueClient(functions: functions),
            orderClient: SupabaseMerchantOrderClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: functions)
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

    func bootstrap() async {
        async let orders: Void = refreshOrders()
        if selectedLocation != nil {
            async let catalogue: Void = refreshCatalogue()
            _ = await (orders, catalogue)
        } else {
            _ = await orders
        }
    }

    func setLocation(_ location: DastakDeliveryLocation) async {
        selectedLocation = location
        await refreshCatalogue()
    }

    func setDiscoveryRadius(_ kilometres: Int) async {
        guard (10...30).contains(kilometres) else { return }
        discoveryRadiusKilometres = kilometres
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
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, fallback: "Nearby stores could not be loaded.")
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
        } catch {
            errorMessage = message(for: error, fallback: "Orders could not be refreshed.")
        }
    }

    func prepareQuote() async {
        guard let storeID = cart.storeID,
              let selectedLocation,
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
            errorMessage = message(for: error, fallback: "The final price could not be calculated.")
        }
    }

    func createOrderAndCheckout() async -> MerchantOrderSnapshot? {
        guard let quote, !isCheckingOut else { return nil }
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
            errorMessage = message(for: error, fallback: "Checkout could not be started.")
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
            errorMessage = message(for: error, fallback: "This order could not be cancelled.")
        }
    }

    func clearCheckoutSession() {
        checkoutSession = nil
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
            errorMessage = message(for: error, fallback: "The parcel fare could not be calculated.")
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
            createdParcel = parcel
            self.parcelQuote = nil
            errorMessage = nil
            return parcel
        } catch {
            errorMessage = message(for: error, fallback: "Parcel checkout could not be started.")
            return nil
        }
    }

    private func makeKey() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private func message(for error: Error, fallback: String) -> String {
        guard case let FunctionClientError.api(_, _, message) = error else {
            return fallback
        }
        return message
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
