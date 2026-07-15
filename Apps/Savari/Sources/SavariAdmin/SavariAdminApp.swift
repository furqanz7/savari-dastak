import MarketplaceInfrastructure
import SwiftUI

@main
struct SavariAdminApp: App {
    var body: some Scene {
        WindowGroup {
            MarketplaceAuthenticationShell(
                applicationName: "Savari Admin",
                product: .savari
            )
        }
    }
}
