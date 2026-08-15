import Foundation
import MarketplaceFoundation

public enum MerchantApplicationStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case rejected
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

    private enum CodingKeys: String, CodingKey {
        case applicationID = "applicationId"
        case status
    }
}

public struct MerchantApplication: Codable, Equatable, Sendable {
    public let applicationID: UUID
    public let accountID: UUID
    public let businessName: String
    public let businessAddress: String
    public let evidenceObjectPath: String
    public let status: MerchantApplicationStatus

    private enum CodingKeys: String, CodingKey {
        case applicationID = "applicationId"
        case accountID = "accountId"
        case businessName
        case businessAddress
        case evidenceObjectPath
        case status
    }
}

public struct MerchantApplicationSnapshot: Codable, Equatable, Sendable {
    public let onboardingState: MerchantOnboardingState
    public let applicationID: UUID?
    public let businessName: String?
    public let businessAddress: String?
    public let evidenceObjectPath: String?
    public let reviewReason: String?

    private enum CodingKeys: String, CodingKey {
        case onboardingState
        case applicationID = "applicationId"
        case businessName
        case businessAddress
        case evidenceObjectPath
        case reviewReason
    }
}

public protocol MerchantApplicationClient: Sendable {
    func submit(
        businessName: String,
        businessAddress: String,
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
        let businessName: String?
        let businessAddress: String?
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
        businessName: String,
        businessAddress: String,
        evidenceObjectPath: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantApplicationResult {
        try await functions.invoke(
            "merchant-applications",
            request: Request(
                operation: "submit",
                businessName: businessName,
                businessAddress: businessAddress,
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
                businessName: nil,
                businessAddress: nil,
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
                businessName: nil,
                businessAddress: nil,
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
                businessName: nil,
                businessAddress: nil,
                evidenceObjectPath: nil,
                applicationId: applicationID,
                decision: decision,
                reason: reason
            ),
            idempotencyKey: idempotencyKey
        )
    }
}
