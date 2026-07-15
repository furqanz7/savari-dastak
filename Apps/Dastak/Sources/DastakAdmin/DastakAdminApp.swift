import MarketplaceInfrastructure
import SwiftUI

@main
struct DastakAdminApp: App {
    var body: some Scene {
        WindowGroup {
            MarketplaceAuthenticationShell(
                applicationName: "Dastak Admin",
                product: .dastak
            )
        }
    }
}
