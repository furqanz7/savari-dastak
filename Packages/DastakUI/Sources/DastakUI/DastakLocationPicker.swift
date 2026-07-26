import MarketplaceDesignSystem
import SwiftUI

struct DastakLocationPicker: View {
    let title: String
    let currentLocation: DastakDeliveryLocation?
    let useLocation: (DastakDeliveryLocation) -> Void
    let requestCurrentLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = DastakPlaceSearchModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        requestCurrentLocation()
                    } label: {
                        Label("Use current location", systemImage: "location.fill")
                    }

                    if let currentLocation {
                        Button {
                            useLocation(currentLocation)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Current location")
                                    .font(.headline)
                                Text(currentLocation.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Search results") {
                    ForEach(search.suggestions) { suggestion in
                        Button {
                            Task {
                                guard let location = await search.resolve(suggestion) else { return }
                                useLocation(location)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if search.isResolving {
                    DastakLoadingOverlay(title: "Finding address")
                }
            }
            .navigationTitle(title)
            .dastakInlineNavigationTitle()
            .searchable(text: $search.query, prompt: "Area, street or landmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
