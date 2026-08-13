import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

public struct DastakDeliveryPartnerRootView: View {
    private let services: MarketplaceAuthenticatedServices

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
    }

    public var body: some View {
        TabView {
            DastakDeliveryPartnerWorkspaceView(functions: services.functions)
                .tabItem { Label("Deliveries", systemImage: "shippingbox") }

            DastakIdentityAccountView(
                roleName: "Delivery Partner",
                services: services
            )
            .tabItem { Label("Account", systemImage: "person") }
        }
        .tint(MarketplaceColors.dastakAccent.color)
    }
}
