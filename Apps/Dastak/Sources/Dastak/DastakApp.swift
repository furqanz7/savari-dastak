import DastakDomain
import DastakUI
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

@main
struct DastakApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-DastakUIPreview") {
                DastakCustomerRootView(preview: true)
            } else {
                authenticatedRoot
            }
            #else
            authenticatedRoot
            #endif
        }
    }

    private var authenticatedRoot: some View {
        MarketplaceAuthenticationShell(
            applicationName: "Dastak",
            product: .dastak,
            requiredAccess: .dastakCustomer,
            showsPersistentSignOut: false
        ) { functionClient in
            DastakCustomerPartnerRoot(
                functionClient: functionClient
            )
        }
    }
}

protocol DeliveryPartnerAccessProviding: Sendable {
    func currentAccess() async throws -> DeliveryPartnerAccess
}

private struct LiveDeliveryPartnerAccessProvider: DeliveryPartnerAccessProviding {
    let client: any DeliveryPartnerClient

    func currentAccess() async throws -> DeliveryPartnerAccess {
        let key = IdempotencyKey(rawValue: UUID().uuidString)!
        let snapshot = try await client.selfSnapshot(idempotencyKey: key)

        switch snapshot.onboardingState {
        case .notApplied:
            return .notApplied
        case .pending:
            return .pending
        case .approved:
            return .approved
        case .rejected:
            return .rejected
        }
    }
}

@MainActor
final class DastakRootModel: ObservableObject {
    @Published private(set) var rootState = DastakAppRootState(
        application: .customerAndPartner
    )
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let accessProvider: any DeliveryPartnerAccessProviding

    init(accessProvider: any DeliveryPartnerAccessProviding) {
        self.accessProvider = accessProvider
    }

    func refreshPartnerAccess() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            rootState.updateDeliveryPartnerAccess(
                try await accessProvider.currentAccess()
            )
            errorMessage = nil
        } catch {
            rootState.updateDeliveryPartnerAccess(.unavailable)
            errorMessage = "Delivery Partner access could not be refreshed."
        }
    }

    func select(_ root: DastakAppRoot) {
        do {
            try rootState.select(root)
        } catch {
            errorMessage = "This mode is not available for this account."
        }
    }
}

private struct DastakCustomerPartnerRoot: View {
    @StateObject private var model: DastakRootModel
    private let functionClient: any FunctionClient

    init(functionClient: any FunctionClient) {
        self.functionClient = functionClient
        _model = StateObject(
            wrappedValue: DastakRootModel(
                accessProvider: LiveDeliveryPartnerAccessProvider(
                    client: SupabaseDeliveryPartnerClient(functions: functionClient)
                )
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.rootState.availableRoots.count > 1 {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { model.rootState.activeRoot },
                        set: { model.select($0) }
                    )
                ) {
                    Text("Customer").tag(DastakAppRoot.customer)
                    Text("Delivery Partner").tag(DastakAppRoot.deliveryPartner)
                }
                .pickerStyle(.segmented)
                .padding()
            }

            activeRoot
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isRefreshing {
                ProgressView()
                    .padding(.bottom)
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .task {
            await model.refreshPartnerAccess()
        }
    }

    @ViewBuilder
    private var activeRoot: some View {
        switch model.rootState.activeRoot {
        case .customer:
            DastakCustomerRootView(functions: functionClient)
        case .deliveryPartner:
            rootLabel("Delivery Partner")
        case .merchant, .admin:
            EmptyView()
        }
    }

    private func rootLabel(_ title: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
