import Foundation
import MarketplaceFoundation

public struct DastakV1AreaContext: Codable, Equatable, Sendable {
    public let addressId: UUID
    public let addressVersion: String

    public init(addressID: UUID, addressVersion: String) {
        self.addressId = addressID
        self.addressVersion = addressVersion
    }

    public func matches(_ other: Self) -> Bool {
        addressId == other.addressId && Self.date(addressVersion) != nil
            && Self.date(addressVersion) == Self.date(other.addressVersion)
    }

    public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

public struct DastakV1AreaAvailability: Codable, Equatable, Sendable {
    public let addressId: UUID
    public let addressVersion: String
    public let checkedAt: String
    public let groceryServiceable: Bool
    public let foodServiceable: Bool
    public let deliveryAvailable: Bool
    public let stock: [String: Int]
    public let restaurants: [String: Bool]
    /// Nil means the server has not supplied a ranking; [] means no local history.
    public let trendingSkus: [DastakV1CatalogueSKU]?

    public func validate(context: DastakV1AreaContext) throws {
        guard context.matches(.init(addressID: addressId, addressVersion: addressVersion)),
              DastakV1AreaContext.date(checkedAt) != nil,
              stock.allSatisfy({ UUID(uuidString: $0.key) != nil && (1...1_000_000).contains($0.value) }),
              restaurants.keys.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw FunctionClientError.invalidResponse
        }
        if let trendingSkus {
            guard trendingSkus.count <= 250, Set(trendingSkus.map(\.id)).count == trendingSkus.count,
                  trendingSkus.allSatisfy({ !$0.name.isEmpty && $0.currencyCode == "INR"
                    && $0.sellingPricePaise >= 0 && $0.listPricePaise >= $0.sellingPricePaise }) else {
                throw FunctionClientError.invalidResponse
            }
        }
    }

    public func quantity(for id: UUID) -> Int {
        stock[id.uuidString.lowercased()] ?? stock[id.uuidString] ?? 0
    }

    public func restaurantOpen(_ id: UUID) -> Bool? {
        restaurants[id.uuidString.lowercased()] ?? restaurants[id.uuidString]
    }
}

public struct DastakV1CheckoutQuote: Codable, Equatable, Sendable {
    public let addressId: UUID
    public let addressVersion: String
    public let lines: [DastakV1OrderLineInput]
    public let restaurantBranchId: UUID?
    public let kind: String
    public let currencyCode: String
    public let pricingVersion: Int
    public let checkedAt: String
    public let validUntil: String
    public let subtotalPaise: Int
    public let deliveryDistanceMeters: Int
    public let deliveryFeePaise: Int
    public let platformFeePaise: Int
    public let taxPaise: Int
    public let discountPaise: Int
    public let totalPaise: Int
    public let deliveryAvailable: Bool

    public func validate(context: DastakV1AreaContext, lines: [DastakV1OrderLineInput], branchID: UUID?) throws {
        guard context.matches(.init(addressID: addressId, addressVersion: addressVersion)),
              self.lines == lines, restaurantBranchId == branchID,
              kind == "ESTIMATE", currencyCode == "INR", pricingVersion == 1,
              let checked = DastakV1AreaContext.date(checkedAt),
              let until = DastakV1AreaContext.date(validUntil), until > checked,
              until.timeIntervalSince(checked) <= 45,
              (0...41_000_000).contains(deliveryDistanceMeters),
              [subtotalPaise, deliveryFeePaise, platformFeePaise, taxPaise, discountPaise, totalPaise]
                .allSatisfy({ (0...1_000_000_000_000).contains($0) }) else {
            throw FunctionClientError.invalidResponse
        }
        let distance = deliveryDistanceMeters
        let delivery = distance <= 1000 ? 1500 : distance <= 2000 ? 2000 : 2000 + 500 * ((distance - 2000 + 999) / 1000)
        let base = subtotalPaise + deliveryFeePaise
        guard deliveryFeePaise == delivery, platformFeePaise == (base * 200 + 5000) / 10000,
              totalPaise == base + platformFeePaise + taxPaise - discountPaise else {
            throw FunctionClientError.invalidResponse
        }
    }
}

public struct DastakV1RestaurantAreaCursor: Codable, Equatable, Sendable {
    public let name: String
    public let branchId: UUID
    public let distanceMeters: Int?
    public let addressId: UUID
    public let addressVersion: String
}

public struct DastakV1RestaurantAreaPage: Decodable, Sendable {
    public let restaurants: [DastakV1RestaurantMenu]
    public let nextCursor: DastakV1RestaurantAreaCursor?
    public let ordering: String
    public let addressId: UUID
    public let addressVersion: String
}

struct DastakV1AreaRequest: Encodable, Sendable {
    let operation: String
    let addressId: UUID
    let addressVersion: String
    var lines: [DastakV1OrderLineInput]? = nil
    var restaurantBranchId: UUID? = nil
    var limit: Int? = nil
    var cursor: DastakV1RestaurantAreaCursor? = nil
}

public extension DastakV1CustomerClient {
    // Older/preview clients must fail closed, never fabricate local stock or prices.
    func areaAvailability(context: DastakV1AreaContext, idempotencyKey: IdempotencyKey) async throws -> DastakV1AreaAvailability { throw FunctionClientError.invalidResponse }
    func checkoutQuote(context: DastakV1AreaContext, lines: [DastakV1OrderLineInput], branchID: UUID?, idempotencyKey: IdempotencyKey) async throws -> DastakV1CheckoutQuote { throw FunctionClientError.invalidResponse }
    func restaurantAreaPage(context: DastakV1AreaContext, cursor: DastakV1RestaurantAreaCursor?, idempotencyKey: IdempotencyKey) async throws -> DastakV1RestaurantAreaPage { throw FunctionClientError.invalidResponse }
}
