import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public struct DastakOrderActivity: Codable, Sendable {
    /// Customer presentation can change with a mission without changing the
    /// order's payment/preparation state or its version.
    public static func presentationStatus(orderStatus: String, trackingPhase: String?, fulfilmentState: String? = nil) -> String {
        if orderStatus == "OUT_FOR_DELIVERY", trackingPhase == "ARRIVED" { return "RIDER_ARRIVED" }
        if ["PAID", "PREPARING"].contains(orderStatus), fulfilmentState == "ASSIGNING_RIDER",
           trackingPhase == nil || trackingPhase == "SEARCHING_RIDER" { return "ASSIGNING_RIDER" }
        return orderStatus
    }
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String
        public var version: Int
        public var updatedAt: Double
        public init(status: String, version: Int, updatedAt: Double) {
            self.status = status; self.version = version; self.updatedAt = updatedAt
        }
        public var stage: Int {
            switch status {
            case "PAID", "PREPARING", "ASSIGNING_RIDER": 1
            case "PICKUP_IN_PROGRESS": 2
            case "OUT_FOR_DELIVERY", "RIDER_ARRIVED": 3
            case "DELIVERED": 4
            default: 0
            }
        }
        public var terminal: Bool {
            ["DELIVERED", "UNAVAILABLE", "PAYMENT_EXPIRED", "CANCELLED_PREPAYMENT", "CANCELLED", "DASTAK_FULFILMENT_FAILURE", "ENDED"].contains(status)
        }
        public var title: String {
            switch status {
            case "CREATED", "MATCHING": "Finding your items"
            case "FULLY_SECURED", "AWAITING_PAYMENT": "Ready to confirm"
            case "PAID", "PREPARING": "Preparing your order"
            case "ASSIGNING_RIDER": "Assigning your rider"
            case "PICKUP_IN_PROGRESS": "Picking up your order"
            case "OUT_FOR_DELIVERY": "On the way to you"
            case "RIDER_ARRIVED": "Rider arrived"
            case "DELIVERED": "Delivered. Enjoy!"
            case "CANCELLED", "CANCELLED_PREPAYMENT": "Order cancelled"
            case "PAYMENT_EXPIRED": "Reservation expired"
            case "UNAVAILABLE": "Items unavailable"
            case "DASTAK_FULFILMENT_FAILURE": "Delivery interrupted"
            default: "Open Dastak for updates"
            }
        }
        public var shortTitle: String {
            switch stage {
            case 1: status == "ASSIGNING_RIDER" ? "Assigning rider" : "Preparing"
            case 2: "Pickup"
            case 3: status == "RIDER_ARRIVED" ? "At your door" : "On the way"
            case 4: "Delivered"
            default: terminal ? "Ended" : "Confirming"
            }
        }
        public var symbol: String {
            if terminal { return status == "DELIVERED" ? "checkmark.circle.fill" : "xmark.circle" }
            if status == "RIDER_ARRIVED" { return "door.left.hand.open" }
            if status == "ASSIGNING_RIDER" { return "person.badge.clock" }
            return ["bag", "takeoutbag.and.cup.and.straw", "shippingbox", "scooter", "checkmark.circle.fill"][stage]
        }
        public var canCallRider: Bool { status == "OUT_FOR_DELIVERY" || status == "RIDER_ARRIVED" }
        /// Milestones, not inferred GPS distance or an invented ETA.
        public var journeyProgress: Double {
            if status == "RIDER_ARRIVED" || status == "DELIVERED" { return 1 }
            return [0.0, 0.16, 0.38, 0.68, 1.0][stage]
        }
        public var detail: String {
            switch status {
            case "RIDER_ARRIVED": "Your delivery partner is at your door"
            case "ASSIGNING_RIDER": "Finding a delivery partner for your order"
            case "OUT_FOR_DELIVERY": "The last stretch to your doorstep"
            case "PICKUP_IN_PROGRESS": "Your delivery partner is collecting your order"
            case "PAID", "PREPARING": "A little care. Then on its way."
            case "DELIVERED": "A little Dastak, delivered."
            default: title
            }
        }
    }
    public let orderID: String
    public let accountID: String
    public let orderNumber: String
    public let isFood: Bool
    public init(orderID: String, accountID: String, orderNumber: String, isFood: Bool) {
        self.orderID = orderID; self.accountID = accountID
        self.orderNumber = orderNumber; self.isFood = isFood
    }
    public var serviceSymbol: String { isFood ? "fork.knife" : "basket" }
    public var serviceName: String { isFood ? "Food" : "Grocery" }
    public var url: URL? {
        guard UUID(uuidString: orderID) != nil else { return nil }
        return URL(string: "com.dastak.app://order/\(orderID)")
    }
    /// Resolve the current assigned partner inside the authenticated app. No
    /// phone number or delivery address is copied into a Lock Screen payload.
    public var callURL: URL? {
        url.flatMap { URL(string: $0.absoluteString + "?action=call-rider") }
    }
}
#if canImport(ActivityKit) && os(iOS)
extension DastakOrderActivity: ActivityAttributes {}
#endif
