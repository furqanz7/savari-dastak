import MarketplaceDesignSystem
import SwiftUI

struct DastakAddressBookView: View {
    @ObservedObject var model: DastakCustomerModel
    let requiresCompletion: Bool
    let currentLocation: DastakDeliveryLocation?
    let requestCurrentLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingAddress: DastakDeliveryLocation?
    @State private var showingEditor = false
    @State private var deletingAddress: DastakDeliveryLocation?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Group {
                if model.savedAddresses.isEmpty {
                    ContentUnavailableView {
                        Label("No saved addresses", systemImage: "map")
                    } description: {
                        Text("Add a precise pin and doorstep instructions for faster checkout.")
                    } actions: {
                        Button("Add address") { addAddress() }
                            .buttonStyle(MarketplacePrimaryButtonStyle())
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                            header
                            ForEach(model.savedAddresses) { address in
                                addressRow(address)
                            }
                            if let error = model.addressErrorMessage {
                                DastakActionNotice(message: error) {}
                            }
                        }
                        .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                        .padding(MarketplaceSpacing.medium)
                        .padding(.bottom, MarketplaceSpacing.xLarge)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .marketplacePage()
            .navigationTitle("Saved addresses")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { addAddress() } label: { Image(systemName: "plus") }
                        .disabled(model.savedAddresses.count >= 10 || isBusy)
                        .accessibilityLabel("Add address")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            DastakDeliveryAddressEditor(
                requiresCompletion: requiresCompletion,
                initialLocation: editingAddress,
                currentLocation: currentLocation,
                requestCurrentLocation: requestCurrentLocation,
                save: { await model.setLocation($0) },
                onSaved: {
                    showingEditor = false
                    if requiresCompletion { dismiss() }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete \(deletingAddress?.displayName ?? "address")?", isPresented: Binding(
            get: { deletingAddress != nil },
            set: { if !$0 { deletingAddress = nil } }
        )) {
            Button("Keep address", role: .cancel) { deletingAddress = nil }
            Button("Delete", role: .destructive) {
                guard let address = deletingAddress else { return }
                deletingAddress = nil
                Task { _ = await model.deleteSavedAddress(address) }
            }
        } message: {
            Text("Orders already placed keep their original delivery details.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(requiresCompletion ? "CHECKOUT" : "ACCOUNT")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Where should we bring it?")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
            Text("Choose a saved address or add another. You can keep up to ten.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, MarketplaceSpacing.small)
    }

    private func addressRow(_ address: DastakDeliveryLocation) -> some View {
        let selected = address.addressID == model.deliveryAddress?.addressID
        return Button {
            isBusy = true
            Task {
                let didSelect = await model.selectSavedAddress(address)
                isBusy = false
                if didSelect && requiresCompletion { dismiss() }
            }
        } label: {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: symbol(for: address.label))
                    .font(.headline)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 40, height: 40)
                    .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(address.displayName).font(.headline).foregroundStyle(.primary)
                        if selected {
                            Label("Default", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        }
                    }
                    Text(address.displayAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    if let notes = address.deliveryNotes {
                        Text("“\(notes)”")
                            .font(.caption)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
            .padding(MarketplaceSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .marketplaceFlatSurface()
        .contextMenu {
            Button { edit(address) } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deletingAddress = address } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deletingAddress = address } label: { Label("Delete", systemImage: "trash") }
            Button { edit(address) } label: { Label("Edit", systemImage: "pencil") }.tint(MarketplaceColors.dastakAccent.color)
        }
    }

    private func addAddress() {
        editingAddress = nil
        showingEditor = true
    }

    private func edit(_ address: DastakDeliveryLocation) {
        editingAddress = address
        showingEditor = true
    }

    private func symbol(for label: String?) -> String {
        switch label?.lowercased() {
        case "home": "house.fill"
        case "work": "briefcase.fill"
        default: "mappin.and.ellipse"
        }
    }
}
