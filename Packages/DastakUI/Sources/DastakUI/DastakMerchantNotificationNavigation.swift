import SwiftUI
import MarketplaceFoundation
import MarketplaceInfrastructure
import MarketplaceDesignSystem

@MainActor
final class DastakMerchantNotificationNavigator: ObservableObject {
    @Published private(set) var choices: [DastakMerchantNotificationChoice] = []
    @Published private(set) var loading = false
    @Published private(set) var message: String?
    @Published private(set) var route: DastakMerchantNotificationRoute?
    private let services: MarketplaceAuthenticatedServices
    private let timeout: Duration
    private var generation = UUID()
    init(services: MarketplaceAuthenticatedServices, timeout: Duration = .seconds(12)) {
        self.services = services; self.timeout = timeout
    }
    func cancel() { generation = UUID(); loading = false; choices = [] }
    func open(_ route: DastakMerchantNotificationRoute) async {
        let token = UUID(); generation = token
        self.route = route; choices = []; loading = true; message = nil
        defer { if generation == token { loading = false } }
        do {
            let result = try await MarketplaceRequestDeadline.run(after: timeout) { [services, timeout] in
                let actor = try await services.accountID()
                let functions = DastakMerchantFunctionClient(base: services.functions, timeout: timeout)
                async let operations = Self.read { try await SupabaseDastakV1MerchantRecoveryClient(functions: functions).feeds(idempotencyKey: Self.key()) }
                async let food = Self.read { try await SupabaseDastakV1MerchantInboxClient(functions: functions).restaurantRequests(idempotencyKey: Self.key()) }
                let (feeds, requests) = await (operations, food)
                guard actor == (try await services.accountID()) else { throw MarketplaceAuthenticatedServicesError.identityMismatch }
                if let error = feeds.error, Self.denied(error) { throw error }
                if let error = requests.error, Self.denied(error) { throw error }
                return (DastakMerchantNotificationResolution.choices(route, feeds: feeds.value, requests: requests.value ?? []),
                    feeds.error != nil || requests.error != nil || feeds.value?.fulfilments == nil)
            }
            guard token == generation, !Task.isCancelled else { return }
            choices = result.0
            message = choices.isEmpty
                ? "This alert's exact record is no longer in the available Merchant reads. It may have expired, finished, moved outside the recent window or be unavailable to this account. Use the relevant Orders queue; no action was performed."
                : result.1 ? "Some records could not be checked. Only the verified matches below are available. Opening a detail checks its permission again."
                : "Choose the authorized record to view its latest details. This does not change your Store workspace or perform an order action."
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            choices = []
            message = "The alert could not be resolved for the current Merchant account. Check your session and connection, retry, or return to Orders. No action was performed."
        }
    }
    private struct Read<Value: Sendable>: Sendable { let value: Value?; let error: Error? }
    private nonisolated static func read<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async -> Read<T> {
        do { return .init(value: try await body(), error: nil) } catch { return .init(value: nil, error: error) }
    }
    private nonisolated static func denied(_ error: Error) -> Bool {
        if case FunctionClientError.authenticationRequired = error { return true }
        if case let FunctionClientError.api(status, _, _) = error { return [401,403].contains(status) }
        return error is MarketplaceAuthenticatedServicesError
    }
    private nonisolated static func key() -> IdempotencyKey { .init(rawValue: UUID().uuidString)! }
}

struct DastakMerchantNotificationDestination: View {
    @ObservedObject var navigator: DastakMerchantNotificationNavigator
    @ObservedObject var merchant: DastakMerchantModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: DastakMerchantDetailTarget?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("From your order alert").font(.title2.bold())
                    if navigator.loading { ProgressView("Checking current Merchant records") }
                    if let message = navigator.message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(navigator.choices) { choice in
                        Button {
                            detail = choice.target
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(choice.location).font(.headline)
                                Text("\(choice.target.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) · \(choice.status.lowercased())").font(.caption)
                                Label("View full order", systemImage: "doc.text.magnifyingglass").font(.subheadline)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).marketplaceFlatSurface()
                        }.buttonStyle(.plain)
                    }
                    Button("Return to Orders", systemImage: "list.bullet.clipboard") { dismiss() }
                    if let route = navigator.route {
                        Button("Retry alert lookup", systemImage: "arrow.clockwise") { Task { await navigator.open(route) } }.disabled(navigator.loading)
                    }
                }.padding(20).frame(maxWidth: MarketplaceMetrics.contentMaxWidth).frame(maxWidth: .infinity)
            }
            .navigationTitle("Order alert").dastakInlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $detail) { target in DastakMerchantOrderDetailView(model: merchant.makeOrderDetail(target)) }
        .onChange(of: navigator.route) { _, _ in detail = nil }
        .onDisappear { navigator.cancel() }
        .marketplacePage()
    }
}
