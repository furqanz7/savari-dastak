import Foundation
import MarketplaceFoundation

public struct DastakMerchantInventoryCursor: Codable, Equatable, Sendable {
    public let name: String
    public let skuId: UUID
}
public struct DastakMerchantInventoryPage: Codable, Sendable {
    public let branchId: UUID
    public let skus: [DastakV1MerchantCatalogueSnapshot.SKU]
    public let nextCursor: DastakMerchantInventoryCursor?
}
public struct DastakMerchantDirectoryLocation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let merchantType: String
    public let canManageStore: Bool
}
public struct DastakMerchantLocationsPage: Codable, Sendable {
    public let locations: [DastakMerchantDirectoryLocation]
    public let focusedLocation: DastakMerchantDirectoryLocation?
    public let nextCursor: UUID?
}
public protocol DastakMerchantDiscoveryClient: Sendable {
    func inventory(branch: UUID, query: String, selectedOnly: Bool, after: DastakMerchantInventoryCursor?, key: IdempotencyKey) async throws -> DastakMerchantInventoryPage
    func locations(after: UUID?, focus: UUID?, key: IdempotencyKey) async throws -> DastakMerchantLocationsPage
}
public struct SupabaseDastakMerchantDiscoveryClient: DastakMerchantDiscoveryClient {
    private let functions: any FunctionClient
    public init(functions: any FunctionClient) { self.functions = functions }
    public func inventory(branch: UUID, query: String, selectedOnly: Bool, after: DastakMerchantInventoryCursor?, key: IdempotencyKey) async throws -> DastakMerchantInventoryPage {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf16.count<=80 else { throw FunctionClientError.invalidResponse }
        let result: DastakMerchantInventoryPage = try await functions.invoke("dastak-v1-catalogue",
            request: InventoryRequest(operation: "merchantInventoryPage",branchId: branch,query: value.isEmpty ? nil : value,
                selectedOnly: selectedOnly,limit: 100,cursor: after), idempotencyKey: key)
        guard result.branchId == branch, result.skus.count<=100, Set(result.skus.map(\.id)).count == result.skus.count,
              result.skus.allSatisfy({ $0.selectionVersion>=0 && $0.currencyCode=="INR" && $0.sellingPricePaise>=0 }),
              result.nextCursor == nil || (result.nextCursor != after && result.nextCursor?.skuId == result.skus.last?.id && result.nextCursor?.name == result.skus.last?.name)
        else { throw FunctionClientError.invalidResponse }
        return result
    }
    public func locations(after: UUID?, focus: UUID?, key: IdempotencyKey) async throws -> DastakMerchantLocationsPage {
        let result: DastakMerchantLocationsPage = try await functions.invoke("dastak-v1-catalogue",
            request: LocationsRequest(operation: "merchantLocationsPage",limit: 100,afterId: after,focusId: focus),idempotencyKey: key)
        guard result.locations.count<=100, Set(result.locations.map(\.id)).count == result.locations.count,
              after == nil || result.locations.allSatisfy({ $0.id.uuidString > after!.uuidString }),
              result.focusedLocation == nil || result.focusedLocation?.id == focus,
              result.nextCursor == nil || (result.nextCursor != after && result.nextCursor == result.locations.last?.id)
        else { throw FunctionClientError.invalidResponse }
        return result
    }
    private struct InventoryRequest: Encodable, Sendable {
        let operation: String; let branchId: UUID; let query: String?; let selectedOnly: Bool; let limit: Int; let cursor: DastakMerchantInventoryCursor?
    }
    private struct LocationsRequest: Encodable, Sendable {
        let operation: String; let limit: Int; let afterId: UUID?; let focusId: UUID?
    }
}

public extension DastakV1MerchantCatalogueSnapshot {
    func mergingInventory(_ rows: [SKU]) -> Self {
        var positions = Dictionary(uniqueKeysWithValues: skus.enumerated().map { ($0.element.id,$0.offset) })
        var merged = skus
        for sku in rows {
            if let index = positions[sku.id] {
                if merged[index].selectionVersion <= sku.selectionVersion { merged[index] = sku }
            }
            else { positions[sku.id] = merged.count; merged.append(sku) }
        }
        return .init(branch: branch,categoryTypes: categoryTypes,categories: categories,subcategories: subcategories,skus: merged,truncated: truncated)
    }
}
