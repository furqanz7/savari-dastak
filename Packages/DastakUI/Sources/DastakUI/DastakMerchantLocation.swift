import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// Internal branch IDs identify an authorized location, not another name field.
struct DastakMerchantLocation: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case retail, restaurant, unknown }
    let id: UUID
    let name: String
    let kind: Kind
    var service: String { switch kind { case .restaurant: "Restaurant / Café"; case .retail: "Grocery"; case .unknown: "Orders · Store access not verified" } }
    var symbol: String { kind == .restaurant ? "fork.knife" : "storefront" }

    init(_ branch: DastakV1MerchantBranch) { id = branch.id; name = branch.displayName; kind = .unknown }
    init(_ location: DastakMerchantDirectoryLocation) {
        id = location.id; name = location.displayName
        kind = !location.canManageStore ? .unknown
            : location.merchantType == "RESTAURANT_CAFE" ? .restaurant
            : ["RETAIL","DASTAK_CONVENIENCE_STORE"].contains(location.merchantType) ? .retail : .unknown
    }
    init(cached location: Self) { id = location.id; name = location.name; kind = .unknown }

    init(_ branch: DastakV1MerchantCatalogueSnapshot.Branch) {
        id = branch.branchID
        name = branch.branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? branch.organizationName : branch.branchName
        kind = .retail
    }
    init(_ restaurant: DastakV1RestaurantIdentity) {
        id = restaurant.branchID
        name = restaurant.branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? restaurant.name : restaurant.branchName
        kind = .restaurant
    }
}

@MainActor
final class DastakMerchantLocationPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ account: UUID) -> String { "dastak.merchant.activeLocation.v1:\(account.uuidString.lowercased())" }
    func read(_ account: UUID) -> UUID? { defaults.string(forKey: key(account)).flatMap(UUID.init(uuidString:)) }
    func save(_ id: UUID, account: UUID) { defaults.set(id.uuidString.lowercased(), forKey: key(account)) }
}

struct DastakMerchantLocationProbe: Sendable {
    let locations: [DastakMerchantLocation]
    let failed: Bool
    let sessionExpired: Bool

    /// Reuses authenticated management reads. An operational branch reference or
    /// saved preference is a candidate, never Store-management authorization.
    static func run(client: any DastakV1MerchantClient, id: UUID?) async -> Self {
        async let retail = capture { try await client.canonicalCatalogue(branchID: id, limit: 1, idempotencyKey: key()) }
        async let food = capture { try await client.restaurantMenu(branchID: id, idempotencyKey: key()) }
        let (store, restaurant) = await (retail, food)
        var locations: [DastakMerchantLocation] = [], failed = false, session = false
        switch store {
        case let .success(value):
            if (id == nil || id == value.branch.branchID), ["RETAIL","DASTAK_CONVENIENCE_STORE"].contains(value.branch.merchantType) {
                locations.append(.init(value.branch))
            } else { failed = true }
        case let .failure(error): failed = failed || !notApplicable(error); session = session || expired(error)
        }
        switch restaurant {
        case let .success(value):
            if (id == nil || id == value.restaurant.branchID), value.restaurant.merchantType == "RESTAURANT_CAFE" {
                locations.append(.init(value.restaurant))
            } else { failed = true }
        case let .failure(error): failed = failed || !notApplicable(error); session = session || expired(error)
        }
        // Conflicting service classifications for one ID are not trustworthy.
        if Set(locations.map(\.id)).count != locations.count { locations = []; failed = true }
        return .init(locations: locations, failed: failed, sessionExpired: session)
    }
    private static func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
    private static func capture<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    private static func notApplicable(_ error: any Error) -> Bool {
        if case let FunctionClientError.api(status, _, _) = error { return status == 404 }
        return false
    }
    private static func expired(_ error: any Error) -> Bool {
        if case FunctionClientError.authenticationRequired = error { return true }
        if case let FunctionClientError.api(status, _, _) = error { return status == 401 }
        return false
    }
}
