import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakMerchantOrderAction: String, Codable, Sendable {
    case accept
    case ready
    case reject
    case confirmReturn
    case refund
}

struct DastakMerchantProductDraft: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { productID ?? draftID }
    private var draftID = UUID()
    var productID: UUID?
    var categoryID: UUID
    var name: String
    var description: String
    var unitLabel: String
    var priceRupees: String
    var imageObjectPath: String?
    var availability: CatalogueAvailability
    var catalogueKind: CatalogueKind
    var isActive: Bool

    init(categoryID: UUID) {
        self.categoryID = categoryID
        name = ""
        description = ""
        unitLabel = ""
        priceRupees = ""
        availability = .inStock
        catalogueKind = .general
        isActive = true
    }

    init(product: CatalogueProduct) {
        productID = product.productID
        categoryID = product.categoryID
        name = product.name
        description = product.description ?? ""
        unitLabel = product.unitLabel
        priceRupees = NSDecimalNumber(decimal: product.price.rupees).stringValue
        imageObjectPath = product.imageObjectPath
        availability = product.availability
        catalogueKind = product.catalogueKind
        isActive = product.isActive
    }
}

@MainActor
final class DastakMerchantModel: ObservableObject {
    @Published private(set) var orders: [MerchantOrderSnapshot] = []
    @Published private(set) var v1Fulfilments: [DastakV1MerchantFulfilment] = []
    @Published private(set) var recoveryOpportunities: [DastakV1RecoveryOpportunity] = []
    @Published private(set) var fulfilmentsCurrent = false
    @Published private(set) var recoveryCurrent = false
    @Published private(set) var returnReceipts: [DastakV1MerchantReturnReceipt] = []
    @Published private(set) var settlements: [DastakV1MerchantSettlement] = []
    @Published private(set) var returnsCurrent = false
    @Published private(set) var settlementsCurrent = false
    @Published private(set) var returnsRefreshedAt: Date?
    @Published private(set) var pendingRecoveryCommand: DastakMerchantRecoveryCommand?
    @Published private(set) var pendingOperationCommand: DastakMerchantOperationCommand?
    @Published private(set) var sessionNeedsAttention = false
    @Published private(set) var catalogueRefreshFailure: String?
    @Published private(set) var catalogueBrowseFailure: String?
    @Published private(set) var isRefreshingCatalogue = false
    @Published private(set) var isRefreshingCatalogueMap = false
    @Published private(set) var canonicalCatalogueCurrent = false
    @Published private(set) var catalogueCheckedAt: Date?
    @Published private(set) var earningsRefreshFailure: String?
    @Published private(set) var recoveryCommandMessage: String?
    @Published private(set) var opportunities: [DastakV1MerchantOpportunity] = []
    @Published private(set) var incomingCurrent = false
    @Published private(set) var foodRequestsCurrent = false
    @Published private(set) var legacyOrdersCurrent = false
    @Published private(set) var restaurantRequests: [DastakV1RestaurantRequest] = []
    @Published private(set) var orderRefreshFailures: [String] = []
    @Published private(set) var lastOrderRefresh: Date?
    let notifications: DastakMerchantNotifications
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var canonicalCatalogue: DastakV1MerchantCatalogueSnapshot?
    @Published private(set) var canonicalBrowseMap: DastakV1CatalogueBrowseMap?
    let menuDrafts: DastakMerchantMenuDraftStore
    @Published private(set) var restaurantMenu: DastakV1RestaurantMenu? {
        didSet { menuDrafts.reconcile(restaurantMenu) }
    }
    @Published private(set) var restaurantRefreshFailure: String?
    @Published private(set) var needsRestaurantRefresh = true
    @Published private(set) var isRefreshingRestaurant = false
    @Published private(set) var pendingRestaurantCommand: DastakMerchantRestaurantCommand?
    @Published private(set) var pendingCanonicalSelections: [UUID: Bool] = [:]
    @Published private(set) var earnings: DastakEarningsSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyIdentity: String?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var merchantJournal: DastakMerchantJournalRecord?
    @Published private(set) var merchantJournalRestored = false
    @Published private(set) var isRestoringMerchantJournal = false
    @Published private(set) var merchantJournalMessage: String?
    @Published private(set) var merchantLocations: [DastakMerchantLocation] = []
    @Published private(set) var selectedLocationID: UUID?
    @Published private(set) var locationsInitialized = false
    @Published private(set) var isRefreshingLocations = false
    @Published private(set) var locationMessage: String?
    @Published private(set) var locationDirectoryCursor: UUID?
    @Published private(set) var locationDirectoryComplete = false
    @Published private(set) var locationDirectoryMessage: String?
    private let discoveryClient: (any DastakMerchantDiscoveryClient)?
    private let locationPreferences: DastakMerchantLocationPreferences
    private var locationGeneration = UUID()
    private var locationAccountID: UUID?
    private let journalStorage: any DastakMerchantJournalStorage
    private var journalAccountID: UUID?

    private let services: MarketplaceAuthenticatedServices
    private let orderClient: any MerchantOrderClient
    private let catalogueClient: any CatalogueClient
    private let checkoutClient: any DastakCheckoutClient
    private let earningsClient: any DastakEarningsClient
    private let v1Client: any DastakV1MerchantClient
    private let inboxClient: any DastakV1MerchantInboxClient
    private var ordersRefreshInFlight = false
    private var ordersRefreshQueued = false
    private let requestTimeout: Duration
    private var mutationEpoch = UUID()
    private var catalogueReadGeneration = UUID()
    private var catalogueAccountID: UUID?
    private var earningsReadGeneration = UUID()
    private var automaticRecoveryCount = 0
    private var lastAutomaticRecovery: Date?
    private var restaurantRefreshGeneration = UUID()
    private var isExecutingRestaurantCommand = false
    private var operationReadGeneration = UUID()
    private let recoveryClient: SupabaseDastakV1MerchantRecoveryClient

    init(
        services: MarketplaceAuthenticatedServices,
        orderClient: any MerchantOrderClient,
        catalogueClient: any CatalogueClient,
        checkoutClient: any DastakCheckoutClient,
        earningsClient: any DastakEarningsClient,
        v1Client: any DastakV1MerchantClient,
        inboxClient: (any DastakV1MerchantInboxClient)? = nil,
        journalStorage: any DastakMerchantJournalStorage = DastakMerchantFileJournal.shared,
        requestTimeout: Duration = .seconds(12),
        locationPreferences: DastakMerchantLocationPreferences = .init(),
        discoveryClient: (any DastakMerchantDiscoveryClient)? = nil,
        menuDraftStorage: (any DastakMerchantMenuDraftStorage)? = nil
    ) {
        self.services = services
        self.menuDrafts = .init(storage: menuDraftStorage)
        self.journalStorage = journalStorage
        self.requestTimeout = requestTimeout
        self.locationPreferences = locationPreferences
        self.discoveryClient = discoveryClient
        let functions = DastakMerchantFunctionClient(base: services.functions, timeout: requestTimeout)
        self.recoveryClient = SupabaseDastakV1MerchantRecoveryClient(functions: functions)
        self.notifications = DastakMerchantNotifications(functions: functions, requestTimeout: requestTimeout,
            accountIDProvider: { try await services.accountID() })
        self.orderClient = orderClient
        self.catalogueClient = catalogueClient
        self.checkoutClient = checkoutClient
        self.earningsClient = earningsClient
        self.v1Client = v1Client
        self.inboxClient = inboxClient ?? SupabaseDastakV1MerchantInboxClient(functions: functions)
    }

    convenience init(services: MarketplaceAuthenticatedServices, journalStorage: any DastakMerchantJournalStorage = DastakMerchantFileJournal.shared,
                     requestTimeout: Duration = .seconds(12), locationPreferences: DastakMerchantLocationPreferences = .init(),
                     menuDraftStorage: (any DastakMerchantMenuDraftStorage)? = nil) {
        let functions = DastakMerchantFunctionClient(base: services.functions, timeout: requestTimeout)
        self.init(
            services: services,
            orderClient: SupabaseMerchantOrderClient(functions: functions),
            catalogueClient: SupabaseCatalogueClient(functions: functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: functions),
            earningsClient: SupabaseDastakEarningsClient(functions: functions),
            v1Client: SupabaseDastakV1MerchantClient(functions: functions),
            journalStorage: journalStorage, requestTimeout: requestTimeout, locationPreferences: locationPreferences,
            discoveryClient: SupabaseDastakMerchantDiscoveryClient(functions: functions), menuDraftStorage: menuDraftStorage
        )
    }

    var activeOrders: [MerchantOrderSnapshot] {
        orders.filter { !$0.isFinal }
    }

    var recentOrders: [MerchantOrderSnapshot] {
        Array(orders.filter(\.isFinal).prefix(10))
    }

    var selectedLocation: DastakMerchantLocation? { merchantLocations.first { $0.id == selectedLocationID } }
    func makeHistory(_ branch: UUID) -> DastakMerchantHistoryModel {
        .init(branch: branch, services: services, timeout: requestTimeout)
    }
    var inventoryReadRevision: UUID { mutationEpoch }
    func makeInventorySearch() -> DastakMerchantInventoryModel {
        .init(services: services,client: SupabaseDastakMerchantDiscoveryClient(functions: DastakMerchantFunctionClient(base: services.functions,timeout: requestTimeout)),timeout: requestTimeout)
    }
    func mergeVerifiedInventory(_ rows: [DastakV1MerchantCatalogueSnapshot.SKU], branch: UUID, revision: UUID) async -> Bool {
        guard revision == mutationEpoch, !isBusy, retailLocationCurrent,
              let snapshot = canonicalCatalogue, snapshot.branch.branchID == branch else { return false }
        do {
            guard catalogueAccountID == (try await currentAccountID()), revision == mutationEpoch, !isBusy else { return false }
            guard let latest = canonicalCatalogue, latest.branch.branchID == branch, retailLocationCurrent else { return false }
            canonicalCatalogue = latest.mergingInventory(rows)
            return true
        } catch { recordConnectionFailure(error); return false }
    }

