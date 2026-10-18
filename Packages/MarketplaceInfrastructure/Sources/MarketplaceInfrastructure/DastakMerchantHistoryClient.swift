import Foundation
import MarketplaceFoundation

public struct DastakMerchantHistoryCursor: Codable, Equatable, Sendable {
    public let committedAt: String
    public let id: UUID
    var validTimestamp: Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: committedAt) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: committedAt) != nil
    }
}

public struct DastakMerchantHistoryPage: Decodable, Sendable {
    public let branchId: UUID
    public let fulfilments: [DastakV1MerchantFulfilment]
    public let nextCursor: DastakMerchantHistoryCursor?
    private enum CodingKeys: String, CodingKey { case branchId, fulfilments, nextCursor }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        branchId = try values.decode(UUID.self, forKey: .branchId)
        fulfilments = try values.decode([DastakV1MerchantFulfilment].self, forKey: .fulfilments)
        guard values.contains(.nextCursor) else {
            throw DecodingError.keyNotFound(CodingKeys.nextCursor, .init(codingPath: decoder.codingPath, debugDescription: "Missing continuation"))
        }
        nextCursor = try values.decodeIfPresent(DastakMerchantHistoryCursor.self, forKey: .nextCursor)
    }

    public static func isHistorical(_ value: DastakV1MerchantFulfilment) -> Bool {
        ["COMPLETED", "RELEASED"].contains(value.status) || [
            "DELIVERED", "CANCELLED", "CANCELLED_PREPAYMENT", "PAYMENT_EXPIRED", "UNAVAILABLE",
            "DELIVERY_FAILED", "RETURNED", "REFUNDED", "DASTAK_FULFILMENT_FAILURE"
        ].contains(value.orderStatus)
    }
    public func validates(branch: UUID, previous: DastakMerchantHistoryCursor?, limit: Int) -> Bool {
        branchId == branch && fulfilments.count <= limit
            && Set(fulfilments.map(\.id)).count == fulfilments.count
            && fulfilments.allSatisfy { $0.branch.id == branch && $0.version > 0 && Self.isHistorical($0) }
            && (nextCursor == nil || (nextCursor != previous && nextCursor?.id == fulfilments.last?.id
                && fulfilments.count == limit && nextCursor?.validTimestamp == true))
    }
}

public struct SupabaseDastakMerchantHistoryClient: Sendable {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    private struct Request: SingleAttemptFunctionRequest {
        let operation = "merchantFulfilmentHistory"
        let branchId: UUID
        let beforeAt: String?
        let beforeId: UUID?
        let limit: Int
    }
    public func page(branch: UUID, before: DastakMerchantHistoryCursor?, limit: Int = 50,
                     key: IdempotencyKey) async throws -> DastakMerchantHistoryPage {
        guard (1...100).contains(limit) else { throw FunctionClientError.invalidResponse }
        let value: DastakMerchantHistoryPage = try await functions.invoke("dastak-v1-orders",
            request: Request(branchId: branch, beforeAt: before?.committedAt, beforeId: before?.id, limit: limit),
            idempotencyKey: key)
        guard value.validates(branch: branch, previous: before, limit: limit) else { throw FunctionClientError.invalidResponse }
        return value
    }
}
