import Foundation
import MarketplaceDesignSystem
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
            "Reconnect to load the latest information."
        case .sessionExpired:
            "Sign in again to load the latest information."
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
    private var orderLiveTracking: DastakOrderLiveTracking?
    func syncOrderLiveTracking() async {
        var byID = Dictionary(uniqueKeysWithValues: v1Orders.map { ($0.id, $0) })
        if let activeV1Order, activeV1Order.version >= (byID[activeV1Order.id]?.version ?? 0) {
            byID[activeV1Order.id] = activeV1Order
        }
        await orderLiveTracking?.sync(byID.values.sorted { $0.createdAt > $1.createdAt })
    }
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var v1Catalogue: DastakV1CatalogueSnapshot?
    @Published private(set) var v1BrowseMap: DastakV1CatalogueBrowseMap?
    @Published private(set) var v1BrowseProducts: [DastakV1CatalogueSKU] = []
    @Published private(set) var v1CategoryProducts: [UUID: [DastakV1CatalogueSKU]] = [:]
    @Published private(set) var loadingV1CategoryIDs: Set<UUID> = []
    @Published private(set) var failedV1CategoryIDs: Set<UUID> = []
    @Published private(set) var v1Restaurants: [DastakV1RestaurantMenu] = []
    @Published private(set) var isLoadingV1Restaurants = false
    @Published private(set) var hasMoreV1Restaurants = false
    @Published private(set) var v1RestaurantsRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var catalogueRevision = 0
    @Published private(set) var isResolvingSavedItems = false
    @Published private(set) var isReordering = false
    private var reorderContextRevision = UUID()
    @Published private(set) var savedItemsRefreshFailure: DastakCustomerRefreshFailure?
    @Published private var resolvedSavedProducts: [DastakV1CatalogueSKU] = []
    @Published private(set) var v1SearchResults: [DastakV1CatalogueSKU] = []
    @Published private(set) var v1Orders: [DastakV1OrderSnapshot] = []
    @Published private(set) var wishlistItems: [CustomerWishlistItem] = []
    @Published private(set) var hasLoadedWishlist = false
    @Published private(set) var wishlistRefreshFailure: DastakCustomerRefreshFailure?
    private var wishlistReadRequest = UUID()
    private var wishlistLifetime = UUID()
    private enum WishlistOverride { case saved(CustomerWishlistItem), removed }
    private var wishlistOverrides: [String: WishlistOverride] = [:]
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
    @Published private(set) var isLoadingMoreV1SearchResults = false
    @Published private(set) var hasMoreV1SearchResults = false
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
    @Published private(set) var defaultDeliveryAddress: DastakDeliveryLocation?
    @Published private(set) var deliveryAddress: DastakDeliveryLocation? {
        didSet {
            if oldValue != deliveryAddress {
                reorderContextRevision = UUID()
                areaRequestID = UUID()
                areaLoadingKey = nil
                quoteRequestID = UUID()
                isLoadingCheckoutEstimate = false
                areaAvailability = nil
                checkoutEstimate = nil
                quotedBasketKey = nil
                availabilityError = nil
                checkoutEstimateError = nil
                if requiresAreaChecks {
                    v1Restaurants = []
                    restaurantRequestID = UUID()
                    restaurantContextKey = nil
                    restaurantCursor = nil
                    hasMoreV1Restaurants = false
                    isLoadingV1Restaurants = false
                    v1RestaurantsRefreshFailure = nil
                }
            }
        }
    }
    @Published private(set) var areaAvailability: DastakV1AreaAvailability?
    @Published private(set) var checkoutEstimate: DastakV1CheckoutQuote?
    @Published private(set) var availabilityError: String?
    @Published private(set) var checkoutEstimateError: String?
    @Published private(set) var isLoadingCheckoutEstimate = false
    private var areaReceivedAt = Date.distantPast
    private var quoteReceivedAt = Date.distantPast
    private var areaRequestID = UUID()
    private var quoteRequestID = UUID()
    private var quotedBasketKey: String?
    private let enforcesAreaChecks: Bool
    var requiresAreaChecks: Bool { accountIDProvider != nil && enforcesAreaChecks }
    @Published var discoveryRadiusKilometres = 10
    @Published var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            // Clear the previous query immediately, including during the UI debounce.
            resetV1Search()
            isSearchingV1Catalogue = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    @Published private(set) var baskets = DastakCustomerBaskets() {
        didSet {
            if !baskets[.grocery].isEmpty {
                groceryBasketPickedUp = true
            }
            if !baskets[.food].isEmpty { foodBasketPickedUp = true }
            if oldValue != baskets { reorderContextRevision = UUID() }
            guard !isRestoringCheckoutState else { return }
            quoteRequestID = UUID()
            isLoadingCheckoutEstimate = false
            checkoutEstimate = nil
            quotedBasketKey = nil
            do { try persistCheckoutState(baskets: baskets, pending: pendingCheckouts) }
            catch {
                isRestoringCheckoutState = true
                baskets = oldValue
                isRestoringCheckoutState = false
                blockCheckoutStorage()
            }
        }
    }
    @Published private(set) var pendingCheckouts: [DastakBasketService: DastakPendingCheckout] = [:]
    @Published private(set) var pendingConfirmations: [UUID: DastakPendingConfirmation] = [:]
    @Published private(set) var checkoutRecoveryIssue: String?
    var pendingCheckout: DastakPendingCheckout? { pendingCheckouts[cartService] }
    @Published var cartService: DastakBasketService = .grocery {
        didSet { if oldValue != cartService { reorderContextRevision = UUID() } }
    }
    @Published private(set) var isCartStorageReady: Bool
    @Published private(set) var submittingCartService: DastakBasketService?
    var cart: DastakCart { baskets[cartService] }
    @Published private(set) var groceryBasketPickedUp = false
    @Published private(set) var foodBasketPickedUp = false
    @Published private(set) var basketPrompt: DastakBasketPrompt?
    @Published private(set) var basketFlight: DastakBasketFlight?
    private var basketPromptTask: Task<Void, Never>?
    // User-command feedback only. Refresh, restoration and polling never emit.
    var hapticFeedback: (MarketplaceHapticEvent) -> Void = { _ in }
    var groceryBasketPrompt: Bool { basketPrompt?.service == .grocery }
    var hasGroceryBasket: Bool { groceryBasketPickedUp || !baskets[.grocery].isEmpty }

    func hasBasket(_ service: DastakBasketService) -> Bool {
        service == .grocery ? hasGroceryBasket : foodBasketPickedUp || !baskets[.food].isEmpty
    }

    func showsBasketDock(_ service: DastakBasketService) -> Bool {
        // A freshly submitted/refreshed order may reach the focused snapshot before history.
        let focusedOrderIsActive = activeV1Order.map { Self.isActiveV1Order($0.status) } ?? false
        return hasBasket(service) && !hasActiveOrders && !focusedOrderIsActive
    }

    func pickUpGroceryBasket() {
        pickUpBasket(.grocery)
    }

    func pickUpBasket(_ service: DastakBasketService) {
        guard !hasBasket(service) else { return }
        cartService = service
        if service == .grocery { groceryBasketPickedUp = true }
        else { foodBasketPickedUp = true }
        basketPromptTask?.cancel()
        basketPrompt = nil
        basketFlight = .init(service: service, productID: nil, imageKey: nil)
        hapticFeedback(.basketPickup)
    }

    private func requireBasket(_ service: DastakBasketService) -> Bool {
        guard !hasBasket(service) else { return true }
        let prompt = DastakBasketPrompt(service: service, expiresAt: Date().addingTimeInterval(5))
        basketPromptTask?.cancel()
        basketPrompt = prompt // A new ID retriggers the pop and restarts the five seconds on every attempt.
        hapticFeedback(.warning)
        basketPromptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.expireBasketPrompt(id: prompt.id)
        }
        return false
    }

    func expireBasketPrompt(id: UUID, now: Date = Date()) {
        guard basketPrompt?.id == id, let deadline = basketPrompt?.expiresAt, now >= deadline else { return }
        basketPrompt = nil
    }

    private func resetBasketExperience() {
        groceryBasketPickedUp = false
        foodBasketPickedUp = false
        basketPromptTask?.cancel()
        basketPrompt = nil
        basketFlight = nil
    }

    // UI-only pickup gate. Recovery/reorder and exact-SKU stock checks remain
    // in the existing basket mutation methods.
    func addShoppingProduct(_ product: DastakV1CatalogueSKU) {
        guard requireBasket(.grocery) else { return }
        addToCart(product)
    }

    func addShoppingFood(restaurant: DastakV1RestaurantMenu, item: DastakV1RestaurantMenuItem, optionIDs: [UUID]) {
        guard requireBasket(.food) else { return }
        addFoodToCart(restaurant: restaurant, item: item, optionIDs: optionIDs)
    }
    var canEditCurrentCart: Bool { canEditCart(cartService) }
    @Published var errorMessage: String?
    @Published var cartErrorMessage: String?
    @Published var v1OrderErrorMessage: String?
    @Published var parcelErrorMessage: String?
    @Published var ordersActionMessage: String?
    @Published private(set) var addressErrorMessage: String?
    @Published private(set) var catalogueRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var v1CatalogueRefreshFailure: DastakCustomerRefreshFailure?
    @Published private(set) var v1SearchRefreshFailure: DastakCustomerRefreshFailure?
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
    private let basketStore: DastakBasketStore
    private let checkoutJournalStorage: any DastakCheckoutJournalStorage
    private var checkoutJournalRevision: UUID?
    private var isDeletingCustomerProfile = false
    private var acknowledgedCustomerDeletionID: UUID?
    private var isRestoringCheckoutState = false
    private var basketAccountID: UUID?
    private let issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)?
    private let oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)?
    private var preferenceScope = "default"
    private var accountDeletionAttempt = DastakAccountDeletionAttempt()
    private var orderPlacementAttempt = DastakOrderPlacementAttempt()
    private var v1IssueAttempt: (
        fingerprint: String,
        key: IdempotencyKey,
        evidencePath: String?
    )?
    private var parcelPlacementAttempt = DastakOrderPlacementAttempt()
    private var ordersRefreshQueued = false
    private var v1OrdersRefreshQueued = false
    private var activeV1OrderRefreshQueued = false
    private var activeV1OrderRefreshInFlight = false
    private var parcelsRefreshQueued = false
    private var v1OrdersNextCursor: DastakV1OrderCursor?
    private var restaurantRequestID = UUID()
    private var restaurantContextKey: String?
    private var restaurantCursor: DastakV1RestaurantAreaCursor?
    private var seenRestaurantCursors: Set<UUID> = []
    private var failedRestaurantLoadMore = false
    private var areaLoadingKey: String?
    private var searchRequestID = UUID()
    private var searchCursor: DastakV1CatalogueCursor?
    private var searchCatalogueVersion: String?
    private var searchLoadedQuery: String?
    private var seenSearchCursors: Set<UUID> = []
    private var searchPageCount = 0
    private var categoryLoadWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

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
        oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil,
        basketDefaults: UserDefaults = .standard,
        checkoutJournalStorage: any DastakCheckoutJournalStorage = DastakFileCheckoutJournalStorage(),
        enforcesAreaChecks: Bool = true
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
        self.enforcesAreaChecks = enforcesAreaChecks
        self.basketStore = DastakBasketStore(defaults: basketDefaults)
        self.checkoutJournalStorage = checkoutJournalStorage
        self.isCartStorageReady = accountIDProvider == nil
        self.issueEvidenceUploader = issueEvidenceUploader
        self.oauthIdentityLinker = oauthIdentityLinker
    }

    convenience init(
        functions: any FunctionClient,
        checkoutCustomerProvider: (@Sendable () async throws -> MarketplaceCheckoutCustomer?)? = nil,
        accountIDProvider: (@Sendable () async throws -> UUID)? = nil,
        issueEvidenceUploader: (@Sendable (Data, String) async throws -> String)? = nil,
        oauthIdentityLinker: (@Sendable (MarketplaceOAuthProvider) async throws -> Void)? = nil,
        basketDefaults: UserDefaults = .standard,
        checkoutJournalStorage: any DastakCheckoutJournalStorage = DastakFileCheckoutJournalStorage(),
        enforcesAreaChecks: Bool = true
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
            oauthIdentityLinker: oauthIdentityLinker,
            basketDefaults: basketDefaults,
            checkoutJournalStorage: checkoutJournalStorage,
            enforcesAreaChecks: enforcesAreaChecks
        )
        if let accountIDProvider {
            orderLiveTracking = DastakOrderLiveTracking(functions: functions, accountID: accountIDProvider)
        }
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
        let products = Dictionary(knownCatalogueProducts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        unresolvedWishlistItems.count
    }
    var unresolvedWishlistItems: [CustomerWishlistItem] {
        let retail = Set(wishlistRetailProducts.map(\.id)), food = Set(wishlistMenuSelections.map(\.id))
        return wishlistItems.filter { $0.kind == .retailSKU ? !retail.contains($0.itemID) : !food.contains($0.itemID) }
    }
    func wishlistChangeDisabled(_ id: UUID) -> Bool {
        !hasLoadedWishlist || isLoadingWishlist || wishlistUpdatingIDs.contains(id)
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
        await restoreCartStorage()
        async let location: Void = restorePreferencesAndAddress()
        async let v1Orders: Void = refreshV1Orders()
        async let v1Catalogue: Void = refreshV1Catalogue()
        async let wishlist: Void = refreshWishlist()
        async let checkoutCustomer: Void = refreshCheckoutCustomer()
        await location
        async let availability: Void = refreshAreaAvailability(force: true)
        _ = await (
            v1Orders,
            v1Catalogue,
            wishlist,
            availability,
            checkoutCustomer
        )
    }

    func refreshWishlist() async {
        guard !isLoadingWishlist, wishlistUpdatingIDs.isEmpty else { return }
        let request = UUID(), lifetime = wishlistLifetime, account = basketAccountID
        wishlistReadRequest = request
        isLoadingWishlist = true
        defer { if wishlistReadRequest == request { isLoadingWishlist = false } }
        do {
            let value = try await wishlistClient.snapshot(idempotencyKey: makeKey())
            guard request == wishlistReadRequest, lifetime == wishlistLifetime, account == basketAccountID else { return }
            guard Set(value.items.map(\.id)).count == value.items.count else { throw FunctionClientError.invalidResponse }
            wishlistItems = value.items; hasLoadedWishlist = true; wishlistRefreshFailure = nil; wishlistOverrides = [:]
        } catch {
            guard request == wishlistReadRequest, lifetime == wishlistLifetime, account == basketAccountID else { return }
            wishlistRefreshFailure = refreshFailure(for: error)
            presentError(for: error, fallback: "Your Wishlist could not be loaded.")
        }
    }

    func toggleWishlist(kind: CustomerWishlistItemKind, itemID: UUID) async {
        guard hasLoadedWishlist else {
            errorMessage = "Load your Wishlist before changing saved items."
            return
        }
        await setWishlistItem(kind: kind, itemID: itemID, wished: !isWishlisted(kind: kind, itemID: itemID))
    }
    func removeWishlistItem(kind: CustomerWishlistItemKind, itemID: UUID) async {
        // An explicit Remove never turns into Save after a concurrent refresh or another device's removal.
        await setWishlistItem(kind: kind, itemID: itemID, wished: false)
    }
    private func setWishlistItem(kind: CustomerWishlistItemKind, itemID: UUID, wished: Bool) async {
        guard !wishlistUpdatingIDs.contains(itemID), !isDeletingCustomerProfile, acknowledgedCustomerDeletionID == nil else { return }
        let lifetime = wishlistLifetime, account = basketAccountID
        if wishlistUpdatingIDs.isEmpty { wishlistOverrides = [:] }
        wishlistReadRequest = UUID(); isLoadingWishlist = false
        wishlistUpdatingIDs.insert(itemID)
        defer { if lifetime == wishlistLifetime { wishlistUpdatingIDs.remove(itemID) } }
        do {
            let value = try await wishlistClient.setItem(
                kind: kind,
                itemID: itemID,
                wished: wished,
                idempotencyKey: makeKey()
            )
            guard lifetime == wishlistLifetime, account == basketAccountID else { return }
            guard Set(value.items.map(\.id)).count == value.items.count,
                  value.items.contains(where: { $0.kind == kind && $0.itemID == itemID }) == wished else { throw FunctionClientError.invalidResponse }
            // Incorporate remote entries while preserving exact acknowledgements from this concurrent batch.
            let targetKey = "\(kind.rawValue):\(itemID.uuidString.lowercased())"
            if let item = value.items.first(where: { $0.kind == kind && $0.itemID == itemID }) { wishlistOverrides[targetKey] = .saved(item) }
            else { wishlistOverrides[targetKey] = .removed }
            var merged = value.items
            for (key, override) in wishlistOverrides {
                merged.removeAll { $0.id == key }
                if case let .saved(item) = override { merged.append(item) }
            }
            wishlistItems = merged.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
            hasLoadedWishlist = true; wishlistRefreshFailure = nil
            errorMessage = nil
        hapticFeedback(.selection)
        } catch {
            guard lifetime == wishlistLifetime, account == basketAccountID else { return }
            presentError(for: error, fallback: "Your Wishlist could not be updated.")
            hapticFeedback(.error)
        }
    }
    private func resetWishlistPresentation() {
        wishlistLifetime = UUID(); wishlistReadRequest = UUID()
        wishlistItems = []; hasLoadedWishlist = false; wishlistRefreshFailure = nil
        isLoadingWishlist = false; wishlistUpdatingIDs = []
        wishlistOverrides = [:]
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
        guard !isDeletingCustomerProfile, !isSubmittingV1Order, !isCheckingOut else {
            throw DastakCustomerDeletionError.busy
        }
        isDeletingCustomerProfile = true
        let wasStorageReady = isCartStorageReady
        defer {
            isDeletingCustomerProfile = false
            if acknowledgedCustomerDeletionID == nil { isCartStorageReady = wasStorageReady }
        }
        let accountID: UUID
        if let acknowledgedCustomerDeletionID { accountID = acknowledgedCustomerDeletionID }
        else {
            guard let accountIDProvider, let current = try? await accountIDProvider(),
                  current == basketAccountID else { throw DastakCustomerDeletionError.identityUnavailable }
            accountID = current
        }
        let scope = accountID.uuidString.lowercased()
        guard !isSubmittingV1Order, !isCheckingOut else { throw DastakCustomerDeletionError.busy }
        if acknowledgedCustomerDeletionID == nil,
           try !checkoutJournalStorage.hasAcknowledgedCustomerDeletion(accountID: accountID) {
            guard isCartStorageReady else { throw DastakCustomerDeletionError.identityUnavailable }
            let saved = try checkoutJournalStorage.load(accountID: accountID)
            guard pendingCheckouts.isEmpty, pendingConfirmations.isEmpty,
                  saved?.pending.isEmpty != false, saved?.confirmations?.isEmpty != false else {
                throw DastakCustomerDeletionError.unresolvedCheckout
            }
            let key = accountDeletionAttempt.key(scope: scope)
            isCartStorageReady = false // No new checkout can start while deletion is awaiting a reply.
            do {
                try await accountProfileClient.deleteAccount(persona: .customer, idempotencyKey: key)
            } catch {
                if case let FunctionClientError.api(status, _, _) = error, (400..<500).contains(status) {
                    throw error // Keep existing reauthentication/active-work rejection handling.
                }
                throw DastakCustomerDeletionError.outcomeUnknown
            }
        }
        acknowledgedCustomerDeletionID = accountID
        isCartStorageReady = false
        do {
            try checkoutJournalStorage.acknowledgeCustomerDeletion(accountID: accountID)
            try finishCustomerDeletionCleanup(accountID: accountID)
        } catch {
            checkoutRecoveryIssue = DastakCustomerDeletionError.cleanupRequired.localizedDescription
            throw DastakCustomerDeletionError.cleanupRequired
        }
    }

    private func finishCustomerDeletionCleanup(accountID: UUID) throws {
        // Only the acknowledged Customer's own cache/preferences are in scope.
        basketStore.remove(accountID: accountID)
        let scope = accountID.uuidString.lowercased()
        for name in ["discoveryLocation", "deliveryLocation", "discoveryRadiusKilometres"] {
            UserDefaults.standard.removeObject(forKey: "dastak.customer.\(scope).\(name)")
        }
        accountDeletionAttempt.complete(scope: scope)
        try checkoutJournalStorage.removeAfterAcknowledgedCustomerDeletion(accountID: accountID)
        isRestoringCheckoutState = true
        baskets = DastakCustomerBaskets()
        pendingCheckouts = [:]
        pendingConfirmations = [:]
        isRestoringCheckoutState = false
        checkoutJournalRevision = nil
        basketAccountID = nil
        resetBasketExperience()
        isCartStorageReady = false
        deliveryAddress = nil
        defaultDeliveryAddress = nil
        savedAddresses = []
        selectedLocation = nil
        checkoutCustomer = nil
        areaRequestID = UUID()
        quoteRequestID = UUID()
        areaAvailability = nil
        checkoutEstimate = nil
        v1Orders = []
        activeV1Order = nil
        resetWishlistPresentation()
        checkoutRecoveryIssue = nil
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
            hapticFeedback(.error)
            identityMessage = "That sign-in may belong to another Dastak account. Sign in to that account or contact support; Dastak never merges accounts by email or phone."
            identityMessageIsSuccess = false
        }
    }

    func setLocation(_ location: DastakDeliveryLocation, makeDefault: Bool = true) async -> Bool {
        guard let label = location.label, let building = location.building else {
            addressErrorMessage = "Add a label and doorstep details before saving."
            hapticFeedback(.warning)
            return false
        }
        do {
            let knownIDs = Set(savedAddresses.compactMap(\.addressID))
            let response = try await addressClient.save(
                addressID: location.addressID,
                label: label,
                address: location.address,
                building: building,
                floor: location.floor,
                landmark: location.landmark,
                deliveryNotes: location.deliveryNotes,
                location: location.point,
                makeDefault: makeDefault,
                idempotencyKey: makeKey()
            )
            let candidates = response.addresses.filter {
                !knownIDs.contains($0.addressID)
                    && $0.label == label.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.address == location.address.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.doorstepBuilding == building.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.location == location.point
            }
            let savedID = makeDefault ? response.addresses.first(where: \.isDefault)?.addressID
                : location.addressID ?? (candidates.count == 1 ? candidates.first?.addressID : nil)
            guard let savedID, response.addresses.contains(where: { $0.addressID == savedID }) else {
                throw URLError(.cannotParseResponse)
            }
            applyAddressSnapshot(response, selectedID: savedID)
            addressErrorMessage = nil
            await refreshAreaAvailability(force: true)
            hapticFeedback(.success)
            return true
        } catch {
            hapticFeedback(.error)
            addressErrorMessage = message(
                for: error,
                fallback: "The address could not be saved. Check your connection and try again."
            )
            return false
        }
    }

    func selectSavedAddress(_ location: DastakDeliveryLocation, makeDefault: Bool = true) async -> Bool {
        guard let addressID = location.addressID else { return await setLocation(location, makeDefault: makeDefault) }
        do {
            // Checkout selects a delivery target, not an account-wide preference.
            let response: CustomerDeliveryAddressCollection
            if makeDefault {
                response = try await addressClient.setDefault(addressID: addressID, idempotencyKey: makeKey())
            } else {
                response = try await addressClient.snapshot(idempotencyKey: makeKey())
            }
            guard response.addresses.contains(where: { $0.addressID == addressID }) else {
                throw URLError(.resourceUnavailable)
            }
            applyAddressSnapshot(response, selectedID: addressID)
            addressErrorMessage = nil
            await refreshAreaAvailability(force: true)
            hapticFeedback(.success)
            return true
        } catch {
            hapticFeedback(.error)
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
            applyAddressSnapshot(response, selectedID: deliveryAddress?.addressID)
            addressErrorMessage = nil
            await refreshAreaAvailability(force: true)
            hapticFeedback(.success)
            return true
        } catch {
            hapticFeedback(.error)
            addressErrorMessage = message(for: error, fallback: "That address could not be deleted. Try again.")
            return false
        }
    }

    private func applyAddressSnapshot(_ response: CustomerDeliveryAddressCollection, selectedID: UUID?) {
        savedAddresses = response.addresses.map(Self.deliveryLocation)
        defaultDeliveryAddress = response.addresses.first(where: \.isDefault).map(Self.deliveryLocation)
        deliveryAddress = savedAddresses.first(where: { selectedID != nil && $0.addressID == selectedID })
            ?? defaultDeliveryAddress
        isDeliveryAddressConfirmed = deliveryAddress?.isReadyForDelivery == true
    }

    func selectDiscoveryLocation(_ location: DastakDeliveryLocation) async {
        selectedLocation = Self.discoveryLocation(from: location)
        quote = nil
        orderPlacementAttempt.reset()
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
            let browseMap = try await v1Client.catalogueBrowseMap(idempotencyKey: makeKey())
            guard browseMap?.isValid != false else {
                throw DastakV1BrowseLoadError.invalidMap
            }
            async let catalogue = v1Client.catalogue(
                query: nil,
                categoryID: nil,
                subcategoryID: nil,
                limit: 250,
                cursor: nil,
                idempotencyKey: makeKey()
            )
            let firstPage = try await catalogue
            try Task.checkCancellation()
            v1Catalogue = firstPage
            v1BrowseMap = browseMap
            v1BrowseProducts = browseMap == nil ? [] : firstPage.skus
            catalogueRevision += 1
            v1CategoryProducts = [:]
            resolvedSavedProducts = []
            loadingV1CategoryIDs = []
            failedV1CategoryIDs = []
            let waiting = categoryLoadWaiters.values.flatMap { $0 }
            categoryLoadWaiters = [:]
            waiting.forEach { $0.resume() }
            v1CatalogueRefreshFailure = nil
        } catch {
            guard !Task.isCancelled else { return }
            v1CatalogueRefreshFailure = refreshFailure(for: error)
        }
    }

    func loadV1Category(_ categoryID: UUID, force: Bool = false) async {
        // A newly opened rail may share a category with the cancelled previous rail.
        // Wait for that request to finish, then use its cache or retry; never strand a spinner.
        while loadingV1CategoryIDs.contains(categoryID) {
            guard !Task.isCancelled else { return }
            await withCheckedContinuation { categoryLoadWaiters[categoryID, default: []].append($0) }
        }
        guard !Task.isCancelled, force || v1CategoryProducts[categoryID] == nil else { return }

        loadingV1CategoryIDs.insert(categoryID)
        failedV1CategoryIDs.remove(categoryID)
        let revision = catalogueRevision
        defer {
            if revision == catalogueRevision {
                loadingV1CategoryIDs.remove(categoryID)
                categoryLoadWaiters.removeValue(forKey: categoryID)?.forEach { $0.resume() }
            }
        }

        do {
            var products: [DastakV1CatalogueSKU] = []
            var cursor: DastakV1CatalogueCursor?
            var pageCount = 0
            var seenCursors: Set<UUID> = []
            repeat {
                let page = try await v1Client.catalogue(
                    query: nil,
                    categoryID: categoryID,
                    subcategoryID: nil,
                    limit: 250,
                    cursor: cursor,
                    idempotencyKey: makeKey()
                )
                guard revision == catalogueRevision else { return }
                try Task.checkCancellation()
                if let expected = v1Catalogue?.catalogueVersion, let actual = page.catalogueVersion,
                   expected != actual { throw DastakV1BrowseLoadError.invalidPagination }
                products.append(contentsOf: page.skus)
                cursor = page.nextCursor
                pageCount += 1
                if let cursor, !seenCursors.insert(cursor.skuID).inserted {
                    throw DastakV1BrowseLoadError.invalidPagination
                }
            } while cursor != nil && pageCount < 20
            guard cursor == nil else { throw DastakV1BrowseLoadError.invalidPagination }

            var seen = Set<UUID>()
            v1CategoryProducts[categoryID] = products
                .filter { seen.insert($0.id).inserted }
                .sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            var known = Set<UUID>()
            v1BrowseProducts = ((v1Catalogue?.skus ?? []) + v1CategoryProducts.values.flatMap { $0 })
                .filter { known.insert($0.id).inserted }
        } catch {
            guard revision == catalogueRevision, !Task.isCancelled else { return }
            failedV1CategoryIDs.insert(categoryID)
        }
    }

    func searchV1Catalogue() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        resetV1Search()
        guard !query.isEmpty else { return }
        searchLoadedQuery = query
        isSearchingV1Catalogue = true
        await loadV1SearchPage(query: query, request: searchRequestID, cursor: nil)
    }

    func loadMoreV1SearchResults() async {
        guard !isSearchingV1Catalogue, !isLoadingMoreV1SearchResults,
              hasMoreV1SearchResults, let cursor = searchCursor,
              let query = searchLoadedQuery,
              query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        isLoadingMoreV1SearchResults = true
        await loadV1SearchPage(query: query, request: searchRequestID, cursor: cursor)
    }

    private func resetV1Search() {
        searchRequestID = UUID()
        v1SearchResults = []
        v1SearchRefreshFailure = nil
        isSearchingV1Catalogue = false
        isLoadingMoreV1SearchResults = false
        hasMoreV1SearchResults = false
        searchCursor = nil
        searchCatalogueVersion = nil
        searchLoadedQuery = nil
        seenSearchCursors = []
        searchPageCount = 0
    }

    private func loadV1SearchPage(query: String, request: UUID, cursor: DastakV1CatalogueCursor?) async {
        v1SearchRefreshFailure = nil
        defer {
            if request == searchRequestID {
                isSearchingV1Catalogue = false
                isLoadingMoreV1SearchResults = false
            }
        }
        do {
            guard searchPageCount < 100 else { throw DastakV1BrowseLoadError.invalidPagination }
            let result = try await v1Client.catalogue(
                query: query,
                categoryID: nil,
                subcategoryID: nil,
                limit: 100,
                cursor: cursor,
                idempotencyKey: makeKey()
            )
            guard !Task.isCancelled, request == searchRequestID,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            // Never mix catalogue generations or silently accept a cyclic/truncated feed.
            guard result.skus.count <= 100,
                  cursor == nil || result.catalogueVersion == searchCatalogueVersion,
                  result.nextCursor.map({ !seenSearchCursors.contains($0.skuID) }) ?? true else {
                throw DastakV1BrowseLoadError.invalidPagination
            }
            if cursor == nil { searchCatalogueVersion = result.catalogueVersion }
            var known = Set(v1SearchResults.map(\.id))
            v1SearchResults.append(contentsOf: result.skus.filter { known.insert($0.id).inserted })
            searchPageCount += 1
            searchCursor = result.nextCursor
            hasMoreV1SearchResults = result.nextCursor != nil
            if let next = result.nextCursor { seenSearchCursors.insert(next.skuID) }
            v1SearchRefreshFailure = nil
        } catch {
            guard !Task.isCancelled, request == searchRequestID,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            if error is DastakV1BrowseLoadError {
                // Keep valid loaded results, but require a fresh search for an invalid feed.
                searchCursor = nil
                hasMoreV1SearchResults = false
            }
            v1SearchRefreshFailure = refreshFailure(for: error)
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
        activeV1OrderRefreshQueued = true
        guard !activeV1OrderRefreshInFlight else { return }
        activeV1OrderRefreshInFlight = true
        defer { activeV1OrderRefreshInFlight = false }

        while activeV1OrderRefreshQueued, !Task.isCancelled {
            activeV1OrderRefreshQueued = false
            guard let requestedOrder = activeV1Order else { return }
            do {
                let refreshed = try await v1Client.order(
                    id: requestedOrder.id,
                    idempotencyKey: makeKey()
                )
                guard activeV1Order?.id == requestedOrder.id,
                      refreshed.version >= (activeV1Order?.version ?? requestedOrder.version) else {
                    continue
                }
                activeV1Order = refreshed
                v1Orders = [refreshed] + v1Orders.filter { $0.id != refreshed.id }
                v1OrderErrorMessage = nil
            } catch {
                v1OrderErrorMessage = message(
                    for: error,
                    fallback: "Your matching status could not be refreshed."
                )
            }
        }
    }

    /// Resolve contact from a fresh, authorized order, never a cached notification.
    func liveActivityRiderCallURL(orderID: UUID) async -> URL? {
        guard let order = try? await v1Client.order(id: orderID, idempotencyKey: makeKey()),
              order.id == orderID, order.status.rawValue == "OUT_FOR_DELIVERY" else { return nil }
        return order.tracking?.customerCallURL(orderStatus: order.status.rawValue)
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
        guard isCartStorageReady, !isDeletingCustomerProfile, !cart.isEmpty, !isSubmittingV1Order, !isCheckingOut else { return false }
        if pendingCheckout == nil && requiresAreaChecks {
            let context = checkoutRefreshKey
            await refreshCheckoutEstimate()
            guard context == checkoutRefreshKey, !isSubmittingV1Order, !isCheckingOut, isCartStorageReady else { return false }
            if let issue = checkoutAvailabilityIssue {
                v1OrderErrorMessage = issue
                hapticFeedback(.warning)
                return false
            }
        }
        let submittedService = cartService
        let submittedCart = cart
        let submittedAccountID = basketAccountID
        let previousAttempt = pendingCheckouts[submittedService]
        let attempt: DastakPendingCheckout
        if let previousAttempt {
            attempt = previousAttempt // Never rebuild a retry from edited address/profile data.
        } else {
            guard hasCompleteDeliveryAddress, let deliveryAddress else {
                v1OrderErrorMessage = "Add a complete delivery address before placing your order."
                hapticFeedback(.warning)
                return false
            }
            guard let customer = checkoutCustomer else {
                v1OrderErrorMessage = "Your account details are still loading. Try again in a moment."
                hapticFeedback(.warning)
                return false
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

            let submission = DastakV1OrderSubmission(
                deliveryAddress: address,
                recipient: DastakV1RecipientInput(name: customer.displayName, phoneNumber: customer.phoneNumber),
                restaurantBranchID: submittedCart.restaurantBranchID,
                lines: submittedCart.orderLines
            )
            attempt = DastakPendingCheckout(service: submittedService, key: makeKey(), submission: submission)
        }
        var prepared = pendingCheckouts
        prepared[submittedService] = attempt
        do {
            // Must reach durable storage before the first network write, even a retry.
            try persistCheckoutState(baskets: baskets, pending: prepared)
            pendingCheckouts = prepared
        } catch {
            hapticFeedback(.error)
            blockCheckoutStorage()
            return false
        }

        isSubmittingV1Order = true
        submittingCartService = submittedService
        defer {
            isSubmittingV1Order = false
            submittingCartService = nil
        }
        do {
            var recovered = attempt
            if recovered.orderID == nil {
                let response = try await v1Client.submit(attempt.submission, idempotencyKey: attempt.key)
                guard basketAccountID == submittedAccountID, isCartStorageReady else { return false }
                recovered.orderID = response.id
                prepared = pendingCheckouts
                prepared[submittedService] = recovered
                try persistCheckoutState(baskets: baskets, pending: prepared)
                pendingCheckouts = prepared
            }
            // Idempotent submit can replay an old response; always read current state.
            let order = try await v1Client.order(id: recovered.orderID!, idempotencyKey: makeKey())
            guard basketAccountID == submittedAccountID, isCartStorageReady else { return false }
            guard order.id == recovered.orderID else { throw FunctionClientError.invalidResponse }
            var remaining = baskets
            remaining[submittedService].removeAll()
            prepared = pendingCheckouts
            prepared[submittedService] = nil
            // Acknowledgement and basket consumption are one atomic write.
            try persistCheckoutState(baskets: remaining, pending: prepared)
            isRestoringCheckoutState = true
            baskets = remaining
            pendingCheckouts = prepared
            isRestoringCheckoutState = false
            activeV1Order = order
            v1Orders = [order] + v1Orders.filter { $0.id != order.id }
            v1OrderErrorMessage = nil
            cartErrorMessage = nil
            hapticFeedback(.success)
            return true
        } catch {
            hapticFeedback(.error)
            // Only a first, explicit pre-admission rejection releases the basket.
            // An ambiguous/restored attempt never gets a new key automatically.
            if previousAttempt == nil, pendingCheckouts[submittedService]?.orderID == nil,
               case let FunctionClientError.api(status, code, _) = error,
               (status == 400 && code == "validation_failed" || status == 409 && code == "invalid_state") {
                var rejected = pendingCheckouts
                rejected[submittedService] = nil
                do {
                    try persistCheckoutState(baskets: baskets, pending: rejected)
                    pendingCheckouts = rejected
                } catch {
                    hapticFeedback(.error)
                    blockCheckoutStorage()
                }
            }
            if error is DastakCheckoutStorageError { blockCheckoutStorage() }
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Checkout is not yet confirmed. Recover this checkout to check its original order; do not start it again."
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
        hapticFeedback(.success)
        } catch {
            hapticFeedback(.error)
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
            hapticFeedback(.success)
            return true
        } catch {
            hapticFeedback(.error)
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Your issue could not be sent. Try again without changing the details."
            )
            return false
        }
    }

    func addToCart(_ product: DastakV1CatalogueSKU) {
        let previous = baskets[.grocery].itemCount
        defer { basketFeedback(.grocery, previousCount: previous) }
        guard canEditCart(.grocery) else { return }
        if let issue = groceryAddIssue(product.id) { cartErrorMessage = issue; return }
        cartService = .grocery
        let previousCount = baskets[.grocery].itemCount
        if baskets[.grocery].add(product) == .quantityLimit {
            cartErrorMessage = "You can add up to \(DastakCart.maximumQuantity) of one item."
        } else {
            cartErrorMessage = nil
        }
        if baskets[.grocery].itemCount > previousCount {
            basketFlight = .init(service: .grocery, productID: product.id, imageKey: product.imageKey)
        }
    }

    func addFoodToCart(
        restaurant: DastakV1RestaurantMenu,
        item: DastakV1RestaurantMenuItem,
        optionIDs: [UUID]
    ) {
        let previous = baskets[.food].itemCount
        defer { basketFeedback(.food, previousCount: previous) }
        guard canEditCart(.food) else { return }
        if let issue = restaurantIssue(restaurant) { cartErrorMessage = issue; return }
        cartService = .food
        let previousCount = baskets[.food].itemCount
        switch baskets[.food].addFood(restaurant: restaurant.restaurant, item: item, optionIDs: optionIDs) {
        case .added:
            cartErrorMessage = nil
        case .quantityLimit:
            cartErrorMessage = "You can add up to \(DastakCart.maximumQuantity) of one item."
        case .differentRestaurant:
            cartErrorMessage = "A basket can contain food from one Restaurant/Cafe. Remove it before choosing another."
        }
        if baskets[.food].itemCount > previousCount {
            basketFlight = .init(service: .food, productID: item.id, imageKey: item.imageKey)
        }
    }

    func imageKey(for line: DastakV1OrderLine) -> String? {
        if let skuID = line.skuID {
            return knownCatalogueProducts.first { $0.id == skuID }?.imageKey
        }
        guard let menuItemID = line.menuItemID else { return nil }
        return v1Restaurants
            .lazy
            .flatMap(\.categories)
            .flatMap(\.items)
            .first { $0.id == menuItemID }?
            .imageKey
    }

    func reviewReorder(_ order: DastakV1OrderSnapshot, service: DastakBasketService? = nil) -> DastakReorderReview? {
        let services = DastakReorderReview.services(for: order)
        guard let target = service ?? (services.count == 1 ? services.first : nil), services.contains(target) else {
            ordersActionMessage = services.count > 1
                ? "Choose Grocery or Food to reorder separately. Your baskets are unchanged."
                : "This order has no supported items to reorder. Your baskets are unchanged."
            return nil
        }
        guard canEditCart(target), pendingConfirmations[order.id] == nil, !isReordering else {
            ordersActionMessage = "Finish or recover the pending \(target.title) basket check before ordering again."
            return nil
        }
        return .init(order: order, service: target, baskets: baskets, activeService: cartService,
                     accountID: basketAccountID, areaKey: availabilityRefreshKey, contextRevision: reorderContextRevision)
    }

    private func reorderContextMatches(_ review: DastakReorderReview) -> Bool {
        review.contextRevision == reorderContextRevision && review.baskets == baskets
            && review.activeService == cartService && review.accountID == basketAccountID
            && review.areaKey == availabilityRefreshKey && canEditCart(review.service)
            && pendingConfirmations[review.order.id] == nil
    }

    /// No replacement consent is inferred by this convenience path.
    func reorderWithCurrentCatalogue(_ order: DastakV1OrderSnapshot) async -> DastakReorderResult {
        guard let review = reviewReorder(order) else { return .init(addedUnits: 0, skippedLines: 0) }
        guard !review.requiresReplacement else {
            ordersActionMessage = "Review replacement of your \(review.service.title) basket before ordering again."
            return .init(addedUnits: 0, skippedLines: 0)
        }
        return await reorderWithCurrentCatalogue(review)
    }

    func reorderWithCurrentCatalogue(_ review: DastakReorderReview) async -> DastakReorderResult {
        func fail(_ message: String) -> DastakReorderResult {
            ordersActionMessage = message
            return .init(addedUnits: 0, skippedLines: 0)
        }
        guard !isReordering, !isResolvingSavedItems, !isLoadingV1Restaurants,
              !requiresAreaChecks || areaLoadingKey == nil,
              reorderContextMatches(review) else {
            return fail("Your basket, location or pending checkout changed. Review Order again before replacing anything.")
        }
        isReordering = true
        defer { isReordering = false }
        do {
            if let accountIDProvider {
                guard try await accountIDProvider() == review.accountID else {
                    return fail("Sign in to the same account and review Order again. Your baskets are unchanged.")
                }
            }
            if requiresAreaChecks {
                await refreshAreaAvailability(force: true)
                guard currentAreaAvailability != nil else {
                    return fail("Availability could not be checked. Your baskets are unchanged; reconnect and try again.")
                }
            }
            let lines = review.order.lines.filter { $0.lineType == (review.service == .grocery ? "RETAIL_SKU" : "FOOD_MENU_ITEM") }
            let products: [DastakV1CatalogueSKU]
            if review.service == .grocery {
                products = try await currentReorderProducts(ids: Set(lines.compactMap(\.skuID)))
            } else {
                products = []
                await refreshV1Restaurants()
                guard v1RestaurantsRefreshFailure == nil,
                      await resolveSavedItems(skuIDs: [], menuIDs: Set(lines.compactMap(\.menuItemID))) else {
                    return fail("The current menu could not be checked. Your baskets are unchanged; try again.")
                }
            }
            try Task.checkCancellation()
            if let accountIDProvider {
                guard try await accountIDProvider() == review.accountID else {
                    return fail("Your account changed. Your baskets are unchanged.")
                }
            }
            try Task.checkCancellation()
            guard reorderContextMatches(review) else {
                return fail("Your basket, location or pending checkout changed while checking items. Review Order again.")
            }
            if requiresAreaChecks, currentAreaAvailability == nil {
                return fail("Availability has expired. Your baskets are unchanged; check again.")
            }
            return commitReorder(review, products: products)
        } catch {
            hapticFeedback(.error)
            return fail("These items could not be checked. Your baskets are unchanged; reconnect and try Order again.")
        }
    }

    /// Existing catalogue API only: fresh bounded pages, never stale search/cache fallbacks.
    private func currentReorderProducts(ids: Set<UUID>) async throws -> [DastakV1CatalogueSKU] {
        var missing = ids, found: [DastakV1CatalogueSKU] = []
        var cursor: DastakV1CatalogueCursor?, version: String?
        var seen = Set<UUID>(), pages = 0
        repeat {
            let page = try await v1Client.catalogue(query: nil, categoryID: nil, subcategoryID: nil,
                                                  limit: 250, cursor: cursor, idempotencyKey: makeKey())
            try Task.checkCancellation()
            if let version, page.catalogueVersion != version { throw DastakV1BrowseLoadError.invalidPagination }
            if version == nil { version = page.catalogueVersion }
            found += page.skus.filter { missing.contains($0.id) }
            missing.subtract(page.skus.map(\.id))
            cursor = page.nextCursor
            pages += 1
            if let cursor, !seen.insert(cursor.skuID).inserted { throw DastakV1BrowseLoadError.invalidPagination }
            if pages >= 40, cursor != nil, !missing.isEmpty { throw DastakV1BrowseLoadError.invalidPagination }
        } while !missing.isEmpty && cursor != nil
        return found
    }

    private func commitReorder(_ review: DastakReorderReview, products: [DastakV1CatalogueSKU]) -> DastakReorderResult {
        var rebuilt = DastakCart()
        var addedUnits = 0
        func unavailable() -> DastakReorderResult {
            ordersActionMessage = "An exact item, quantity, restaurant or dish option is unavailable. Nothing was replaced."
            return .init(addedUnits: 0, skippedLines: 0)
        }
        for line in review.order.lines where line.lineType == (review.service == .grocery ? "RETAIL_SKU" : "FOOD_MENU_ITEM") {
            guard (1...DastakCart.maximumQuantity).contains(line.quantity) else { return unavailable() }
            let quantity = line.quantity
            if review.service == .grocery, let skuID = line.skuID,
               let product = products.first(where: { $0.id == skuID }) {
                let total = (rebuilt.entries.first { $0.id == skuID }?.quantity ?? 0) + quantity
                guard total <= DastakCart.maximumQuantity else { return unavailable() }
                if requiresAreaChecks {
                    guard let area = currentAreaAvailability, area.groceryServiceable,
                          total <= area.quantity(for: skuID) else { return unavailable() }
                }
                for _ in 0..<quantity { _ = rebuilt.add(product) }
                addedUnits += quantity
                continue
            }
            if review.service == .food, let menuItemID = line.menuItemID,
               let restaurant = v1Restaurants.first(where: {
                   $0.restaurant.branchID == review.order.restaurant?.branchID
               }),
               restaurantIssue(restaurant) == nil,
               let item = restaurant.categories.filter({ $0.status == "ACTIVE" }).lazy.flatMap(\.items)
                   .first(where: { $0.id == menuItemID }) {
                let requestedOptionIDs = line.foodSelection?.options.map(\.id) ?? []
                guard Self.validReorderOptions(item: item, ids: requestedOptionIDs) else { return unavailable() }
                for _ in 0..<quantity {
                    if rebuilt.addFood(
                        restaurant: restaurant.restaurant,
                        item: item,
                        optionIDs: requestedOptionIDs
                    ) != .added {
                        return unavailable()
                    }
                }
                addedUnits += quantity
                continue
            }
            return unavailable()
        }
        var replacement = baskets
        replacement[review.service] = rebuilt
        guard addedUnits > 0, replacement.isValid else { return unavailable() }
        baskets = replacement
        guard isCartStorageReady, baskets == replacement else {
            ordersActionMessage = "Your basket could not be saved safely. Nothing was replaced."
            return .init(addedUnits: 0, skippedLines: 0)
        }
        cartService = review.service
        cartErrorMessage = nil
        ordersActionMessage = "Added \(addedUnits) item\(addedUnits == 1 ? "" : "s") to your \(review.service.title) basket. Review prices and availability before ordering."
        hapticFeedback(.success)
        return .init(addedUnits: addedUnits, skippedLines: 0)
    }

    static func validReorderOptions(item: DastakV1RestaurantMenuItem, ids: [UUID]) -> Bool {
        let selected = Set(ids)
        let options = item.optionGroups.filter { $0.status == "ACTIVE" }.flatMap(\.options).filter { $0.status == "ACTIVE" }
        let safePrice = Int.max / DastakCart.maximumQuantity / 1_000
        var price = item.basePricePaise
        guard (0...safePrice).contains(price) else { return false }
        for option in options where selected.contains(option.id) {
            let sum = price.addingReportingOverflow(option.priceDeltaPaise)
            guard !sum.overflow else { return false }
            price = sum.partialValue
        }
        guard (0...safePrice).contains(price) else { return false }
        return item.status == "ACTIVE" && selected.count == ids.count
            && selected.isSubset(of: Set(options.map(\.id))) && item.optionGroups.allSatisfy { group in
                let count = group.options.filter { selected.contains($0.id) }.count
                return group.status == "ACTIVE" && group.minimumSelections >= 0
                    && group.maximumSelections >= group.minimumSelections
                    && count >= group.minimumSelections && count <= group.maximumSelections
                    && (group.selectionType != "SINGLE" || count <= 1)
            }
    }

    func resolveWishlistContents() async {
        _ = await resolveSavedItems(skuIDs: Set(wishlistItems.filter { $0.kind == .retailSKU }.map(\.itemID)),
                                    menuIDs: Set(wishlistItems.filter { $0.kind == .menuItem }.map(\.itemID)))
    }

    /// Existing API has no exact-SKU lookup: scan bounded pages on demand and retain only requested products.
    func resolveSavedItems(skuIDs: Set<UUID>, menuIDs: Set<UUID> = []) async -> Bool {
        guard !isResolvingSavedItems else { return false }
        isResolvingSavedItems = true
        defer { isResolvingSavedItems = false }
        savedItemsRefreshFailure = nil
        let revision = catalogueRevision, account = basketAccountID, areaKey = availabilityRefreshKey
        do {
            var missing = skuIDs.subtracting(knownCatalogueProducts.map(\.id))
            if !missing.isEmpty {
                var cursor = v1Catalogue?.nextCursor
                var expectedVersion = v1Catalogue?.catalogueVersion
                var seen = Set<UUID>()
                var found: [DastakV1CatalogueSKU] = []
                // A complete first page with no cursor proves there are no remaining SKUs.
                if v1Catalogue == nil || cursor != nil {
                    var pages = 0
                    repeat {
                        let page = try await v1Client.catalogue(query: nil, categoryID: nil, subcategoryID: nil,
                                                              limit: 250, cursor: cursor, idempotencyKey: makeKey())
                        try Task.checkCancellation()
                        guard revision == catalogueRevision, account == basketAccountID else { return false }
                        if let expected = expectedVersion, let actual = page.catalogueVersion,
                           expected != actual { throw DastakV1BrowseLoadError.invalidPagination }
                        if expectedVersion == nil { expectedVersion = page.catalogueVersion }
                        found += page.skus.filter { missing.contains($0.id) }
                        missing.subtract(page.skus.map(\.id))
                        cursor = page.nextCursor
                        pages += 1
                        if let cursor, !seen.insert(cursor.skuID).inserted { throw DastakV1BrowseLoadError.invalidPagination }
                        if pages >= 40, cursor != nil, !missing.isEmpty { throw DastakV1BrowseLoadError.invalidPagination }
                    } while !missing.isEmpty && cursor != nil
                    resolvedSavedProducts += found
                }
            }
            if !menuIDs.isEmpty {
                if requiresAreaChecks {
                    await refreshAreaAvailability()
                    guard currentAreaAvailability != nil, areaKey == availabilityRefreshKey else { return false }
                }
                func missingMenuIDs() -> Set<UUID> {
                    menuIDs.subtracting(v1Restaurants.flatMap { $0.categories.flatMap(\.items).map(\.id) })
                }
                if !missingMenuIDs().isEmpty, v1Restaurants.isEmpty { await refreshV1Restaurants() }
                var pages = 0
                while !missingMenuIDs().isEmpty && hasMoreV1Restaurants {
                    guard pages < 100 else { throw DastakV1BrowseLoadError.invalidPagination }
                    guard !isLoadingV1Restaurants else { return false }
                    await refreshV1Restaurants(loadMore: true)
                    pages += 1
                    if let failure = v1RestaurantsRefreshFailure { savedItemsRefreshFailure = failure; return false }
                    guard areaKey == availabilityRefreshKey else { return false }
                    try Task.checkCancellation()
                }
                if let failure = v1RestaurantsRefreshFailure { savedItemsRefreshFailure = failure; return false }
            }
            guard !Task.isCancelled, revision == catalogueRevision, account == basketAccountID,
                  areaKey == availabilityRefreshKey else { return false }
            return true
        } catch {
            guard revision == catalogueRevision, account == basketAccountID, !Task.isCancelled else { return false }
            savedItemsRefreshFailure = refreshFailure(for: error)
            return false
        }
    }

    func decrementCartItem(_ productID: UUID) {
        let previous = baskets[.grocery].itemCount
        defer { basketFeedback(.grocery, previousCount: previous) }
        guard canEditCart(.grocery) else { return }
        baskets[.grocery].decrement(productID)
        cartErrorMessage = nil
    }

    func decrementFoodCartItem(_ entryID: String) {
        let previous = baskets[.food].itemCount
        defer { basketFeedback(.food, previousCount: previous) }
        guard canEditCart(.food) else { return }
        baskets[.food].decrementFood(entryID)
        cartErrorMessage = nil
    }

    func incrementFoodCartItem(_ entryID: String) {
        let previous = baskets[.food].itemCount
        defer { basketFeedback(.food, previousCount: previous) }
        guard canEditCart(.food) else { return }
        if requiresAreaChecks, let entry = baskets[.food].foodEntries.first(where: { $0.id == entryID }),
           currentAreaAvailability?.restaurantOpen(entry.restaurantBranchID) != true {
            cartErrorMessage = "Store closed or availability could not be checked."
            return
        }
        if baskets[.food].incrementFood(entryID) == .quantityLimit {
            cartErrorMessage = "You can add up to \(DastakCart.maximumQuantity) of one item."
        } else {
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
                    hapticFeedback(.warning)
                    ordersActionMessage = "Cancellation confirmed. Your refund is queued and will update here."
                }
            } else if updated.refundDecision?.decisionStatus == .reviewRequired {
                ordersActionMessage = "Your cancellation request is under review. Dastak will show the refund decision here."
            } else {
                ordersActionMessage = "Order cancelled. You were not charged."
            }
            await refreshOrders()
        } catch {
            hapticFeedback(.error)
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
        guard isCartStorageReady, !isDeletingCustomerProfile, !isCheckingOut, !isSubmittingV1Order else { return false }
        let existing = pendingConfirmations[order.id]
        guard existing != nil || (order.status == .awaitingPayment && order.launchPayment?.canCommit == true) else { return false }
        isCheckingOut = true
        defer { isCheckingOut = false }
        let accountID = basketAccountID
        let attempt = existing ?? DastakPendingConfirmation(orderID: order.id, expectedVersion: order.version, key: makeKey())
        guard await confirmationAccountMatches(accountID) else { return false }
        do {
            var prepared = pendingConfirmations
            prepared[order.id] = attempt
            try persistCheckoutState(baskets: baskets, pending: pendingCheckouts, confirmations: prepared)
            pendingConfirmations = prepared
            // Recovery is explicit, never an automatic confirmation on app launch.
            if existing != nil {
                let current = try await v1Client.order(id: attempt.orderID, idempotencyKey: makeKey())
                guard await confirmationAccountMatches(accountID) else { return false }
                guard current.id == attempt.orderID else { throw FunctionClientError.invalidResponse }
                if current.launchPayment?.committedAt != nil || !DastakV1OrderPresentation.isActive(current.status) {
                    return try acknowledgeConfirmation(current)
                }
            }
            _ = try await v1Client.commitLaunchPayment(id: attempt.orderID,
                expectedVersion: attempt.expectedVersion, idempotencyKey: attempt.key)
            // Idempotent responses may be historical; publish only a fresh read.
            let current = try await v1Client.order(id: attempt.orderID, idempotencyKey: makeKey())
            guard await confirmationAccountMatches(accountID) else { return false }
            guard current.id == attempt.orderID else { throw FunctionClientError.invalidResponse }
            guard current.launchPayment?.committedAt != nil || !DastakV1OrderPresentation.isActive(current.status) else {
                throw FunctionClientError.invalidResponse
            }
            return try acknowledgeConfirmation(current)
        } catch {
            if error is DastakCheckoutStorageError { blockCheckoutStorage() }
            // These responses mean the database transaction rejected the command.
            // Release only after a current owned read, never on a timeout/unknown result.
            if case let FunctionClientError.api(status, code, _) = error,
               status == 409, code == "stale_version" || code == "invalid_state" {
                do {
                    let current = try await v1Client.order(id: attempt.orderID, idempotencyKey: makeKey())
                    guard await confirmationAccountMatches(accountID), current.id == attempt.orderID else { return false }
                    if current.launchPayment?.committedAt != nil || !DastakV1OrderPresentation.isActive(current.status) {
                        return try acknowledgeConfirmation(current)
                    }
                    if current.status == .awaitingPayment, current.launchPayment?.canCommit == true {
                        var remaining = pendingConfirmations
                        remaining[current.id] = nil
                        try persistCheckoutState(baskets: baskets, pending: pendingCheckouts, confirmations: remaining)
                        pendingConfirmations = remaining
                        publishConfirmationOrder(current)
                        v1OrderErrorMessage = "The order changed and confirmation was rejected. Review its updated details in Orders before confirming again."
                        return false
                    }
                } catch {
                    if error is DastakCheckoutStorageError { blockCheckoutStorage() }
                }
            }
            v1OrderErrorMessage = message(
                for: error,
                fallback: "Confirmation could not be verified. Recover this confirmation to check the original order. No new payment will be started."
            )
            return false
        }
    }

    func recoverConfirmation(orderID: UUID) async {
        guard let attempt = pendingConfirmations[orderID], isCartStorageReady,
              !isCheckingOut, !isSubmittingV1Order else { return }
        // Obtain a snapshot for the shared recovery path; do not issue a write here.
        let accountID = basketAccountID
        do {
            let current = try await v1Client.order(id: attempt.orderID, idempotencyKey: makeKey())
            guard await confirmationAccountMatches(accountID), current.id == orderID,
                  pendingConfirmations[orderID] == attempt else { return }
            _ = await retryPayment(for: current)
        } catch {
            hapticFeedback(.error)
            v1OrderErrorMessage = message(for: error, fallback: "The original order could not be checked. Try recovery again when connected.")
        }
    }

    private func confirmationAccountMatches(_ accountID: UUID?) async -> Bool {
        guard basketAccountID == accountID, isCartStorageReady else { return false }
        guard let accountIDProvider else { return true }
        return (try? await accountIDProvider()) == accountID
    }

    private func acknowledgeConfirmation(_ current: DastakV1OrderSnapshot) throws -> Bool {
        var remaining = pendingConfirmations
        remaining[current.id] = nil
        try persistCheckoutState(baskets: baskets, pending: pendingCheckouts, confirmations: remaining)
        pendingConfirmations = remaining
        publishConfirmationOrder(current)
        let confirmed = current.launchPayment?.committedAt != nil
        v1OrderErrorMessage = confirmed ? nil : "This reservation is no longer active. No confirmation was made; review its current status in Orders."
        hapticFeedback(confirmed ? .success : .warning)
        return confirmed
    }

    private func publishConfirmationOrder(_ current: DastakV1OrderSnapshot) {
        v1Orders = mergeV1Orders([current])
        let latest = v1Orders.first { $0.id == current.id } ?? current
        if activeV1Order?.id != latest.id || (activeV1Order?.version ?? 0) <= latest.version {
            activeV1Order = latest
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
                    hapticFeedback(.warning)
                    ordersActionMessage = "Delivery cancelled. Your refund is queued and will update here."
                }
            } else {
                ordersActionMessage = "Delivery cancelled. You were not charged."
            }
            await refreshParcels()
        } catch {
            hapticFeedback(.error)
            ordersActionMessage = message(for: error, fallback: "This parcel delivery could not be cancelled.")
        }
    }

    func clearCart() {
        let service = cartService, previous = cart.itemCount
        defer { basketFeedback(service, previousCount: previous) }
        guard canEditCurrentCart else { return }
        baskets[cartService].removeAll()
        quote = nil
        orderPlacementAttempt.reset()
        cartErrorMessage = nil
        v1OrderErrorMessage = nil
    }

    func resetParcelQuote() {
        parcelQuote = nil
        parcelPlacementAttempt.reset()
    }

    private func basketFeedback(_ service: DastakBasketService, previousCount: Int) {
        let count = baskets[service].itemCount
        if count > previousCount { hapticFeedback(.itemAdded) }
        else if count < previousCount { hapticFeedback(.itemRemoved) }
        else if cartErrorMessage != nil { hapticFeedback(.warning) }
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
        await restoreCartStorage()
        if let basketAccountID { preferenceScope = basketAccountID.uuidString.lowercased() }
        selectedLocation = Self.savedDiscoveryLocation(scope: preferenceScope)
        discoveryRadiusKilometres = Self.savedDiscoveryRadius(scope: preferenceScope)
        hasCompletedOnboarding = UserDefaults.standard.bool(
            forKey: preferenceKey("onboardingCompleted")
        )

        do {
            let response = try await addressClient.snapshot(idempotencyKey: makeKey())
            applyAddressSnapshot(response, selectedID: deliveryAddress?.addressID)
            if let saved = defaultDeliveryAddress {
                if selectedLocation == nil {
                    selectedLocation = Self.discoveryLocation(from: saved)
                }
                persistDiscoveryPreferences()
            }
            addressErrorMessage = nil
        } catch {
            addressErrorMessage = message(
                for: error,
                fallback: "Saved addresses are unavailable. Try again before ordering."
            )
        }
    }

    func restoreCartStorage(force: Bool = false) async {
        guard !isSubmittingV1Order, !isCheckingOut, !isDeletingCustomerProfile,
              acknowledgedCustomerDeletionID == nil else { return }
        guard let accountIDProvider else { return } // Preview stays memory-only.
        guard let accountID = try? await accountIDProvider() else {
            resetWishlistPresentation()
            basketAccountID = nil
            resetBasketExperience()
            isRestoringCheckoutState = true
            baskets = DastakCustomerBaskets()
            pendingCheckouts = [:]
            pendingConfirmations = [:]
            isRestoringCheckoutState = false
            isCartStorageReady = false
            cartErrorMessage = "Sign in again to load your saved baskets."
            return
        }
        guard force || basketAccountID != accountID else {
            return
        }
        reorderContextRevision = UUID()
        do {
            if try checkoutJournalStorage.hasAcknowledgedCustomerDeletion(accountID: accountID) {
                acknowledgedCustomerDeletionID = accountID
                isCartStorageReady = false
                try finishCustomerDeletionCleanup(accountID: accountID)
                checkoutRecoveryIssue = "Your Customer profile was deleted. Sign out before continuing."
                return
            }
        } catch {
            blockCheckoutStorage()
            return
        }
        if basketAccountID != accountID {
            resetWishlistPresentation()
            resetBasketExperience()
        }
        basketAccountID = nil // Never save the previous account's contents into this account.
        areaRequestID = UUID()
        areaLoadingKey = nil
        restaurantRequestID = UUID()
        restaurantContextKey = nil
        restaurantCursor = nil
        seenRestaurantCursors = []
        resolvedSavedProducts = []
        isLoadingV1Restaurants = false
        hasMoreV1Restaurants = false
        v1RestaurantsRefreshFailure = nil
        areaAvailability = nil
        checkoutEstimate = nil
        v1Restaurants = []
        checkoutJournalRevision = nil
        isRestoringCheckoutState = true
        defer { isRestoringCheckoutState = false }
        do {
            let saved = try checkoutJournalStorage.load(accountID: accountID)
            baskets = saved?.baskets ?? basketStore.load(accountID: accountID)
            pendingCheckouts = Dictionary(uniqueKeysWithValues: (saved?.pending ?? []).map { ($0.service, $0) })
            pendingConfirmations = Dictionary(uniqueKeysWithValues: (saved?.confirmations ?? []).map { ($0.orderID, $0) })
            checkoutJournalRevision = saved?.revision
            basketAccountID = accountID
            // Migrate the previous basket-only cache into the canonical journal.
            if saved == nil { try persistCheckoutState(baskets: baskets, pending: pendingCheckouts) }
            // Drop the old copy only after the canonical journal has loaded/migrated safely.
            basketStore.remove(accountID: accountID)
            cartService = pendingCheckouts[.grocery] != nil ? .grocery : pendingCheckouts[.food] != nil ? .food : .grocery
            isCartStorageReady = true
            checkoutRecoveryIssue = nil
            cartErrorMessage = nil
        } catch {
            baskets = DastakCustomerBaskets()
            pendingCheckouts = [:]
            pendingConfirmations = [:]
            blockCheckoutStorage()
        }
    }

    private func canEditCart(_ service: DastakBasketService) -> Bool {
        isCartStorageReady && !isDeletingCustomerProfile && submittingCartService != service && pendingCheckouts[service] == nil
    }

    private var areaContext: DastakV1AreaContext? {
        guard isCartStorageReady, let addressID = deliveryAddress?.addressID,
              let version = deliveryAddress?.addressVersion,
              DastakV1AreaContext.date(version) != nil else { return nil }
        return .init(addressID: addressID, addressVersion: version)
    }

    var availabilityRefreshKey: String {
        "\(basketAccountID?.uuidString ?? "preview")|\(areaContext?.addressId.uuidString ?? "none")|\(areaContext?.addressVersion ?? "none")"
    }

    var checkoutRefreshKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = (try? encoder.encode(cart.orderLines)).flatMap { String(data: $0, encoding: .utf8) } ?? "invalid"
        return "\(availabilityRefreshKey)|\(cartService.rawValue)|\(cart.restaurantBranchID?.uuidString ?? "none")|\(lines)"
    }

    var currentAreaAvailability: DastakV1AreaAvailability? {
        guard let context = areaContext, let area = areaAvailability,
              context.matches(.init(addressID: area.addressId, addressVersion: area.addressVersion)),
              let checked = DastakV1AreaContext.date(area.checkedAt),
              Date().timeIntervalSince(areaReceivedAt) < 45,
              Date().timeIntervalSince(checked) < 45, checked.timeIntervalSinceNow < 5 else { return nil }
        return area
    }

    var currentCheckoutEstimate: DastakV1CheckoutQuote? {
        guard pendingCheckout == nil, quotedBasketKey == checkoutRefreshKey, let estimate = checkoutEstimate,
              let until = DastakV1AreaContext.date(estimate.validUntil), until > Date(),
              let checked = DastakV1AreaContext.date(estimate.checkedAt), checked.timeIntervalSinceNow < 5,
              Date().timeIntervalSince(quoteReceivedAt) < 45 else { return nil }
        return estimate
    }

    // Browsing depends on nearby stores, not on delivery-partner availability.
    var browsingAreaMessage: String? {
        guard requiresAreaChecks else { return nil }
        guard areaContext != nil else { return "Choose your delivery location to check availability." }
        guard let area = currentAreaAvailability else { return availabilityError ?? "Checking availability in your area. Your cart is saved." }
        if cartService == .grocery && !area.groceryServiceable { return "This area is not serviceable yet." }
        if cartService == .food && !area.foodServiceable { return "Food delivery isn’t available in your area yet." }
        return nil
    }

    var areaMessage: String? {
        if let message = browsingAreaMessage { return message }
        if requiresAreaChecks, currentAreaAvailability?.deliveryAvailable == false {
            return "No delivery partners are available in your area right now. Your cart is saved."
        }
        return nil
    }

    // Stock labels describe merchant inventory, not how many more a customer
    // can add. A full basket allowance must not mislabel a pack as sold out.
    func groceryStockQuantity(_ id: UUID) -> Int? {
#if DEBUG
        if !requiresAreaChecks, ProcessInfo.processInfo.arguments.contains("-DastakUIPreviewPackStock") {
            return ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]
                .contains(id.uuidString.lowercased()) ? 0 : 5
        }