    func makeOrderDetail(_ target: DastakMerchantDetailTarget) -> DastakMerchantOrderDetailModel {
        .init(target: target, services: services)
    }
    var scopedOpportunities: [DastakV1MerchantOpportunity] { opportunities.filter { $0.branch.id == selectedLocationID } }
    var scopedRestaurantRequests: [DastakV1RestaurantRequest] { restaurantRequests.filter { $0.branch.id == selectedLocationID } }
    var scopedFulfilments: [DastakV1MerchantFulfilment] { v1Fulfilments.filter { $0.branch.id == selectedLocationID } }
    var scopedRecoveryOpportunities: [DastakV1RecoveryOpportunity] { recoveryOpportunities.filter { $0.branch.id == selectedLocationID } }
    var scopedReturnReceipts: [DastakV1MerchantReturnReceipt] { returnReceipts.filter { $0.branch.id == selectedLocationID } }
    var locationSwitchDisabled: Bool { isBusy || isRefreshingLocations || hasPendingCanonicalSelections }
    private var journalLocationID: UUID? {
        pendingRestaurantCommand?.branchID ?? pendingRecoveryCommand?.branchID ?? pendingOperationCommand?.branchID
    }

    /// Filtering is navigation, not authorization. Server actor checks remain
    /// authoritative for every read and mutation.
    private func permitsLocation(_ id: UUID) -> Bool { !locationsInitialized || selectedLocationID == id }
    private var retailLocationCurrent: Bool {
        canonicalCatalogueCurrent && (!locationsInitialized || (selectedLocation?.kind == .retail && canonicalCatalogue?.branch.branchID == selectedLocationID))
    }
    var canonicalChangesDisabled: Bool { isBusy || isRefreshingCatalogue || !retailLocationCurrent || catalogueRefreshFailure != nil }

