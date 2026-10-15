import Foundation
import MarketplaceFoundation

public struct DastakAdminMerchantListing: Decodable, Equatable, Identifiable, Sendable {
    public struct Organization: Decodable, Equatable, Sendable {
        public let id: UUID
        public let displayName: String
        public let merchantType: String
        public let status: String
        public let version: Int?
        public let activeNonTerminalFulfilmentCount: Int?
        public let activePickupReturnWorkCount: Int?
    }
    public struct Branch: Decodable, Equatable, Sendable {
        public struct OperationalState: Decodable, Equatable, Sendable {
            public let isOpen: Bool
            public let acceptingOrders: Bool
        }
        public let id: UUID
        public let displayName: String
        public let status: String
        public let version: Int
        public let customerListingVisible: Bool?
        public let operationalState: OperationalState
        public let normalizedAddress: DastakAdminBranchAddress?
        public let latitude: Double?
        public let longitude: Double?
        public let serviceZone: DastakAdminMerchantServiceZone?
        public let capacityLimit: Int?
        public let activeNonTerminalFulfilmentCount: Int?
        public let activePickupReturnWorkCount: Int?
        public let operationalPause: OperationalPause?

        public struct OperationalPause: Decodable, Equatable, Sendable {
            public let active: Bool
            public let reason: String
        }
    }
    public var id: UUID { branch.id }
    public let organization: Organization
    public let branch: Branch
    public let updatedAt: String

    public var supportsVisibilityChange: Bool {
        organization.merchantType == "RESTAURANT_CAFE" &&
        organization.status != "PENDING_REVIEW" && branch.status != "PENDING_REVIEW" &&
        branch.version > 0 && branch.customerListingVisible != nil
    }
}

public struct DastakAdminMerchantListingCursor: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let rowId: UUID
    public init(updatedAt: String, rowId: UUID) {
        self.updatedAt = updatedAt
        self.rowId = rowId
    }
}

public struct DastakAdminMerchantListingPage: Decodable, Sendable {
    public let merchants: [DastakAdminMerchantListing]
    public let hasMore: Bool
    public let nextCursor: DastakAdminMerchantListingCursor?
    public let serviceZones: [DastakAdminMerchantServiceZone]?
}

public struct DastakAdminRestaurantVisibilityResult: Decodable, Sendable {
    public let branchId: UUID
    public let customerListingVisible: Bool
    public let version: Int
    public let updatedAt: String
}

public protocol DastakAdminRestaurantListingClient: Sendable {
    func merchantListingPage(query: String?, limit: Int, cursor: DastakAdminMerchantListingCursor?,
                             idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantListingPage
    func setRestaurantCustomerVisibility(branchID: UUID, visible: Bool, expectedVersion: Int,
                                         reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminRestaurantVisibilityResult
}

extension SupabaseDastakV1AdminClient {
    private struct ListingRequest: Encodable, Sendable {
        let operation = "adminMerchantGovernancePage"
        let query: String?
        let limit: Int
        let cursor: DastakAdminMerchantListingCursor?
    }
    private struct VisibilityRequest: Encodable, Sendable {
        let operation = "setAdminRestaurantCustomerVisibility"
        let branchId: UUID
        let visible: Bool
        let expectedVersion: Int
        let reason: String
    }

    public func merchantListingPage(query: String?, limit: Int,
                                   cursor: DastakAdminMerchantListingCursor?,
                                   idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantListingPage {
        guard (1...100).contains(limit) else { throw FunctionClientError.invalidResponse }
        let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await functions.invoke("dastak-v1-orders", request: ListingRequest(
            query: normalized?.isEmpty == false ? normalized : nil, limit: limit, cursor: cursor
        ), idempotencyKey: idempotencyKey)
    }

    public func setRestaurantCustomerVisibility(branchID: UUID, visible: Bool, expectedVersion: Int,
                                               reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminRestaurantVisibilityResult {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedVersion > 0, (3...500).contains(normalized.count) else {
            throw FunctionClientError.invalidResponse
        }
        return try await functions.invoke("dastak-v1-orders", request: VisibilityRequest(
            branchId: branchID, visible: visible, expectedVersion: expectedVersion, reason: normalized
        ), idempotencyKey: idempotencyKey)
    }
}
