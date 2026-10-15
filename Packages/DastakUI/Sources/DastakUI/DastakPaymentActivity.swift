import MarketplaceInfrastructure

/// Confirmation is not collection: never infer a payment from PAID workflow status.
enum DastakPaymentActivity {
    static func title(_ order: DastakV1OrderSnapshot) -> String? {
        if let launch = order.launchPayment {
            if launch.collectedAt != nil {
                return launch.collectionMethod == .cash ? "Collected by cash" : launch.collectionMethod == .upi ? "Collected by UPI" : "Payment collected"
            }
            switch order.status {
            case .cancelled, .cancelledPrepayment, .paymentExpired, .unavailable, .fulfilmentFailure:
                return "No payment collection recorded"
            default: break
            }
            if launch.state == .collectionRetryNeeded { return "Collection needs attention" }
            if launch.committedAt != nil { return "Confirmed — pay at delivery" }
            if launch.canCommit { return "Awaiting order confirmation" }
            return nil
        }
        return order.paidAt != nil ? "Payment recorded" : nil
    }

    static func timestamp(_ order: DastakV1OrderSnapshot) -> String? {
        if let launch = order.launchPayment { return launch.collectedAt ?? launch.committedAt ?? order.updatedAt }
        return order.paidAt
    }
}
