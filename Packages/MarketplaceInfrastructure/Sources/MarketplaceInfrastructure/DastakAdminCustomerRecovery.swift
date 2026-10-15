import Foundation
import MarketplaceFoundation

public struct DastakAdminCustomerRecoveryRow: Decodable, Equatable, Identifiable, Sendable {
    public struct Account: Decodable, Equatable, Sendable {
        public let accountId: UUID
        public let displayName: String
        public let currentPhoneNumber: String
        public let maskedPhoneNumber: String
        public let email: String?
        public let accountState: String
        public let customerState: String
        public let createdAt: String
    }
    public struct PhoneClaim: Decodable, Equatable, Sendable {
        public let version: Int
        public let state: String
        public let verificationSource: String
    }
    public struct Session: Decodable, Equatable, Identifiable, Sendable {
        public let sessionId: UUID
        public let deviceName: String
        public let platform: String
        public let appName: String
        public let createdAt: String
        public let lastSeenAt: String
        public var id: UUID { sessionId }
    }
    public let account: Account
    public let phoneClaim: PhoneClaim
    public let identityProviders: [String]
    public let activeSessionCount: Int
    public let sessions: [Session]
    public let updatedAt: String
    public var id: UUID { account.accountId }
    public var valid: Bool {
        DastakAdminCustomerRecoveryContract.phone(account.currentPhoneNumber) && !account.displayName.isEmpty && !account.maskedPhoneNumber.isEmpty &&
        !account.accountState.isEmpty && !account.customerState.isEmpty &&
        DastakAdminContract.date(account.createdAt) != nil && DastakAdminContract.date(updatedAt) != nil &&
        (0...9_007_199_254_740_991).contains(phoneClaim.version) && !phoneClaim.state.isEmpty && !phoneClaim.verificationSource.isEmpty &&
        identityProviders.allSatisfy { !$0.isEmpty } && activeSessionCount >= 0 && activeSessionCount == sessions.count &&
        Set(sessions.map(\.id)).count == sessions.count && sessions.allSatisfy {
            ["ios", "web"].contains($0.platform) && !$0.deviceName.isEmpty && !$0.appName.isEmpty &&
            DastakAdminContract.date($0.createdAt) != nil && DastakAdminContract.date($0.lastSeenAt) != nil
        }
    }
}
public struct DastakAdminCustomerRecoveryCursor: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let accountId: UUID
}
public struct DastakAdminCustomerRecoveryPage: Decodable, Sendable {
    public let customers: [DastakAdminCustomerRecoveryRow]
    public let hasMore: Bool
    public let nextCursor: DastakAdminCustomerRecoveryCursor?
}
public struct DastakAdminCustomerSessionResult: Decodable, Sendable {
    public let accountId: UUID
    public let scope: String
    public let revokedSessionCount: Int
    public let revokedSessionId: UUID?
    public let activeSessionCount: Int
    public let updatedAt: String
}
public struct DastakAdminCustomerPhoneResult: Decodable, Sendable {
    public let accountId: UUID
    public let maskedPhoneNumber: String
    public let phoneClaimVersion: Int
    public let phoneVerificationState: String
    public let updatedAt: String
}
public enum DastakAdminCustomerRecoveryContract {
    public static func date(_ text: String) -> Date? { DastakAdminContract.date(text) }
    public static func phone(_ text: String) -> Bool { text.range(of: #"^\+[1-9][0-9]{7,14}$"#, options: .regularExpression) != nil && text.unicodeScalars.allSatisfy { !CharacterSet.newlines.contains($0) } }
    public static func mask(_ text: String) -> String { String(repeating: "•", count: max(text.count - 4, 4)) + " " + text.suffix(4) }
}
public protocol DastakAdminCustomerRecoveryClient: Sendable {
    func customerRecoveryPage(query: String?, accountId: UUID?, limit: Int, cursor: DastakAdminCustomerRecoveryCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminCustomerRecoveryPage
    func revokeCustomerSessions(accountId: UUID, scope: String, sessionId: UUID?, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminCustomerSessionResult
    func correctCustomerPhone(accountId: UUID, reviewedCurrentPhone: String, replacementPhone: String, expectedPhoneClaimVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminCustomerPhoneResult
}
extension SupabaseDastakV1AdminClient: DastakAdminCustomerRecoveryClient {
    private struct CustomerPageRequest: Encodable, Sendable {
        let operation = "adminCustomerRecoveryPage"
        let query: String?
        let accountId: UUID?
        let limit: Int
        let cursor: DastakAdminCustomerRecoveryCursor?
    }
    private struct CustomerSessionRequest: SingleAttemptFunctionRequest {
        let operation = "revokeAdminCustomerSessions"
        let accountId: UUID
        let scope: String
        let sessionId: UUID?
        let reason: String
    }
    private struct CustomerPhoneRequest: SingleAttemptFunctionRequest {
        let operation = "correctAdminCustomerPhone"
        let accountId: UUID
        let reviewedCurrentPhone: String
        let replacementPhone: String
        let expectedPhoneClaimVersion: Int
        let reason: String
    }
    public func customerRecoveryPage(query: String?, accountId: UUID?, limit: Int, cursor: DastakAdminCustomerRecoveryCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakAdminCustomerRecoveryPage {
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (query?.count ?? 0) <= 100, (1...100).contains(limit), cursor == nil || DastakAdminContract.date(cursor!.updatedAt) != nil else { throw FunctionClientError.invalidResponse }
        let page: DastakAdminCustomerRecoveryPage = try await functions.invoke("dastak-v1-orders", request: CustomerPageRequest(query: query?.isEmpty == false ? query : nil, accountId: accountId, limit: limit, cursor: cursor), idempotencyKey: idempotencyKey)
        guard page.customers.count <= limit, page.customers.allSatisfy(\.valid), Set(page.customers.map(\.id)).count == page.customers.count,
              accountId == nil || page.customers.allSatisfy({ $0.id == accountId }),
              page.hasMore ? (page.nextCursor != nil && page.nextCursor != cursor && page.customers.last?.id == page.nextCursor?.accountId && page.customers.last?.updatedAt == page.nextCursor?.updatedAt && DastakAdminContract.date(page.nextCursor!.updatedAt) != nil) : page.nextCursor == nil else { throw FunctionClientError.invalidResponse }
        return page
    }
    public func revokeCustomerSessions(accountId: UUID, scope: String, sessionId: UUID?, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminCustomerSessionResult {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["SINGLE", "ALL"].contains(scope), (scope == "SINGLE" ? sessionId != nil : sessionId == nil), (3...200).contains(reason.count) else { throw FunctionClientError.invalidResponse }
        return try await functions.invoke("dastak-v1-orders", request: CustomerSessionRequest(accountId: accountId, scope: scope, sessionId: sessionId, reason: reason), idempotencyKey: idempotencyKey)
    }
    public func correctCustomerPhone(accountId: UUID, reviewedCurrentPhone: String, replacementPhone: String, expectedPhoneClaimVersion: Int, reason: String, idempotencyKey: IdempotencyKey) async throws -> DastakAdminCustomerPhoneResult {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DastakAdminCustomerRecoveryContract.phone(reviewedCurrentPhone), DastakAdminCustomerRecoveryContract.phone(replacementPhone), reviewedCurrentPhone != replacementPhone,
              (1..<9_007_199_254_740_991).contains(expectedPhoneClaimVersion), (3...500).contains(reason.count) else { throw FunctionClientError.invalidResponse }
        return try await functions.invoke("dastak-v1-orders", request: CustomerPhoneRequest(accountId: accountId, reviewedCurrentPhone: reviewedCurrentPhone, replacementPhone: replacementPhone, expectedPhoneClaimVersion: expectedPhoneClaimVersion, reason: reason), idempotencyKey: idempotencyKey)
    }
}
