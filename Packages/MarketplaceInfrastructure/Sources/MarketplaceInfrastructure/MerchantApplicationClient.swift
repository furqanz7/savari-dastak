import Foundation
import MarketplaceFoundation

public enum MerchantApplicationStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case rejected
}

public enum MerchantType: String, Codable, Equatable, Sendable, CaseIterable {
    case retail = "RETAIL"
    case restaurantCafe = "RESTAURANT_CAFE"

    public var displayName: String {
        switch self {
        case .retail: "Retail store"
        case .restaurantCafe: "Restaurant or cafe"
        }
    }
}

public enum MerchantOnboardingState: String, Codable, Equatable, Sendable {
    case notApplied = "not_applied"
    case pending
    case approved
    case rejected
}

public enum MerchantReviewDecision: String, Codable, Equatable, Sendable {
    case approve
    case reject
}

public struct MerchantApplicationResult: Codable, Equatable, Sendable {
    public let applicationID: UUID
    public let status: MerchantApplicationStatus
    public let merchantType: MerchantType
    public let serviceZoneID: UUID
    public let serviceZoneName: String

    private enum CodingKeys: String, CodingKey {
        case applicationID = "applicationId"
        case status
        case merchantType
        case serviceZoneID = "serviceZoneId"
        case serviceZoneName
    }
}

public struct MerchantApplication: Codable, Equatable, Sendable {
    public let applicationID: UUID
    public let accountID: UUID
    public let applicantName: String
    public let applicantPhone: String
    public let merchantType: MerchantType
    public let legalName: String
    public let businessName: String
    public let businessAddress: String
    public let latitude: Double
    public let longitude: Double
    public let serviceZoneID: UUID
    public let serviceZoneName: String
    public let evidenceObjectPath: String
    public let status: MerchantApplicationStatus
    public let submittedAt: String

    private enum CodingKeys: String, CodingKey {
        case applicationID = "applicationId"
        case accountID = "accountId"
        case applicantName
        case applicantPhone
        case merchantType
        case legalName
        case businessName
        case businessAddress
        case latitude
        case longitude
        case serviceZoneID = "serviceZoneId"
        case serviceZoneName
        case evidenceObjectPath
        case status
        case submittedAt
    }
}

public struct MerchantApplicationSnapshot: Codable, Equatable, Sendable {
    public let onboardingState: MerchantOnboardingState
    public let applicationID: UUID?
    public let merchantType: MerchantType?
    public let legalName: String?
    public let businessName: String?
    public let businessAddress: String?
    public let latitude: Double?
    public let longitude: Double?
    public let serviceZoneID: UUID?
    public let serviceZoneName: String?
    public let evidenceObjectPath: String?
    public let reviewReason: String?
    public let organizationID: UUID?
    public let branchID: UUID?

    private enum CodingKeys: String, CodingKey {
        case onboardingState
        case applicationID = "applicationId"
        case merchantType
        case legalName
        case businessName
        case businessAddress
        case latitude
        case longitude
        case serviceZoneID = "serviceZoneId"
        case serviceZoneName
        case evidenceObjectPath
        case reviewReason
        case organizationID = "organizationId"
        case branchID = "branchId"
    }
}

public protocol MerchantApplicationClient: Sendable {
    func submit(
        merchantType: MerchantType,
        legalName: String,
        businessName: String,
        businessAddress: String,
        latitude: Double,
        longitude: Double,
        evidenceObjectPath: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationResult

    func selfSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationSnapshot

    func listPending(
        idempotencyKey: IdempotencyKey
    ) async throws -> [MerchantApplication]

    func review(
        applicationID: UUID,
        decision: MerchantReviewDecision,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationResult
}

public struct SupabaseMerchantApplicationClient: MerchantApplicationClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let merchantType: MerchantType?
        let legalName: String?
        let businessName: String?
        let businessAddress: String?
        let latitude: Double?
        let longitude: Double?
        let evidenceObjectPath: String?
        let applicationId: UUID?
        let decision: MerchantReviewDecision?
        let reason: String?
    }

    private struct ListResponse: Decodable, Sendable {
        let applications: [MerchantApplication]
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func submit(
        merchantType: MerchantType,
        legalName: String,
        businessName: String,
        businessAddress: String,
        latitude: Double,
        longitude: Double,
        evidenceObjectPath: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationResult {
        try await functions.invoke(
            "merchant-applications",
            request: Request(
                operation: "submit",
                merchantType: merchantType,
                legalName: legalName,
                businessName: businessName,
                businessAddress: businessAddress,
                latitude: latitude,
                longitude: longitude,
                evidenceObjectPath: evidenceObjectPath,
                applicationId: nil,
                decision: nil,
                reason: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func selfSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationSnapshot {
        try await functions.invoke(
            "merchant-applications",
            request: Request(
                operation: "selfSnapshot",
                merchantType: nil,
                legalName: nil,
                businessName: nil,
                businessAddress: nil,
                latitude: nil,
                longitude: nil,
                evidenceObjectPath: nil,
                applicationId: nil,
                decision: nil,
                reason: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func listPending(
        idempotencyKey: IdempotencyKey
    ) async throws -> [MerchantApplication] {
        let response: ListResponse = try await functions.invoke(
            "merchant-applications",
            request: Request(
                operation: "list",
                merchantType: nil,
                legalName: nil,
                businessName: nil,
                businessAddress: nil,
                latitude: nil,
                longitude: nil,
                evidenceObjectPath: nil,
                applicationId: nil,
                decision: nil,
                reason: nil
            ),
            idempotencyKey: idempotencyKey
        )
        return response.applications
    }

    public func review(
        applicationID: UUID,
        decision: MerchantReviewDecision,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationResult {
        try await functions.invoke(
            "merchant-applications",
            request: Request(
                operation: "review",
                merchantType: nil,
                legalName: nil,
                businessName: nil,
                businessAddress: nil,
                latitude: nil,
                longitude: nil,
                evidenceObjectPath: nil,
                applicationId: applicationID,
                decision: decision,
                reason: reason
            ),
            idempotencyKey: idempotencyKey
        )
    }
}
