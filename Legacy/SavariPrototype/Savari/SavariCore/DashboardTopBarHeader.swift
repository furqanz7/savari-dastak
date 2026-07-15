import SwiftUI

struct DashboardTopBarHeader: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    let isSigningOut: Bool
    let onSignOut: () -> Void

    var body: some View {
        HStack {
            Text("Savari.")
                .font(.largeTitle.monospacedDigit())
                .foregroundColor(.primary)

            Spacer()

            Circle()
                .fill(vm.isRealtimeActive ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 12, height: 12)

            Menu {
                Button(role: .destructive, action: onSignOut) {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Material.ultraThin)
                    .clipShape(Circle())
            }
            .disabled(isSigningOut)
        }
    }
}
