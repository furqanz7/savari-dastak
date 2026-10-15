import Foundation
import MarketplaceFoundation

public struct DastakDeliveryOrderDetail: Decodable, Sendable {
    public let kind: String
    public let workId: UUID
    public let missionStatus: String
    public let terminal: Bool
    public let order: DastakV1OrderSnapshot
    public let pickupStops: [Stop]
    public let collection: DastakV1LaunchCollection?

    public struct Stop: Decodable, Identifiable, Sendable {
        public let id: UUID
        public let sequence: Int
        public let status: String?
        public let packageCount: Int?
        public let name: String
        public let address: String
        enum CodingKeys: String, CodingKey { case id, sequence, status, packageCount, name, address, branch }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            sequence = try c.decode(Int.self, forKey: .sequence)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            packageCount = try c.decodeIfPresent(Int.self, forKey: .packageCount)
            if let branch = try? c.decode(DastakV1OfferStop.Branch.self, forKey: .branch) {
                name = branch.displayName; address = branch.address.display
            } else {
                name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Pickup"
                address = (try? c.decode(String.self, forKey: .address))
                    ?? (try? c.decode(DastakV1ReturnMission.Address.self, forKey: .address).display) ?? "Address unavailable"
            }
        }
    }
}

public struct DastakDeliveryOrderDetailClient: Sendable {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    public func detail(kind: String, workID: UUID) async throws -> DastakDeliveryOrderDetail {
        guard ["V1_DELIVERY", "RETURN", "LEGACY_DELIVERY", "PARCEL"].contains(kind) else { throw FunctionClientError.invalidResponse }
        struct Request: Encodable, Sendable { let operation = "partnerOrderDetail"; let kind: String; let workId: UUID }
        let reply: DastakDeliveryOrderDetail = try await functions.invoke("courier-dispatch",
            request: Request(kind: kind, workId: workID), idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!)
        let price = reply.order.price
        guard reply.kind == kind, reply.workId == workID, !reply.order.lines.isEmpty,
              price.currencyCode == "INR", [price.subtotalPaise, price.deliveryFeePaise, price.platformFeePaise, price.discountPaise, price.taxPaise, price.totalPaise].allSatisfy({ $0 >= 0 }),
              Set(reply.order.lines.map(\.id)).count == reply.order.lines.count,
              reply.order.lines.allSatisfy({ !$0.name.isEmpty && $0.quantity > 0 && $0.unitPricePaise >= 0 && $0.lineTotalPaise >= 0 }),
              Set(reply.pickupStops.map(\.id)).count == reply.pickupStops.count,
              reply.pickupStops.allSatisfy({ $0.sequence > 0 && ($0.packageCount ?? 0) >= 0 }),
              !reply.terminal || (reply.order.deliveryAddress == nil && reply.order.recipient == nil)
        else { throw FunctionClientError.invalidResponse }
        return reply
    }
}
