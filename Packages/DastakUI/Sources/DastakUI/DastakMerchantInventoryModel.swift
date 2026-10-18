import Foundation
import SwiftUI
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakMerchantInventoryContext: Hashable {
    let branch: UUID
    let query: String
    let selectedOnly: Bool
    let revision: UUID
    let checkedAt: Date?
}
@MainActor
final class DastakMerchantInventoryModel: ObservableObject {
    @Published private(set) var rows: [DastakV1MerchantCatalogueSnapshot.SKU] = []
    @Published private(set) var cursor: DastakMerchantInventoryCursor?
    @Published private(set) var loading = false
    @Published private(set) var current = false
    @Published private(set) var failure: String?
    @Published private(set) var context: DastakMerchantInventoryContext?
    private let services: MarketplaceAuthenticatedServices
    private let client: any DastakMerchantDiscoveryClient
    private let timeout: Duration
    private var generation = UUID()
    private var seen: Set<String> = []
    private var owner: UUID?
    init(services: MarketplaceAuthenticatedServices, client: any DastakMerchantDiscoveryClient, timeout: Duration = .seconds(12)) {
        self.services = services; self.client = client; self.timeout = timeout
    }
    func invalidate() { generation = UUID(); loading = false; current = false }
    func load(_ input: DastakMerchantInventoryContext, more: Bool = false) async {
        guard !more || (input == context && cursor != nil && current && !loading) else { return }
        let token = UUID(); generation = token
        guard input.query.utf16.count<=80 else {
            context = input; rows = []; cursor = nil; loading = false; current = false
            failure = "Use up to 80 characters for a product, brand, pack or category search."; return
        }
        let after = more ? cursor : nil
        if !more { rows = []; cursor = nil; seen = [] }
        context = input; loading = true; current = false; failure = nil
        defer { if generation == token { loading = false } }
        do {
            let previous = more ? owner : nil
            let response = try await MarketplaceRequestDeadline.run(after: timeout) { [services,client] in
                let account = try await services.accountID()
                guard previous == nil || previous == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                let result = try await client.inventory(branch: input.branch,query: input.query,selectedOnly: input.selectedOnly,after: after,
                    key: IdempotencyKey(rawValue: UUID().uuidString)!)
                guard account == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return (account,result)
            }
            guard generation == token, !Task.isCancelled else { return }
            let page = response.1
            if let next = page.nextCursor {
                let fingerprint = next.name + ":" + next.skuId.uuidString
                guard seen.insert(fingerprint).inserted else { throw FunctionClientError.invalidResponse }
            }
            var values = more ? rows : []
            var positions = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element.id,$0.offset) })
            for row in page.skus {
                if let index = positions[row.id] { values[index] = row }
                else { positions[row.id] = values.count; values.append(row) }
            }
            owner = response.0; rows = values; cursor = page.nextCursor; current = true
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            rows = []; cursor = nil; current = false
            failure = "The complete catalogue could not be searched. Retry the paged read; no empty-catalogue claim or new product change is made from this failure."
            if case let FunctionClientError.api(status,_,_) = error, status == 400 {
                failure = "Use product words and up to 80 characters. The catalogue query was not accepted."
            }
        }
    }
}
