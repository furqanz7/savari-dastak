import Foundation
import SwiftUI
import MarketplaceFoundation
import MarketplaceInfrastructure
import MarketplaceDesignSystem

@MainActor
final class DastakMerchantHistoryModel: ObservableObject {
    @Published private(set) var rows: [DastakV1MerchantFulfilment] = []
    @Published private(set) var cursor: DastakMerchantHistoryCursor?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published private(set) var checkedAt: Date?
    private let branch: UUID
    private let services: MarketplaceAuthenticatedServices
    private let timeout: Duration
    private var account: UUID?
    init(branch: UUID, services: MarketplaceAuthenticatedServices, timeout: Duration = .seconds(12)) {
        self.branch = branch; self.services = services; self.timeout = timeout
    }
    func load(older: Bool = false) async {
        guard !loading, !older || (cursor != nil && failure == nil) else { return }
        loading = true
        defer { loading = false }
        let before = older ? cursor : nil
        do {
            let value = try await MarketplaceRequestDeadline.run(after: timeout) { [services, branch, account, timeout] in
                let actor = try await services.accountID()
                guard account == nil || actor == account else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                let client = SupabaseDastakMerchantHistoryClient(functions: DastakMerchantFunctionClient(base: services.functions, timeout: timeout))
                let page = try await client.page(branch: branch, before: before, key: IdempotencyKey(rawValue: UUID().uuidString)!)
                guard actor == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                return (actor, page)
            }
            guard !Task.isCancelled else { return }
            account = value.0
            // A concurrent terminal-state change may repeat an ID between pages.
            // Keep one latest server snapshot per fulfilment without changing its position.
            var result = older ? rows : []
            var positions = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.id, $0.offset) })
            for row in value.1.fulfilments {
                if let index = positions[row.id] { result[index] = row }
                else { positions[row.id] = result.count; result.append(row) }
            }
            rows = result; cursor = value.1.nextCursor; checkedAt = .now; failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            if error is MarketplaceAuthenticatedServicesError { rows = []; cursor = nil; checkedAt = nil }
            if case FunctionClientError.authenticationRequired = error { rows = []; cursor = nil; checkedAt = nil }
            if case let FunctionClientError.api(status, _, _) = error, [401,403,404].contains(status) {
                rows = []; cursor = nil; checkedAt = nil
            }
            failure = "History could not be checked. Retained records are read-only; refresh history to try again."
        }
    }
}

struct DastakMerchantHistorySection: View {
    @ObservedObject var merchant: DastakMerchantModel
    @StateObject private var history: DastakMerchantHistoryModel
    init(merchant: DastakMerchantModel, branch: UUID) {
        self.merchant = merchant
        _history = StateObject(wrappedValue: merchant.makeHistory(branch))
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("Past fulfilments").font(.title3.bold())
            Text("Your store's newest commitments first. Load older orders to continue; earlier legacy orders and return records are separate.")
                .font(.footnote).foregroundStyle(.secondary)
            if let failure = history.failure { Label(failure, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange) }
            if history.loading { ProgressView("Loading history") }
            ForEach(history.rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    Text(row.displayOrderNumber).font(.headline).textSelection(.enabled)
                    Text("\(row.orderStatus.replacingOccurrences(of: "_", with: " ").capitalized) · Fulfilment \(row.status.replacingOccurrences(of: "_", with: " ").lowercased())").font(.subheadline)
                    ForEach(row.lines) { line in Text("\(line.quantity) × \(line.name)").font(.subheadline) }
                    DastakMerchantOrderDetailButton(model: merchant,
                        target: .init(kind: .fulfilment, id: row.id, branchID: row.branch.id))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18).marketplaceFlatSurface()
            }
            if history.checkedAt != nil, history.rows.isEmpty, history.failure == nil {
                Text("No past fulfilments for your store.").foregroundStyle(.secondary)
            }
            if history.cursor != nil {
                Button("Load older orders", systemImage: "clock.arrow.circlepath") { Task { await history.load(older: true) } }
                    .frame(minHeight: 44)
                    .disabled(history.loading || history.failure != nil)
            } else if !history.rows.isEmpty, history.failure == nil {
                Text("All currently available fulfilment history loaded.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Refresh history", systemImage: "arrow.clockwise") { Task { await history.load() } }.frame(minHeight: 44).disabled(history.loading)
            if let checked = history.checkedAt {
                Text("Checked \(checked.formatted(date: .abbreviated, time: .shortened)) · Refresh to include newly finished orders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.task { await history.load() }
    }
}
