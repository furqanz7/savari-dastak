import SwiftUI

struct RoleSelectionStep: View {
    @Binding var role: String?
    @Binding var lastRole: String?
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            RoleCard(title: "Passenger", subtitle: "Find a ride nearby", icon: "figure.walk", tint: .blue) {
                role = "Passenger"
                lastRole = "Passenger"
                onContinue()
            }

            RoleCard(title: "Driver", subtitle: "Offer your ride", icon: "car.fill", tint: .mint) {
                role = "Driver"
                lastRole = "Driver"
                onContinue()
            }
        }
    }
}

struct RoleCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground).opacity(0.06)))
        }
        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
    }
}
