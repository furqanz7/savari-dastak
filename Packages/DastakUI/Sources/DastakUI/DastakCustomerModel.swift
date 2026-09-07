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

struct DastakWishlistMenuSelection: Identifiable {
    let restaurant: DastakV1RestaurantMenu
    let item: DastakV1RestaurantMenuItem
    var id: UUID { item.id }
}

@MainActor
final class DastakCustomerModel: ObservableObject {
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var v1Catalogue: DastakV1CatalogueSnapshot?
    @Published private(set) var v1CategoryProducts: [UUID: [DastakV1CatalogueSKU]] = [:]
    @Published private(set) var loadingV1CategoryIDs: Set<UUID> = []
    @Published private(set) var failedV1CategoryIDs: Set<UUID> = []
    @Published private(set) var v1Restaurants: [DastakV1RestaurantMenu] = []
    @Published private(set) var v1SearchResults: [DastakV1CatalogueSKU] = []
    @Published private(set) var v1Orders: [DastakV1OrderSnapshot] = []
    @Published private(set) var wishlistItems: [CustomerWishlistItem] = []
    @Published private(set) var activeV1Order: DastakV1OrderSnapshot?
    @Published private(set) var orders: [MerchantOrderSnapshot] = []
    @Published private(set) var quote: MerchantOrderQuote?
    @Published private(set) var checkoutSession: DastakCheckoutSession?
    @Published private(set) var checkoutCustomer: MarketplaceCheckoutCustomer?
    @Published private(set) var parcelQuote: ParcelQuote?
    @Published private(set) var parcels: [CustomerParcelDelivery] = []
    @Published private(set) var orderDetails: [UUID: MerchantOrderSnapshot] = [:]
    @Published private(set) var parcelDetails: [UUID: CustomerParcelDelivery] = [:]
    @Published private(set) var loadingOrderDetailIDs: Set<UUID> = []
    @Published private(set) var loadingParcelDetailIDs: Set<UUID> = []
    @Published private(set) var orderDetailFailures: [UUID: DastakCustomerRefreshFailure] = [:]
    @Published private(set) var parcelDetailFailures: [UUID: DastakCustomerRefreshFailure] = [:]
    @Published private(set) var isLoadingCatalogue = false
    @Published private(set) var isLoadingV1Catalogue = false
    @Published private(set) var isSearchingV1Catalogue = false
    @Published private(set) var isSubmittingV1Order = false
    @Published private(set) var isLoadingV1Orders = false
    @Published private(set) var isLoadingMoreV1Orders = false
    @Published private(set) var isLoadingWishlist = false
    @Published private(set) var wishlistUpdatingIDs: Set<UUID> = []
    @Published private(set) var isLoadingOrders = false
    @Published private(set) var isLoadingParcels = false
    @Published private(set) var isCheckingOut = false
    @Published private(set) var isReportingV1Issue = false
    @Published var selectedLocation: DastakDeliveryLocation?
    @Published private(set) var savedAddresses: [DastakDeliveryLocation] = []
    @Published private(set) var deliveryAddress: DastakDeliveryLocation?
    @Published var discoveryRadiusKilometres = 10
    @Published var searchText = ""
    @Published var cart = DastakCart()
    @Published var errorMessage: String?
    @Published var cartErrorMessage: String?
    @Published var v1OrderErrorMessage: String?
    @Published var parcelErrorMessage: String?
    @Published var ordersActionMessage: String?
    @Published private(set) var addressErrorMessage: String?
    @Published private(set) var catalogueRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var v1CatalogueRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var accountRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var ordersRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var v1OrdersRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var parcelsRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var sessionExpired = false
    @Published private(set) var isDeliveryAddressConfirmed = false
    @Published private(set) var hasCompletedOnboarding = false
    @Published private(set) var linkedIdentities: [MarketplaceLinkedIdentity] = []
    @Published private(set) var isLinkingIdentity = false
    @Published var identityMessage: String?
    @Published private(set) var identityMessageIsSuccess = false

    private var hasLoadedAdditionalV1OrderPage = false

    let parcelClient: any ParcelDeliveryClient

