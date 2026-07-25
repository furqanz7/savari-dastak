public enum RefundDecision: String, Codable, Equatable, Sendable {
    case noPayment = "no_payment"
    case full
    case ownerOrMerchantFailure = "owner_or_merchant_failure"
    case deliveryFeeRetainedUnlessFault = "delivery_fee_retained_unless_fault"
    case notRefundable = "not_refundable"
    case alreadyResolved = "already_resolved"
}

public struct RefundEligibility: Codable, Equatable, Sendable {
    public let status: DeliveryStatus

    public init(status: DeliveryStatus) {
        self.status = status
    }

    public var decision: RefundDecision {
        switch status {
        case .paymentPending:
            .noPayment
        case .paid:
            .full
        case .merchantAccepted, .ready, .assigned, .enRouteToPickup, .atStore:
            .ownerOrMerchantFailure
        case .pickedUp, .inTransit, .returningToMerchant:
            .deliveryFeeRetainedUnlessFault
        case .delivered:
            .notRefundable
        case .cancelled:
            .alreadyResolved
        }
    }
}
