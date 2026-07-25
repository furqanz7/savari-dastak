import Foundation

public struct MerchantOrderLine: Codable, Equatable, Sendable {
    public let productID: UUID
    public let quantity: Int

    public init(productID: UUID, quantity: Int) {
        self.productID = productID
        self.quantity = quantity
    }

    private enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case quantity
    }
}

public struct MerchantOrder: Codable, Equatable, Sendable {
    public let orderID: UUID
    public let storeID: UUID
    public let lines: [MerchantOrderLine]

    public init(
        orderID: UUID,
        storeID: UUID,
        lines: [MerchantOrderLine]
    ) {
        self.orderID = orderID
        self.storeID = storeID
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
        case storeID = "storeId"
        case lines
    }
}