#endif
        guard requiresAreaChecks, let area = currentAreaAvailability, area.groceryServiceable else { return nil }
        return area.quantity(for: id)
    }

    func groceryAddIssue(_ id: UUID) -> String? {
        guard requiresAreaChecks else { return nil }
        guard areaContext != nil else { return "Choose your delivery location to check stock." }
        guard let area = currentAreaAvailability else { return availabilityError ?? "Checking stock in your area…" }
        guard area.groceryServiceable else { return "This area is not serviceable yet." }
        let quantity = baskets[.grocery].entries.first { $0.id == id }?.quantity ?? 0
        guard quantity < min(99, area.quantity(for: id)) else { return quantity == 0 ? "Out of stock" : "No more stock is available in your area." }
        return nil
    }

    func restaurantIssue(_ menu: DastakV1RestaurantMenu) -> String? {
        if requiresAreaChecks {
            guard let area = currentAreaAvailability else { return areaMessage ?? "Checking restaurants in your area…" }
            guard area.foodServiceable, let open = area.restaurantOpen(menu.id) else { return "Food delivery isn’t available in your area yet." }
            guard open else { return "Store closed" }
        }
        guard menu.restaurant.acceptingOrders, menu.restaurant.isOpen,
              menu.restaurant.branchStatus == "ACTIVE" else { return "Store closed" }
        return nil
    }

    var checkoutAvailabilityIssue: String? {
        guard requiresAreaChecks else { return nil }
        if let message = areaMessage { return message }
        guard let area = currentAreaAvailability else { return "Check availability before placing an order." }
        if cartService == .grocery && cart.entries.contains(where: { $0.quantity > area.quantity(for: $0.id) }) {
            return "Some packs are out of stock in your area. Review your saved cart before ordering."
        }
        if cartService == .food, let id = cart.restaurantBranchID, area.restaurantOpen(id) != true { return "Store closed" }
        guard let estimate = currentCheckoutEstimate else { return checkoutEstimateError ?? "Check the latest delivery and platform fees before placing your order." }
        return estimate.deliveryAvailable ? nil : "No delivery partners are available in your area right now. Your cart is saved."
    }

    func refreshAreaAvailability(force: Bool = false) async {
        guard requiresAreaChecks else { return }
        guard let context = areaContext else { areaAvailability = nil; v1Restaurants = []; return }
        if !force && currentAreaAvailability != nil { return }
        let request = UUID(), key = availabilityRefreshKey
        guard areaLoadingKey != key else { return }
        areaLoadingKey = key
        areaRequestID = request
        defer { if request == areaRequestID { areaLoadingKey = nil } }
        do {
            let value = try await v1Client.areaAvailability(context: context, idempotencyKey: makeKey())
            guard !Task.isCancelled, request == areaRequestID, key == availabilityRefreshKey else { return }
            areaAvailability = value
            areaReceivedAt = Date()
            availabilityError = nil
            // Food menu transport must not invalidate Grocery stock or rider checks.
            v1Restaurants.removeAll { value.restaurants[$0.id.uuidString.lowercased()] == nil }
            if !value.foodServiceable {
                v1Restaurants = []
                restaurantRequestID = UUID()
                restaurantCursor = nil
                hasMoreV1Restaurants = false
                isLoadingV1Restaurants = false
                restaurantContextKey = key
                v1RestaurantsRefreshFailure = nil
            } else if restaurantContextKey != key {
                await refreshV1Restaurants()
            }
        } catch {
            guard !Task.isCancelled, request == areaRequestID, key == availabilityRefreshKey else { return }
            areaAvailability = nil
            restaurantRequestID = UUID()
            restaurantContextKey = nil
            restaurantCursor = nil
            hasMoreV1Restaurants = false
            isLoadingV1Restaurants = false
            v1Restaurants = []
            availabilityError = "Availability could not be checked. Reconnect and try again; your cart is saved."
        }
    }

    func refreshV1Restaurants(loadMore: Bool = false) async {
        let key = availabilityRefreshKey
        let context = areaContext
        if requiresAreaChecks {
            guard context != nil, currentAreaAvailability?.foodServiceable == true else { return }
        }
        guard !isLoadingV1Restaurants || restaurantContextKey != key else { return }
        guard !loadMore || (hasMoreV1Restaurants && restaurantContextKey == key) else { return }
        let request = UUID()
        restaurantRequestID = request
        restaurantContextKey = key
        isLoadingV1Restaurants = true
        defer { if request == restaurantRequestID { isLoadingV1Restaurants = false } }
        let cursor = loadMore ? restaurantCursor : nil
        do {
            let menus: [DastakV1RestaurantMenu]
            let next: DastakV1RestaurantAreaCursor?
            if let context, requiresAreaChecks {
                let page = try await v1Client.restaurantAreaPage(context: context, cursor: cursor, idempotencyKey: makeKey())
                menus = page.restaurants
                next = page.nextCursor
            } else {
                menus = try await v1Client.restaurants(query: nil, limit: 50, idempotencyKey: makeKey())
                next = nil
            }
            guard !Task.isCancelled, request == restaurantRequestID, key == availabilityRefreshKey else { return }
            var seen = loadMore ? seenRestaurantCursors : []
            if let next, !seen.insert(next.branchId).inserted { throw FunctionClientError.invalidResponse }
            var ids = Set<UUID>()
            let merged = (loadMore ? v1Restaurants : []) + menus
            guard merged.count <= 10_000 else { throw FunctionClientError.invalidResponse }
            v1Restaurants = merged.filter { ids.insert($0.id).inserted }
            restaurantCursor = next
            seenRestaurantCursors = seen
            hasMoreV1Restaurants = next != nil
            v1RestaurantsRefreshFailure = nil
        } catch {
            guard !Task.isCancelled, request == restaurantRequestID, key == availabilityRefreshKey else { return }
            failedRestaurantLoadMore = loadMore
            v1RestaurantsRefreshFailure = refreshFailure(for: error)
        }
    }

    func retryV1Restaurants() async {
        await refreshV1Restaurants(loadMore: failedRestaurantLoadMore)
    }

    func refreshFood() async {
        let previousRequest = restaurantRequestID
        if requiresAreaChecks { await refreshAreaAvailability(force: true) }
        // A new location's availability refresh already fetches the first Food page.
        if previousRequest == restaurantRequestID { await refreshV1Restaurants() }
    }

    var knownCatalogueProducts: [DastakV1CatalogueSKU] {
        var seen = Set<UUID>()
        return ((currentAreaAvailability?.trendingSkus ?? []) + (v1Catalogue?.skus ?? []) + v1CategoryProducts.values.flatMap { $0 } + resolvedSavedProducts + v1SearchResults)
            .filter { seen.insert($0.id).inserted }
    }

    var localTrendingProducts: [DastakV1CatalogueSKU]? {
        #if DEBUG
        if !requiresAreaChecks, ProcessInfo.processInfo.arguments.contains("-DastakUIPreviewTrending") {
            return v1BrowseProducts.filter { $0.categoryID == v1BrowseProducts.first?.categoryID }
        }
        #endif
        guard let area = currentAreaAvailability, area.groceryServiceable else { return nil }
        return area.trendingSkus
    }

    private func subcategories(forBrowseNode key: String) -> [UUID: UUID] {
        guard let map = v1BrowseMap, let catalogue = v1Catalogue,
              let types = catalogue.categoryTypes else { return [:] }
        let taxonomy = DastakV1CatalogueBrowseMap.Taxonomy(
            typeSlugs: Dictionary(types.map { ($0.id, $0.slug) }, uniquingKeysWith: { first, _ in first }),
            categories: catalogue.categories.compactMap { category in
                category.categoryTypeID.map { .init(id: category.id, typeID: $0, slug: category.slug) }
            },
            subcategories: catalogue.subcategories.map { .init(id: $0.id, categoryID: $0.categoryID, slug: $0.slug) }
        )
        return map.matchingSubcategories(nodeKey: key, taxonomy: taxonomy)
    }

    func categories(forBrowseNode key: String) -> [UUID] {
        let categoryIDs = Set(subcategories(forBrowseNode: key).values)
        return canonicalCategories.filter { categoryIDs.contains($0.id) }.map(\.id)
    }

    func products(forBrowseNode key: String) -> [DastakV1CatalogueSKU] {
        let subcategories = subcategories(forBrowseNode: key)
        return v1BrowseProducts.filter { subcategories[$0.subcategoryID] == $0.categoryID }
    }

    func loadV1BrowseNode(_ key: String, force: Bool = false) async {
        for id in categories(forBrowseNode: key) {
            guard !Task.isCancelled else { return }
            await loadV1Category(id, force: force)
        }
    }

    func refreshCheckoutEstimate() async {
        guard requiresAreaChecks, pendingCheckout == nil, !cart.isEmpty else { return }
        let request = UUID(), key = checkoutRefreshKey
        quoteRequestID = request
        isLoadingCheckoutEstimate = true
        defer { if quoteRequestID == request { isLoadingCheckoutEstimate = false } }
        checkoutEstimate = nil
        checkoutEstimateError = nil
        await refreshAreaAvailability()
        guard !Task.isCancelled, key == checkoutRefreshKey, request == quoteRequestID,
              let context = areaContext, currentAreaAvailability != nil else { return }
        do {
            let value = try await v1Client.checkoutQuote(context: context, lines: cart.orderLines,
                branchID: cart.restaurantBranchID, idempotencyKey: makeKey())
            guard !Task.isCancelled, key == checkoutRefreshKey, request == quoteRequestID else { return }
            checkoutEstimate = value
            quotedBasketKey = key
            quoteReceivedAt = Date()
        } catch {
            guard !Task.isCancelled, key == checkoutRefreshKey, request == quoteRequestID else { return }
            checkoutEstimateError = "Checkout fees could not be checked. Try again before placing your order."
        }
    }

    private func persistCheckoutState(baskets: DastakCustomerBaskets,
                                      pending: [DastakBasketService: DastakPendingCheckout],
                                      confirmations: [UUID: DastakPendingConfirmation]? = nil) throws {
        guard let basketAccountID else { return } // No disk writes for preview fixtures.
        guard acknowledgedCustomerDeletionID == nil else { throw DastakCheckoutStorageError.customerDeleted }
        let record = DastakCheckoutJournal(accountID: basketAccountID, baskets: baskets,
            pending: pending.values.sorted { $0.service.rawValue < $1.service.rawValue },
            confirmations: (confirmations ?? pendingConfirmations).values.sorted { $0.orderID.uuidString < $1.orderID.uuidString })
        do { try checkoutJournalStorage.save(record, replacing: checkoutJournalRevision) }
        catch { throw DastakCheckoutStorageError.unavailable }
        checkoutJournalRevision = record.revision
    }

    private func blockCheckoutStorage() {
        isCartStorageReady = false
        checkoutRecoveryIssue = "Saved checkout could not be safely read or updated. Retry loading it before placing an order. Your recovery record has not been discarded."
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
            addressVersion: address.updatedAt,
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
    static func preview(panelFixtures: Bool = false, shoppingFixtures: Bool = false) -> DastakCustomerModel {
        let functions: any FunctionClient = shoppingFixtures ? DastakShoppingPreviewClient() : DastakPreviewFunctionClient()
        let model = DastakCustomerModel(functions: functions)
        model.hasLoadedWishlist = true // Preview's known empty list is synthetic, never a live acceptance claim.
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
        model.defaultDeliveryAddress = model.deliveryAddress
        model.isDeliveryAddressConfirmed = true
        model.v1Catalogue = try? JSONDecoder().decode(
            DastakV1CatalogueSnapshot.self,
            from: Data(Self.previewCatalogueJSON.utf8)
        )
        if panelFixtures {
            // Debug-only synthetic data for pack-picker and open/closed Food UI checks.
            if var catalogue = try? JSONSerialization.jsonObject(with: Data(Self.previewCatalogueJSON.utf8)) as? [String: Any],
               var skus = catalogue["skus"] as? [[String: Any]], !skus.isEmpty {
                skus[0]["brand"] = ["id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "name": "Preview Dairy", "slug": "preview-dairy"]
                var smaller = skus[0]
                smaller["id"] = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
                smaller["packSize"] = "500 ml"
                smaller["sellingPricePaise"] = 3500
                smaller["listPricePaise"] = 3600
                skus.append(smaller)
                if ProcessInfo.processInfo.arguments.contains("-DastakUIPreviewLongTitles"), skus.count > 1 {
                    skus[1]["name"] = "Sample Schezwan Chutney | Fiery Flavour Fusion | Easy to Cook, Dip and Spread | Rich flavours | 100% Veg"
                    skus[1]["brand"] = ["id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd", "name": "Sample Pantry", "slug": "sample-pantry"]
                }
                catalogue["skus"] = skus
                let typeID = "aaaaaaaa-0000-4000-8000-000000000001"
                catalogue["categoryTypes"] = [["id": typeID, "name": "Grocery", "slug": "grocery", "sortOrder": 0]]
                if let categories = catalogue["categories"] as? [[String: Any]] {
                    catalogue["categories"] = categories.map { category in
                        var category = category
                        category["categoryTypeId"] = typeID
                        return category
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: catalogue) {
                    model.v1Catalogue = try? JSONDecoder().decode(DastakV1CatalogueSnapshot.self, from: data)
                }
                model.v1BrowseMap = try? JSONDecoder().decode(DastakV1CatalogueBrowseMap.self,
                    from: Data(Self.previewBrowseMapJSON.utf8))
                model.v1BrowseProducts = model.v1Catalogue?.skus ?? []
                model.v1CategoryProducts = Dictionary(grouping: model.v1BrowseProducts, by: \.categoryID)
                model.checkoutCustomer = MarketplaceCheckoutCustomer(displayName: "Preview shopper", email: nil,
                    phoneNumber: "")
            }
            model.v1Restaurants = (try? JSONDecoder().decode([DastakV1RestaurantMenu].self, from: Self.previewRestaurantsData)) ?? []
        }
        return model
    }

    nonisolated static var previewRestaurantsData: Data {
            var restaurantData = Data(previewRestaurantsJSON.utf8)
            // Opt-in, local-only long menu for checking category jumps without
            // signing in or editing a real merchant's menu.
            if ProcessInfo.processInfo.arguments.contains("-DastakUIPreviewMenuNavigation"),
               var menus = try? JSONSerialization.jsonObject(with: restaurantData) as? [[String: Any]],
               var menu = menus.first,
               let category = (menu["categories"] as? [[String: Any]])?.first,
               let item = (category["items"] as? [[String: Any]])?.first {
                menu["categories"] = ["Hot drinks", "Cold drinks", "Desserts"].enumerated().map { section, name in
                    var sampleCategory = category
                    sampleCategory["id"] = String(format: "00000000-0000-4000-8000-%012d", 800 + section)
                    sampleCategory["name"] = name
                    sampleCategory["sortOrder"] = section
                    sampleCategory["items"] = (0..<4).map { index in
                        var sampleItem = item
                        sampleItem["id"] = String(format: "00000000-0000-4000-8000-%012d", 900 + section * 10 + index)
                        sampleItem["name"] = "Sample \(name.lowercased()) \(index + 1)"
                        sampleItem["sortOrder"] = index
                        return sampleItem
                    }
                    return sampleCategory
                }
                menus[0] = menu
                restaurantData = (try? JSONSerialization.data(withJSONObject: menus)) ?? restaurantData
            }
            return restaurantData
    }

    nonisolated static let previewRestaurantsJSON = """
    [
      {"restaurant":{"organizationId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","branchId":"dddddddd-dddd-4ddd-8ddd-dddddddddddd",
        "name":"Preview Kitchen","branchName":"Sample branch","acceptingOrders":true,"isOpen":true,"branchStatus":"ACTIVE",
        "merchantType":"RESTAURANT","softActiveOrderThreshold":10,"activeOrderCount":0},
       "categories":[{"id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","name":"Lunch","sortOrder":1,"status":"ACTIVE","version":1,
        "items":[{"id":"ffffffff-ffff-4fff-8fff-ffffffffffff","name":"Sample rice bowl","basePricePaise":12000,"currencyCode":"INR",
        "taxRateBps":0,"status":"ACTIVE","sortOrder":1,"version":1,"logisticsAttributes":{},"optionGroups":[]}]}]},
      {"restaurant":{"organizationId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","branchId":"abababab-abab-4bab-8bab-abababababab",
        "name":"Preview Café","branchName":"Sample closed branch","acceptingOrders":false,"isOpen":false,"branchStatus":"ACTIVE",
        "merchantType":"CAFE","softActiveOrderThreshold":10,"activeOrderCount":0},"categories":[]}
    ]
    """

    nonisolated static let previewBrowseMapJSON = """
    {"version":1,"nodes":[
      {"key":"fresh","kind":"SECTION","label":"Fresh Items","sortOrder":1,"sources":[]},
      {"key":"essentials","parentKey":"fresh","kind":"DESTINATION","label":"Everyday essentials","sortOrder":1,
       "sources":[{"typeSlug":"grocery","categorySlug":"essentials","excludedCategorySlugs":[],"excludedSubcategorySlugs":[]}]},
      {"key":"dairy-breakfast","parentKey":"essentials","kind":"RAIL","label":"Dairy & breakfast","sortOrder":1,
       "sources":[{"typeSlug":"grocery","categorySlug":"essentials","subcategorySlug":"dairy-breakfast","excludedCategorySlugs":[],"excludedSubcategorySlugs":[]}]}
    ]}
    """

    nonisolated static let previewCatalogueJSON = """
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
