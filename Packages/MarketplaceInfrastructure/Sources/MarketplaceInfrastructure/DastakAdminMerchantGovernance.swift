import Foundation
import MarketplaceFoundation

public struct DastakAdminMerchantServiceZone: Codable, Equatable, Sendable {
    public let id: UUID?
    public let name: String?
}

public struct DastakAdminBranchAddress: Codable, Equatable, Sendable {
    public let line1: String?
    public let line2: String?
    public let city: String?
    public let state: String?
    public let postalCode: String?
    public let countryCode: String?
    public init(line1: String?, line2: String? = nil, city: String? = nil, state: String? = nil,
                postalCode: String? = nil, countryCode: String?) {
        self.line1 = line1; self.line2 = line2; self.city = city; self.state = state
        self.postalCode = postalCode; self.countryCode = countryCode
    }
    public var summary: String {
        [line1, line2, city, state, postalCode, countryCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

public enum DastakAdminMerchantStatus: String, Codable, Sendable { case active = "ACTIVE", suspended = "SUSPENDED" }
public enum DastakAdminMerchantTarget: String, Sendable { case organization, branch }

public struct DastakAdminBranchPatch: Encodable, Equatable, Sendable {
    public let displayName: String?
    public let address: DastakAdminBranchAddress?
    public let latitude: Double?
    public let longitude: Double?
    public let serviceZoneId: UUID?
    public let capacityLimit: Int?
    public init(displayName: String? = nil, address: DastakAdminBranchAddress? = nil,
                latitude: Double? = nil, longitude: Double? = nil, serviceZoneId: UUID? = nil, capacityLimit: Int? = nil) {
        self.displayName = displayName; self.address = address; self.latitude = latitude
        self.longitude = longitude; self.serviceZoneId = serviceZoneId; self.capacityLimit = capacityLimit
    }
    public var isRouteCritical: Bool { address != nil || latitude != nil || longitude != nil || serviceZoneId != nil }
    public var isValid: Bool {
        guard displayName != nil || address != nil || latitude != nil || longitude != nil || serviceZoneId != nil || capacityLimit != nil else { return false }
        if let displayName, !(1...100).contains(displayName.trimmingCharacters(in: .whitespacesAndNewlines).count) { return false }
        if let address {
            guard let line1 = address.line1, (3...200).contains(line1.trimmingCharacters(in: .whitespacesAndNewlines).count),
                  let country = address.countryCode, country.utf8.count == 2,
                  country.utf8.allSatisfy({ (65...90).contains($0) }) else { return false }
            if (address.line2?.count ?? 0) > 200 || (address.city?.count ?? 0) > 100 ||
                (address.state?.count ?? 0) > 100 || (address.postalCode?.count ?? 0) > 20 { return false }
        }
        guard (latitude == nil) == (longitude == nil) else { return false }
        if let latitude, let longitude,
           (!latitude.isFinite || !longitude.isFinite || !(-90...90).contains(latitude) || !(-180...180).contains(longitude)) { return false }
        if let capacityLimit, !(1...500).contains(capacityLimit) { return false }
        return true
    }
}

public struct DastakAdminMerchantGovernanceResult: Decodable, Sendable {
    public let organizationId: UUID
    public let branchId: UUID?
    public let status: String
    public let version: Int
    public let changedFields: [String]?
    public let updatedAt: String
}

public protocol DastakAdminMerchantGovernanceClient: DastakAdminRestaurantListingClient {
    func setMerchantStatus(target: DastakAdminMerchantTarget, id: UUID, status: DastakAdminMerchantStatus,
                           expectedVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantGovernanceResult
    func correctMerchantBranch(id: UUID, changes: DastakAdminBranchPatch, expectedVersion: Int,
                               reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantGovernanceResult
}

extension SupabaseDastakV1AdminClient {
    private struct StatusRequest: Encodable, Sendable {
        let operation: String
        let organizationId: UUID?
        let branchId: UUID?
        let status: DastakAdminMerchantStatus
        let expectedVersion: Int
        let reason: String
    }
    private struct CorrectionRequest: Encodable, Sendable {
        let operation = "correctAdminMerchantBranchDetails"
        let branchId: UUID
        let changes: DastakAdminBranchPatch
        let expectedVersion: Int
        let reason: String
    }
    public func setMerchantStatus(target: DastakAdminMerchantTarget, id: UUID, status: DastakAdminMerchantStatus,
                                  expectedVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantGovernanceResult {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedVersion > 0, (3...500).contains(reason.count) else { throw FunctionClientError.invalidResponse }
        return try await functions.invoke("dastak-v1-orders", request: StatusRequest(
            operation: target == .organization ? "setAdminMerchantOrganizationStatus" : "setAdminMerchantBranchStatus",
            organizationId: target == .organization ? id : nil, branchId: target == .branch ? id : nil,
            status: status, expectedVersion: expectedVersion, reason: reason), idempotencyKey: idempotencyKey)
    }
    public func correctMerchantBranch(id: UUID, changes: DastakAdminBranchPatch, expectedVersion: Int,
                                     reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminMerchantGovernanceResult {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedVersion > 0, (3...500).contains(reason.count), changes.isValid else { throw FunctionClientError.invalidResponse }
        return try await functions.invoke("dastak-v1-orders", request: CorrectionRequest(branchId: id,
            changes: changes, expectedVersion: expectedVersion, reason: reason), idempotencyKey: idempotencyKey)
    }
}
