import MarketplaceInfrastructure
import SwiftUI

@main
struct SavariApp: App {
    var body: some Scene {
        WindowGroup {
            MarketplaceAuthenticationShell(
                applicationName: "Savari",
                product: .savari
            )
        }
    }
}
