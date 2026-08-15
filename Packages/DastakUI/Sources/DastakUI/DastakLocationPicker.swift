import MapKit
import MarketplaceDesignSystem
import SwiftUI

struct DastakLocationPicker: View {
    let title: String
    let currentLocation: DastakDeliveryLocation?
    let useLocation: (DastakDeliveryLocation) -> Void
    let requestCurrentLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = DastakPlaceSearchModel()
    @State private var selectedLocation: DastakDeliveryLocation?
    @State private var cameraPosition: MapCameraPosition
    @State private var waitingForCurrentLocation = false

    init(
        title: String,
        currentLocation: DastakDeliveryLocation?,
        useLocation: @escaping (DastakDeliveryLocation) -> Void,
        requestCurrentLocation: @escaping () -> Void
    ) {
        self.title = title
        self.currentLocation = currentLocation
        self.useLocation = useLocation
        self.requestCurrentLocation = requestCurrentLocation
        _selectedLocation = State(initialValue: currentLocation)
        _cameraPosition = State(initialValue: Self.camera(for: currentLocation))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    map
                    currentLocationButton
                    searchContent
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.small)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .marketplacePage()
            .navigationTitle(title)
            .dastakInlineNavigationTitle()
#if os(iOS)
            .searchable(
                text: $search.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Area, street or landmark"
            )
#else
            .searchable(text: $search.query, prompt: "Area, street or landmark")
#endif
            .safeAreaInset(edge: .bottom) {
                confirmButton
                    .padding(MarketplaceSpacing.medium)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: currentLocation) { _, location in
            guard waitingForCurrentLocation, let location else { return }
            waitingForCurrentLocation = false
            select(location)
        }
    }

    private var map: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            if let selectedLocation {
                Marker(
                    "Selected location",
                    coordinate: CLLocationCoordinate2D(
                        latitude: selectedLocation.point.latitude,
                        longitude: selectedLocation.point.longitude
                    )
                )
                .tint(MarketplaceColors.dastakAccent.color)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: MarketplaceMetrics.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MarketplaceMetrics.controlCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            if let selectedLocation {
                HStack(alignment: .top, spacing: MarketplaceSpacing.small) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    Text(selectedLocation.address)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(MarketplaceSpacing.compact)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(MarketplaceSpacing.small)
            }
        }
        .accessibilityLabel(selectedLocation == nil ? "Map awaiting a location" : "Map showing the selected location")
    }

    private var currentLocationButton: some View {
        Button {
            if let currentLocation {
                select(currentLocation)
            } else {
                waitingForCurrentLocation = true
                requestCurrentLocation()
            }
        } label: {
            HStack(spacing: MarketplaceSpacing.compact) {
                Image(systemName: waitingForCurrentLocation ? "location.magnifyingglass" : "location.fill")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 34, height: 34)
                    .background(MarketplaceColors.dastakAccentSoft.color, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(waitingForCurrentLocation ? "Finding your location" : "Use current location")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Uses your location once to place the pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if waitingForCurrentLocation {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(MarketplaceSpacing.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
    }

    @ViewBuilder
    private var searchContent: some View {
        if search.isResolving {
            HStack(spacing: MarketplaceSpacing.compact) {
                ProgressView()
                Text("Finding that address")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
        } else if !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.suggestions) { suggestion in
                    Button {
                        Task {
                            guard let location = await search.resolve(suggestion) else { return }
                            select(location)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                            Image(systemName: "mappin")
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, MarketplaceSpacing.compact)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if suggestion.id != search.suggestions.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .padding(.horizontal, MarketplaceSpacing.compact)
            .marketplaceFlatSurface()
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("Search any serviceable city")
                    .font(.headline)
                Text("Enter an area, street, building or landmark above, then confirm the pin on the map.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, MarketplaceSpacing.small)
        }

        if let errorMessage = search.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.destructive.color)
        }
    }

    private var confirmButton: some View {
        Button {
            guard let selectedLocation else { return }
            useLocation(selectedLocation)
            dismiss()
        } label: {
            HStack {
                Text("Use this location")
                Spacer()
                Image(systemName: "checkmark")
            }
        }
        .buttonStyle(MarketplacePrimaryButtonStyle())
        .disabled(selectedLocation == nil)
    }

    private func select(_ location: DastakDeliveryLocation) {
        selectedLocation = location
        search.query = ""
        cameraPosition = Self.camera(for: location)
    }

    private static func camera(for location: DastakDeliveryLocation?) -> MapCameraPosition {
        let center = CLLocationCoordinate2D(
            latitude: location?.point.latitude ?? 20.5937,
            longitude: location?.point.longitude ?? 78.9629
        )
        return .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: location == nil ? 22 : 0.012,
                    longitudeDelta: location == nil ? 22 : 0.012
                )
            )
        )
    }
}
