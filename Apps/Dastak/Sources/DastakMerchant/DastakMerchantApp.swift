import DastakDomain
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
            ) { _ in
                DastakMerchantRoot()
            }
        }
    }
}

private struct DastakMerchantRoot: View {
    private let rootState = DastakAppRootState(application: .merchant)

    var body: some View {
        Group {
            if rootState.activeRoot == .merchant {
                Text("Merchant")
                    .font(.title2)
                    .bold()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
