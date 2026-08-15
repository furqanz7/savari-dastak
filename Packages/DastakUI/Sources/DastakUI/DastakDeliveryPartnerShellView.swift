import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

public struct DastakDeliveryPartnerRootView: View {
    private enum Tab: Hashable {
        case deliveries
        case account
    }

    private let services: MarketplaceAuthenticatedServices
    @State private var selectedTab: Tab = .deliveries

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DastakDeliveryPartnerWorkspaceView(functions: services.functions)
                .tabItem { Label("Deliveries", systemImage: "shippingbox") }
                .tag(Tab.deliveries)

            DastakIdentityAccountView(
                roleName: "Delivery Partner",
                openWorkspace: { selectedTab = .deliveries },
                services: services
            )
            .tabItem { Label("Account", systemImage: "person") }
            .tag(Tab.account)
        }
        .tint(MarketplaceColors.dastakAccent.color)
    }
}
