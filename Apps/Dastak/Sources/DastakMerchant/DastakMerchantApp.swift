import DastakUI
import MarketplaceInfrastructure
import SwiftUI

@main
struct DastakMerchantApp: App {
    var body: some Scene {
        WindowGroup {
            MarketplaceAuthenticationShell(
                applicationName: "Dastak Merchant",
                product: .dastak,
                requiredAccess: .dastakMerchant
            ) { services in
                DastakMerchantRootView(services: services)
            } restrictedContent: { route, services in
                DastakMerchantAccessView(route: route, services: services)
            }
        }
    }
}
