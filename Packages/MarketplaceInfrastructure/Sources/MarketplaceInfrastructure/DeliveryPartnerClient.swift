import Foundation
import MarketplaceFoundation

public enum DeliveryMethod: String, Codable, Equatable, Sendable {
    case walking
    case bicycle
    case bike
    case auto
    case car
}

public enum DeliveryPartnerApplicationStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case rejected
}

public enum DeliveryPartnerOnboardingState: String, Codable, Equatable, Sendable {
    case notApplied = "not_applied"
    case pending
    case approved
    case rejected
}

public enum DeliveryPartnerReviewDecision: String, Codable, Equatable, Sendable {
    case approve
    case reject
}

public enum DeliveryPartnerAvailabilityStatus: String, Codable, Equatable, Sendable {
    case offline
    case online
}

public struct DeliveryPartnerApplicationResult: Codable, Equatable, Sendable {
    public let applicationID: UUID
    public let status: DeliveryPartnerApplicationStatus
    public let deliveryMethod: DeliveryMethod

    private enum CodingKeys: String, CodingKey {
        case applicationID = "applicationId"
        case status
        case deliveryMethod
    }
}

public struct DeliveryPartnerApplication: Codable, Equatable, Sendable {
    public let applicationID: UUID
    public let accountID: UUID
    public let displayName: String
    public let phoneNumber: String
    public let deliveryMethod: DeliveryMethod
    public let identityEvidenceObjectPath: String
    public let status: DeliveryPartnerApplicationStatus
    public let submittedAt: String

    private enum CodingKeys: String, CodingKey {
        case applicationID = "applicationId"
        case accountID = "accountId"
        case displayName
        case phoneNumber
        case deliveryMethod
        case identityEvidenceObjectPath
        case status
        case submittedAt
    }
}

public struct DeliveryPartnerAvailability: Codable, Equatable, Sendable {
    public let status: DeliveryPartnerAvailabilityStatus
    public let location: GeoPoint?
    public let serviceZoneID: UUID?
    public let availableUntil: String?
    public let stateVersion: Int64

    private enum CodingKeys: String, CodingKey {
        case status
        case location
        case serviceZoneID = "serviceZoneId"
        case availableUntil
        case stateVersion
    }
}

public struct DeliveryPartnerSnapshot: Codable, Equatable, Sendable {
    public let onboardingState: DeliveryPartnerOnboardingState
    public let applicationID: UUID?
    public let deliveryMethod: DeliveryMethod?
    public let identityEvidenceObjectPath: String?
    public let reviewReason: String?
    public let availability: DeliveryPartnerAvailability?

    private enum CodingKeys: String, CodingKey {
        case onboardingState
        case applicationID = "applicationId"
        case deliveryMethod
        case identityEvidenceObjectPath
        case reviewReason
        case availability
    }
}

public protocol DeliveryPartnerClient: Sendable {
    func submit(
        deliveryMethod: DeliveryMethod,
        identityEvidenceObjectPath: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerApplicationResult

    func selfSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerSnapshot

    func listPending(
        idempotencyKey: IdempotencyKey
    ) async throws -> [DeliveryPartnerApplication]

    func review(
        applicationID: UUID,
        decision: DeliveryPartnerReviewDecision,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerApplicationResult

    func setAvailability(
        online: Bool,
        location: GeoPoint?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerAvailability
}

public struct SupabaseDeliveryPartnerClient: DeliveryPartnerClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let deliveryMethod: DeliveryMethod?
        let identityEvidenceObjectPath: String?
        let applicationId: UUID?
        let decision: DeliveryPartnerReviewDecision?
        let reason: String?
        let online: Bool?
        let location: GeoPoint?

        init(
            operation: String,
            deliveryMethod: DeliveryMethod? = nil,
            identityEvidenceObjectPath: String? = nil,
            applicationId: UUID? = nil,
            decision: DeliveryPartnerReviewDecision? = nil,
            reason: String? = nil,
            online: Bool? = nil,
            location: GeoPoint? = nil
        ) {
            self.operation = operation
            self.deliveryMethod = deliveryMethod
            self.identityEvidenceObjectPath = identityEvidenceObjectPath
            self.applicationId = applicationId
            self.decision = decision
            self.reason = reason
            self.online = online
            self.location = location
        }
    }

    private struct ListResponse: Decodable, Sendable {
        let applications: [DeliveryPartnerApplication]
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func submit(
        deliveryMethod: DeliveryMethod,
        identityEvidenceObjectPath: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerApplicationResult {
        try await invoke(
            Request(
                operation: "submit",
                deliveryMethod: deliveryMethod,
                identityEvidenceObjectPath: identityEvidenceObjectPath
            ),
            key: idempotencyKey
        )
    }

    public func selfSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerSnapshot {
        try await invoke(Request(operation: "selfSnapshot"), key: idempotencyKey)
    }

    public func listPending(
        idempotencyKey: IdempotencyKey
    ) async throws -> [DeliveryPartnerApplication] {
        let response: ListResponse = try await invoke(
            Request(operation: "listPending"),
            key: idempotencyKey
        )
        return response.applications
    }

    public func review(
        applicationID: UUID,
        decision: DeliveryPartnerReviewDecision,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerApplicationResult {
        try await invoke(
            Request(
                operation: "review",
                applicationId: applicationID,
                decision: decision,
                reason: reason
            ),
            key: idempotencyKey
        )
    }

    public func setAvailability(
        online: Bool,
        location: GeoPoint?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DeliveryPartnerAvailability {
        try await invoke(
            Request(operation: "setAvailability", online: online, location: location),
            key: idempotencyKey
        )
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke(
            "delivery-partners",
            request: request,
            idempotencyKey: key
        )
    }
}
