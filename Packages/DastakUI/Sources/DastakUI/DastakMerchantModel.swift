import Foundation
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
    @Published private(set) var catalogue: CatalogueSnapshot?
    @Published private(set) var canonicalCatalogue: DastakV1MerchantCatalogueSnapshot?
    @Published private(set) var earnings: DastakEarningsSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var busyIdentity: String?
    @Published var errorMessage: String?
    @Published var notice: String?

    private let services: MarketplaceAuthenticatedServices
    private let orderClient: any MerchantOrderClient
    private let catalogueClient: any CatalogueClient
    private let checkoutClient: any DastakCheckoutClient
    private let earningsClient: any DastakEarningsClient
    private let v1Client: any DastakV1MerchantClient
    private var actionKeys: [String: IdempotencyKey] = [:]
    private var ordersRefreshInFlight = false
    private var ordersRefreshQueued = false

    init(
        services: MarketplaceAuthenticatedServices,
        orderClient: any MerchantOrderClient,
        catalogueClient: any CatalogueClient,
        checkoutClient: any DastakCheckoutClient,
        earningsClient: any DastakEarningsClient,
        v1Client: any DastakV1MerchantClient
    ) {
        self.services = services
        self.orderClient = orderClient
        self.catalogueClient = catalogueClient
        self.checkoutClient = checkoutClient
        self.earningsClient = earningsClient
        self.v1Client = v1Client
    }

    convenience init(services: MarketplaceAuthenticatedServices) {
        self.init(
            services: services,
            orderClient: SupabaseMerchantOrderClient(functions: services.functions),
            catalogueClient: SupabaseCatalogueClient(functions: services.functions),
            checkoutClient: SupabaseDastakCheckoutClient(functions: services.functions),
            earningsClient: SupabaseDastakEarningsClient(functions: services.functions),
            v1Client: SupabaseDastakV1MerchantClient(functions: services.functions)
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
        busyIdentity != nil
    }

    func bootstrap() async {
        await refreshAll()
        isLoading = false
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let orders = orderClient.merchantSnapshot(idempotencyKey: makeKey())
            async let catalogue = catalogueClient.merchantSnapshot(idempotencyKey: makeKey())
            async let earnings = earningsClient.merchantSnapshot(idempotencyKey: makeKey())
            async let v1 = v1Client.fulfilments(limit: 50, idempotencyKey: makeKey())
            let result = try await (orders, catalogue, earnings, v1)
            self.orders = Self.sorted(result.0.orders)
            self.catalogue = result.1
            self.earnings = result.2
            v1Fulfilments = result.3
            errorMessage = nil
            await refreshCanonicalCatalogue(reportFailure: false)
        } catch {
            errorMessage = message(for: error, fallback: "Merchant information could not be refreshed.")
        }
    }

    func refreshCanonicalCatalogue(reportFailure: Bool = true) async {
        do {
            canonicalCatalogue = try await v1Client.canonicalCatalogue(
                branchID: canonicalCatalogue?.branch.branchID,
                limit: 1_000,
                idempotencyKey: makeKey()
            )
            if reportFailure { errorMessage = nil }
        } catch {
            canonicalCatalogue = nil
            if reportFailure,
               !String(describing: error).localizedCaseInsensitiveContains("retail-only")
            {
                errorMessage = message(for: error, fallback: "The store catalogue could not be refreshed.")
            }
        }
    }

    func setCanonicalSelection(_ sku: DastakV1MerchantCatalogueSnapshot.SKU) async {
        guard let snapshot = canonicalCatalogue else { return }
        let identity = "canonical-sku:\(sku.skuID):\(sku.selectionVersion):\(!sku.selected)"
        guard !isBusy else { return }
        busyIdentity = identity
        defer { busyIdentity = nil }
        do {
            _ = try await v1Client.updateCatalogueSelection(
                branchID: snapshot.branch.branchID,
                skuID: sku.skuID,
                selected: !sku.selected,
                expectedVersion: sku.selectionVersion,
                idempotencyKey: actionKey(for: identity)
            )
            actionKeys[identity] = nil
            await refreshCanonicalCatalogue()
            notice = sku.selected ? "Removed from your storefront." : "Added to your storefront."
        } catch {
            errorMessage = message(for: error, fallback: "The storefront selection could not be saved.")
            await refreshCanonicalCatalogue(reportFailure: false)
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
        ordersRefreshQueued = true
        guard !ordersRefreshInFlight else { return }
        ordersRefreshInFlight = true
        defer { ordersRefreshInFlight = false }

        while ordersRefreshQueued, !Task.isCancelled {
            ordersRefreshQueued = false
            do {
                async let legacy = orderClient.merchantSnapshot(idempotencyKey: makeKey())
                async let current = v1Client.fulfilments(limit: 50, idempotencyKey: makeKey())
                let result = try await (legacy, current)
                orders = Self.sorted(result.0.orders)
                v1Fulfilments = result.1
                errorMessage = nil
            } catch {
                errorMessage = message(for: error, fallback: "Orders could not be refreshed.")
            }
        }
    }

    func declareV1Packages(_ fulfilment: DastakV1MerchantFulfilment, count: Int) async {
        await performV1(identity: "packages:\(fulfilment.id):\(count)") {
            try await self.v1Client.declarePackages(
                fulfilmentID: fulfilment.id,
                packageCount: count,
                expectedVersion: fulfilment.version,
                idempotencyKey: self.actionKey(for: "packages:\(fulfilment.id):\(count)")
            )
        }
    }

    func addV1ReadyEvidence(
        _ fulfilment: DastakV1MerchantFulfilment,
        data: Data,
        contentType: String,
        fileExtension: String
    ) async {
        guard !data.isEmpty, data.count <= 10 * 1_024 * 1_024 else {
            errorMessage = "Choose a clear Ready photo up to 10 MB."
            return
        }
        let identity = "evidence:\(fulfilment.id):\(data.count)"
        await performV1(identity: identity) {
            let accountID = try await self.services.accountID()
            let path = "merchant-ready/\(accountID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension)"
            try await self.services.uploadObject(
                bucket: "dastak-evidence",
                path: path,
                data: data,
                contentType: contentType
            )
            return try await self.v1Client.addEvidence(
                fulfilmentID: fulfilment.id,
                objectPath: path,
                expectedVersion: fulfilment.version,
                idempotencyKey: self.actionKey(for: identity)
            )
        }
    }

    func markV1Ready(_ fulfilment: DastakV1MerchantFulfilment) async {
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
            errorMessage = message(for: error, fallback: "The fulfilment could not be updated.")
        }
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
