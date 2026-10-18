import SwiftUI
import MarketplaceDesignSystem

struct DastakMerchantLocationView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var proposedLocation: DastakMerchantLocation?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DastakMerchantAdaptiveRow {
              HStack(spacing: 12) {
                Image(systemName: model.selectedLocation?.symbol ?? "storefront").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedLocation?.service.uppercased() ?? "CURRENT LOCATION").font(.caption2.weight(.semibold)).tracking(1)
                    Text(model.selectedLocation?.name ?? (model.locationsInitialized || model.locationMessage != nil ? "No location available" : "Checking locations…"))
                        .font(.subheadline.weight(.semibold))
                }
              }.frame(maxWidth: .infinity, alignment: .leading)
              HStack(spacing: 12) {
                if model.isRefreshingLocations { ProgressView() }
                if model.merchantLocations.count > 1 {
                    Menu {
                        ForEach(model.merchantLocations) { location in
                            Button {
                                proposedLocation = location
                            } label: {
                                Label(menuName(location), systemImage: location.id == model.selectedLocationID ? "checkmark" : location.symbol)
                            }
                        }
                    } label: { Image(systemName: "chevron.up.chevron.down").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Choose store location")
                        .disabled(model.locationSwitchDisabled)
                }
                Button {
                    Task { await model.refreshLocations(); await model.refreshSelectedStore() }
                } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Refresh locations")
                    .disabled(model.locationSwitchDisabled)
              }
            }
            if model.hasPendingCanonicalSelections {
                Text("Save or discard your product selections before changing locations.").font(.caption).foregroundStyle(.secondary)
            }
            if model.merchantJournal != nil {
                Text("Resolve the saved action before changing locations. It keeps its original location.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.locationMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if model.locationDirectoryCursor != nil {
                Button("Load more authorized locations") { Task { await model.refreshLocations(loadMore: true) } }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(model.locationSwitchDisabled)
            }
            DisclosureGroup("About this location list") {
                Text(model.locationDirectoryMessage ?? "Locations found through accessible Store and recent order records; this may not be a complete list.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            }.font(.caption).frame(minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("merchant.location.context")
        .confirmationDialog("Switch store location?", isPresented: Binding(get: { proposedLocation != nil },
            set: { if !$0 { proposedLocation = nil } }), titleVisibility: .visible) {
            if let location = proposedLocation {
                Button("Switch to \(location.name)") {
                    proposedLocation = nil
                    Task { await model.selectLocation(location.id) }
                }.disabled(model.locationSwitchDisabled)
            }
            Button("Keep current location", role: .cancel) { proposedLocation = nil }
        } message: {
            Text("Orders and Store will use this location. Any unsaved editor in the current Store will close. Saved actions keep their original location.")
        }
    }
    private func menuName(_ location: DastakMerchantLocation) -> String {
        let duplicate = model.merchantLocations.filter { $0.name == location.name && $0.kind == location.kind }.count > 1
        return "\(location.name) · \(location.service)" + (duplicate ? " · \(location.id.uuidString.suffix(6))" : "")
    }
}
