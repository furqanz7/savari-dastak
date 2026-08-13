import DastakDomain
import DastakLaunchUI
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
                    requiredAccess: .dastakAdmin
                ) { _ in
                    DastakAdminRoot()
                }
            }
        }
    }
}

private struct DastakAdminRoot: View {
    private let rootState = DastakAppRootState(application: .admin)

    var body: some View {
        Group {
            if rootState.activeRoot == .admin {
                Text("Admin")
                    .font(.title2)
                    .bold()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
