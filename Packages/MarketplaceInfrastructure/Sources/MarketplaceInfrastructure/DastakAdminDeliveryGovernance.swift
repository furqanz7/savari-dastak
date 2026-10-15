import Foundation
import MarketplaceFoundation

public enum DastakAdminRiderStatus: String, Codable, Sendable { case active = "ACTIVE", suspended = "SUSPENDED" }
public enum DastakAdminRiderAvailability: String, Codable, Sendable { case online = "ONLINE", offline = "OFFLINE" }

public struct DastakAdminDeliveryPartner: Decodable, Equatable, Identifiable, Sendable {
    public struct Rider: Decodable, Equatable, Sendable {
        public let accountId: UUID
        public let displayName: String
        public let maskedPhoneNumber: String?
        public let accountState: String
    }
    public struct Approval: Decodable, Equatable, Sendable {
        public let applicationId: UUID
        public let status: String
        public let submittedAt: String
        public let reviewedAt: String?
        public let verificationVersion: Int
        public let hasIdentityEvidence: Bool
        public let hasVehicleEvidence: Bool
    }
    public struct Governance: Decodable, Equatable, Sendable {
        public let status: DastakAdminRiderStatus
        public let version: Int
        public let suspendedAt: String?
        public let reason: String?
    }
    public struct Availability: Decodable, Equatable, Sendable {
        public let status: DastakAdminRiderAvailability
        public let version: Int
        public let availableUntil: String?
        public let lastSeenAt: String?
        public let serviceZone: DastakAdminMerchantServiceZone?
        public let trackingReceivedAt: String?
    }
    public struct ActiveWork: Decodable, Equatable, Sendable {
        public enum Domain: String, Decodable, Sendable {
            case delivery = "DASTAK_V1", returns = "RETURN", courier = "LEGACY_COURIER", parcel = "PARCEL"
        }
        public let domain: Domain
        public let id: UUID
    }
    public let rider: Rider
    public let approval: Approval
    public let transportMethod: String
    public let governance: Governance
    public let availability: Availability
    public let activeWork: ActiveWork?
    public let updatedAt: String
    public var id: UUID { rider.accountId }
}

public struct DastakAdminDeliveryCursor: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let riderId: UUID
}
public struct DastakAdminDeliveryPage: Decodable, Sendable {
    public let deliveryPartners: [DastakAdminDeliveryPartner]
    public let hasMore: Bool
    public let nextCursor: DastakAdminDeliveryCursor?
}
public struct DastakAdminDeliveryStatusResult: Decodable, Sendable {
    public let riderId: UUID
    public let status: DastakAdminRiderStatus
    public let governanceVersion: Int
    public let availabilityStatus: DastakAdminRiderAvailability
    public let availabilityVersion: Int
    public let updatedAt: String
}
public protocol DastakAdminDeliveryGovernanceClient: Sendable {
    func deliveryGovernancePage(query: String?, status: DastakAdminRiderStatus?, limit: Int,
        cursor: DastakAdminDeliveryCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminDeliveryPage
    func setDeliveryPartnerStatus(riderID: UUID, status: DastakAdminRiderStatus,
        expectedGovernanceVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminDeliveryStatusResult
}

extension SupabaseDastakV1AdminClient {
    private struct DeliveryPageRequest: Encodable, Sendable {
        let operation = "adminDeliveryPartnerGovernancePage"
        let query: String?
        let status: DastakAdminRiderStatus?
        let limit: Int
        let cursor: DastakAdminDeliveryCursor?
    }
    private struct DeliveryStatusRequest: Encodable, Sendable {
        let operation = "setAdminDeliveryPartnerStatus"
        let riderId: UUID
        let status: DastakAdminRiderStatus
        let expectedGovernanceVersion: Int
        let reason: String
    }
    public func deliveryGovernancePage(query: String?, status: DastakAdminRiderStatus?, limit: Int,
        cursor: DastakAdminDeliveryCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminDeliveryPage {
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (query?.count ?? 0) <= 100, (1...100).contains(limit),
              cursor == nil || DastakAdminContract.date(cursor!.updatedAt) != nil else { throw FunctionClientError.invalidResponse }
        return try await functions.invoke("dastak-v1-orders", request: DeliveryPageRequest(
            query: query?.isEmpty == false ? query : nil, status: status, limit: limit, cursor: cursor), idempotencyKey: idempotencyKey)
    }
    public func setDeliveryPartnerStatus(riderID: UUID, status: DastakAdminRiderStatus,
        expectedGovernanceVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminDeliveryStatusResult {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedGovernanceVersion > 0, (3...500).contains(reason.count) else { throw FunctionClientError.invalidResponse }
        return try await functions.invoke("dastak-v1-orders", request: DeliveryStatusRequest(
            riderId: riderID, status: status, expectedGovernanceVersion: expectedGovernanceVersion, reason: reason), idempotencyKey: idempotencyKey)
    }
}

enum DastakAdminContract {
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    static func isAuditID(_ text: String) -> Bool {
        guard text.count <= 80 else { return false }
        if text.hasPrefix("legacy:") { return UUID(uuidString: String(text.dropFirst(7))) != nil }
        return text.hasPrefix("v1:") && text.count > 3 && text.dropFirst(3).utf8.allSatisfy { (48...57).contains($0) }
    }
}
