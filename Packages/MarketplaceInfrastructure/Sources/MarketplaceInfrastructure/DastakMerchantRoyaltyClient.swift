import Foundation
import MarketplaceFoundation

/// Merchant-organization ledger. Deliberately distinct from Rider earnings and
/// older aggregate snapshots. Unknown provider/private fields are not retained.
public struct DastakMerchantRoyalty: Decodable, Sendable {
    public struct Availability: Decodable, Sendable {
        public let destinationRegistrationAvailable: Bool
        public let withdrawalExecutionAvailable: Bool
        public let merchantControlsAvailable: Bool?
    }
    public struct Destination: Decodable, Equatable, Sendable {
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
        public let fulfilmentId: UUID?
        public let refundId: UUID?
        public let withdrawalId: UUID?
    }
    public struct Withdrawal: Decodable, Identifiable, Sendable {
        public struct Destination: Decodable, Sendable {
            public let type: String?
            public let displayLabel: String?
        }
        public let id: UUID
        public let amountPaise: Int
        public let currency: String
        public let status: String
        public let destination: Destination?
        public let reconciliationState: String?
        public let requestedAt: String
        public let processingAt: String?
        public let paidAt: String?
        public let failedAt: String?
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
        public let canManagePayouts: Bool?
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

    public var isValid: Bool {
        guard currency == "INR", availablePaise >= 0, negativeBalancePaise >= 0, lifetimeEarnedPaise >= 0,
              !subjects.isEmpty, Set(subjects.map(\.id)).count == subjects.count,
              subjects.allSatisfy({ subject in
                  subject.subjectType == "MERCHANT_ORGANIZATION" && subject.currency == "INR"
                  && subject.balancePaise != Int.min
                  && subject.availablePaise == max(subject.balancePaise, 0)
                  && subject.negativeBalancePaise == max(-subject.balancePaise, 0)
                  && subject.lifetimeEarnedPaise >= 0
                  && (subject.payoutDestination.map { $0.status == "ACTIVE" && $0.version > 0 && !$0.displayLabel.isEmpty } ?? true)
                  && validEntries(subject.entries) && validEntries(subject.adjustments)
                  && Set(subject.withdrawals.map(\.id)).count == subject.withdrawals.count
                  && subject.withdrawals.allSatisfy { $0.currency == "INR" && $0.amountPaise > 0 && $0.version > 0
                      && ["REQUESTED", "PROCESSING", "PAID", "FAILED_RETRYABLE", "FAILED", "REVERSED"].contains($0.status) }
              }) else { return false }
        // Aggregate balances are sums across organizations, not one net account.
        return sum(subjects.map(\.balancePaise)) == balancePaise
            && sum(subjects.map(\.availablePaise)) == availablePaise
            && sum(subjects.map(\.negativeBalancePaise)) == negativeBalancePaise
            && sum(subjects.map(\.lifetimeEarnedPaise)) == lifetimeEarnedPaise
    }
    private func validEntries(_ entries: [Entry]) -> Bool {
        Set(entries.map(\.id)).count == entries.count && entries.allSatisfy { !$0.type.isEmpty && !$0.createdAt.isEmpty && $0.amountPaise != Int.min }
    }
    private func sum(_ amounts: [Int]) -> Int? {
        var total = 0
        for amount in amounts {
            let next = total.addingReportingOverflow(amount)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }
}

public struct DastakMerchantRoyaltyClient: Sendable {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    public func snapshot() async throws -> DastakMerchantRoyalty {
        struct Request: Encodable, Sendable { let operation: String }
        let result: DastakMerchantRoyalty
        do { result = try await functions.invoke("earnings",request:Request(operation:"merchantRoyaltyControlsSnapshot"),idempotencyKey:key()) }
        catch FunctionClientError.api(statusCode:400,code:"invalid_operation",message:_) {
            // Compatibility is read-only. Never downgrade a financial write.
            result = try await functions.invoke("earnings",request:Request(operation:"merchantRoyaltySnapshot"),idempotencyKey:key())
        }
        guard result.isValid else { throw FunctionClientError.invalidResponse }
        return result
    }
    public func withdraw(organization: UUID,amount: Int,destination: UUID,version: Int,key: IdempotencyKey) async throws -> DastakMerchantPayoutReply {
        struct Request: SingleAttemptFunctionRequest {
            let operation = "requestMerchantRoyaltyWithdrawal", subjectType = "MERCHANT_ORGANIZATION"
            let subjectId: UUID; let amountPaise: Int; let destinationId: UUID; let destinationVersion: Int
        }
        return try await functions.invoke("earnings",request:Request(subjectId:organization,amountPaise:amount,destinationId:destination,destinationVersion:version),idempotencyKey:key)
    }
    public func retry(withdrawal: UUID,version: Int,key: IdempotencyKey) async throws -> DastakMerchantPayoutReply {
        struct Request: SingleAttemptFunctionRequest {
            let operation = "retryRoyaltyWithdrawal", subjectType = "MERCHANT_ORGANIZATION"
            let withdrawalId: UUID; let expectedVersion: Int
        }
        return try await functions.invoke("earnings",request:Request(withdrawalId:withdrawal,expectedVersion:version),idempotencyKey:key)
    }
    public func register(_ request: DastakMerchantDestinationRequest,key: IdempotencyKey) async throws -> DastakMerchantDestinationReply {
        guard request.valid else { throw FunctionClientError.invalidResponse }
        let reply: DastakMerchantDestinationReply = try await functions.invoke("earnings",request:request,idempotencyKey:key)
        guard reply.status == "ACTIVE",reply.version>0,reply.type==request.destinationType,reply.displayLabel==request.maskedLabel else { throw FunctionClientError.invalidResponse }
        return reply
    }
    private func key() -> IdempotencyKey { IdempotencyKey(rawValue:UUID().uuidString)! }
}

public struct DastakMerchantPayoutReply: Decodable, Sendable {
    public let withdrawalId: UUID
    public let amountPaise: Int?
    public let status: String
}
public struct DastakMerchantDestinationReply: Decodable, Sendable {
    public let destinationId: UUID
    public let status: String
    public let version: Int
    public let type: String
    public let displayLabel: String
}

/// Sensitive request. Do not log/reflect, put in UserDefaults/files, or expose
/// as a description. Merchant recovery may hold it in device-only Keychain.
public struct DastakMerchantDestinationRequest: Codable, Equatable, Sendable, SingleAttemptFunctionRequest {
    public let subjectId: UUID
    public let destinationType: String
    public let holderName: String
    public let accountNumber: String?
    public let confirmAccountNumber: String?
    public let ifsc: String?
    public let vpa: String?
    private var operation: String { "registerRoyaltyPayoutDestination" }
    public var maskedLabel: String {
        if let accountNumber { return "Bank account •••• " + accountNumber.suffix(4) }
        let parts = (vpa ?? "").split(separator:"@",omittingEmptySubsequences:false)
        guard parts.count==2 else { return "UPI" }
        let user = parts[0], masked = user.count<=2 ? String(user.prefix(1))+"*" : String(user.prefix(2))+"***"
        return "UPI • " + masked + "@" + parts[1]
    }
    public init(organization: UUID,holder: String,account: String,confirmation: String,ifsc: String) {
        subjectId = organization; destinationType = "BANK_ACCOUNT"; holderName = Self.holder(holder)
        accountNumber = account.replacingOccurrences(of:"\\s+",with:"",options:.regularExpression)
        confirmAccountNumber = confirmation.replacingOccurrences(of:"\\s+",with:"",options:.regularExpression)
        self.ifsc = ifsc.trimmingCharacters(in:.whitespacesAndNewlines).uppercased(); vpa = nil
    }
    public init(organization: UUID,holder: String,vpa: String) {
        subjectId = organization; destinationType = "UPI"; holderName = Self.holder(holder)
        self.vpa = vpa.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        accountNumber = nil; confirmAccountNumber = nil; ifsc = nil
    }
    public var valid: Bool {
        guard (3...50).contains(holderName.utf16.count),holderName.range(of:"^[A-Za-z0-9 ._()/'-]+$",options:.regularExpression) != nil,
              holderName.range(of:"[A-Za-z0-9.]$",options:.regularExpression) != nil else { return false }
        if destinationType == "BANK_ACCOUNT" {
            return accountNumber == confirmAccountNumber && accountNumber?.range(of:"^[0-9]{6,34}$",options:.regularExpression) != nil
                && ifsc?.range(of:"^[A-Z]{4}0[A-Z0-9]{6}$",options:.regularExpression) != nil && vpa == nil
        }
        return destinationType == "UPI" && vpa.map { $0.utf16.count<=120 && $0.range(of:"^[a-z0-9._-]{2,64}@[a-z0-9.-]{2,64}$",options:.regularExpression) != nil } == true
            && accountNumber == nil && confirmAccountNumber == nil && ifsc == nil
    }
    private static func holder(_ value: String) -> String { value.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression) }
    private enum CodingKeys: String,CodingKey { case operation,subjectType,subjectId,destinationType,holderName,accountNumber,confirmAccountNumber,ifsc,vpa }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy:CodingKeys.self)
        try values.encode(operation,forKey:.operation); try values.encode("MERCHANT_ORGANIZATION",forKey:.subjectType)
        try values.encode(subjectId,forKey:.subjectId); try values.encode(destinationType,forKey:.destinationType); try values.encode(holderName,forKey:.holderName)
        try values.encodeIfPresent(accountNumber,forKey:.accountNumber); try values.encodeIfPresent(confirmAccountNumber,forKey:.confirmAccountNumber)
        try values.encodeIfPresent(ifsc,forKey:.ifsc); try values.encodeIfPresent(vpa,forKey:.vpa)
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        guard try values.decode(String.self,forKey:.operation)=="registerRoyaltyPayoutDestination",
              try values.decode(String.self,forKey:.subjectType)=="MERCHANT_ORGANIZATION" else { throw FunctionClientError.invalidResponse }
        subjectId = try values.decode(UUID.self,forKey:.subjectId); destinationType = try values.decode(String.self,forKey:.destinationType)
        holderName = try values.decode(String.self,forKey:.holderName); accountNumber = try values.decodeIfPresent(String.self,forKey:.accountNumber)
        confirmAccountNumber = try values.decodeIfPresent(String.self,forKey:.confirmAccountNumber); ifsc = try values.decodeIfPresent(String.self,forKey:.ifsc); vpa = try values.decodeIfPresent(String.self,forKey:.vpa)
        guard valid else { throw FunctionClientError.invalidResponse }
    }
}
