import SwiftUI

struct DriverDashboardTopBar: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    let isSigningOut: Bool
    let onSignOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Savari Driver")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Material.ultraThin)
        .cornerRadius(16)
    }

    private var statusColor: Color {
        if vm.rideAccepted {
            return .blue
        }
        return vm.isOnline ? .green : .secondary
    }

    private var statusText: String {
        if vm.rideAccepted {
            return "Active ride"
        }
        return vm.isOnline ? "Online and waiting" : "Offline"
    }
}
