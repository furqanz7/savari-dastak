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
    @State private var deliveryRefreshToken = 0

    public init(services: MarketplaceAuthenticatedServices) {
        self.services = services
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DastakDeliveryPartnerWorkspaceView(
                services: services,
                refreshToken: deliveryRefreshToken
            )
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
        .onChange(of: selectedTab) { _, tab in
            guard tab == .deliveries else { return }
            deliveryRefreshToken &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("dastak.notification.orderOpened"))) { event in
            if event.userInfo?["entityType"] as? String == "delivery" {
                selectedTab = .deliveries
                deliveryRefreshToken &+= 1
            }
        }
    }
}
