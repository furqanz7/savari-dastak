import Foundation
import CryptoKit
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakMerchantOrderAction: String {
    case accept
    case ready
    case reject
    case confirmReturn
    case refund
}

struct DastakMerchantProductDraft: Identifiable {
    var id: UUID { productID ?? draftID }
    private let draftID = UUID()
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
    @Published private(set) var recoveryCommandMessage: String?
    @Published private(set) var opportunities: [DastakV1MerchantOpportunity] = []
    @Published private(set) var restaurantRequests: [DastakV1RestaurantRequest] = []
    @Published private(set) var orderRefreshFailures: [String] = []
    @Published private(set) var lastOrderRefresh: Date?
    let notifications: DastakMerchantNotifications
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var canonicalCatalogue: DastakV1MerchantCatalogueSnapshot?
    @Published private(set) var canonicalBrowseMap: DastakV1CatalogueBrowseMap?
    @Published private(set) var restaurantMenu: DastakV1RestaurantMenu?
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
    private let journalStorage: any DastakMerchantJournalStorage
    private var journalAccountID: UUID?

    private let services: MarketplaceAuthenticatedServices
    private let orderClient: any MerchantOrderClient
    private let catalogueClient: any CatalogueClient
    private let checkoutClient: any DastakCheckoutClient
    private let earningsClient: any DastakEarningsClient
    private let v1Client: any DastakV1MerchantClient
    private let inboxClient: any DastakV1MerchantInboxClient
    private var readyEvidencePaths: [String: String] = [:]
    private var actionKeys: [String: IdempotencyKey] = [:]
    private var ordersRefreshInFlight = false
    private var ordersRefreshQueued = false
    private var canonicalSelectionSaveKey: IdempotencyKey?
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
        journalStorage: any DastakMerchantJournalStorage = DastakMerchantFileJournal.shared
    ) {
        self.services = services
        self.journalStorage = journalStorage
        self.recoveryClient = SupabaseDastakV1MerchantRecoveryClient(functions: services.functions)
        self.notifications = DastakMerchantNotifications(functions: services.functions)
        self.orderClient = orderClient
        self.catalogueClient = catalogueClient
        self.checkoutClient = checkoutClient
        self.earningsClient = earningsClient
        self.v1Client = v1Client
        self.inboxClient = inboxClient ?? SupabaseDastakV1MerchantInboxClient(functions: services.functions)
    }

    convenience init(services: MarketplaceAuthenticatedServices, journalStorage: any DastakMerchantJournalStorage = DastakMerchantFileJournal.shared) {
        self.init(
            services: services,
            orderClient: SupabaseMerchantOrderClient(functions: services.functions),
            catalogueClient: SupabaseCatalogueClient(functions: services.functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: services.functions),
            earningsClient: SupabaseDastakEarningsClient(functions: services.functions),
            v1Client: SupabaseDastakV1MerchantClient(functions: services.functions),
            journalStorage: journalStorage
        )
    }

    var activeOrders: [MerchantOrderSnapshot] {
        orders.filter { !$0.isFinal }
    }

    var recentOrders: [MerchantOrderSnapshot] {
        Array(orders.filter(\.isFinal).prefix(10))
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
        busyIdentity != nil || !merchantJournalRestored || merchantJournal != nil
    }

    func restoreMerchantCommands() async {
        guard !merchantJournalRestored, !isRestoringMerchantJournal, busyIdentity == nil else { return }
        isRestoringMerchantJournal = true; defer { isRestoringMerchantJournal = false }
        do {
            let account = try await services.accountID()
            let saved = try await journalStorage.load(account)
            guard try await services.accountID() == account else { throw DastakAdminExecutionError.changed }
            journalAccountID = account; merchantJournal = saved; merchantJournalRestored = true
            adoptJournal(saved)
            merchantJournalMessage = saved == nil ? nil : "A saved Merchant action needs recovery. Other Merchant changes stay paused until the original action is resolved."
        } catch { merchantJournalMessage = "Merchant recovery storage could not be read. Editing stays locked; no saved request was removed." }
    }
    private func adoptJournal(_ saved: DastakMerchantJournalRecord?) {
        pendingRecoveryCommand = nil; pendingRestaurantCommand = nil
        if let saved { switch saved.command { case let .recovery(value): pendingRecoveryCommand = value; case let .restaurant(value): pendingRestaurantCommand = value } }
    }
    private func secureJournal(_ command: DastakMerchantJournalRecord.Command) async -> Bool {
        guard merchantJournalRestored, merchantJournal == nil, command.valid, let account = journalAccountID else { return false }
        let saved = DastakMerchantJournalRecord(accountID: account, command: command)
        do {
            try await requireJournalAccount(account)
            try await journalStorage.replace(saved, accountID: account, expectedRevision: nil)
            merchantJournal = saved; adoptJournal(saved)
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
        guard try await journalStorage.load(account) == saved else { throw DastakAdminExecutionError.changed }
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
        guard try await services.accountID() == account else {
            // Clear presentation only; the original actor's unresolved file remains intact.
            merchantJournal = nil; journalAccountID = nil; merchantJournalRestored = false; adoptJournal(nil)
            orders = []; v1Fulfilments = []; recoveryOpportunities = []; opportunities = []; restaurantRequests = []
            returnReceipts = []; settlements = []; restaurantMenu = nil; catalogue = nil; canonicalCatalogue = nil
            canonicalBrowseMap = nil; earnings = nil; pendingCanonicalSelections = [:]
            fulfilmentsCurrent = false; recoveryCurrent = false; returnsCurrent = false; settlementsCurrent = false
            needsRestaurantRefresh = true; operationReadGeneration = UUID(); restaurantRefreshGeneration = UUID()
            throw MarketplaceAuthenticatedServicesError.identityMismatch
        }
    }
    private func handleJournalFailure(_ error: Error) async -> Bool {
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
        else { await restoreMerchantCommands() }
    }

    var restaurantChangesDisabled: Bool {
        isBusy || isRefreshingRestaurant || needsRestaurantRefresh || pendingRestaurantCommand != nil
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
        if let snapshot = try? await catalogueClient.merchantSnapshot(idempotencyKey: makeKey()) {
            catalogue = snapshot
        }
        async let retail: Void = refreshCanonicalCatalogue(reportFailure: false)
        async let restaurant = refreshRestaurantMenu(reportFailure: false)
        _ = await (retail, restaurant)
    }

    private func refreshEarnings() async {
        if let snapshot = try? await earningsClient.merchantSnapshot(idempotencyKey: makeKey()) {
            earnings = snapshot
        }
    }

    func refreshCanonicalCatalogue(reportFailure: Bool = true) async {
        do {
            let browseMap = try await v1Client.catalogueBrowseMap(idempotencyKey: makeKey())
            guard browseMap?.isValid != false else { throw DastakV1BrowseLoadError.invalidMap }
            let refreshed = try await v1Client.canonicalCatalogue(
                branchID: canonicalCatalogue?.branch.branchID,
                limit: 5_000,
                idempotencyKey: makeKey()
            )
            canonicalCatalogue = refreshed
            canonicalBrowseMap = browseMap
            pendingCanonicalSelections = pendingCanonicalSelections.filter { skuID, desired in
                refreshed.skus.first(where: { $0.skuID == skuID })?.selected != desired
            }
            if pendingCanonicalSelections.isEmpty { canonicalSelectionSaveKey = nil }
            if reportFailure { errorMessage = nil }
        } catch {
            if reportFailure,
               !String(describing: error).localizedCaseInsensitiveContains("retail-only")
            {
                errorMessage = message(for: error, fallback: "The store catalogue could not be refreshed.")
            }
        }
    }

    @discardableResult
    func refreshRestaurantMenu(reportFailure: Bool = true) async -> Bool {
        await restoreMerchantCommands()
        return await loadRestaurantMenu(reportFailure: reportFailure, duringCommand: false)
    }

    private func loadRestaurantMenu(reportFailure: Bool, duringCommand: Bool) async -> Bool {
        guard !isExecutingRestaurantCommand || duringCommand else { return false }
        let generation = UUID()
        restaurantRefreshGeneration = generation
        let branchID = pendingRestaurantCommand?.branchID ?? restaurantMenu?.restaurant.branchID
        isRefreshingRestaurant = true
        needsRestaurantRefresh = true
        defer { if restaurantRefreshGeneration == generation { isRefreshingRestaurant = false } }
        do {
            let refreshed = try await v1Client.restaurantMenu(branchID: branchID, idempotencyKey: makeKey())
            guard branchID == nil || refreshed.restaurant.branchID == branchID,
                  refreshed.restaurant.operationalVersion.map({ $0 >= 0 }) != false else {
                throw FunctionClientError.invalidResponse
            }
            guard restaurantRefreshGeneration == generation, !Task.isCancelled else { return false }
            restaurantMenu = refreshed
            restaurantRefreshFailure = nil
            needsRestaurantRefresh = false
            if reportFailure { errorMessage = nil }
            return true
        } catch {
            guard restaurantRefreshGeneration == generation else { return false }
            restaurantRefreshFailure = "Restaurant details could not be refreshed. Any displayed details may be outdated. Refresh before making changes."
            if reportFailure { errorMessage = message(for: error, fallback: restaurantRefreshFailure!) }
            return false
        }
    }

    func saveRestaurantEntity(entityID: UUID?, expectedVersion: Int, payload: DastakV1RestaurantMenuPayload) async -> Bool {
        guard !restaurantChangesDisabled, let menu = restaurantMenu else { return false }
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
        guard !restaurantChangesDisabled, let menu = restaurantMenu else { return false }
        guard !data.isEmpty, data.count <= 5 * 1_024 * 1_024,
              ["image/jpeg", "image/png", "image/webp"].contains(contentType) else {
            errorMessage = "Choose a clear JPG, PNG or WebP image up to 5 MB."
            return false
        }
        let currentVersion: Int?
        if entityType == "RESTAURANT_BRANCH_BANNER", entityID == menu.restaurant.branchID {
            currentVersion = menu.restaurant.mediaVersion ?? 1
        } else if entityType == "RESTAURANT_MENU_ITEM" {
            currentVersion = menu.categories.lazy.flatMap(\.items).first { $0.id == entityID }.map { $0.mediaVersion ?? 1 }
        } else { currentVersion = nil }
        guard currentVersion == expectedMediaVersion, (0..<Int.max).contains(expectedMediaVersion) else { return false }
        busyIdentity = "securing-restaurant-command"
        let secured = await secureJournal(.restaurant(.init(branchID: menu.restaurant.branchID, key: makeKey(),
            operation: .media(entityType: entityType, entityID: entityID, expectedVersion: expectedMediaVersion,
                              data: data, contentType: contentType, fileName: fileName))))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRestaurantCommand()
    }

    @discardableResult
    func setRestaurantOperatingState(isOpen: Bool, acceptingOrders: Bool) async -> Bool {
        guard canChangeRestaurantOperatingState, let restaurant = restaurantMenu?.restaurant,
              let version = restaurant.operationalVersion else { return false }
        busyIdentity = "securing-restaurant-command"
        let secured = await secureJournal(.restaurant(.init(branchID: restaurant.branchID, key: makeKey(), operation: .operating(isOpen: isOpen, acceptingOrders: isOpen && acceptingOrders, expectedVersion: version))))
        busyIdentity = nil
        guard secured else { return false }
        return await retryRestaurantCommand()
    }

    @discardableResult
    func retryRestaurantCommand() async -> Bool {
        guard busyIdentity == nil, merchantJournalRestored, !isExecutingRestaurantCommand, let command = pendingRestaurantCommand else { return false }
        busyIdentity = "restaurant-command"
        isExecutingRestaurantCommand = true
        restaurantRefreshGeneration = UUID() // Invalidate an older, pre-mutation read.
        isRefreshingRestaurant = false
        needsRestaurantRefresh = true
        notice = nil
        errorMessage = nil
        defer { busyIdentity = nil; isExecutingRestaurantCommand = false }
        do {
            guard try await prepareJournalAttempt() else {
                _ = await loadRestaurantMenu(reportFailure: false, duringCommand: true)
                return true
            }
            switch command.operation {
            case let .menu(entityID, version, payload):
                let result = try await v1Client.upsertRestaurantMenuEntity(branchID: command.branchID,
                    entityID: entityID, expectedVersion: version, payload: payload, idempotencyKey: command.key)
                guard result.menu.restaurant.branchID == command.branchID, result.entityType == payload.entityType,
                      entityID == nil || result.entityID == entityID,
                      result.menu.entityVersion(type: payload.entityType, id: result.entityID).map({ $0 > version }) == true else {
                    throw FunctionClientError.invalidResponse
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
            try await acknowledgeJournal()
            notice = "\(command.description) saved."
            // An acknowledged save and a failed subsequent read are different outcomes.
            _ = await loadRestaurantMenu(reportFailure: false, duringCommand: true)
            return true
        } catch {
            if await handleJournalFailure(error) {
                errorMessage = message(for: error, fallback: "The change was rejected. Refresh and review the latest details.")
            } else {
                errorMessage = "This change has not been confirmed. Check the pending action in Store and retry its original details before making another change."
            }
            _ = await loadRestaurantMenu(reportFailure: false, duringCommand: true)
            return false
        }
    }

    var recoveryActionsDisabled: Bool { isBusy || !recoveryCurrent || pendingRecoveryCommand != nil }

    func recoveryBlocks(_ fulfilment: DastakV1MerchantFulfilment) -> Bool {
        pendingRecoveryCommand?.orderID == fulfilment.orderID
    }

    func canReportProblem(_ fulfilment: DastakV1MerchantFulfilment) -> Bool {
        fulfilmentsCurrent && !isBusy && pendingRecoveryCommand == nil && fulfilment.version > 0
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
        guard !recoveryActionsDisabled, recoveryOpportunities.contains(offer), offer.status == "OFFERED",
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
        busyIdentity = "recovery-command"
        operationReadGeneration = UUID()
        fulfilmentsCurrent = false; recoveryCurrent = false
        recoveryCommandMessage = nil
        defer { busyIdentity = nil }
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
            await refreshV1Fulfilments()
            return true
        } catch {
            if await handleJournalFailure(error) {
                recoveryCommandMessage = message(for: error, fallback: "This action was rejected. Review the latest order before trying again.")
            } else {
                recoveryCommandMessage = "The result is uncertain. Retry the pending action with its original details; do not submit a replacement report or response."
            }
            await refreshV1Fulfilments()
            return false
        }
    }

    func canonicalSelection(for sku: DastakV1MerchantCatalogueSnapshot.SKU) -> Bool {
        pendingCanonicalSelections[sku.skuID] ?? sku.selected
    }

    func stageCanonicalSelection(_ sku: DastakV1MerchantCatalogueSnapshot.SKU) {
        guard sku.catalogueStatus == "ACTIVE", busyIdentity != "canonical-catalogue-save" else { return }
        let desired = !canonicalSelection(for: sku)
        var next = pendingCanonicalSelections
        if desired == sku.selected { next[sku.skuID] = nil }
        else { next[sku.skuID] = desired }
        pendingCanonicalSelections = next
        canonicalSelectionSaveKey = nil
        errorMessage = nil
    }

    func discardCanonicalSelections() {
        pendingCanonicalSelections = [:]
        canonicalSelectionSaveKey = nil
    }

    func saveCanonicalSelections() async {
        guard let snapshot = canonicalCatalogue,
              !pendingCanonicalSelections.isEmpty,
              !isBusy
        else { return }
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

        busyIdentity = "canonical-catalogue-save"
        errorMessage = nil
        let saveKey = canonicalSelectionSaveKey ?? makeKey()
        canonicalSelectionSaveKey = saveKey
        defer { busyIdentity = nil }
        do {
            _ = try await v1Client.updateCatalogueSelections(
                branchID: snapshot.branch.branchID,
                selections: commands,
                idempotencyKey: saveKey
            )
            pendingCanonicalSelections = [:]
            canonicalSelectionSaveKey = nil
            await refreshCanonicalCatalogue()
            notice = "\(commands.count) storefront \(commands.count == 1 ? "change" : "changes") saved."
        } catch {
            errorMessage = message(for: error, fallback: "The storefront changes could not be saved.")
            await refreshCanonicalCatalogue(reportFailure: false)
        }
    }

    func addCanonicalSKU(_ sku: DastakV1MerchantCatalogueSnapshot.SKU) async -> Bool {
        guard let snapshot = canonicalCatalogue, !isBusy, !sku.selected,
              sku.catalogueStatus == "ACTIVE", sku.stockQuantity != 0 else { return false }
        busyIdentity = "add-sku:\(sku.id)"
        errorMessage = nil
        defer { busyIdentity = nil }
        do {
            _ = try await v1Client.updateCatalogueSelections(
                branchID: snapshot.branch.branchID,
                selections: [.init(skuID: sku.id, selected: true, expectedVersion: sku.selectionVersion)],
                idempotencyKey: makeKey()
            )
            pendingCanonicalSelections.removeValue(forKey: sku.id)
            canonicalSelectionSaveKey = nil
            await refreshCanonicalCatalogue()
            return canonicalCatalogue?.skus.first(where: { $0.id == sku.id })?.selected == true
        } catch {
            errorMessage = message(for: error, fallback: "The product could not be added. Please try again.")
            await refreshCanonicalCatalogue(reportFailure: false)
            return false
        }
    }

    func saveStockCount(_ sku: DastakV1MerchantCatalogueSnapshot.SKU, quantity: Int) async -> Bool {
        guard let snapshot = canonicalCatalogue, !isBusy, (0...1_000_000).contains(quantity) else { return false }
        busyIdentity = "stock:\(sku.id)"
        errorMessage = nil
        defer { busyIdentity = nil }
        do {
            _ = try await v1Client.updateCatalogueSelections(
                branchID: snapshot.branch.branchID,
                selections: [.init(skuID: sku.id, selected: quantity > 0, expectedVersion: sku.selectionVersion, stockQuantity: quantity)],
                idempotencyKey: makeKey()
            )
            pendingCanonicalSelections.removeValue(forKey: sku.id)
            canonicalSelectionSaveKey = nil
            await refreshCanonicalCatalogue()
            notice = "Stock count saved."
            return true
        } catch {
            errorMessage = message(for: error, fallback: "Stock could not be saved. Check the latest count and try again.")
            await refreshCanonicalCatalogue(reportFailure: false)
            return false
        }
    }

    func setCanonicalBranch(isOpen: Bool, acceptingOrders: Bool) async {
        guard let snapshot = canonicalCatalogue else { return }
        let state = snapshot.branch.operationalState
        let identity = "canonical-branch:\(state.version):\(isOpen):\(acceptingOrders)"
        guard !isBusy else { return }
        busyIdentity = identity
        defer { busyIdentity = nil }
        do {
            _ = try await v1Client.updateBranchState(
                branchID: snapshot.branch.branchID,
                isOpen: isOpen,
                acceptingOrders: isOpen && acceptingOrders,
                expectedVersion: state.version,
                idempotencyKey: actionKey(for: identity)
            )
            actionKeys[identity] = nil
            await refreshCanonicalCatalogue()
            notice = isOpen ? (acceptingOrders ? "Store is accepting orders." : "New orders are paused.") : "Store is closed."
        } catch {
            errorMessage = message(for: error, fallback: "The store status could not be updated.")
            await refreshCanonicalCatalogue(reportFailure: false)
        }
    }

    func refreshOrders() async {
        await restoreMerchantCommands()
        ordersRefreshQueued = true
        guard !ordersRefreshInFlight else { return }
        ordersRefreshInFlight = true
        defer { ordersRefreshInFlight = false }

        while ordersRefreshQueued, !Task.isCancelled {
            ordersRefreshQueued = false
            async let incoming = refreshOpportunities()
            async let restaurant = refreshRestaurantRequests()
            async let current = refreshFulfilments()
            async let legacy = refreshLegacyOrders()
            let failures = await [incoming, restaurant, legacy].compactMap { $0 } + current
            orderRefreshFailures = failures
            if failures.isEmpty { lastOrderRefresh = Date() }
        }
    }

    private func refreshOpportunities() async -> String? {
        do {
            opportunities = try await inboxClient.opportunities(idempotencyKey: makeKey())
            isLoading = false
            return nil
        } catch { return "Incoming orders" }
    }

    private func refreshRestaurantRequests() async -> String? {
        do {
            restaurantRequests = try await inboxClient.restaurantRequests(idempotencyKey: makeKey())
            isLoading = false
            return nil
        } catch { return "Food requests" }
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
        fulfilmentsCurrent = false
        recoveryCurrent = false
        returnsCurrent = false
        settlementsCurrent = false
        do {
            let feeds = try await recoveryClient.feeds(idempotencyKey: makeKey())
            guard operationReadGeneration == generation, !Task.isCancelled else { return currentOperationReadFailures }
            var failures: [String] = []
            if let fulfilments = feeds.fulfilments {
                v1Fulfilments = fulfilments; fulfilmentsCurrent = true
            } else { failures.append("Preparation and pickup") }
            if let recovery = feeds.recoveryOpportunities {
                recoveryOpportunities = recovery; recoveryCurrent = true
            } else { failures.append("Exact-item recovery") }
            if let receipts = feeds.returnReceipts {
                returnReceipts = receipts; returnsCurrent = true; returnsRefreshedAt = .now
            } else { failures.append("Return receipts") }
            if let entries = feeds.settlements {
                settlements = entries; settlementsCurrent = true
            } else { failures.append("Settlement status") }
            isLoading = false
            return failures
        } catch {
            guard operationReadGeneration == generation else { return currentOperationReadFailures }
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
        do {
            orders = Self.sorted(try await orderClient.merchantSnapshot(idempotencyKey: makeKey()).orders)
            return nil
        } catch { return "Earlier orders" }
    }

    func respondToOpportunity(_ opportunity: DastakV1MerchantOpportunity, accept: Bool, prepMinutes: Int) async {
        let identity = "opportunity:\(opportunity.id):\(opportunity.version):\(accept):\(prepMinutes)"
        await respondToIncoming(identity: identity) {
            let updated = try await self.inboxClient.respond(
                opportunity: opportunity, accept: accept, prepMinutes: prepMinutes,
                idempotencyKey: self.actionKey(for: identity)
            )
            self.opportunities = self.opportunities.map { $0.id == updated.id ? updated : $0 }
        }
    }

    func respondToRestaurant(_ request: DastakV1RestaurantRequest, accept: Bool, prepMinutes: Int, reason: String?) async {
        let identity = "restaurant:\(request.id):\(request.version):\(accept):\(prepMinutes):\(reason ?? "")"
        await respondToIncoming(identity: identity) {
            let updated = try await self.inboxClient.respond(
                request: request, accept: accept, prepMinutes: prepMinutes, reason: reason,
                idempotencyKey: self.actionKey(for: identity)
            )
            self.restaurantRequests = self.restaurantRequests.map { $0.id == updated.id ? updated : $0 }
        }
    }

    private func respondToIncoming(identity: String, operation: () async throws -> Void) async {
        guard !isBusy else { return }
        busyIdentity = identity
        defer { busyIdentity = nil }
        do {
            try await operation()
            actionKeys[identity] = nil
            notice = "Response saved. The order status has been refreshed."
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, fallback: "The request changed or could not be updated. Review the refreshed order before retrying.")
        }
        await refreshOrders()
    }

    func declareV1Packages(_ fulfilment: DastakV1MerchantFulfilment, count: Int) async {
        guard fulfilmentsCurrent, !recoveryBlocks(fulfilment) else { return }
        await performV1(identity: "packages:\(fulfilment.id):\(fulfilment.version):\(count)") {
            try await self.v1Client.declarePackages(
                fulfilmentID: fulfilment.id,
                packageCount: count,
                expectedVersion: fulfilment.version,
                idempotencyKey: self.actionKey(for: "packages:\(fulfilment.id):\(fulfilment.version):\(count)")
            )
        }
    }

    func addV1ReadyEvidence(
        _ fulfilment: DastakV1MerchantFulfilment,
        data: Data,
        contentType: String,
        fileExtension: String
    ) async {
        guard fulfilmentsCurrent, !recoveryBlocks(fulfilment) else { return }
        guard !data.isEmpty, data.count <= 10 * 1_024 * 1_024 else {
            errorMessage = "Choose a clear Ready photo up to 10 MB."
            return
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let identity = "evidence:\(fulfilment.id):\(fulfilment.version):\(digest)"
        await performV1(identity: identity) {
            let accountID = try await self.services.accountID()
            let path: String
            if let uploaded = self.readyEvidencePaths[identity] {
                path = uploaded
            } else {
                path = "merchant-ready/\(accountID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension)"
                try await self.services.uploadObject(
                    bucket: "dastak-evidence", path: path, data: data, contentType: contentType
                )
                self.readyEvidencePaths[identity] = path
            }
            return try await self.v1Client.addEvidence(
                fulfilmentID: fulfilment.id,
                objectPath: path,
                expectedVersion: fulfilment.version,
                idempotencyKey: self.actionKey(for: identity)
            )
        }
    }

    func markV1Ready(_ fulfilment: DastakV1MerchantFulfilment) async {
        guard fulfilmentsCurrent, !recoveryBlocks(fulfilment) else { return }
        let identity = "ready:\(fulfilment.id):\(fulfilment.version)"
        await performV1(identity: identity) {
            try await self.v1Client.markReady(
                fulfilmentID: fulfilment.id,
                expectedVersion: fulfilment.version,
                idempotencyKey: self.actionKey(for: identity)
            )
        }
    }

    private func performV1(
        identity: String,
        operation: () async throws -> DastakV1MerchantFulfilment
    ) async {
        guard !isBusy else { return }
        busyIdentity = identity
        defer { busyIdentity = nil }
        do {
            let updated = try await operation()
            v1Fulfilments = [updated] + v1Fulfilments.filter { $0.id != updated.id }
            actionKeys[identity] = nil
            errorMessage = nil
            notice = updated.status == "READY"
                ? "Ready recorded. The delivery partner can now complete pickup."
                : "Preparation evidence saved."
        } catch {
            if isRecoverableOrderConflict(error) {
                actionKeys[identity] = nil
                errorMessage = nil
                await refreshOrders()
                notice = "This order changed while you were working. The latest status is now shown."
            } else {
                errorMessage = message(for: error, fallback: "The fulfilment could not be updated.")
                await refreshOrders()
            }
        }
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
        let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = [
            action.rawValue,
            order.orderID.uuidString,
            String(order.stateVersion),
            normalizedReason ?? ""
        ].joined(separator: ":")
        guard !isBusy else { return }
        busyIdentity = identity
        defer { busyIdentity = nil }

        do {
            let updated: MerchantOrderSnapshot
            switch action {
            case .accept:
                updated = try await orderClient.merchantAccept(
                    orderID: order.orderID,
                    idempotencyKey: actionKey(for: identity)
                )
            case .ready:
                updated = try await orderClient.merchantMarkReady(
                    orderID: order.orderID,
                    idempotencyKey: actionKey(for: identity)
                )
            case .reject:
                guard let normalizedReason, !normalizedReason.isEmpty else { return }
                updated = try await orderClient.merchantReject(
                    orderID: order.orderID,
                    reason: normalizedReason,
                    idempotencyKey: actionKey(for: identity)
                )
            case .confirmReturn:
                updated = try await orderClient.merchantConfirmReturn(
                    orderID: order.orderID,
                    reason: normalizedReason ?? "Returned items received by merchant",
                    idempotencyKey: actionKey(for: identity)
                )
            case .refund:
                _ = try await checkoutClient.processMerchantOrderRefund(
                    orderID: order.orderID,
                    idempotencyKey: actionKey(for: identity)
                )
                actionKeys[identity] = nil
                await refreshOrders()
                return
            }

            update(updated)
            actionKeys[identity] = nil
            if updated.paymentState == .refundPending,
               action == .reject || action == .confirmReturn
            {
                _ = try await checkoutClient.processMerchantOrderRefund(
                    orderID: updated.orderID,
                    idempotencyKey: makeKey()
                )
                await refreshOrders()
            }
            errorMessage = nil
        } catch {
            errorMessage = message(for: error, fallback: "The order could not be updated.")
        }
    }

    func saveStore(
        name: String,
        address: String,
        location: GeoPoint,
        isPublished: Bool,
        acceptingOrders: Bool
    ) async -> Bool {
        await mutation("store") {
            _ = try await catalogueClient.upsertStore(
                name: name,
                address: address,
                location: location,
                isPublished: isPublished,
                acceptingOrders: isPublished && acceptingOrders,
                idempotencyKey: makeKey()
            )
            try await reloadCatalogue()
            notice = "Store settings saved."
        }
    }

    func saveCategory(
        categoryID: UUID?,
        name: String,
        displayOrder: Int,
        isActive: Bool
    ) async -> Bool {
        await mutation("category:\(categoryID?.uuidString ?? "new")") {
            _ = try await catalogueClient.upsertCategory(
                categoryID: categoryID,
                name: name,
                displayOrder: displayOrder,
                isActive: isActive,
                idempotencyKey: makeKey()
            )
            try await reloadCatalogue()
            notice = "Category saved."
        }
    }

    func saveProduct(
        _ draft: DastakMerchantProductDraft,
        imageData: Data?,
        imageContentType: String?
    ) async -> Bool {
        await mutation("product:\(draft.productID?.uuidString ?? "new")") {
            let paise = try DastakMerchantPriceParser.paise(from: draft.priceRupees)
            var imagePath = draft.imageObjectPath
            if let imageData, let imageContentType {
                imagePath = try await uploadProductImage(
                    imageData,
                    contentType: imageContentType
                )
            }
            _ = try await catalogueClient.upsertProduct(
                productID: draft.productID,
                categoryID: draft.categoryID,
                name: draft.name,
                description: draft.description.isEmpty ? nil : draft.description,
                unitLabel: draft.unitLabel,
                price: Money(paise: paise),
                imageObjectPath: imagePath,
                availability: draft.availability,
                catalogueKind: draft.catalogueKind,
                isActive: draft.isActive,
                idempotencyKey: makeKey()
            )
            try await reloadCatalogue()
            notice = "Product saved."
        }
    }

    private func mutation(
        _ identity: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isBusy else { return false }
        busyIdentity = identity
        notice = nil
        errorMessage = nil
        defer { busyIdentity = nil }
        do {
            try await operation()
            return true
        } catch {
            errorMessage = message(for: error, fallback: "The change could not be saved.")
            return false
        }
    }

    private func reloadCatalogue() async throws {
        catalogue = try await catalogueClient.merchantSnapshot(idempotencyKey: makeKey())
    }

    private func uploadProductImage(
        _ data: Data,
        contentType: String
    ) async throws -> String {
        guard data.count <= 5 * 1_024 * 1_024,
              let fileExtension = Self.imageExtension(contentType)
        else {
            throw DastakMerchantValidationError.invalidProductImage
        }
        let accountID = try await services.accountID()
        let path = "merchant/\(accountID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension)"
        try await services.uploadObject(
            bucket: "dastak-catalogue",
            path: path,
            data: data,
            contentType: contentType
        )
        return path
    }

    private func update(_ updated: MerchantOrderSnapshot) {
        if let index = orders.firstIndex(where: { $0.orderID == updated.orderID }) {
            orders[index] = updated
        } else {
            orders.append(updated)
        }
        orders = Self.sorted(orders)
    }

    private func actionKey(for identity: String) -> IdempotencyKey {
        if let key = actionKeys[identity] {
            return key
        }
        let key = makeKey()
        actionKeys[identity] = key
        return key
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
    if let error = error as? FunctionClientError {
        switch error {
        case let .api(_, _, message): return message
        case .authenticationRequired: return "Sign in again to continue."
        case .invalidResponse, .malformedErrorResponse: return fallback
        }
    }
    if let error = error as? DastakMerchantValidationError {
        switch error {
        case .invalidPrice: return "Enter a valid product price."
        case .invalidProductImage: return "Choose a JPG, PNG, or WebP image up to 5 MB."
        }
    }
    return fallback
}
