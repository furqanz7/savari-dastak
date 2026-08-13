import DastakDomain
import DastakLaunchUI
import DastakUI
import MarketplaceInfrastructure
import SwiftUI

@main
struct DastakAdminApp: App {
    var body: some Scene {
        WindowGroup {
            DastakLaunchView(variant: .admin) {
                MarketplaceAuthenticationShell(
                    applicationName: "Dastak Admin",
                    product: .dastak,
                    requiredAccess: .dastakAdmin,
                    showsPersistentSignOut: false,
                    authenticatedServicesContent: { services in
                        DastakAdminRoot(services: services)
                    },
                    restrictedContent: { _, _ in EmptyView() }
                )
            }
        }
    }
}

private struct DastakAdminRoot: View {
    let services: MarketplaceAuthenticatedServices

    var body: some View {
        DastakIdentityAccountView(
            roleName: "Owner",
            accessLabel: "Full access",
            allowsAccountDeletion: false,
            services: services
        )
    }
}
