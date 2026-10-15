import Foundation
import MarketplaceFoundation

public struct DastakDeliveryEarnings: Decodable, Sendable {
    public struct Availability: Decodable, Sendable {
        public let destinationRegistrationAvailable: Bool
        public let withdrawalExecutionAvailable: Bool
    }
    public struct Destination: Decodable, Sendable {
        public let id: UUID
        public let type: String
        public let displayLabel: String
        public let status: String
        public let version: Int
    }
    public struct Entry: Decodable, Identifiable, Sendable {
        public let id: UUID
        public let type: String
        public let amountPaise: Int
        public let reason: String
        public let createdAt: String
        public let orderId: UUID?
        public let missionId: UUID?
    }
    public struct Withdrawal: Decodable, Identifiable, Sendable {
        public struct MaskedDestination: Decodable, Sendable { public let type: String; public let displayLabel: String }
        public let id: UUID
        public let amountPaise: Int
        public let currency: String
        public let status: String
        public let destination: MaskedDestination?
        public let reconciliationState: String?
        public let requestedAt: String
        public let paidAt: String?
        public let failureCode: String?
        public let version: Int
    }
    public struct Subject: Decodable, Identifiable, Sendable {
        public var id: UUID { subjectId }
        public let subjectType: String
        public let subjectId: UUID
        public let currency: String
        public let balancePaise: Int
        public let availablePaise: Int
        public let negativeBalancePaise: Int
        public let lifetimeEarnedPaise: Int
        public let canWithdraw: Bool
        public let payoutDestination: Destination?
        public let entries: [Entry]
        public let adjustments: [Entry]
        public let withdrawals: [Withdrawal]
    }
    public let currency: String
    public let balancePaise: Int
    public let availablePaise: Int
    public let negativeBalancePaise: Int
    public let lifetimeEarnedPaise: Int
    public let payoutAvailability: Availability?
    public let subjects: [Subject]
    public func isValid(for accountID: UUID) -> Bool {
        currency == "INR" && availablePaise >= 0 && negativeBalancePaise >= 0 && lifetimeEarnedPaise >= 0
        && subjects.count <= 1 && subjects.allSatisfy { subject in
            subject.subjectType == "RIDER" && subject.subjectId == accountID && subject.currency == "INR"
            && subject.availablePaise >= 0 && subject.negativeBalancePaise >= 0 && subject.lifetimeEarnedPaise >= 0
            && (subject.payoutDestination.map { $0.status == "ACTIVE" && $0.version > 0 } ?? true)
            && subject.withdrawals.allSatisfy { $0.currency == "INR" && $0.version > 0 && $0.amountPaise > 0
                && ["REQUESTED", "PROCESSING", "PAID", "FAILED_RETRYABLE", "FAILED", "REVERSED"].contains($0.status) }
        }
    }
}

public struct DastakDeliveryPayoutRequest: Codable, Equatable, Sendable, SingleAttemptFunctionRequest {
    public let operation: String
    public let subjectType: String
    public let subjectId: UUID?
    public let amountPaise: Int?
    public let withdrawalId: UUID?
    public let expectedVersion: Int?
    public init(subjectID: UUID, amountPaise: Int) {
        operation = "requestRoyaltyWithdrawal"; subjectType = "RIDER"; subjectId = subjectID; self.amountPaise = amountPaise
        withdrawalId = nil; expectedVersion = nil
    }
    public init(withdrawalID: UUID, version: Int) {
        operation = "retryRoyaltyWithdrawal"; subjectType = "RIDER"; subjectId = nil; amountPaise = nil
        withdrawalId = withdrawalID; expectedVersion = version
    }
}

public struct DastakDeliveryPayoutReply: Decodable, Sendable {
    public let withdrawalId: UUID
    public let amountPaise: Int?
    public let status: String?
}

public struct DastakDeliveryDestinationRequest: Encodable, Sendable, SingleAttemptFunctionRequest {
    public let operation = "registerRoyaltyPayoutDestination"
    public let subjectType = "RIDER"
    public let subjectId: UUID
    public let destinationType: String
    public let holderName: String
    public let accountNumber: String?
    public let confirmAccountNumber: String?
    public let ifsc: String?
    public let vpa: String?
    public init(subjectID: UUID, holderName: String, accountNumber: String, confirmation: String, ifsc: String) {
        subjectId = subjectID; destinationType = "BANK_ACCOUNT"; self.holderName = holderName
        self.accountNumber = accountNumber; confirmAccountNumber = confirmation; self.ifsc = ifsc; vpa = nil
    }
    public init(subjectID: UUID, holderName: String, vpa: String) {
        subjectId = subjectID; destinationType = "UPI"; self.holderName = holderName; self.vpa = vpa
        accountNumber = nil; confirmAccountNumber = nil; ifsc = nil
    }
}

public struct DastakDeliveryEarningsClient: Sendable {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    public func snapshot(accountID: UUID) async throws -> DastakDeliveryEarnings {
        struct Request: Encodable, Sendable { let operation = "deliveryRoyaltySnapshot" }
        let reply: DastakDeliveryEarnings = try await functions.invoke("earnings", request: Request(), idempotencyKey: key())
        guard reply.isValid(for: accountID) else { throw FunctionClientError.invalidResponse }
        return reply
    }
    public func payout(_ request: DastakDeliveryPayoutRequest, key: IdempotencyKey) async throws -> DastakDeliveryPayoutReply {
        try await functions.invoke("earnings", request: request, idempotencyKey: key)
    }
    public func destination(_ request: DastakDeliveryDestinationRequest) async throws {
        // Discard provider metadata. Confirmation is a new authenticated snapshot.
        let _: DastakAdminTraceRecord = try await functions.invoke("earnings", request: request, idempotencyKey: key())
    }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
}
