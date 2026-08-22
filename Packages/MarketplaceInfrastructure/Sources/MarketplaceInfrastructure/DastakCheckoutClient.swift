import Foundation
import MarketplaceFoundation

public enum DastakCheckoutEntityType: String, Codable, Equatable, Sendable {
    case merchantOrder = "merchant_order"
    case parcel
    case dastakV1Order = "dastak_v1_order"
}

public struct DastakCheckoutSession: Codable, Equatable, Sendable {
    public let orderID: UUID
    public let entityType: DastakCheckoutEntityType
    public let attemptID: UUID?
    public let providerOrderID: String
    public let keyID: String
    public let amountPaise: Int
    public let currency: String
    public let receipt: String

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
        case entityType
        case attemptID = "attemptId"
        case providerOrderID = "providerOrderId"
        case keyID = "keyId"
        case amountPaise
        case currency
        case receipt
    }

    // Older deployed payment responses did not include entityType. Keep those
    // sessions usable while the updated Edge Function rolls out.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderID = try container.decode(UUID.self, forKey: .orderID)
        entityType = try container.decodeIfPresent(DastakCheckoutEntityType.self, forKey: .entityType) ?? .merchantOrder
        attemptID = try container.decodeIfPresent(UUID.self, forKey: .attemptID)
        providerOrderID = try container.decode(String.self, forKey: .providerOrderID)
        keyID = try container.decode(String.self, forKey: .keyID)
        amountPaise = try container.decode(Int.self, forKey: .amountPaise)
        currency = try container.decode(String.self, forKey: .currency)
        receipt = try container.decode(String.self, forKey: .receipt)
    }
}

public enum DastakV1CheckoutFailureCode: String, Codable, Equatable, Sendable {
    case checkoutFailed = "CHECKOUT_FAILED"
    case checkoutDismissed = "CHECKOUT_DISMISSED"
}

public struct DastakV1PaymentAttemptResult: Codable, Equatable, Sendable {
    public let attemptID: UUID
    public let status: String

    private enum CodingKeys: String, CodingKey {
        case attemptID = "attemptId"
        case status
    }
}

public enum DastakRefundState: String, Codable, Equatable, Sendable {
    case pending
    case processed
}

public struct DastakRefundResult: Codable, Equatable, Sendable {
    public let orderID: UUID
    public let refundState: DastakRefundState

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
        case refundState
    }
}

public protocol DastakCheckoutClient: Sendable {
    func createMerchantOrderCheckout(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakCheckoutSession

    func createParcelCheckout(
        parcelID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakCheckoutSession

    func createV1OrderCheckout(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakCheckoutSession

    func reportV1CheckoutFailure(
        orderID: UUID,
        attemptID: UUID,
        failureCode: DastakV1CheckoutFailureCode,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1PaymentAttemptResult

    func processMerchantOrderRefund(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakRefundResult

    func processParcelRefund(
        parcelID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakRefundResult
}

public struct SupabaseDastakCheckoutClient: DastakCheckoutClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let entityType: DastakCheckoutEntityType?
        let orderId: UUID?
        let parcelId: UUID?
        let paymentAttemptId: UUID?
        let failureCode: DastakV1CheckoutFailureCode?
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func createMerchantOrderCheckout(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakCheckoutSession {
        try await invoke(
            Request(
                operation: "createCheckout",
                entityType: nil,
                orderId: orderID,
                parcelId: nil,
                paymentAttemptId: nil,
                failureCode: nil
            ),
            key: idempotencyKey
        )
    }

    public func createParcelCheckout(
        parcelID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakCheckoutSession {
        try await invoke(
            Request(
                operation: "createCheckout",
                entityType: .parcel,
                orderId: nil,
                parcelId: parcelID,
                paymentAttemptId: nil,
                failureCode: nil
            ),
            key: idempotencyKey
        )
    }

    public func createV1OrderCheckout(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakCheckoutSession {
        try await invoke(
            Request(
                operation: "createCheckout",
                entityType: .dastakV1Order,
                orderId: orderID,
                parcelId: nil,
                paymentAttemptId: nil,
                failureCode: nil
            ),
            key: idempotencyKey
        )
    }

    public func reportV1CheckoutFailure(
        orderID: UUID,
        attemptID: UUID,
        failureCode: DastakV1CheckoutFailureCode,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1PaymentAttemptResult {
        try await invoke(
            Request(
                operation: "reportPaymentFailure",
                entityType: .dastakV1Order,
                orderId: orderID,
                parcelId: nil,
                paymentAttemptId: attemptID,
                failureCode: failureCode
            ),
            key: idempotencyKey
        )
    }

    public func processMerchantOrderRefund(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakRefundResult {
        try await invoke(
            Request(
                operation: "processRefund",
                entityType: nil,
                orderId: orderID,
                parcelId: nil,
                paymentAttemptId: nil,
                failureCode: nil
            ),
            key: idempotencyKey
        )
    }

    public func processParcelRefund(
        parcelID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakRefundResult {
        try await invoke(
            Request(
                operation: "processRefund",
                entityType: .parcel,
                orderId: nil,
                parcelId: parcelID,
                paymentAttemptId: nil,
                failureCode: nil
            ),
            key: idempotencyKey
        )
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke(
            "dastak-payments",
            request: request,
            idempotencyKey: key
        )
    }
}