    private let catalogueClient: any CatalogueClient
    private let v1Client: any DastakV1CustomerClient
    private let wishlistClient: any CustomerWishlistClient
    private let orderClient: any MerchantOrderClient
    private let checkoutClient: any DastakCheckoutClient
    private let addressClient: any CustomerAddressClient
    private let accountProfileClient: any AccountProfileClient
    private let checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)?
    private let accountIDProvider: (@Sendable () async throws -> UUID)?
    private let issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)?
    private let oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)?
    private var preferenceScope = "default"
    private var accountDeletionAttempt = DastakAccountDeletionAttempt()
    private var orderPlacementAttempt = DastakOrderPlacementAttempt()
    private var v1SubmissionAttempt: (fingerprint: String, key: IdempotencyKey)?
    private var v1IssueAttempt: (
        fingerprint: String,
        key: IdempotencyKey,
        evidencePath: String?
    )?
    private var parcelPlacementAttempt = DastakOrderPlacementAttempt()
    private var ordersRefreshQueued = false
    private var v1OrdersRefreshQueued = false
    private var parcelsRefreshQueued = false
    private var v1OrdersNextCursor: DastakV1OrderCursor?

    init(
        catalogueClient: any CatalogueClient,
        v1Client: any DastakV1CustomerClient,
        wishlistClient: any CustomerWishlistClient,
        orderClient: any MerchantOrderClient,
        parcelClient: any ParcelDeliveryClient,
        checkoutClient: any DastakCheckoutClient,
        addressClient: any CustomerAddressClient,
        accountProfileClient: any AccountProfileClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil,
        issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)? = nil,
        oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil
    ) {
        self.catalogueClient = catalogueClient
        self.v1Client = v1Client
        self.wishlistClient = wishlistClient
        self.orderClient = orderClient
        self.parcelClient = parcelClient
        self.checkoutClient = checkoutClient
        self.addressClient = addressClient
        self.accountProfileClient = accountProfileClient
        self.checkoutCustomerProvider = checkoutCustomerProvider
        self.accountIDProvider = accountIDProvider
        self.issueEvidenceUploader = issueEvidenceUploader
        self.oauthIdentityLinker = oauthIdentityLinker
    }

    convenience init(
        functions: any FunctionClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil,
        issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)? = nil,
        oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil
    ) {
        self.init(
            catalogueClient: SupabaseCatalogueClient(functions: functions),
            v1Client: SupabaseDastakV1CustomerClient(functions: functions),
            wishlistClient: SupabaseCustomerWishlistClient(functions: functions),
            orderClient: SupabaseMerchantOrderClient(functions: functions),
            parcelClient: SupabaseParcelDeliveryClient(functions: functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: functions),
            addressClient: SupabaseCustomerAddressClient(functions: functions),
            accountProfileClient: SupabaseAccountProfileClient(functions: functions),
            checkoutCustomerProvider: checkoutCustomerProvider,
            accountIDProvider: accountIDProvider,
            issueEvidenceUploader: issueEvidenceUploader,
            oauthIdentityLinker: oauthIdentityLinker
        )
    }

    var activeProducts: [DastakV1CatalogueSKU] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? v1Catalogue?.skus ?? [] : v1SearchResults
    }

    var canonicalCategories: [DastakV1CatalogueCategory] {
        v1Catalogue?.categories ?? []
    }

    var canonicalCategoryTypes: [DastakV1CatalogueCategory] {
        v1Catalogue?.categoryTypes ?? []
    }

    var canonicalSubcategories: [DastakV1CatalogueSubcategory] {
        v1Catalogue?.subcategories ?? []
    }

    var wishlistRetailProducts: [DastakV1CatalogueSKU] {
        let products = Dictionary(uniqueKeysWithValues: (v1Catalogue?.skus ?? []).map { ($0.id, $0) })
        return wishlistItems.compactMap { item in
            item.kind == .retailSKU ? products[item.itemID] : nil
        }
    }

    var wishlistMenuSelections: [DastakWishlistMenuSelection] {
        let selections = v1Restaurants.flatMap { restaurant in
            restaurant.categories.flatMap { category in
                category.items.map { item in (item.id, DastakWishlistMenuSelection(restaurant: restaurant, item: item)) }
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: selections)
        return wishlistItems.compactMap { item in
            item.kind == .menuItem ? byID[item.itemID] : nil
        }
    }

    var unresolvedWishlistItemCount: Int {
        wishlistItems.count - wishlistRetailProducts.count - wishlistMenuSelections.count
    }

    func isWishlisted(kind: CustomerWishlistItemKind, itemID: UUID) -> Bool {
        wishlistItems.contains { $0.kind == kind && $0.itemID == itemID }
    }

    func products(in categoryID: UUID) -> [DastakV1CatalogueSKU] {
        if let scoped = v1CategoryProducts[categoryID] { return scoped }
        return (v1Catalogue?.skus ?? []).filter { $0.categoryID == categoryID }
    }

    func products(inSubcategory subcategoryID: UUID) -> [DastakV1CatalogueSKU] {
        guard let categoryID = canonicalSubcategories.first(where: { $0.id == subcategoryID })?.categoryID else {
            return (v1Catalogue?.skus ?? []).filter { $0.subcategoryID == subcategoryID }
        }
        return products(in: categoryID).filter { $0.subcategoryID == subcategoryID }
    }

    var hasCompleteDeliveryAddress: Bool {
        guard isDeliveryAddressConfirmed,
              let deliveryAddress,
              deliveryAddress.isReadyForDelivery else { return false }
        return true
    }

    var ordersAndParcelsRefreshFailure: DastakCustomerRefreshFailure? {
        let failures = [v1OrdersRefreshFailure, ordersRefreshFailure, parcelsRefreshFailure]
            .compactMap { $0 }
        return failures.first(where: { $0 == .sessionExpired }) ?? failures.first
    }

    var hasActiveOrders: Bool {
        return v1Orders.contains { Self.isActiveV1Order($0.status) }
            || orders.contains { ![.delivered, .cancelled].contains($0.status) }
            || parcels.contains { ![.delivered, .cancelled].contains($0.parcel.status) }
    }

    nonisolated static func isActiveV1Order(_ status: DastakV1OrderStatus) -> Bool {
        ![.delivered, .unavailable, .paymentExpired, .cancelledPrepayment, .cancelled,
          .fulfilmentFailure].contains(status)
    }

    func bootstrap() async {
        await restorePreferencesAndAddress()
        async let orders: Void = refreshOrders()
        async let v1Orders: Void = refreshV1Orders()
        async let v1Catalogue: Void = refreshV1Catalogue()
        async let wishlist: Void = refreshWishlist()
        async let parcels: Void = refreshParcels()
        async let checkoutCustomer: Void = refreshCheckoutCustomer()
        _ = await (
            orders,
            v1Orders,
            v1Catalogue,
            wishlist,
            parcels,
            checkoutCustomer
        )
    }

    func refreshWishlist() async {
        guard !isLoadingWishlist else { return }
        isLoadingWishlist = true
        defer { isLoadingWishlist = false }
        do {
            wishlistItems = try await wishlistClient.snapshot(idempotencyKey: makeKey()).items
        } catch {
            presentError(for: error, fallback: "Your Wishlist could not be loaded.")
        }
    }

    func toggleWishlist(kind: CustomerWishlistItemKind, itemID: UUID) async {
        guard !wishlistUpdatingIDs.contains(itemID) else { return }
        wishlistUpdatingIDs.insert(itemID)
        defer { wishlistUpdatingIDs.remove(itemID) }
        let desiredState = !isWishlisted(kind: kind, itemID: itemID)
        do {
            wishlistItems = try await wishlistClient.setItem(
                kind: kind,
                itemID: itemID,
                wished: desiredState,
                idempotencyKey: makeKey()
            ).items
            errorMessage = nil
        } catch {
            presentError(for: error, fallback: "Your Wishlist could not be updated.")
        }
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
        let key = accountDeletionAttempt.key(scope: preferenceScope)
        try await accountProfileClient.deleteAccount(persona: .customer, idempotencyKey: key)
        accountDeletionAttempt.complete(scope: preferenceScope)
    }

    func exportAccount() async throws -> MarketplaceAccountExport {
        try await accountProfileClient.exportAccount(idempotencyKey: makeKey())
    }

    @discardableResult
    func refreshCustomerIdentities() async -> Bool {
        do {
            linkedIdentities = try await accountProfileClient.identitySnapshot(
                idempotencyKey: makeKey()
            )
            identityMessage = nil
            identityMessageIsSuccess = false
            return true
        } catch {
            identityMessage = "Sign-in methods could not be loaded. Try again."
            identityMessageIsSuccess = false
            return false
        }
    }

    func linkIdentity(_ provider: MarketplaceOAuthProvider) async {
        guard let oauthIdentityLinker, !isLinkingIdentity else { return }
        isLinkingIdentity = true
        identityMessage = nil
        identityMessageIsSuccess = false
        defer { isLinkingIdentity = false }
        do {
            try await accountProfileClient.beginIdentityLink(
                provider: provider,
                idempotencyKey: makeKey()
            )
            try await oauthIdentityLinker(provider)
            linkedIdentities = try await accountProfileClient.identitySnapshot(
                idempotencyKey: makeKey()
            )
            guard linkedIdentities.contains(where: { $0.provider == provider }) else {
                throw DastakIdentityLinkError.notConfirmed
            }
            identityMessage = "\(provider == .apple ? "Apple" : "Google") is now linked to this Dastak account."
            identityMessageIsSuccess = true
        } catch {
            identityMessage = "That sign-in may belong to another Dastak account. Sign in to that account or contact support; Dastak never merges accounts by email or phone."
            identityMessageIsSuccess = false
        }
    }

    func setLocation(_ location: DastakDeliveryLocation) async -> Bool {
        guard let label = location.label, let building = location.building else {
            addressErrorMessage = "Add a label and doorstep details before saving."
            return false
        }
        do {
            let response = try await addressClient.save(
                addressID: location.addressID,
                label: label,
                address: location.address,
                building: building,
                floor: location.floor,
                landmark: location.landmark,
                deliveryNotes: location.deliveryNotes,
                location: location.point,
                makeDefault: true,
                idempotencyKey: makeKey()
            )
            savedAddresses = response.addresses.map(Self.deliveryLocation)
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

    func selectSavedAddress(_ location: DastakDeliveryLocation) async -> Bool {
        guard let addressID = location.addressID else { return await setLocation(location) }
        do {
            let response = try await addressClient.setDefault(
                addressID: addressID,
                idempotencyKey: makeKey()
            )
            savedAddresses = response.addresses.map(Self.deliveryLocation)
            deliveryAddress = response.addresses.first(where: \.isDefault).map(Self.deliveryLocation)
            isDeliveryAddressConfirmed = deliveryAddress?.isReadyForDelivery == true
            addressErrorMessage = nil
            return true
        } catch {
            addressErrorMessage = message(for: error, fallback: "That address could not be selected. Try again.")
            return false
        }
    }

    func deleteSavedAddress(_ location: DastakDeliveryLocation) async -> Bool {
        guard let addressID = location.addressID else { return false }
        do {
            let response = try await addressClient.delete(
                addressID: addressID,
                idempotencyKey: makeKey()
            )
            savedAddresses = response.addresses.map(Self.deliveryLocation)
            deliveryAddress = response.addresses.first(where: \.isDefault).map(Self.deliveryLocation)
            isDeliveryAddressConfirmed = deliveryAddress?.isReadyForDelivery == true
            addressErrorMessage = nil
            return true
        } catch {
            addressErrorMessage = message(for: error, fallback: "That address could not be deleted. Try again.")
            return false
        }
    }

    func selectDiscoveryLocation(_ location: DastakDeliveryLocation) async {
        selectedLocation = Self.discoveryLocation(from: location)
        quote = nil
        orderPlacementAttempt.reset()
        v1SubmissionAttempt = nil
        cartErrorMessage = nil
        persistDiscoveryPreferences()
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

    func refreshV1Catalogue() async {
        guard !isLoadingV1Catalogue else { return }
        isLoadingV1Catalogue = true
        defer { isLoadingV1Catalogue = false }
        do {
            async let catalogue = v1Client.catalogue(
                query: nil,
                categoryID: nil,
                subcategoryID: nil,
                limit: 250,
                cursor: nil,
                idempotencyKey: makeKey()
            )
            async let restaurants = v1Client.restaurants(
                query: nil,
                limit: 50,
                idempotencyKey: makeKey()
            )
            v1Catalogue = try await catalogue
            v1CategoryProducts = [:]
            failedV1CategoryIDs = []
            v1Restaurants = try await restaurants
            v1CatalogueRefreshFailure = nil
        } catch {
            v1CatalogueRefreshFailure = refreshFailure(for: error)
        }
    }

    func loadV1Category(_ categoryID: UUID, force: Bool = false) async {
        guard (force || v1CategoryProducts[categoryID] == nil),
              !loadingV1CategoryIDs.contains(categoryID)
        else { return }

        loadingV1CategoryIDs.insert(categoryID)
        failedV1CategoryIDs.remove(categoryID)
        defer { loadingV1CategoryIDs.remove(categoryID) }

        do {
            var products: [DastakV1CatalogueSKU] = []
            var cursor: DastakV1CatalogueCursor?
            var pageCount = 0
            repeat {
                let page = try await v1Client.catalogue(
                    query: nil,
                    categoryID: categoryID,
                    subcategoryID: nil,
                    limit: 250,
                    cursor: cursor,
                    idempotencyKey: makeKey()
                )
                products.append(contentsOf: page.skus)
                cursor = page.nextCursor
                pageCount += 1
            } while cursor != nil && pageCount < 20

            var seen = Set<UUID>()
            v1CategoryProducts[categoryID] = products
                .filter { seen.insert($0.id).inserted }
                .sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        } catch {
            failedV1CategoryIDs.insert(categoryID)
        }
    }

    func searchV1Catalogue() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            v1SearchResults = []
            return
        }
        guard !isSearchingV1Catalogue else { return }
        isSearchingV1Catalogue = true
        defer { isSearchingV1Catalogue = false }
        do {
            let result = try await v1Client.catalogue(
                query: query,
                categoryID: nil,
                subcategoryID: nil,
                limit: 100,
                cursor: nil,
                idempotencyKey: makeKey()
            )
            guard query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            v1SearchResults = result.skus
            v1CatalogueRefreshFailure = nil
        } catch {
            v1CatalogueRefreshFailure = refreshFailure(for: error)
        }
    }

    func refreshV1Orders() async {
        v1OrdersRefreshQueued = true
        guard !isLoadingV1Orders else { return }
        isLoadingV1Orders = true
        defer { isLoadingV1Orders = false }

        while v1OrdersRefreshQueued, !Task.isCancelled {
            v1OrdersRefreshQueued = false
            do {
                let result = try await v1Client.orders(
                    limit: 50,
                    cursor: nil,
                    idempotencyKey: makeKey()
                )
                v1Orders = mergeV1Orders(result.orders)
                if !hasLoadedAdditionalV1OrderPage {
                    v1OrdersNextCursor = result.nextCursor
                }
                if let focused = activeV1Order,
                   let refreshed = v1Orders.first(where: { $0.id == focused.id }) {
                    activeV1Order = refreshed
                } else if activeV1Order == nil {
                    activeV1Order = v1Orders.first(where: {
                        Self.isActiveV1Order($0.status)
                    })
                }
                v1OrdersRefreshFailure = nil
            } catch {
                v1OrdersRefreshFailure = refreshFailure(for: error)
            }
        }
    }

    var canLoadMoreV1Orders: Bool { v1OrdersNextCursor != nil }

    func loadMoreV1Orders() async {
        guard let cursor = v1OrdersNextCursor,
              !isLoadingV1Orders, !isLoadingMoreV1Orders else { return }
        isLoadingMoreV1Orders = true
        defer { isLoadingMoreV1Orders = false }
        do {
            let result = try await v1Client.orders(
                limit: 50,
                cursor: cursor,
                idempotencyKey: makeKey()
            )
            hasLoadedAdditionalV1OrderPage = true
            v1Orders = mergeV1Orders(result.orders)
            v1OrdersNextCursor = result.nextCursor
            v1OrdersRefreshFailure = nil
        } catch {
            v1OrdersRefreshFailure = refreshFailure(for: error)
        }
    }

    private func mergeV1Orders(
        _ incoming: [DastakV1OrderSnapshot]
    ) -> [DastakV1OrderSnapshot] {
        var byID = Dictionary(uniqueKeysWithValues: v1Orders.map { ($0.id, $0) })
        for order in incoming where order.version >= (byID[order.id]?.version ?? 0) {
            byID[order.id] = order
        }
        return byID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    func refreshActiveV1Order() async {
        guard let activeV1Order else { return }
        do {
            let refreshed = try await v1Client.order(
                id: activeV1Order.id,
                idempotencyKey: makeKey()
            )
            guard refreshed.version >= activeV1Order.version else { return }
            self.activeV1Order = refreshed
            v1Orders = [refreshed] + v1Orders.filter { $0.id != refreshed.id }
            v1OrderErrorMessage = nil
        } catch {
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Your matching status could not be refreshed."
            )
        }
    }

    func focusV1Order(_ order: DastakV1OrderSnapshot) {
        activeV1Order = order
        v1OrderErrorMessage = nil
    }

    @discardableResult
    func focusV1Order(id orderID: UUID) async -> Bool {
        if let order = v1Orders.first(where: { $0.id == orderID }) {
            focusV1Order(order)
            return true
        }
        do {
            let order = try await v1Client.order(
                id: orderID,
                idempotencyKey: makeKey()
            )
            activeV1Order = order
            v1Orders = [order] + v1Orders.filter { $0.id != order.id }
            v1OrderErrorMessage = nil
            return true
        } catch {
            v1OrderErrorMessage = message(
                for: error,
                fallback: "This order could not be opened. Try again from Orders."
            )
            return false
        }
    }

    func submitV1Order() async -> Bool {
        guard !cart.isEmpty, !isSubmittingV1Order else { return false }
        guard hasCompleteDeliveryAddress, let deliveryAddress else {
            v1OrderErrorMessage = "Add a complete delivery address before placing your order."
            return false
        }
        guard let customer = checkoutCustomer else {
            v1OrderErrorMessage = "Your account details are still loading. Try again in a moment."
            return false
        }

        let fingerprint = cart.orderLines
            .map {
                "\($0.lineType):\($0.skuID?.uuidString ?? $0.menuItemID?.uuidString ?? "-"):\(($0.optionIDs ?? []).map(\.uuidString).sorted().joined(separator: ",")):\($0.quantity)"
            }
            .sorted()
            .joined(separator: "|")
            + "|\(deliveryAddress.id)|\(customer.phoneNumber)"
        let key: IdempotencyKey
        if let attempt = v1SubmissionAttempt, attempt.fingerprint == fingerprint {
            key = attempt.key
        } else {
            key = makeKey()
            v1SubmissionAttempt = (fingerprint, key)
        }

        let address = DastakV1DeliveryAddressInput(
            label: deliveryAddress.label,
            line1: deliveryAddress.address,
            line2: [deliveryAddress.building, deliveryAddress.floor]
                .compactMap { $0 }
                .joined(separator: ", ")
                .nilIfEmpty,
            landmark: deliveryAddress.landmark,
            city: nil,
            state: nil,
            postalCode: nil,
            latitude: deliveryAddress.point.latitude,
            longitude: deliveryAddress.point.longitude,
            instructions: deliveryAddress.deliveryNotes
        )

        isSubmittingV1Order = true
        defer { isSubmittingV1Order = false }
        do {
            let order = try await v1Client.submit(
                DastakV1OrderSubmission(
                    deliveryAddress: address,
                    recipient: DastakV1RecipientInput(
                        name: customer.displayName,
                        phoneNumber: customer.phoneNumber
                    ),
                    restaurantBranchID: cart.restaurantBranchID,
                    lines: cart.orderLines
                ),
                idempotencyKey: key
            )
            activeV1Order = order
            v1Orders = [order] + v1Orders.filter { $0.id != order.id }
            cart.removeAll()
            v1SubmissionAttempt = nil
            v1OrderErrorMessage = nil
            cartErrorMessage = nil
            return true
        } catch {
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Your order could not be submitted. Try again without changing your basket."
            )
            return false
        }
    }

    func cancelActiveV1Order() async {
        guard let activeV1Order else { return }
        do {
            let cancelled = try await v1Client.cancel(
                id: activeV1Order.id,
                expectedVersion: activeV1Order.version,
                idempotencyKey: makeKey()
            )
            self.activeV1Order = cancelled
            v1Orders = [cancelled] + v1Orders.filter { $0.id != cancelled.id }
            v1OrderErrorMessage = nil
        } catch {
            v1OrderErrorMessage = message(
                for: error,
                fallback: "This order could not be cancelled. Refresh and try again."
            )
        }
    }

    func reportV1Issue(
        category: DastakV1CustomerIssueCategory,
        orderLineID: UUID?,
        description: String,
        evidenceData: Data?,
        evidenceContentType: String?
    ) async -> Bool {
        guard let activeV1Order, !isReportingV1Issue else { return false }
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...1_000).contains(normalized.count) else {
            v1OrderErrorMessage = "Add a few details so Operations can investigate."
            return false
        }
        let evidenceRequired = ![.deliveryProblem, .other].contains(category)
        guard (evidenceData == nil) == (evidenceContentType == nil),
              !evidenceRequired || evidenceData != nil
        else {
            v1OrderErrorMessage = "Add a clear photo of the affected item or package."
            return false
        }
        if let evidenceData, let evidenceContentType {
            guard (1...(10 * 1_024 * 1_024)).contains(evidenceData.count),
                  ["image/jpeg", "image/png", "image/heic"].contains(evidenceContentType),
                  issueEvidenceUploader != nil
            else {
                v1OrderErrorMessage = "Choose a JPG, PNG, or HEIC photo up to 10 MB."
                return false
            }
        }
        isReportingV1Issue = true
        defer { isReportingV1Issue = false }
        do {
            let fingerprint = [
                activeV1Order.id.uuidString,
                orderLineID?.uuidString ?? "ORDER",
                category.rawValue,
                normalized,
                evidenceData.map { "\($0.count):\($0.hashValue)" } ?? "NO_EVIDENCE",
                evidenceContentType ?? "NO_CONTENT_TYPE"
            ].joined(separator: ":")
            var attempt: (
                fingerprint: String,
                key: IdempotencyKey,
                evidencePath: String?
            )
            if let existing = v1IssueAttempt, existing.fingerprint == fingerprint {
                attempt = existing
            } else {
                attempt = (
                    fingerprint: fingerprint,
                    key: makeKey(),
                    evidencePath: nil
                )
            }
            if let evidenceData,
               let evidenceContentType,
               attempt.evidencePath == nil,
               let issueEvidenceUploader {
                attempt.evidencePath = try await issueEvidenceUploader(
                    evidenceData,
                    evidenceContentType
                )
            }
            v1IssueAttempt = attempt
            _ = try await v1Client.reportIssue(
                orderID: activeV1Order.id,
                orderLineID: orderLineID,
                category: category,
                description: normalized,
                objectPath: attempt.evidencePath,
                contentType: evidenceContentType,
                idempotencyKey: attempt.key
            )
            v1IssueAttempt = nil
            await refreshActiveV1Order()
            return true
        } catch {
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Your issue could not be sent. Try again without changing the details."
            )
            return false
        }
    }

    func addToCart(_ product: DastakV1CatalogueSKU) {
        if cart.add(product) == .quantityLimit {
            cartErrorMessage = "You can add up to \(DastakCart.maximumQuantity) of one item."
        } else {
            cartErrorMessage = nil
            v1SubmissionAttempt = nil
        }
    }

    func addFoodToCart(
        restaurant: DastakV1RestaurantMenu,
        item: DastakV1RestaurantMenuItem,
        optionIDs: [UUID]
    ) {
        switch cart.addFood(restaurant: restaurant.restaurant, item: item, optionIDs: optionIDs) {
        case .added:
            cartErrorMessage = nil
            v1SubmissionAttempt = nil
        case .quantityLimit:
            cartErrorMessage = "You can add up to \(DastakCart.maximumQuantity) of one item."
        case .differentRestaurant:
            cartErrorMessage = "A basket can contain food from one Restaurant/Cafe. Remove it before choosing another."
        }
    }

    func imageKey(for line: DastakV1OrderLine) -> String? {
        if let skuID = line.skuID {
            return (v1Catalogue?.skus.first { $0.id == skuID } ??
                    v1SearchResults.first { $0.id == skuID })?.imageKey
        }
        guard let menuItemID = line.menuItemID else { return nil }
        return v1Restaurants
            .lazy
            .flatMap(\.categories)
            .flatMap(\.items)
            .first { $0.id == menuItemID }?
            .imageKey
    }

    @discardableResult
    func reorder(_ order: DastakV1OrderSnapshot) -> DastakReorderResult {
        var rebuilt = DastakCart()
        var addedUnits = 0
        var skippedLines = 0
        let knownSKUs = (v1Catalogue?.skus ?? []) + v1SearchResults

        for line in order.lines {
            if let skuID = line.skuID,
               let product = knownSKUs.first(where: { $0.id == skuID }) {
                let quantity = min(max(1, line.quantity), DastakCart.maximumQuantity)
                for _ in 0..<quantity { _ = rebuilt.add(product) }
                addedUnits += quantity
                continue
            }

            if let menuItemID = line.menuItemID,
               let restaurant = v1Restaurants.first(where: {
                   $0.restaurant.branchID == order.restaurant?.branchID
               }),
               let item = restaurant.categories.lazy.flatMap(\.items)
                   .first(where: { $0.id == menuItemID }) {
                let availableOptionIDs = Set(item.optionGroups.flatMap(\.options).map(\.id))
                let requestedOptionIDs = line.foodSelection?.options.map(\.id) ?? []
                guard requestedOptionIDs.allSatisfy(availableOptionIDs.contains) else {
                    skippedLines += 1
                    continue
                }
                let quantity = min(max(1, line.quantity), DastakCart.maximumQuantity)
                var added = true
                for _ in 0..<quantity {
                    if rebuilt.addFood(
                        restaurant: restaurant.restaurant,
                        item: item,
                        optionIDs: requestedOptionIDs
                    ) != .added {
                        added = false
                        break
                    }
                }
                if added { addedUnits += quantity }
                else { skippedLines += 1 }
                continue
            }

            skippedLines += 1
        }

        guard addedUnits > 0 else {
            ordersActionMessage = "These items are not currently available to reorder."
            return DastakReorderResult(addedUnits: 0, skippedLines: skippedLines)
        }

        cart = rebuilt
        v1SubmissionAttempt = nil
        cartErrorMessage = nil
        ordersActionMessage = skippedLines == 0
            ? "Added \(addedUnits) item\(addedUnits == 1 ? "" : "s") to your basket."
            : "Added \(addedUnits) available item\(addedUnits == 1 ? "" : "s"); \(skippedLines) unavailable line\(skippedLines == 1 ? " was" : "s were") skipped."
        return DastakReorderResult(addedUnits: addedUnits, skippedLines: skippedLines)
    }

    func decrementCartItem(_ productID: UUID) {
        cart.decrement(productID)
        v1SubmissionAttempt = nil
        cartErrorMessage = nil
    }

    func decrementFoodCartItem(_ entryID: String) {
        cart.decrementFood(entryID)
        v1SubmissionAttempt = nil
        cartErrorMessage = nil
    }

    func incrementFoodCartItem(_ entryID: String) {
        if cart.incrementFood(entryID) == .quantityLimit {
            cartErrorMessage = "You can add up to \(DastakCart.maximumQuantity) of one item."
        } else {
            v1SubmissionAttempt = nil
            cartErrorMessage = nil
        }
    }

    func refreshOrders() async {
        ordersRefreshQueued = true
        guard !isLoadingOrders else { return }
        isLoadingOrders = true
        defer { isLoadingOrders = false }

        while ordersRefreshQueued, !Task.isCancelled {
            ordersRefreshQueued = false
            do {
                let refreshed = try await orderClient.customerSnapshot(
                    idempotencyKey: makeKey()
                ).orders
                .sorted { $0.updatedAt > $1.updatedAt }
                orders = refreshed
                for order in refreshed where orderDetails[order.orderID] != nil {
                    orderDetails[order.orderID] = order
                }
                ordersRefreshFailure = nil
            } catch {
                ordersRefreshFailure = refreshFailure(for: error)
            }
        }
    }

    func refreshParcels() async {
        parcelsRefreshQueued = true
        guard !isLoadingParcels else { return }
        isLoadingParcels = true
        defer { isLoadingParcels = false }

        while parcelsRefreshQueued, !Task.isCancelled {
            parcelsRefreshQueued = false
            do {
                let refreshed = try await parcelClient.customerSnapshot(
                    idempotencyKey: makeKey()
                )
                .sorted {
                    ($0.parcel.updatedAt ?? $0.parcel.createdAt ?? "") >
                        ($1.parcel.updatedAt ?? $1.parcel.createdAt ?? "")
                }
                parcels = refreshed
                for customerParcel in refreshed
                where parcelDetails[customerParcel.parcel.parcelID] != nil {
                    parcelDetails[customerParcel.parcel.parcelID] = customerParcel
                }
                parcelsRefreshFailure = nil
            } catch {
                parcelsRefreshFailure = refreshFailure(for: error)
            }
        }
    }

    func refreshOrdersAndParcels() async {
        async let orders: Void = refreshOrders()
        async let v1Orders: Void = refreshV1Orders()
        async let parcels: Void = refreshParcels()
        _ = await (orders, v1Orders, parcels)
    }

    func order(withID orderID: UUID) -> MerchantOrderSnapshot? {
        orderDetails[orderID] ?? orders.first { $0.orderID == orderID }
    }

    func customerParcel(withID parcelID: UUID) -> CustomerParcelDelivery? {
        parcelDetails[parcelID] ?? parcels.first { $0.parcel.parcelID == parcelID }
    }

    func refreshOrderDetail(orderID: UUID) async {
        guard !loadingOrderDetailIDs.contains(orderID) else { return }
        loadingOrderDetailIDs.insert(orderID)
        defer { loadingOrderDetailIDs.remove(orderID) }
        do {
            let detail = try await orderClient.customerDetail(
                orderID: orderID,
                idempotencyKey: makeKey()
            )
            orderDetails[orderID] = detail
            orders = [detail] + orders.filter { $0.orderID != orderID }
            orderDetailFailures[orderID] = nil
        } catch {
            orderDetailFailures[orderID] = refreshFailure(for: error)
        }
    }

    func refreshParcelDetail(parcelID: UUID) async {
        guard !loadingParcelDetailIDs.contains(parcelID) else { return }
        loadingParcelDetailIDs.insert(parcelID)
        defer { loadingParcelDetailIDs.remove(parcelID) }
        do {
            let detail = try await parcelClient.customerParcelDetail(
                parcelID: parcelID,
                idempotencyKey: makeKey()
            )
            parcelDetails[parcelID] = detail
            parcels = [detail] + parcels.filter { $0.parcel.parcelID != parcelID }
            parcelDetailFailures[parcelID] = nil
        } catch {
            parcelDetailFailures[parcelID] = refreshFailure(for: error)
        }
    }

    func requestSupport(
        for order: MerchantOrderSnapshot,
        category: CustomerOrderSupportCategory,
        message: String
    ) async throws -> CustomerOrderSupportCase {
        let response = try await orderClient.createCustomerSupport(
            orderID: order.orderID,
            category: category,
            message: message,
            idempotencyKey: makeKey()
        )
        await refreshOrderDetail(orderID: order.orderID)
        return response.supportCase
    }

    func requestSupport(
        for parcel: CustomerParcelDelivery,
        category: CustomerOrderSupportCategory,
        message: String
    ) async throws -> CustomerOrderSupportCase {
        let response = try await parcelClient.createCustomerSupport(
            parcelID: parcel.parcel.parcelID,
            category: category,
            message: message,
            idempotencyKey: makeKey()
        )
        await refreshParcelDetail(parcelID: parcel.parcel.parcelID)
        return response.supportCase
    }

    /// Checkout completion is not payment authority. Wait briefly for the
    /// signed Razorpay webhook to update this customer's server-side order.
    func waitForPaymentConfirmation(session: DastakCheckoutSession) async -> Bool {
        for attempt in 0..<6 {
            switch session.entityType {
            case .dastakV1Order:
                do {
                    let order = try await v1Client.order(
                        id: session.orderID,
                        idempotencyKey: makeKey()
                    )
                    activeV1Order = order
                    v1Orders = [order] + v1Orders.filter { $0.id != order.id }
                    if order.status == .paid { return true }
                    if order.status == .paymentExpired { return false }
                } catch {
                    // Continue the bounded confirmation poll.
                }
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

    func retryPayment(for order: DastakV1OrderSnapshot) async -> Bool {
        guard order.status == .awaitingPayment,
              order.launchPayment?.canCommit == true,
              !isCheckingOut else { return false }
        isCheckingOut = true
        defer { isCheckingOut = false }
        do {
            let committed = try await v1Client.commitLaunchPayment(
                id: order.id,
                expectedVersion: order.version,
                idempotencyKey: makeKey()
            )
            activeV1Order = committed
            v1Orders = [committed] + v1Orders.filter { $0.id != committed.id }
            v1OrderErrorMessage = nil
            return true
        } catch {
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Your order could not be confirmed. The secured reservation is unchanged; try again before it expires."
            )
            return false
        }
    }

    func reportV1CheckoutFailure(
        session: DastakCheckoutSession,
        failureCode: DastakV1CheckoutFailureCode
    ) async {
        guard session.entityType == .dastakV1Order,
              let attemptID = session.attemptID else { return }
        _ = try? await checkoutClient.reportV1CheckoutFailure(
            orderID: session.orderID,
            attemptID: attemptID,
            failureCode: failureCode,
            idempotencyKey: makeKey()
        )
        if activeV1Order?.id == session.orderID {
            await refreshActiveV1Order()
        } else {
            await refreshV1Orders()
        }
    }

    func completeV1CustomCheckout(
        session: DastakCheckoutSession,
        providerOrderID: String,
        providerPaymentID: String,
        providerSignature: String
    ) async throws -> DastakCustomCheckoutCompletionResult {
        guard session.entityType == .dastakV1Order,
              let attemptID = session.attemptID else {
            throw FunctionClientError.invalidResponse
        }
        return try await checkoutClient.completeV1CustomCheckout(
            orderID: session.orderID,
            attemptID: attemptID,
            providerOrderID: providerOrderID,
            providerPaymentID: providerPaymentID,
            providerSignature: providerSignature,
            idempotencyKey: makeKey()
        )
    }

    func prepareV1TestRehearsal(
        session: DastakCheckoutSession,
        outcome: DastakTestPaymentOutcome
    ) async throws -> DastakTestPaymentRehearsal {
        guard session.entityType == .dastakV1Order,
              session.providerMode == .test,
              session.testRehearsalAvailable,
              let attemptID = session.attemptID else {
            throw FunctionClientError.invalidResponse
        }
        return try await checkoutClient.prepareV1TestRehearsal(
            orderID: session.orderID,
            attemptID: attemptID,
            outcome: outcome,
            idempotencyKey: makeKey()
        )
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
        v1SubmissionAttempt = nil
        cartErrorMessage = nil
        v1OrderErrorMessage = nil
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
            savedAddresses = response.addresses.map(Self.deliveryLocation)
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
            addressID: address.addressID,
            address: address.address,
            point: address.location,
            label: address.label,
            details: address.details,
            building: address.building,
            floor: address.floor,
            landmark: address.landmark,
            deliveryNotes: address.deliveryNotes
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

private enum DastakIdentityLinkError: Error {
    case notConfirmed
}

struct DastakAccountDeletionAttempt {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    mutating func key(scope: String) -> IdempotencyKey {
        let storageKey = keyName(scope: scope)
        if let rawValue = defaults.string(forKey: storageKey),
           let key = IdempotencyKey(rawValue: rawValue) {
            return key
        }
        let key = IdempotencyKey(rawValue: UUID().uuidString)!
        defaults.set(key.rawValue, forKey: storageKey)
        return key
    }

    mutating func complete(scope: String) {
        defaults.removeObject(forKey: keyName(scope: scope))
    }

    private func keyName(scope: String) -> String {
        "dastak.customer.\(scope).accountDeletionIdempotencyKey"
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
        model.v1Catalogue = try? JSONDecoder().decode(
            DastakV1CatalogueSnapshot.self,
            from: Data(Self.previewCatalogueJSON.utf8)
        )
        return model
    }

    private static let previewCatalogueJSON = """
    {
      "catalogueVersion":"2026-08-22T10:00:00Z",
      "categories":[
        {
          "id":"44444444-4444-4444-8444-444444444444",
          "name":"Everyday essentials","slug":"essentials","imageKey":null,"sortOrder":1
        },
        {
          "id":"99999999-9999-4999-8999-999999999999",
          "name":"Health & care","slug":"health-care","imageKey":null,"sortOrder":2
        }
      ],
      "subcategories":[
        {
          "id":"55555555-5555-4555-8555-555555555555",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "name":"Dairy & breakfast","slug":"dairy-breakfast","imageKey":null,"sortOrder":1
        },
        {
          "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "categoryId":"99999999-9999-4999-8999-999999999999",
          "name":"Everyday care","slug":"everyday-care","imageKey":null,"sortOrder":1
        }
      ],
      "skus":[
        {
          "id":"11111111-1111-4111-8111-111111111111",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "subcategoryId":"55555555-5555-4555-8555-555555555555",
          "brand":null,"name":"Fresh whole milk","slug":"fresh-whole-milk","variant":null,
          "packSize":"1 litre","description":"Local dairy milk","imageKey":null,"barcode":null,
          "listPricePaise":7200,"sellingPricePaise":6800,"currencyCode":"INR",
          "logisticsAttributes":{"weightGrams":1030,"temperatureClass":"CHILLED"}
        },
        {
          "id":"22222222-2222-4222-8222-222222222222",
          "categoryId":"44444444-4444-4444-8444-444444444444",
          "subcategoryId":"55555555-5555-4555-8555-555555555555",
          "brand":null,"name":"Farm eggs","slug":"farm-eggs","variant":null,
          "packSize":"6 pieces","description":"Six fresh eggs","imageKey":null,"barcode":null,
          "listPricePaise":7600,"sellingPricePaise":7200,"currencyCode":"INR",
          "logisticsAttributes":{"fragile":true}
        },
        {
          "id":"77777777-7777-4777-8777-777777777777",
          "categoryId":"99999999-9999-4999-8999-999999999999",
          "subcategoryId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "brand":null,"name":"Pain relief tablets","slug":"pain-relief-tablets","variant":null,
          "packSize":"10 tablets","description":"Everyday pain relief","imageKey":null,"barcode":null,
          "listPricePaise":4500,"sellingPricePaise":4500,"currencyCode":"INR",
          "logisticsAttributes":{}
        }
      ]
      ,"nextCursor":null
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
