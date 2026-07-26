import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakAccountView: View {
    let location: DastakDeliveryLocation?
    let discoveryRadiusKilometres: Int
    let chooseLocation: () -> Void

    @Environment(\.marketplaceSignOut) private var signOut

    var body: some View {
        List {
            Section {
                HStack {
                    DastakWordmark(size: 28)
                    Spacer()
                }
                .padding(.vertical, MarketplaceSpacing.small)
            }

            Section("Delivery") {
                Button(action: chooseLocation) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delivery location")
                                .foregroundStyle(.primary)
                            Text(location?.address ?? "Not selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: "location")
                    }
                }

                LabeledContent("Discovery range", value: "\(discoveryRadiusKilometres) km")
            }

            Section("Support") {
                Link(destination: URL(string: "tel:112")!) {
                    Label("Emergency assistance", systemImage: "sos")
                }
                Label("Help with an order", systemImage: "questionmark.circle")
                Label("Privacy", systemImage: "hand.raised")
            }

            Section {
                Button("Sign out", role: .destructive) {
                    Task { await signOut() }
                }
            }

            Section {
                Text("Dastak follows your iPhone language and appearance settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Account")
    }
}