    func refreshLocations(loadMore: Bool = false) async {
        guard !isRefreshingLocations, busyIdentity == nil, !hasPendingCanonicalSelections else { return }
        if let discoveryClient, await refreshLocationDirectory(discoveryClient, loadMore: loadMore) { return }
        if loadMore { return }
        let generation = UUID(); locationGeneration = generation
        let epoch = mutationEpoch
        isRefreshingLocations = true
        defer { if locationGeneration == generation { isRefreshingLocations = false } }
        do {
            if let existing = journalAccountID { try await requireJournalAccount(existing) }
            let account = try await currentAccountID()
            if let previous = locationAccountID, previous != account {
                merchantLocations = []; selectedLocationID = nil; clearLocationStore()
            }
            locationAccountID = account
            let preferred = journalLocationID ?? selectedLocationID ?? locationPreferences.read(account)
            let candidates = opportunities.map(\.branch) + restaurantRequests.map(\.branch)
                + v1Fulfilments.map(\.branch) + recoveryOpportunities.map(\.branch) + returnReceipts.map(\.branch)
            var discovered = Dictionary(candidates.map { ($0.id, DastakMerchantLocation($0)) }, uniquingKeysWith: { first, _ in first })
            let defaults = await DastakMerchantLocationProbe.run(client: v1Client, id: nil)
            var failed = defaults.failed
            var expired = defaults.sessionExpired
            for location in defaults.locations { discovered[location.id] = location }
            var ids = Set(discovered.values.filter { $0.kind == .unknown }.map(\.id))
            if let preferred, discovered[preferred]?.kind == nil || discovered[preferred]?.kind == .unknown { ids.insert(preferred) }
            // Probe only server-observed IDs and the account's saved candidate,
            // with four concurrent probes. No arbitrary ID picker is exposed.
            let client = v1Client
            let probes = await withTaskGroup(of: DastakMerchantLocationProbe.self, returning: [DastakMerchantLocationProbe].self) { group in
                var remaining = ids.sorted { $0.uuidString < $1.uuidString }.makeIterator()
                for _ in 0..<4 { if let id = remaining.next() { group.addTask { await DastakMerchantLocationProbe.run(client: client, id: id) } } }
                var results: [DastakMerchantLocationProbe] = []
                while let probe = await group.next() {
                    results.append(probe)
                    if !Task.isCancelled, let id = remaining.next() { group.addTask { await DastakMerchantLocationProbe.run(client: client, id: id) } }
                }
                return results
            }
            for probe in probes {
                failed = failed || probe.failed; expired = expired || probe.sessionExpired
                for location in probe.locations { discovered[location.id] = location }
            }
            guard locationGeneration == generation, mutationEpoch == epoch, busyIdentity == nil,
                  !hasPendingCanonicalSelections, !Task.isCancelled else { return }
            try await requireJournalAccount(account)
            guard locationGeneration == generation, mutationEpoch == epoch, busyIdentity == nil,
                  !hasPendingCanonicalSelections, !Task.isCancelled else { return }
            if failed, let current = selectedLocation, discovered[current.id] == nil {
                // Keep navigation stable during an outage, without retaining a
                // claim that Store management access was freshly verified.
                discovered[current.id] = .init(cached: current)
            }
            merchantLocations = discovered.values.sorted {
                $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let next: UUID?
            if let pinned = journalLocationID { next = discovered[pinned] == nil ? nil : pinned }
            else { next = preferred.flatMap { discovered[$0] == nil ? nil : $0 } ?? merchantLocations.first?.id }
            if selectedLocationID != next { selectedLocationID = next; invalidateReads(); clearLocationStore() }
            locationsInitialized = true
            if let next { locationPreferences.save(next, account: account) }
            locationMessage = failed ? "Some Store permissions could not be checked. Order-only locations remain available; retry to check Store access."
                : merchantLocations.isEmpty ? "No locations were found in accessible Store or recent order records." : nil
            if journalLocationID != nil, next == nil {
                locationMessage = "The saved action's original location is unavailable. Recover that action before choosing a different location."
            }
            if expired { sessionNeedsAttention = true }
        } catch {
            guard locationGeneration == generation else { return }
            recordConnectionFailure(error)
            locationMessage = "Locations could not be checked. Retry when your connection and Merchant session are available."
        }
    }

    /// Directory failure is never a claim of completeness. Access denial must
    /// not fall back to cached operational IDs from an older permission scope.
    private func refreshLocationDirectory(_ client: any DastakMerchantDiscoveryClient, loadMore: Bool) async -> Bool {
        guard !loadMore || locationDirectoryCursor != nil else { return true }
        let generation = UUID(); locationGeneration = generation
        let epoch = mutationEpoch, after = loadMore ? locationDirectoryCursor : nil
        isRefreshingLocations = true
        defer { if locationGeneration == generation { isRefreshingLocations = false } }
        do {
            let account = try await currentAccountID()
            if let owner = journalAccountID { try await requireJournalAccount(owner) }
            if let previous = locationAccountID, previous != account {
                if loadMore { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                merchantLocations = []; selectedLocationID = nil; clearLocationStore(); locationDirectoryCursor = nil
            }
            locationAccountID = account
            let preferred = journalLocationID ?? selectedLocationID ?? locationPreferences.read(account)
            let services = services
            let page = try await MarketplaceRequestDeadline.run(after: requestTimeout) {
                guard account == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                let result = try await client.locations(after: after,focus: preferred,key: IdempotencyKey(rawValue: UUID().uuidString)!)
                guard account == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return result
            }
            guard generation == locationGeneration, epoch == mutationEpoch, busyIdentity == nil,
                  !hasPendingCanonicalSelections, !Task.isCancelled else { return true }
            var values = loadMore ? Dictionary(merchantLocations.map { ($0.id,$0) },uniquingKeysWith: { first,_ in first }) : [:]
            for row in page.locations { values[row.id] = .init(row) }
            if let focused = page.focusedLocation { values[focused.id] = .init(focused) }
            else if let preferred { values.removeValue(forKey: preferred) }
            merchantLocations = values.values.sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let next = preferred.flatMap { values[$0] == nil ? nil : $0 }
                ?? (journalLocationID == nil ? merchantLocations.first?.id : nil)
            if selectedLocationID != next { selectedLocationID = next; invalidateReads(); clearLocationStore() }
            locationDirectoryCursor = page.nextCursor; locationDirectoryComplete = page.nextCursor == nil
            locationDirectoryMessage = page.nextCursor == nil ? "All currently authorized locations loaded." : "More authorized locations are available. Load the next page below."
            locationMessage = journalLocationID != nil && next == nil
                ? "The saved action's location is no longer authorized. Recover that action before choosing another location."
                : merchantLocations.isEmpty ? "No authorized Merchant locations are available to this account." : nil
            locationsInitialized = true
            if let next { locationPreferences.save(next,account: account) }
            return true
        } catch {
            guard generation == locationGeneration else { return true }
            var denied = error is MarketplaceAuthenticatedServicesError
            if case FunctionClientError.authenticationRequired = error { denied = true }
            if case let FunctionClientError.api(status,_,_) = error, [401,403].contains(status) { denied = true }
            locationDirectoryComplete = false
            if !loadMore { locationDirectoryCursor = nil }
            locationDirectoryMessage = "The complete location directory could not be checked. Refresh to retry; older Store/recent-order discovery is limited."
            recordConnectionFailure(error)
            if denied {
                merchantLocations = []; selectedLocationID = nil; locationDirectoryCursor = nil; clearLocationStore()
                locationMessage = "Reconnect your Merchant session or check current location permissions."
                return true
            }
            return loadMore
        }
    }

    @discardableResult
    func selectLocation(_ id: UUID) async -> Bool {
        guard !locationSwitchDisabled, merchantLocations.contains(where: { $0.id == id }), let account = locationAccountID else { return false }
        let lease = UUID().uuidString
        busyIdentity = lease
        defer { if busyIdentity == lease { busyIdentity = nil } }
        do { try await requireJournalAccount(account) } catch { recordConnectionFailure(error); return false }
        selectedLocationID = id; locationPreferences.save(id, account: account)
        invalidateReads(); clearLocationStore()
        busyIdentity = nil
        await refreshSelectedStore()
        return true
    }

    func discoverNewOperationalLocations() async {
        let ids = Set(opportunities.map { $0.branch.id } + restaurantRequests.map { $0.branch.id }
            + v1Fulfilments.map { $0.branch.id } + recoveryOpportunities.map { $0.branch.id } + returnReceipts.map { $0.branch.id })
        guard locationsInitialized, !ids.isSubset(of: Set(merchantLocations.map(\.id))) else { return }
        let previous = selectedLocationID
        await refreshLocations()
        if previous != selectedLocationID { await refreshSelectedStore() }
    }

    func refreshSelectedStore() async {
        if !locationsInitialized { await refreshLocations() }
        switch selectedLocation?.kind {
        case .retail: await refreshCanonicalCatalogue(reportFailure: false)
        case .restaurant: _ = await refreshRestaurantMenu(reportFailure: false)
        case .unknown: locationMessage = "Orders are available for this location. Refresh locations to verify Store management access."
        case nil: break
        }
    }

    private func clearLocationStore() {
        canonicalCatalogue = nil; canonicalBrowseMap = nil; restaurantMenu = nil
        canonicalCatalogueCurrent = false; catalogueCheckedAt = nil; catalogueBrowseFailure = nil
        isRefreshingCatalogue = false; isRefreshingCatalogueMap = false
        pendingCanonicalSelections = [:]; needsRestaurantRefresh = true
        catalogueRefreshFailure = nil; restaurantRefreshFailure = nil
    }


    var store: CatalogueStore? {
        catalogue?.stores.first
    }

    var categories: [CatalogueCategory] {
        (catalogue?.categories ?? []).sorted {
            $0.displayOrder == $1.displayOrder
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.displayOrder < $1.displayOrder
        }
    }

    var products: [CatalogueProduct] {
        (catalogue?.products ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var isBusy: Bool {
        busyIdentity != nil || !merchantJournalRestored || merchantJournal != nil || sessionNeedsAttention
    }

    func restoreMerchantCommands() async {
        guard !merchantJournalRestored, !isRestoringMerchantJournal, busyIdentity == nil else { return }
        isRestoringMerchantJournal = true; defer { isRestoringMerchantJournal = false }
        do {
            let account = try await currentAccountID()
            let saved = try await journalStorage.load(account)
            guard try await currentAccountID() == account else { throw DastakAdminExecutionError.changed }
            journalAccountID = account; merchantJournal = saved; merchantJournalRestored = true
            adoptJournal(saved)
            merchantJournalMessage = saved == nil ? nil : "A saved Merchant action needs recovery. Other Merchant changes stay paused until the original action is resolved."
        } catch {
            recordConnectionFailure(error)
            merchantJournalMessage = "Merchant recovery storage could not be read. Editing stays locked; no saved request was removed."
        }
    }
    private func adoptJournal(_ saved: DastakMerchantJournalRecord?) {
        pendingRecoveryCommand = nil; pendingRestaurantCommand = nil; pendingOperationCommand = nil
        if let saved { switch saved.command {
            case let .recovery(value): pendingRecoveryCommand = value
            case let .restaurant(value): pendingRestaurantCommand = value
            case let .operation(value): pendingOperationCommand = value
        } }
    }
    private func secureJournal(_ command: DastakMerchantJournalRecord.Command) async -> Bool {
        guard merchantJournalRestored, merchantJournal == nil, command.valid, let account = journalAccountID else { return false }
        let saved = DastakMerchantJournalRecord(accountID: account, command: command)
        do {
            try await requireJournalAccount(account)
            try await journalStorage.replace(saved, accountID: account, expectedRevision: nil)
            merchantJournal = saved; adoptJournal(saved)
            automaticRecoveryCount = 0; lastAutomaticRecovery = .now
            return true
        } catch {
            merchantJournalRestored = false; adoptJournal(nil)
            merchantJournalMessage = "The action could not be secured. No request was sent. Reload recovery before editing."
            return false
        }
    }
    private func prepareJournalAttempt() async throws -> Bool {
        guard var saved = merchantJournal, let account = journalAccountID, saved.accountID == account else { throw DastakAdminExecutionError.changed }
        try await requireJournalAccount(account)
        let authoritative = try await journalStorage.load(account)
        guard authoritative == saved else {
            // Another window may have completed or advanced the same command.
            // Adopt its protected record, never overwrite it with this snapshot.
            merchantJournal = authoritative; adoptJournal(authoritative)
            if authoritative == nil { return false }
            throw DastakAdminExecutionError.changed
        }
        if saved.acknowledged {
            try await journalStorage.replace(nil, accountID: account, expectedRevision: saved.revision)
            merchantJournal = nil; adoptJournal(nil)
            merchantJournalMessage = "The action was already acknowledged. Local recovery finished without another write."
            notice = merchantJournalMessage
            return false
        }
        let old = saved.revision; saved.attempts += 1; saved.revision = UUID()
        try await journalStorage.replace(saved, accountID: account, expectedRevision: old)
        merchantJournal = saved
        try await requireJournalAccount(account)
        guard try await journalStorage.load(account) == saved else { throw DastakAdminExecutionError.changed }
        return true
    }
    private func acknowledgeJournal() async throws {
        guard var saved = merchantJournal, let account = journalAccountID else { throw DastakAdminExecutionError.changed }
        try await requireJournalAccount(account)
        guard try await journalStorage.load(account) == saved else { throw DastakAdminExecutionError.changed }
        let old = saved.revision; saved.acknowledged = true; saved.revision = UUID()
        try await journalStorage.replace(saved, accountID: account, expectedRevision: old)
        merchantJournal = saved
        try await journalStorage.replace(nil, accountID: account, expectedRevision: saved.revision)
        merchantJournal = nil; adoptJournal(nil); merchantJournalMessage = nil
    }
    private func requireJournalAccount(_ account: UUID) async throws {
        guard try await currentAccountID() == account else {
            sessionNeedsAttention = true
            // Clear presentation only; the original actor's unresolved file remains intact.
            merchantJournal = nil; journalAccountID = nil; merchantJournalRestored = false; adoptJournal(nil)
            orders = []; v1Fulfilments = []; recoveryOpportunities = []; opportunities = []; restaurantRequests = []
            returnReceipts = []; settlements = []; restaurantMenu = nil; catalogue = nil; canonicalCatalogue = nil
            canonicalBrowseMap = nil; earnings = nil; pendingCanonicalSelections = [:]
            canonicalCatalogueCurrent = false; catalogueCheckedAt = nil; catalogueBrowseFailure = nil
            fulfilmentsCurrent = false; recoveryCurrent = false; returnsCurrent = false; settlementsCurrent = false
            incomingCurrent = false; foodRequestsCurrent = false; legacyOrdersCurrent = false
            menuDrafts.setAccount(nil)
            needsRestaurantRefresh = true; invalidateReads()
            locationGeneration = UUID(); isRefreshingLocations = false; locationsInitialized = false
            merchantLocations = []; selectedLocationID = nil; locationAccountID = nil
            locationDirectoryCursor = nil; locationDirectoryComplete = false; locationDirectoryMessage = nil
            throw MarketplaceAuthenticatedServicesError.identityMismatch
        }
    }
    private func handleJournalFailure(_ error: Error) async -> Bool {
        recordConnectionFailure(error)
        if let saved = merchantJournal, saved.attempts == 1, !saved.acknowledged,
           case let FunctionClientError.api(status, _, _) = error, (400..<500).contains(status), ![408, 429].contains(status) {
            do {
                try await journalStorage.replace(nil, accountID: saved.accountID, expectedRevision: saved.revision)
                merchantJournal = nil; adoptJournal(nil); merchantJournalMessage = "The first request was rejected. Refresh and review a new action."
                return true
            } catch { /* Keep the unresolved disk record. */ }
        }
        merchantJournalMessage = "Outcome or local storage is uncertain. Retry the original saved action; do not replace its details."
        return false
    }
    func retryMerchantJournal() async {
        if pendingRecoveryCommand != nil { _ = await retryRecoveryCommand() }
        else if pendingRestaurantCommand != nil { _ = await retryRestaurantCommand() }
        else if pendingOperationCommand != nil { _ = await retryOperationCommand() }
        else { await restoreMerchantCommands() }
    }

    private func currentAccountID() async throws -> UUID {
        try await MarketplaceRequestDeadline.run(after: requestTimeout) { [services] in try await services.accountID() }
    }

    private func invalidateReads() {
        mutationEpoch = UUID(); operationReadGeneration = UUID()
        restaurantRefreshGeneration = UUID(); catalogueReadGeneration = UUID(); earningsReadGeneration = UUID()
        // An invalidated reader must not leave its spinner owning the new read.
        isRefreshingRestaurant = false
        isRefreshingCatalogue = false; isRefreshingCatalogueMap = false
        needsRestaurantRefresh = true
    }

    private func recordConnectionFailure(_ error: Error) {
        if case FunctionClientError.authenticationRequired = error { sessionNeedsAttention = true }
        if case let FunctionClientError.api(status, _, _) = error, status == 401 { sessionNeedsAttention = true }
        if case MarketplaceAuthenticatedServicesError.identityMismatch = error { sessionNeedsAttention = true }
    }

    func reconnectSession() async {
        guard busyIdentity == nil else { return }
        busyIdentity = "session-recovery"
        do {
            try await MarketplaceRequestDeadline.run(after: requestTimeout) { [services] in try await services.refreshSession() }
            sessionNeedsAttention = false
        } catch { sessionNeedsAttention = true }
        busyIdentity = nil
        if !sessionNeedsAttention { await refreshAll() }
    }

    /// Foreground only, bounded backoff; manual retry remains available after
    /// the budget. Never manufactures success from a missing feed or version.
    func recoverPendingActionIfNeeded(now: Date = .now) async {
        guard busyIdentity == nil, !sessionNeedsAttention, automaticRecoveryCount < 5 else { return }
        let delay: TimeInterval = automaticRecoveryCount == 0 ? 3 : automaticRecoveryCount == 1 ? 10 : 30
        guard lastAutomaticRecovery.map({ now.timeIntervalSince($0) >= delay }) ?? true else { return }
        guard !merchantJournalRestored || merchantJournal != nil else { return }
        lastAutomaticRecovery = now; automaticRecoveryCount += 1
        await retryMerchantJournal()
    }

    private func submitOperation(_ operation: DastakMerchantOperationCommand.Operation) async -> Bool {
        guard !isBusy else {
            errorMessage = sessionNeedsAttention ? "Sign in again before making changes."
                : merchantJournal != nil ? "Resolve the saved action above before starting another change."
                : "Wait for the current action or saved-action check to finish."
            return false
        }
        let command = DastakMerchantOperationCommand(operation: operation, key: makeKey())
        guard command.valid else { errorMessage = "Check the required fields and supported values before saving."; return false }
        guard command.branchID.map(permitsLocation) != false else {
            errorMessage = DastakMerchantStoreReadError.wrongLocation.message; return false
        }
        busyIdentity = "securing-operation"
        let secured = await secureJournal(.operation(command))
        busyIdentity = nil
        guard secured else { return false }
        return await retryOperationCommand()
    }

    @discardableResult
    func retryOperationCommand() async -> Bool {
        guard busyIdentity == nil, merchantJournalRestored, let command = pendingOperationCommand else { return false }
        busyIdentity = "merchant-operation"
        invalidateReads()
        switch command.operation {
        case .retailResponse: incomingCurrent = false
        case .foodResponse: foodRequestsCurrent = false
        case .packages, .evidence, .ready: fulfilmentsCurrent = false
        case .legacyOrder: legacyOrdersCurrent = false
        case .selections, .operating:
            catalogueRefreshFailure = "Checking the latest store products before another change."
        default: break
        }
        notice = nil; errorMessage = nil
        var succeeded = false
        do {
            if try await prepareJournalAttempt() {
                if let upload = command.upload, merchantJournal?.uploadCompleted != true {
                    do {
                        try await MarketplaceRequestDeadline.run(after: requestTimeout) { [services] in
                            try await services.uploadObject(bucket: upload.bucket, path: upload.path, data: upload.data, contentType: upload.contentType)
                        }
                    } catch where DastakEvidenceUpload.isDuplicate(error) {
                        // Only an immutable, account-owned, randomly generated
                        // path secured before upload can reach this branch.
                    }
                    guard let account = journalAccountID, var saved = merchantJournal else { throw DastakAdminExecutionError.changed }
                    try await requireJournalAccount(account)
                    let old = saved.revision; saved.uploadCompleted = true; saved.revision = UUID()
                    try await journalStorage.replace(saved, accountID: account, expectedRevision: old)
                    merchantJournal = saved
                }
                guard let account = journalAccountID else { throw DastakAdminExecutionError.changed }
                try await requireJournalAccount(account)
                guard try await journalStorage.load(account) == merchantJournal else { throw DastakAdminExecutionError.changed }
                let followup = try await executeOperation(command)
                if let followup, let saved = merchantJournal {
                    // Acknowledged earlier-order rejection can lead to its
                    // existing refund workflow. Persist the follow-up atomically
                    // before relinquishing the original command's ownership.
                    let next = DastakMerchantJournalRecord(accountID: account,
                        command: .operation(.init(operation: followup, key: makeKey())))
                    try await requireJournalAccount(account)
                    try await journalStorage.replace(next, accountID: account, expectedRevision: saved.revision)
                    merchantJournal = next; adoptJournal(next)
                    automaticRecoveryCount = 0; lastAutomaticRecovery = .now
                } else { try await acknowledgeJournal() }
            }
            notice = "\(command.description) saved."
            succeeded = true
        } catch {
            if await handleJournalFailure(error) {
                if isRecoverableOrderConflict(error) {
                    notice = "This order changed while you were working. The latest status is now shown."
                } else { errorMessage = message(for: error, fallback: "This change was rejected. Refresh and review the latest details.") }
            } else {
                merchantJournalMessage = "Connection interrupted. Your original action is saved and will be checked automatically. You can also retry it safely."
            }
        }
        // A post-save read never owns the action's button/lock lease.
        busyIdentity = nil
        guard journalAccountID != nil else { return false }
        switch command.operation {
        case let .selections(_, selections):
            if succeeded {
                for selection in selections where pendingCanonicalSelections[selection.skuID] == selection.selected {
                    pendingCanonicalSelections[selection.skuID] = nil
                }
            }
            await refreshCanonicalCatalogue(reportFailure: false)
        case .operating:
            await refreshCanonicalCatalogue(reportFailure: false)
        case .legacyStore, .legacyCategory, .legacyProduct:
            await refreshStoreInformation()
        default: await refreshOrders()
        }
        return succeeded
    }

    private func executeOperation(_ command: DastakMerchantOperationCommand) async throws -> DastakMerchantOperationCommand.Operation? {
        let key = command.key
        switch command.operation {
        case let .retailResponse(item, accept, minutes):
            let updated = try await inboxClient.respond(opportunity: item, accept: accept, prepMinutes: minutes, idempotencyKey: key)
            guard updated.id == item.id, updated.branch.id == item.branch.id, updated.version > item.version,
                  updated.status == (accept ? "SELECTED" : "DECLINED") else { throw FunctionClientError.invalidResponse }
        case let .foodResponse(item, accept, minutes, reason):
            let updated = try await inboxClient.respond(request: item, accept: accept, prepMinutes: minutes, reason: reason, idempotencyKey: key)
            guard updated.id == item.id, updated.orderId == item.orderId, updated.branch.id == item.branch.id,
                  updated.version > item.version, updated.status == (accept ? "CONFIRMED" : "DECLINED") else { throw FunctionClientError.invalidResponse }
        case let .packages(target, count):
            let updated = try await v1Client.declarePackages(fulfilmentID: target.id, packageCount: count, expectedVersion: target.version, idempotencyKey: key)
            try validate(updated, target: target)
            guard updated.packageCount == count else { throw FunctionClientError.invalidResponse }
        case let .evidence(target, upload):
            let updated = try await v1Client.addEvidence(fulfilmentID: target.id, objectPath: upload.path, expectedVersion: target.version, idempotencyKey: key)
            try validate(updated, target: target)
            guard updated.evidence.contains(where: { $0.objectPath == upload.path }) else { throw FunctionClientError.invalidResponse }
        case let .ready(target):
            let updated = try await v1Client.markReady(fulfilmentID: target.id, expectedVersion: target.version, idempotencyKey: key)
            try validate(updated, target: target)
            guard updated.status == "READY" else { throw FunctionClientError.invalidResponse }
        case let .selections(branch, selections):
            let result = try await v1Client.updateCatalogueSelections(branchID: branch, selections: selections, idempotencyKey: key)
            guard result.branchID == branch, result.updatedCount == selections.count, result.selections.count == selections.count,
                  Set(result.selections.map(\.skuID)).count == selections.count,
                  selections.allSatisfy({ requested in result.selections.contains {
                      $0.branchID == branch && $0.skuID == requested.skuID && $0.selected == requested.selected && $0.version > requested.expectedVersion
                  } }) else { throw FunctionClientError.invalidResponse }
        case let .operating(branch, open, accepting, version):
            let result = try await v1Client.updateBranchState(branchID: branch, isOpen: open, acceptingOrders: accepting, expectedVersion: version, idempotencyKey: key)
            guard result.branchID == branch, result.isOpen == open, result.acceptingOrders == accepting, result.version > version else { throw FunctionClientError.invalidResponse }
        case let .legacyOrder(action, id, version, reason):
            if action == .refund {
                let result = try await checkoutClient.processMerchantOrderRefund(orderID: id, idempotencyKey: key)
                guard result.orderID == id else { throw FunctionClientError.invalidResponse }
            } else {
                let updated: MerchantOrderSnapshot
                switch action {
                case .accept: updated = try await orderClient.merchantAccept(orderID: id, idempotencyKey: key)
                case .ready: updated = try await orderClient.merchantMarkReady(orderID: id, idempotencyKey: key)
                case .reject: updated = try await orderClient.merchantReject(orderID: id, reason: reason ?? "", idempotencyKey: key)
                case .confirmReturn: updated = try await orderClient.merchantConfirmReturn(orderID: id, reason: reason ?? "Returned items received by merchant", idempotencyKey: key)
                case .refund: throw FunctionClientError.invalidResponse
                }
                guard updated.orderID == id, updated.stateVersion >= version else { throw FunctionClientError.invalidResponse }
                if updated.paymentState == .refundPending, action == .reject || action == .confirmReturn {
                    return .legacyOrder(.refund, orderID: id, version: updated.stateVersion, reason: nil)
                }
            }
        case let .legacyStore(name, address, location, published, accepting):
            let result = try await catalogueClient.upsertStore(name: name, address: address, location: location, isPublished: published, acceptingOrders: accepting, idempotencyKey: key)
            guard result.name == name, result.address == address, result.location == location,
                  result.isPublished == published, result.acceptingOrders == accepting else { throw FunctionClientError.invalidResponse }
        case let .legacyCategory(id, name, sort, active):
            let result = try await catalogueClient.upsertCategory(categoryID: id, name: name, displayOrder: sort, isActive: active, idempotencyKey: key)
            guard id == nil || result.categoryID == id, result.name == name, result.displayOrder == sort, result.isActive == active else { throw FunctionClientError.invalidResponse }
        case let .legacyProduct(draft, paise, upload):
            let result = try await catalogueClient.upsertProduct(productID: draft.productID, categoryID: draft.categoryID, name: draft.name,
                description: draft.description.isEmpty ? nil : draft.description, unitLabel: draft.unitLabel, price: Money(paise: paise),
                imageObjectPath: upload?.path ?? draft.imageObjectPath, availability: draft.availability, catalogueKind: draft.catalogueKind, isActive: draft.isActive, idempotencyKey: key)
            guard draft.productID == nil || result.productID == draft.productID,
                  result.categoryID == draft.categoryID, result.name == draft.name, result.price.paise == paise,
                  result.availability == draft.availability, result.isActive == draft.isActive else { throw FunctionClientError.invalidResponse }
        }
        return nil
    }

    private func validate(_ updated: DastakV1MerchantFulfilment, target: DastakMerchantOperationCommand.Target) throws {
        guard updated.id == target.id, updated.orderID == target.orderID, updated.branch.id == target.branchID,
              updated.version > target.version else { throw FunctionClientError.invalidResponse }
    }

    var restaurantChangesDisabled: Bool {
        isBusy || isRefreshingRestaurant || needsRestaurantRefresh || pendingRestaurantCommand != nil
            || (locationsInitialized && (selectedLocation?.kind != .restaurant || restaurantMenu?.restaurant.branchID != selectedLocationID))
    }

    var restaurantEditUnavailableReason: String? {
        if sessionNeedsAttention { return "Sign in again before changing the menu." }
        if merchantJournal != nil { return "Resolve the saved action above before changing the menu." }
        if isBusy { return "Wait for the current action or connection check to finish." }
        if isRefreshingRestaurant { return "Checking the latest menu. Editing resumes when the check finishes." }
        if needsRestaurantRefresh { return "Refresh this restaurant's menu before making changes." }
        if locationsInitialized && (selectedLocation?.kind != .restaurant || restaurantMenu?.restaurant.branchID != selectedLocationID) {
            return "Choose the correct Restaurant / Café location, then refresh its menu."
        }
        return nil
    }

    var canChangeRestaurantOperatingState: Bool {
        !restaurantChangesDisabled && restaurantMenu?.restaurant.branchStatus == "ACTIVE"
            && restaurantMenu?.restaurant.operationalVersion.map { (0..<Int.max).contains($0) } == true
    }

    var hasPendingCanonicalSelections: Bool {
        !pendingCanonicalSelections.isEmpty
    }

    func bootstrap() async {
        await restoreMerchantCommands()
        await refreshAll()
        await refreshLocations()
        await refreshSelectedStore()
        isLoading = false
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let orderRefresh: Void = refreshOrders()
        async let catalogueRefresh: Void = refreshStoreInformation()
        async let earningsRefresh: Void = refreshEarnings()
        async let notificationRefresh: Void = notifications.refresh()
        _ = await (orderRefresh, catalogueRefresh, earningsRefresh, notificationRefresh)
    }

    private func refreshStoreInformation() async {
        if locationsInitialized { await refreshSelectedStore(); return }
        async let legacy: Void = refreshLegacyCatalogue()
        async let retail: Void = refreshCanonicalCatalogue(reportFailure: false)
        async let restaurant = refreshRestaurantMenu(reportFailure: false)
        _ = await (legacy, retail, restaurant)
    }

    private func refreshLegacyCatalogue() async {
        let epoch = mutationEpoch
        do {
            let snapshot = try await catalogueClient.merchantSnapshot(idempotencyKey: makeKey())
            guard epoch == mutationEpoch, !Task.isCancelled else { return }
            catalogue = snapshot
        } catch { if epoch == mutationEpoch { recordConnectionFailure(error) } }
    }

    private func refreshEarnings() async {
        let generation = UUID(); earningsReadGeneration = generation
        do {
            let snapshot = try await earningsClient.merchantSnapshot(idempotencyKey: makeKey())
            guard generation == earningsReadGeneration, !Task.isCancelled else { return }
            earnings = snapshot; earningsRefreshFailure = nil
        } catch {
            guard generation == earningsReadGeneration else { return }
            recordConnectionFailure(error)
            earningsRefreshFailure = "Earnings could not update. Any displayed balance is from the last successful check."
        }
    }

    func refreshCanonicalCatalogue(reportFailure: Bool = true) async {
        if locationsInitialized, selectedLocation?.kind != .retail { return }
        guard !isRefreshingCatalogue, !isRefreshingCatalogueMap else { return }
        let branch = selectedLocationID ?? canonicalCatalogue?.branch.branchID
        let generation = UUID(); catalogueReadGeneration = generation
        isRefreshingCatalogue = true; isRefreshingCatalogueMap = true; canonicalCatalogueCurrent = false
        let services = services, client = v1Client, timeout = requestTimeout, owner = catalogueAccountID
        let productKey = makeKey(), mapKey = makeKey()
        async let products = Self.catalogueRead {
            try await MarketplaceRequestDeadline.run(after: timeout) {
                let account = try await services.accountID()
                guard owner == nil || owner == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                let snapshot = try await client.canonicalCatalogue(branchID: branch, limit: 5_000, idempotencyKey: productKey)
                guard try await services.accountID() == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return (account, snapshot)
            }
        }
        async let navigation = Self.catalogueRead {
            try await MarketplaceRequestDeadline.run(after: timeout) { try await client.catalogueBrowseMap(idempotencyKey: mapKey) }
        }
        defer {
            if generation == catalogueReadGeneration { isRefreshingCatalogue = false; isRefreshingCatalogueMap = false }
        }
        let productResult = await products
        guard generation == catalogueReadGeneration, !Task.isCancelled else { return }
        switch productResult {
        case let .success((account, refreshed)):
          do {
            guard branch == nil || refreshed.branch.branchID == branch else { throw DastakMerchantStoreReadError.wrongLocation }
            guard ["RETAIL","DASTAK_CONVENIENCE_STORE"].contains(refreshed.branch.merchantType) else { throw DastakMerchantStoreReadError.wrongService }
            guard DastakMerchantCataloguePresentation.validSnapshot(refreshed) else { throw FunctionClientError.invalidResponse }
            canonicalCatalogue = refreshed
            catalogueAccountID = account; canonicalCatalogueCurrent = true; catalogueCheckedAt = .now; catalogueRefreshFailure = nil
            if pendingOperationCommand == nil {
                pendingCanonicalSelections = pendingCanonicalSelections.filter { skuID, desired in
                    // An omitted SKU is unknown, not proof that a pending removal
                    // or addition was acknowledged by a capped snapshot.
                    guard let sku = refreshed.skus.first(where: { $0.skuID == skuID }) else { return true }
                    return sku.selected != desired
                }
            }
            if reportFailure { errorMessage = nil }
          } catch { catalogueReadFailed(error, reportFailure: reportFailure) }
        case let .failure(error): catalogueReadFailed(error, reportFailure: reportFailure)
        }
        isRefreshingCatalogue = false
        let mapResult = await navigation
        guard generation == catalogueReadGeneration, !Task.isCancelled else { return }
        switch mapResult {
        case let .success(map):
            if map?.isValid == true { canonicalBrowseMap = map; catalogueBrowseFailure = nil }
            else {
                canonicalBrowseMap = nil
                catalogueBrowseFailure = map == nil ? "Category navigation is not available. Use search, My storefront or the department directory." : "Category navigation could not be verified. Use search or the department directory."
            }
        case let .failure(error):
            canonicalBrowseMap = nil
            catalogueBrowseFailure = "Category navigation could not update. Products and search remain available when their own read succeeds."
            recordConnectionFailure(error)
        }
    }

    private nonisolated static func catalogueRead<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async -> Result<Value, Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private func catalogueReadFailed(_ error: Error, reportFailure: Bool) {
        canonicalCatalogueCurrent = false
        var denied = error is MarketplaceAuthenticatedServicesError
        if case DastakMerchantStoreReadError.wrongService = error { denied = true }
        if case FunctionClientError.authenticationRequired = error { denied = true }
        if case let FunctionClientError.api(status, _, _) = error, [401,403,404].contains(status) { denied = true }
        if denied { canonicalCatalogue = nil; canonicalBrowseMap = nil; catalogueCheckedAt = nil; pendingCanonicalSelections = [:] }
        recordConnectionFailure(error)
        catalogueRefreshFailure = (error as? DastakMerchantStoreReadError)?.message ?? "Store products could not update. Any displayed results are last-known; refresh before changing stock or selections."
        if reportFailure, !String(describing: error).localizedCaseInsensitiveContains("retail-only") {
            errorMessage = message(for: error, fallback: "The store catalogue could not be refreshed.")
        }
    }

    @discardableResult
    func refreshRestaurantMenu(reportFailure: Bool = true) async -> Bool {
        await restoreMerchantCommands()
        return await loadRestaurantMenu(reportFailure: reportFailure, duringCommand: false)
    }

    private func loadRestaurantMenu(reportFailure: Bool, duringCommand: Bool) async -> Bool {
        guard !isExecutingRestaurantCommand || duringCommand else { return false }
        if locationsInitialized, selectedLocation?.kind != .restaurant, !duringCommand { return false }
        let generation = UUID()
        restaurantRefreshGeneration = generation
        let branchID = pendingRestaurantCommand?.branchID ?? selectedLocationID ?? restaurantMenu?.restaurant.branchID
        isRefreshingRestaurant = true
        needsRestaurantRefresh = true
        defer { if restaurantRefreshGeneration == generation { isRefreshingRestaurant = false } }
        do {
            let services = services, client = v1Client, owner = journalAccountID, key = makeKey()
            let (account, refreshed) = try await MarketplaceRequestDeadline.run(after: requestTimeout) {
                let account = try await services.accountID()
                guard owner == nil || owner == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                let menu = try await client.restaurantMenu(branchID: branchID, idempotencyKey: key)
                guard account == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return (account,menu)
            }
            guard branchID == nil || refreshed.restaurant.branchID == branchID else { throw DastakMerchantStoreReadError.wrongLocation }
            guard refreshed.restaurant.operationalVersion.map({ $0 >= 0 }) != false else {
                throw FunctionClientError.invalidResponse
            }
            guard refreshed.restaurant.merchantType == "RESTAURANT_CAFE" else {
                throw DastakMerchantStoreReadError.wrongService
            }
            guard restaurantRefreshGeneration == generation, !Task.isCancelled else { return false }
            menuDrafts.setAccount(account)
            restaurantMenu = refreshed
            restaurantRefreshFailure = nil
            needsRestaurantRefresh = false
            if reportFailure { errorMessage = nil }
            return true
        } catch {
            guard restaurantRefreshGeneration == generation else { return false }
            recordConnectionFailure(error)
            if case MarketplaceAuthenticatedServicesError.identityMismatch = error {
                menuDrafts.setAccount(nil); restaurantMenu = nil
            }
            if case DastakMerchantStoreReadError.wrongService = error { restaurantMenu = nil }
            restaurantRefreshFailure = (error as? DastakMerchantStoreReadError)?.message ?? "Restaurant details could not be refreshed. Any displayed details may be outdated. Refresh before making changes."
            if reportFailure { errorMessage = message(for: error, fallback: restaurantRefreshFailure!) }
            return false
        }
    }

    func saveRestaurantEntity(entityID: UUID?, expectedVersion: Int, payload: DastakV1RestaurantMenuPayload, branchID: UUID? = nil) async -> Bool {
        guard !restaurantChangesDisabled, let menu = restaurantMenu else {
            errorMessage = restaurantEditUnavailableReason ?? "Load this restaurant's menu before saving."; return false
        }
        guard branchID == nil || branchID == menu.restaurant.branchID else {
            errorMessage = DastakMerchantStoreReadError.wrongLocation.message; return false
        }
        if let issue = DastakMerchantValidation.menuIssue(payload) { errorMessage = issue; return false }
        guard expectedVersion >= 0, expectedVersion < Int.max,
              entityID.map({ menu.entityVersion(type: payload.entityType, id: $0) == expectedVersion })
                ?? (expectedVersion == 0) else {
            errorMessage = "This menu entry changed. Review the latest details before saving."
            return false
        }
        busyIdentity = "securing-restaurant-command"
        let secured = await secureJournal(.restaurant(.init(branchID: menu.restaurant.branchID, key: makeKey(), operation: .menu(entityID: entityID, expectedVersion: expectedVersion, payload: payload))))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRestaurantCommand()
    }

    func uploadRestaurantMedia(entityType: String, entityID: UUID, expectedMediaVersion: Int, data: Data, contentType: String, fileName: String) async -> Bool {
        guard !restaurantChangesDisabled, let menu = restaurantMenu else {
            errorMessage = restaurantEditUnavailableReason ?? "Load this restaurant's menu before changing its photo."; return false
        }
        guard let inspected = DastakMerchantImageInspector.inspect(data), inspected.contentType == contentType else {
            errorMessage = "Choose a valid JPEG, PNG or WebP image up to 5 MB. HEIC must be converted before upload."
            return false
        }
        guard !fileName.isEmpty, fileName.count <= 200, fileName.rangeOfCharacter(from: .newlines) == nil else {
            errorMessage = "This photo's filename is invalid. Choose the photo again."
            return false
        }
        let currentVersion: Int?
        if entityType == "RESTAURANT_BRANCH_BANNER", entityID == menu.restaurant.branchID {
            currentVersion = menu.restaurant.mediaVersion ?? 1
        } else if entityType == "RESTAURANT_MENU_ITEM" {
            currentVersion = menu.categories.lazy.flatMap(\.items).first { $0.id == entityID }.map { $0.mediaVersion ?? 1 }
        } else { currentVersion = nil }
        guard currentVersion == expectedMediaVersion, (0..<Int.max).contains(expectedMediaVersion) else {
            errorMessage = "This photo or menu entry changed. Refresh the menu, review it and choose the photo again."; return false
        }
        busyIdentity = "securing-restaurant-command"
        let secured = await secureJournal(.restaurant(.init(branchID: menu.restaurant.branchID, key: makeKey(),
            operation: .media(entityType: entityType, entityID: entityID, expectedVersion: expectedMediaVersion,
                              data: data, contentType: contentType, fileName: fileName))))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRestaurantCommand()
    }

    @discardableResult
    func setRestaurantOperatingState(isOpen: Bool, acceptingOrders: Bool, branchID: UUID? = nil) async -> Bool {
        guard canChangeRestaurantOperatingState, let restaurant = restaurantMenu?.restaurant,
              let version = restaurant.operationalVersion else {
            errorMessage = restaurantEditUnavailableReason ?? "Operating controls are unavailable for this restaurant. Refresh locations and check its approval status."; return false
        }
        guard branchID == nil || branchID == restaurant.branchID else {
            errorMessage = DastakMerchantStoreReadError.wrongLocation.message; return false
        }
        busyIdentity = "securing-restaurant-command"
        let secured = await secureJournal(.restaurant(.init(branchID: restaurant.branchID, key: makeKey(), operation: .operating(isOpen: isOpen, acceptingOrders: isOpen && acceptingOrders, expectedVersion: version))))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRestaurantCommand()
    }

    @discardableResult
    func retryRestaurantCommand() async -> Bool {
        guard busyIdentity == nil, merchantJournalRestored, !isExecutingRestaurantCommand, let command = pendingRestaurantCommand else { return false }
        let lease = UUID().uuidString
        busyIdentity = lease
        invalidateReads()
        isExecutingRestaurantCommand = true
        restaurantRefreshGeneration = UUID() // Invalidate an older, pre-mutation read.
        isRefreshingRestaurant = false
        needsRestaurantRefresh = true
        notice = nil
        errorMessage = nil
        defer {
            if busyIdentity == lease { busyIdentity = nil }
            isExecutingRestaurantCommand = false
        }
        do {
            guard try await prepareJournalAttempt() else {
                _ = await loadRestaurantMenu(reportFailure: false, duringCommand: true)
                reconcileAcknowledgedMenuDraft(command)
                return true
            }
            switch command.operation {
            case let .menu(entityID, version, payload):
                let requestID = entityID ?? command.creationEntityID
                let result = try await v1Client.upsertRestaurantMenuEntity(branchID: command.branchID,
                    entityID: requestID, expectedVersion: version, payload: payload, idempotencyKey: command.key)
                guard result.menu.restaurant.branchID == command.branchID, result.entityType == payload.entityType,
                      requestID == nil || result.entityID == requestID,
                      result.menu.entityVersion(type: payload.entityType, id: result.entityID).map({ $0 > version }) == true else {
                    throw FunctionClientError.invalidResponse
                }
                if let account = journalAccountID {
                    try await requireJournalAccount(account)
                    menuDrafts.setAccount(account)
                }
                restaurantMenu = result.menu
            case let .operating(isOpen, accepting, version):
                let result = try await v1Client.updateBranchState(branchID: command.branchID, isOpen: isOpen,
                    acceptingOrders: accepting, expectedVersion: version, idempotencyKey: command.key)
                guard result.branchID == command.branchID, result.isOpen == isOpen,
                      result.acceptingOrders == accepting, result.version == version + 1 else {
                    throw FunctionClientError.invalidResponse
                }
            case let .media(type, entityID, version, data, contentType, fileName):
                let result = try await v1Client.uploadGovernedRestaurantMedia(entityType: type, entityID: entityID,
                    expectedMediaVersion: version, data: data, contentType: contentType, fileName: fileName,
                    sourceReference: "Merchant-owned image: \(fileName)", reason: command.description, idempotencyKey: command.key)
                guard result.entityID == entityID, result.mediaVersion > version, !result.imageKey.isEmpty else {
                    throw FunctionClientError.invalidResponse
                }
            }
            reconcileAcknowledgedMenuDraft(command)
            // Persist clearing of matching unsent forms before removing the
            // immutable saved command. Disk failure must not restore a
            // duplicate-ready creation form after a successful server write.
            if case .menu = command.operation { try menuDrafts.flush() }
            try await acknowledgeJournal()
            notice = "\(command.description) saved."
            busyIdentity = nil
            // An acknowledged save and a failed subsequent read are different outcomes.
            _ = await loadRestaurantMenu(reportFailure: false, duringCommand: true)
            return true
        } catch {
            if await handleJournalFailure(error) {
                errorMessage = message(for: error, fallback: "The change was rejected. Refresh and review the latest details.")
            } else {
                errorMessage = "This change has not been confirmed. Check the pending action in Store and retry its original details before making another change."
            }
            if journalAccountID != nil { _ = await loadRestaurantMenu(reportFailure: false, duringCommand: true) }
            return false
        }
    }

    private func reconcileAcknowledgedMenuDraft(_ command: DastakMerchantRestaurantCommand) {
        guard menuDrafts.branchID == command.branchID, case let .menu(entityID, version, payload) = command.operation else { return }
        if let entityID { menuDrafts.acknowledge(entityID: entityID, expectedVersion: version, payload: payload) }
        else { menuDrafts.acknowledgeCreation(payload) }
    }

    var recoveryActionsDisabled: Bool { isBusy || !recoveryCurrent || pendingRecoveryCommand != nil }

    func recoveryBlocks(_ fulfilment: DastakV1MerchantFulfilment) -> Bool {
        pendingRecoveryCommand?.orderID == fulfilment.orderID
    }

    func canReportProblem(_ fulfilment: DastakV1MerchantFulfilment) -> Bool {
        fulfilmentsCurrent && !isBusy && permitsLocation(fulfilment.branch.id) && pendingRecoveryCommand == nil && fulfilment.version > 0
            && fulfilment.version < Int.max && fulfilment.orderStatus == "PREPARING"
            && ["PREPARING", "READY"].contains(fulfilment.status)
            && v1Fulfilments.contains { $0.id == fulfilment.id && $0.version == fulfilment.version
                && $0.branch.id == fulfilment.branch.id && $0.orderID == fulfilment.orderID }
    }

    @discardableResult
    func reportRecoveryProblem(_ fulfilment: DastakV1MerchantFulfilment, lineID: UUID?, reason: String) async -> Bool {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canReportProblem(fulfilment), reason.count >= 3, reason.utf16.count <= 500 else { return false }
        let operation: DastakMerchantRecoveryCommand.Operation
        if let lineID {
            guard fulfilment.canReportExactSkuFailure == true, fulfilment.status == "PREPARING",
                  fulfilment.packageCount == nil, fulfilment.lines.contains(where: { $0.id == lineID && $0.quantity > 0 }) else { return false }
            operation = .exactFailure(.init(fulfilment), lineID: lineID, reason: reason)
        } else { operation = .problem(.init(fulfilment), reason: reason) }
        busyIdentity = "securing-recovery-command"
        let secured = await secureJournal(.recovery(.init(operation: operation, key: makeKey())))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRecoveryCommand()
    }

    @discardableResult
    func respondToRecovery(_ offer: DastakV1RecoveryOpportunity, accept: Bool, prepMinutes: Int,
        physicallyConfirmed: Bool, now: Date = .now) async -> Bool {
        guard !recoveryActionsDisabled, permitsLocation(offer.branch.id), recoveryOpportunities.contains(offer), offer.status == "OFFERED",
              offer.version > 0, offer.version < Int.max, offer.requestedQuantity > 0,
              let expiry = DastakMerchantOrderClock.date(offer.expiresAt), expiry > now,
              !accept || (physicallyConfirmed && (1...1440).contains(prepMinutes)) else { return false }
        busyIdentity = "securing-recovery-command"
        let secured = await secureJournal(.recovery(.init(operation: .response(offer, accept: accept, prepMinutes: accept ? prepMinutes : 0), key: makeKey())))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRecoveryCommand()
    }

    @discardableResult
    func retryRecoveryCommand() async -> Bool {
        guard busyIdentity == nil, merchantJournalRestored, let command = pendingRecoveryCommand else { return false }
        let lease = UUID().uuidString
        busyIdentity = lease
        invalidateReads()
        operationReadGeneration = UUID()
        fulfilmentsCurrent = false; recoveryCurrent = false
        recoveryCommandMessage = nil
        defer { if busyIdentity == lease { busyIdentity = nil } }
        do {
            guard try await prepareJournalAttempt() else { await refreshV1Fulfilments(); return true }
            switch command.operation {
            case let .exactFailure(order, lineID, reason):
                let receipt = try await recoveryClient.reportExactFailure(fulfilmentID: order.id, lineID: lineID,
                    reason: reason, version: order.version, key: command.key)
                guard receipt.orderId == order.orderID, receipt.orderLineId == lineID,
                      receipt.status == "SEARCHING_EXACT_SKU", !receipt.customerPaymentChanged,
                      receipt.quantity == order.lines.first(where: { $0.id == lineID })?.quantity else {
                    throw FunctionClientError.invalidResponse
                }
            case let .problem(order, reason):
                let updated = try await recoveryClient.reportProblem(fulfilmentID: order.id, reason: reason,
                    version: order.version, key: command.key)
                guard updated.id == order.id, updated.orderID == order.orderID, updated.branch.id == order.branch.id,
                      updated.version > order.version,
                      updated.problemReports?.contains(where: { $0.reason == reason && $0.statusAtReport == order.status }) == true else {
                    throw FunctionClientError.invalidResponse
                }
            case let .response(offer, accept, minutes):
                let receipt = try await recoveryClient.respond(offerID: offer.id, accept: accept,
                    prepMinutes: minutes, version: offer.version, key: command.key)
                guard receipt.recoveryOpportunityId == offer.id, receipt.recoveryCaseId == offer.recoveryCaseId else {
                    throw FunctionClientError.invalidResponse
                }
                if accept {
                    guard receipt.status == "RECOVERED", receipt.replacementFulfilmentId != nil,
                          receipt.exactSkuId == offer.sku.id, receipt.quantity == offer.requestedQuantity,
                          receipt.additionalCustomerPaymentPaise == 0 else { throw FunctionClientError.invalidResponse }
                } else if receipt.status != "DECLINED" { throw FunctionClientError.invalidResponse }
            }
            try await acknowledgeJournal()
            recoveryCommandMessage = "\(command.description) recorded."
            busyIdentity = nil
            await refreshV1Fulfilments()
            return true
        } catch {
            if await handleJournalFailure(error) {
                recoveryCommandMessage = message(for: error, fallback: "This action was rejected. Review the latest order before trying again.")
            } else {
                recoveryCommandMessage = "The result is uncertain. Retry the pending action with its original details; do not submit a replacement report or response."
            }
            if journalAccountID != nil { await refreshV1Fulfilments() }
            return false
        }
    }

    func canonicalSelection(for sku: DastakV1MerchantCatalogueSnapshot.SKU) -> Bool {
        pendingCanonicalSelections[sku.skuID] ?? sku.selected
    }

    func stageCanonicalSelection(_ sku: DastakV1MerchantCatalogueSnapshot.SKU, branchID: UUID? = nil) {
        guard sku.catalogueStatus == "ACTIVE", !isBusy, retailLocationCurrent else { return }
        guard branchID == nil || branchID == canonicalCatalogue?.branch.branchID else { return }
        let desired = !canonicalSelection(for: sku)
        var next = pendingCanonicalSelections
        if desired == sku.selected { next[sku.skuID] = nil }
        else { next[sku.skuID] = desired }
        pendingCanonicalSelections = next
        errorMessage = nil
    }

    func discardCanonicalSelections() {
        guard !isBusy else { return }
        pendingCanonicalSelections = [:]
    }

    func saveCanonicalSelections() async {
        guard retailLocationCurrent, catalogueRefreshFailure == nil, let snapshot = canonicalCatalogue,
              !pendingCanonicalSelections.isEmpty,
              !isBusy
        else { return }
        guard missingCanonicalSelectionCount == 0 else {
            errorMessage = "Some unsaved selections are outside the loaded catalogue. Refresh to recover those products or explicitly discard the selections; no partial batch was sent."
            return
        }
        let commands = snapshot.skus.compactMap { sku -> DastakV1MerchantSelectionCommand? in
            guard let selected = pendingCanonicalSelections[sku.skuID], selected != sku.selected else { return nil }
            return DastakV1MerchantSelectionCommand(
                skuID: sku.skuID,
                selected: selected,
                expectedVersion: sku.selectionVersion
            )
        }
        guard !commands.isEmpty else {
            discardCanonicalSelections()
            return
        }

        _ = await submitOperation(.selections(branchID: snapshot.branch.branchID, commands))
    }

    var missingCanonicalSelectionCount: Int {
        let known = Set(canonicalCatalogue?.skus.map(\.id) ?? [])
        return pendingCanonicalSelections.keys.filter { !known.contains($0) }.count
    }

    func addCanonicalSKU(_ sku: DastakV1MerchantCatalogueSnapshot.SKU, branchID: UUID? = nil) async -> Bool {
        guard retailLocationCurrent, catalogueRefreshFailure == nil, let snapshot = canonicalCatalogue, !isBusy, !sku.selected,
              sku.catalogueStatus == "ACTIVE", sku.stockQuantity != 0 else { return false }
        guard branchID == nil || branchID == snapshot.branch.branchID else { return false }
        return await submitOperation(.selections(branchID: snapshot.branch.branchID,
            [.init(skuID: sku.id, selected: true, expectedVersion: sku.selectionVersion)]))
    }

    func saveStockCount(_ sku: DastakV1MerchantCatalogueSnapshot.SKU, quantity: Int, branchID: UUID? = nil) async -> Bool {
        guard retailLocationCurrent, catalogueRefreshFailure == nil, let snapshot = canonicalCatalogue, !isBusy, (0...1_000_000).contains(quantity) else { return false }
        guard branchID == nil || branchID == snapshot.branch.branchID else { return false }
        return await submitOperation(.selections(branchID: snapshot.branch.branchID,
            [.init(skuID: sku.id, selected: quantity > 0, expectedVersion: sku.selectionVersion, stockQuantity: quantity)]))
    }

    func setCanonicalBranch(isOpen: Bool, acceptingOrders: Bool, branchID: UUID? = nil) async {
        guard retailLocationCurrent, catalogueRefreshFailure == nil, let snapshot = canonicalCatalogue else { return }
        guard branchID == nil || branchID == snapshot.branch.branchID else { return }
        let state = snapshot.branch.operationalState
        _ = await submitOperation(.operating(branchID: snapshot.branch.branchID, open: isOpen,
            accepting: isOpen && acceptingOrders, version: state.version))
    }

    func refreshOrders() async {
        await restoreMerchantCommands()
        ordersRefreshQueued = true
        guard !ordersRefreshInFlight else { return }
        ordersRefreshInFlight = true
        defer { ordersRefreshInFlight = false }

        var passes = 0
        while ordersRefreshQueued, !Task.isCancelled, passes < 2 {
            passes += 1
            ordersRefreshQueued = false
            let epoch = mutationEpoch
            async let incoming = refreshOpportunities()
            async let restaurant = refreshRestaurantRequests()
            async let current = refreshFulfilments()
            async let legacy = refreshLegacyOrders()
            let failures = await [incoming, restaurant, legacy].compactMap { $0 } + current
            guard epoch == mutationEpoch else { ordersRefreshQueued = true; continue }
            orderRefreshFailures = failures
            if failures.isEmpty { lastOrderRefresh = Date() }
        }
    }

    private func refreshOpportunities() async -> String? {
        let epoch = mutationEpoch
        do {
            let result = try await inboxClient.opportunities(idempotencyKey: makeKey())
            guard epoch == mutationEpoch, !Task.isCancelled else { return nil }
            opportunities = result
            incomingCurrent = true
            isLoading = false
            return nil
        } catch {
            guard epoch == mutationEpoch else { return nil }
            incomingCurrent = false; recordConnectionFailure(error); return "Incoming orders"
        }
    }

    private func refreshRestaurantRequests() async -> String? {
        let epoch = mutationEpoch
        do {
            let result = try await inboxClient.restaurantRequests(idempotencyKey: makeKey())
            guard epoch == mutationEpoch, !Task.isCancelled else { return nil }
            restaurantRequests = result
            foodRequestsCurrent = true
            isLoading = false
            return nil
        } catch {
            guard epoch == mutationEpoch else { return nil }
            foodRequestsCurrent = false; recordConnectionFailure(error); return "Food requests"
        }
    }

    private var currentOperationReadFailures: [String] {
        (fulfilmentsCurrent ? [] : ["Preparation and pickup"])
            + (recoveryCurrent ? [] : ["Exact-item recovery"])
            + (returnsCurrent ? [] : ["Return receipts"])
            + (settlementsCurrent ? [] : ["Settlement status"])
    }

    private func refreshFulfilments() async -> [String] {
        await restoreMerchantCommands()
        let generation = UUID()
        operationReadGeneration = generation
        returnsCurrent = false; settlementsCurrent = false
        do {
            let feeds = try await recoveryClient.feeds(idempotencyKey: makeKey())
            guard operationReadGeneration == generation, !Task.isCancelled else { return currentOperationReadFailures }
            var failures: [String] = []
            if let fulfilments = feeds.fulfilments {
                v1Fulfilments = fulfilments; fulfilmentsCurrent = true
            } else { fulfilmentsCurrent = false; failures.append("Preparation and pickup") }
            if let recovery = feeds.recoveryOpportunities {
                recoveryOpportunities = recovery; recoveryCurrent = true
            } else { recoveryCurrent = false; failures.append("Exact-item recovery") }
            if let receipts = feeds.returnReceipts {
                returnReceipts = receipts; returnsCurrent = true; returnsRefreshedAt = .now
            } else { returnsCurrent = false; failures.append("Return receipts") }
            if let entries = feeds.settlements {
                settlements = entries; settlementsCurrent = true
            } else { settlementsCurrent = false; failures.append("Settlement status") }
            isLoading = false
            return failures
        } catch {
            guard operationReadGeneration == generation else { return currentOperationReadFailures }
            fulfilmentsCurrent = false; recoveryCurrent = false; returnsCurrent = false; settlementsCurrent = false
            recordConnectionFailure(error)
            return currentOperationReadFailures
        }
    }

    /// Reuse the single V1 operations read (fulfilments, recovery, returns and settlements).
    /// This avoids refetching the inbox, food requests and legacy order history
    /// on every rider tracking sample.
    func refreshV1Fulfilments() async {
        let failures = await refreshFulfilments()
        orderRefreshFailures.removeAll { ["Preparation and pickup", "Exact-item recovery", "Return receipts", "Settlement status"].contains($0) }
        orderRefreshFailures.append(contentsOf: failures)
        if failures.isEmpty { lastOrderRefresh = .now }
    }

    private func refreshLegacyOrders() async -> String? {
        let epoch = mutationEpoch
        do {
            let result = try await orderClient.merchantSnapshot(idempotencyKey: makeKey()).orders
            guard epoch == mutationEpoch, !Task.isCancelled else { return nil }
            orders = Self.sorted(result)
            legacyOrdersCurrent = true
            return nil
        } catch {
            guard epoch == mutationEpoch else { return nil }
            legacyOrdersCurrent = false; recordConnectionFailure(error); return "Earlier orders"
        }
    }

    func respondToOpportunity(_ opportunity: DastakV1MerchantOpportunity, accept: Bool, prepMinutes: Int) async {
        guard incomingCurrent, permitsLocation(opportunity.branch.id), opportunities.contains(opportunity), opportunity.status == "OFFERED" else { return }
        _ = await submitOperation(.retailResponse(opportunity, accept: accept, minutes: prepMinutes))
    }

    func respondToRestaurant(_ request: DastakV1RestaurantRequest, accept: Bool, prepMinutes: Int, reason: String?) async {
        guard foodRequestsCurrent, permitsLocation(request.branch.id), restaurantRequests.contains(request), request.status == "OFFERED" else { return }
        _ = await submitOperation(.foodResponse(request, accept: accept, minutes: prepMinutes,
            reason: accept ? nil : reason?.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func declareV1Packages(_ fulfilment: DastakV1MerchantFulfilment, count: Int) async {
        guard DastakMerchantValidation.packageRange.contains(count) else {
            errorMessage = DastakMerchantValidation.packageHelp; return
        }
        guard fulfilmentsCurrent, permitsLocation(fulfilment.branch.id), !recoveryBlocks(fulfilment),
              v1Fulfilments.contains(where: { $0.id == fulfilment.id && $0.version == fulfilment.version }),
              fulfilment.canDeclarePackages else {
            errorMessage = "This order is not ready for package changes. Refresh the order desk and resolve any item recovery first."; return
        }
        _ = await submitOperation(.packages(.init(fulfilment), count: count))
    }

    func addV1ReadyEvidence(
        _ fulfilment: DastakV1MerchantFulfilment,
        data: Data,
        contentType: String,
        fileExtension: String
    ) async {
        guard fulfilmentsCurrent, permitsLocation(fulfilment.branch.id), !recoveryBlocks(fulfilment) else { return }
        guard !data.isEmpty, data.count <= 10 * 1_024 * 1_024 else {
            errorMessage = "Choose a clear Ready photo up to 10 MB."
            return
        }
        guard let account = journalAccountID, ["jpg", "jpeg", "png", "heic"].contains(fileExtension) else { return }
        let path = "merchant-ready/\(account.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension)"
        _ = await submitOperation(.evidence(.init(fulfilment), .init(path: path,
            bucket: "dastak-evidence", data: data, contentType: contentType)))
    }

    func markV1Ready(_ fulfilment: DastakV1MerchantFulfilment) async {
        guard fulfilmentsCurrent, permitsLocation(fulfilment.branch.id), !recoveryBlocks(fulfilment) else { return }
        _ = await submitOperation(.ready(.init(fulfilment)))
    }

    private func isRecoverableOrderConflict(_ error: Error) -> Bool {
        guard case let FunctionClientError.api(_, code, _) = error else { return false }
        return ["invalid_state", "not_found", "stale_version"].contains(code)
    }

    func perform(
        _ action: DastakMerchantOrderAction,
        order: MerchantOrderSnapshot,
        reason: String? = nil
    ) async {
        guard legacyOrdersCurrent, orders.contains(where: { $0.orderID == order.orderID && $0.stateVersion == order.stateVersion }) else { return }
        _ = await submitOperation(.legacyOrder(action, orderID: order.orderID, version: order.stateVersion,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func saveStore(
        name: String,
        address: String,
        location: GeoPoint,
        isPublished: Bool,
        acceptingOrders: Bool
    ) async -> Bool {
        await submitOperation(.legacyStore(name: name, address: address, location: location,
            published: isPublished, accepting: isPublished && acceptingOrders))
    }

    func saveCategory(
        categoryID: UUID?,
        name: String,
        displayOrder: Int,
        isActive: Bool
    ) async -> Bool {
        await submitOperation(.legacyCategory(id: categoryID, name: name, sort: displayOrder, active: isActive))
    }

    func saveProduct(
        _ draft: DastakMerchantProductDraft,
        imageData: Data?,
        imageContentType: String?
    ) async -> Bool {
        guard !isBusy else { return false }
        do {
            let paise = try DastakMerchantPriceParser.paise(from: draft.priceRupees)
            var upload: DastakMerchantOperationCommand.Upload?
            guard (imageData == nil) == (imageContentType == nil) else { throw DastakMerchantValidationError.invalidProductImage }
            if let imageData, let imageContentType {
                guard let account = journalAccountID, let ext = Self.imageExtension(imageContentType),
                      DastakMerchantImageInspector.inspect(imageData)?.contentType == imageContentType else {
                    throw DastakMerchantValidationError.invalidProductImage
                }
                upload = .init(path: "merchant/\(account.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)",
                    bucket: "dastak-catalogue", data: imageData, contentType: imageContentType)
            }
            return await submitOperation(.legacyProduct(draft, paise: paise, upload: upload))
        } catch {
            errorMessage = message(for: error, fallback: "Check the product price and photo before saving.")
            return false
        }
    }

    private func update(_ updated: MerchantOrderSnapshot) {
        if let index = orders.firstIndex(where: { $0.orderID == updated.orderID }) {
            orders[index] = updated
        } else {
            orders.append(updated)
        }
        orders = Self.sorted(orders)
    }

    private func makeKey() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private static func sorted(_ orders: [MerchantOrderSnapshot]) -> [MerchantOrderSnapshot] {
        orders.sorted { ($0.createdAt, $0.orderID.uuidString) > ($1.createdAt, $1.orderID.uuidString) }
    }

    private static func imageExtension(_ contentType: String) -> String? {
        switch contentType.lowercased() {
        case "image/jpeg": "jpg"
        case "image/png": "png"
        case "image/webp": "webp"
        default: nil
        }
    }
}

enum DastakMerchantPriceParser {
    static func paise(from value: String) throws -> Int {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^[0-9]{1,7}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil else {
            throw DastakMerchantValidationError.invalidPrice
        }
        guard let decimal = Decimal(
            string: value.trimmingCharacters(in: .whitespacesAndNewlines),
            locale: Locale(identifier: "en_US_POSIX")
        ), decimal > 0, decimal <= 1_000_000 else {
            throw DastakMerchantValidationError.invalidPrice
        }
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else {
            throw DastakMerchantValidationError.invalidPrice
        }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

private enum DastakMerchantValidationError: Error {
    case invalidPrice
    case invalidProductImage
}

private extension MerchantOrderSnapshot {
    var isFinal: Bool {
        status == .cancelled || status == .delivered
    }
}

private func message(for error: Error, fallback: String) -> String {
    if let error = error as? DastakMerchantStoreReadError { return error.message }
    if let error = error as? FunctionClientError {
        switch error {
        case let .api(_, _, message): return message
        case .authenticationRequired: return "Sign in again to continue."
        case .invalidResponse, .malformedErrorResponse: return fallback
        }
    }
    if let error = error as? DastakMerchantValidationError {
        switch error {
        case .invalidPrice: return DastakMerchantValidation.priceHelp
        case .invalidProductImage: return "Choose a JPG, PNG, or WebP image up to 5 MB."
        }
    }
    return fallback
}
