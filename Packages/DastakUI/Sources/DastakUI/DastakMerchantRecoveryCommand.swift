import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// Only the original target/receipt fields are retained; never persist pickup PINs or rider tracking.
struct DastakMerchantRecoveryCommand: Codable, Equatable, Sendable {
    struct Fulfilment: Codable, Equatable, Sendable {
        struct Line: Codable, Equatable, Sendable { let id: UUID; let name: String; let quantity: Int; let packSize: String?; let variant: String? }
        let id: UUID
        let orderID: UUID
        let displayOrderNumber: String
        let status: String
        let version: Int
        let branch: DastakV1MerchantBranch
        let lines: [Line]
        init(_ value: DastakV1MerchantFulfilment) {
            id = value.id; orderID = value.orderID; displayOrderNumber = value.displayOrderNumber
            status = value.status; version = value.version; branch = value.branch
            lines = value.lines.map { .init(id: $0.id, name: $0.name, quantity: $0.quantity, packSize: $0.packSize, variant: $0.variant) }
        }
    }
    enum Operation: Codable, Equatable, Sendable {
        case exactFailure(Fulfilment, lineID: UUID, reason: String)
        case problem(Fulfilment, reason: String)
        case response(DastakV1RecoveryOpportunity, accept: Bool, prepMinutes: Int)
    }
    let operation: Operation
    let key: IdempotencyKey
    var branchID: UUID {
        switch operation { case let .exactFailure(order, _, _), let .problem(order, _): order.branch.id; case let .response(offer, _, _): offer.branch.id }
    }
    var valid: Bool {
        guard UUID(uuidString: key.rawValue) != nil else { return false }
        switch operation {
        case let .exactFailure(order, line, reason): return order.version > 0 && order.version < Int.max && reason.count >= 3 && reason.utf16.count <= 500 && order.lines.contains { $0.id == line && $0.quantity > 0 }
        case let .problem(order, reason): return order.version > 0 && order.version < Int.max && reason.count >= 3 && reason.utf16.count <= 500 && ["PREPARING", "READY"].contains(order.status)
        case let .response(offer, accept, minutes): return offer.version > 0 && offer.version < Int.max && offer.requestedQuantity > 0 && (accept ? (1...1440).contains(minutes) : minutes == 0)
        }
    }
    var orderID: UUID {
        switch operation {
        case let .exactFailure(order, _, _), let .problem(order, _): order.orderID
        case let .response(offer, _, _): offer.orderId
        }
    }
    var description: String {
        switch operation {
        case let .exactFailure(order, lineID, _):
            "Report unavailable item: \(order.lines.first { $0.id == lineID }?.name ?? "item") · \(order.displayOrderNumber)"
        case let .problem(order, _): "Report fulfilment problem · \(order.displayOrderNumber)"
        case let .response(offer, accept, _): "\(accept ? "Accept" : "Decline") recovery · \(offer.requestedQuantity) × \(offer.sku.name) · \(offer.sku.packSize)"
        }
    }
    var detail: String {
        switch operation {
        case let .exactFailure(order, lineID, reason):
            let line = order.lines.first { $0.id == lineID }
            return "\(order.branch.displayName) · \(line?.quantity ?? 0) × \(line?.packSize ?? line?.variant ?? "exact item") · \(reason)"
        case let .problem(order, reason): return "\(order.branch.displayName) · \(reason)"
        case let .response(offer, accept, minutes):
            return "\(offer.branch.displayName) · \(accept ? "Physical stock confirmed; preparation \(minutes) minutes." : "Item unavailable.")"
        }
    }
}
