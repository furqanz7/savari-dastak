import MarketplaceInfrastructure
import SwiftUI

@main
struct DastakApp: App {
    var body: some Scene {
        WindowGroup {
            MarketplaceAuthenticationShell(
                applicationName: "Dastak",
                product: .dastak
            )
        }
    }
}
