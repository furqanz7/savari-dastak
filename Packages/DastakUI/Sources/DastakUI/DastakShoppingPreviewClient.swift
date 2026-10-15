#if DEBUG
import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// Synthetic, in-memory UI scenarios. No network transport and no fallback to a live client.
actor DastakShoppingPreviewClient: FunctionClient {
    private var saved: [[String: String]] = [
        ["kind": "RETAIL_SKU", "itemId": "11111111-1111-4111-8111-111111111111", "createdAt": "2026-10-11T00:00:00Z"],
        ["kind": "MENU_ITEM", "itemId": "ffffffff-ffff-4fff-8fff-ffffffffffff", "createdAt": "2026-10-11T00:00:00Z"],
        ["kind": "RETAIL_SKU", "itemId": "dddddddd-0000-4000-8000-000000000001", "createdAt": "2026-10-11T00:00:00Z"]
    ]

    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Response {
        guard let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any],
              let operation = body["operation"] as? String else { throw FunctionClientError.invalidResponse }
        let response: Any
        switch (name, operation) {
        case ("dastak-v1-catalogue", "customerCatalogue"):
            guard var catalogue = try Self.object(DastakCustomerModel.previewCatalogueJSON) as? [String: Any] else {
                throw FunctionClientError.invalidResponse
            }
            let query = (body["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if query.lowercased() == "offline" { throw URLError(.notConnectedToInternet) }
            if !query.isEmpty {
                let products = catalogue["skus"] as? [[String: Any]] ?? []
                catalogue["skus"] = products.filter { ($0["name"] as? String ?? "").localizedCaseInsensitiveContains(query) }
            }
            response = catalogue
        case ("dastak-v1-catalogue", "customerRestaurants"):
            response = ["restaurants": try Self.object(String(decoding: DastakCustomerModel.previewRestaurantsData, as: UTF8.self))]
        case ("dastak-v1-orders", "list"):
            response = ["orders": Self.orders(), "nextCursor": NSNull()]
        case ("merchant-orders", "customerSnapshot"):
            response = ["orders": []]
        case ("parcel-deliveries", "customerSnapshot"):
            response = [Any]()
        case ("customer-wishlist", "snapshot"):
            response = ["items": saved]
        case ("customer-wishlist", "set"):
            guard let kind = body["itemKind"] as? String, ["RETAIL_SKU", "MENU_ITEM"].contains(kind),
                  let id = body["itemId"] as? String, UUID(uuidString: id) != nil,
                  let wished = body["wished"] as? Bool else { throw FunctionClientError.invalidResponse }
            saved.removeAll { $0["kind"] == kind && $0["itemId"]?.lowercased() == id.lowercased() }
            if wished { saved.append(["kind": kind, "itemId": id, "createdAt": "2026-10-11T00:00:00Z"]) }
            response = ["items": saved]
        default:
            // Fail closed: no submits, confirmations, address/account writes, payments or unrelated endpoints.
            throw FunctionClientError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
    }

    private static func object(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    private static func orders() -> [[String: Any]] {
        let retail: [String: Any] = ["id": "00000000-0000-4000-8000-000000000011", "lineType": "RETAIL_SKU",
            "skuId": "11111111-1111-4111-8111-111111111111", "name": "Fresh whole milk", "packSize": "1 litre",
            "quantity": 1, "unitPricePaise": 6800, "lineTotalPaise": 6800, "status": "DELIVERED"]
        let food: [String: Any] = ["id": "00000000-0000-4000-8000-000000000012", "lineType": "FOOD_MENU_ITEM",
            "menuItemId": "ffffffff-ffff-4fff-8fff-ffffffffffff", "name": "Sample rice bowl",
            "quantity": 1, "unitPricePaise": 12000, "lineTotalPaise": 12000, "status": "DELIVERED"]
        return [false, true].map { mixed in
            let subtotal = mixed ? 18800 : 6800
            let fee = mixed ? 406 : 166
            var order: [String: Any] = ["id": mixed ? "00000000-0000-4000-8000-000000000022" : "00000000-0000-4000-8000-000000000021",
                "displayOrderNumber": mixed ? "SAMPLE-MIXED" : "SAMPLE-GROCERY", "orderType": "RETAIL", "status": "DELIVERED", "version": 1,
                "createdAt": "2026-10-10T00:00:00Z", "updatedAt": "2026-10-10T00:00:00Z",
                "price": ["snapshotKind": "FINAL", "subtotalPaise": subtotal, "deliveryFeePaise": 1500,
                    "platformFeePaise": fee, "taxPaise": 0, "discountPaise": 0, "totalPaise": subtotal + 1500 + fee, "currencyCode": "INR"],
                "lines": mixed ? [retail, food] : [retail]]
            if mixed {
                order["restaurant"] = ["organizationId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    "branchId": "dddddddd-dddd-4ddd-8ddd-dddddddddddd", "name": "Preview Kitchen", "branchName": "Sample branch"]
            }
            return order
        }
    }
}
#endif
