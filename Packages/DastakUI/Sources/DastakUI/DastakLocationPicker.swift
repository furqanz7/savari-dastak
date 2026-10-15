import MapKit
import MarketplaceDesignSystem
import SwiftUI

struct DastakLocationPicker: View {
    let title: String
    let currentLocation: DastakDeliveryLocation?
    let currentLocationError: String?
    let useLocation: (DastakDeliveryLocation) -> Void
    let requestCurrentLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.marketplaceHapticScope) private var haptics
    @StateObject private var search = DastakPlaceSearchModel()
    @StateObject private var pin: DastakPinSelection
    @State private var cameraPosition: MapCameraPosition
    @State private var waitingForCurrentLocation = false
    @State private var pinTask: Task<Void, Never>?
    @State private var locationWaitTask: Task<Void, Never>?
    @State private var locationNotice: String?
    @State private var geocoder = CLGeocoder()
    @State private var visibleRegion: MKCoordinateRegion?
    @FocusState private var searching: Bool

    private var selectedLocation: DastakDeliveryLocation? { pin.location }

    init(
        title: String,
        initialLocation: DastakDeliveryLocation? = nil,
        currentLocation: DastakDeliveryLocation?,
        currentLocationError: String? = nil,
        useLocation: @escaping (DastakDeliveryLocation) -> Void,
        requestCurrentLocation: @escaping () -> Void
    ) {
        self.title = title
        self.currentLocation = currentLocation
        self.currentLocationError = currentLocationError
        self.useLocation = useLocation
        self.requestCurrentLocation = requestCurrentLocation
        let initial = initialLocation ?? currentLocation
        _pin = StateObject(wrappedValue: DastakPinSelection(location: initial))
        _cameraPosition = State(initialValue: Self.camera(for: initial))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    searchField
                    searchContent
                    currentLocationButton
                    map
                    pinDetails
                    if selectedLocation != nil { pinAdjustments }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.small)
                .padding(.bottom, MarketplaceSpacing.medium)
            }
            .scrollIndicators(.hidden)
            .marketplacePage()
            .navigationTitle(title)
            .dastakInlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                confirmButton
                    .padding(MarketplaceSpacing.medium)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    MarketplaceFeedbackButton("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: currentLocation) { _, location in
            guard waitingForCurrentLocation, let location else { return }
            waitingForCurrentLocation = false
            select(location)
        }
        .onChange(of: currentLocationError) { _, error in
            if error != nil {
                waitingForCurrentLocation = false
                locationWaitTask?.cancel()
            }
        }
        .onChange(of: search.query) { _, query in
            if !query.isEmpty {
                waitingForCurrentLocation = false
                locationWaitTask?.cancel()
            }
        }
        .onDisappear {
            pinTask?.cancel()
            geocoder.cancelGeocode()
            locationWaitTask?.cancel()
            pin.invalidatePendingMove()
            search.query = ""
            search.cancelResolution()
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Area, street or landmark", text: $search.query)
                .focused($searching)
                .autocorrectionDisabled()
                .accessibilityIdentifier("dastak.location.search")
            if !search.query.isEmpty {
                MarketplaceFeedbackButton { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear address search")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, MarketplaceSpacing.compact)
        .frame(minHeight: 52)
        .marketplaceFlatSurface()
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {}
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    guard cameraPosition.positionedByUser else { return }
                    movePin(context.region.center)
                }
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(point, from: .local) else { return }
                    movePin(coordinate)
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coordinate,
                        span: visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    ))
                }
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: MarketplaceMetrics.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MarketplaceMetrics.controlCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .accessibilityLabel(selectedLocation == nil ? "Map awaiting a location" : "Map showing the selected location")
        .accessibilityHint("Move the map beneath the pin or tap the map to choose a point. Search is available above.")
    }

    private var pinDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Move the map beneath the pin, or tap your exact spot.", systemImage: "hand.draw")
                .font(.footnote)
            if let selectedLocation {
                Text(pin.isResolving ? "Finding the street for this pin…" : selectedLocation.address)
                    .font(.headline)
                Text(String(format: "%.5f, %.5f", selectedLocation.point.latitude, selectedLocation.point.longitude))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dastak.location.coordinates")
            }
            if let notice = pin.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            Text("Check the exact pin before continuing. Selecting a pin does not guarantee service availability.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentLocationButton: some View {
        MarketplaceFeedbackButton {
            locationNotice = nil
            waitingForCurrentLocation = true
            requestCurrentLocation()
            locationWaitTask?.cancel()
            locationWaitTask = Task {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, waitingForCurrentLocation else { return }
                waitingForCurrentLocation = false
                locationNotice = "Current location has not arrived. You can search for an address or place the pin manually."
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
        .disabled(waitingForCurrentLocation)
        .marketplaceFlatSurface()
    }

    private var pinAdjustments: some View {
        DisclosureGroup("Fine-tune the pin") {
            HStack {
                nudgeButton("North", symbol: "arrow.up", latitude: 0.0001, longitude: 0)
                nudgeButton("South", symbol: "arrow.down", latitude: -0.0001, longitude: 0)
                nudgeButton("West", symbol: "arrow.left", latitude: 0, longitude: -0.0001)
                nudgeButton("East", symbol: "arrow.right", latitude: 0, longitude: 0.0001)
            }
            Text("Each tap makes a small adjustment. Check the pin against the entrance before continuing.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func nudgeButton(_ title: String, symbol: String, latitude: Double, longitude: Double) -> some View {
        MarketplaceFeedbackButton {
            guard let point = selectedLocation?.point else { return }
            let coordinate = CLLocationCoordinate2D(
                latitude: max(-90, min(90, point.latitude + latitude)),
                longitude: max(-180, min(180, point.longitude + longitude))
            )
            movePin(coordinate)
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        } label: {
            Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Move pin \(title.lowercased())")
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
            if search.suggestions.isEmpty {
                Text(search.isSearching ? "Searching addresses…" : "No matching addresses. Try a nearby street or landmark, or choose the pin on the map.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.suggestions) { suggestion in
                    MarketplaceFeedbackButton {
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
                Text("Search anywhere in India")
                    .font(.headline)
                Text("Suggestions appear below as you type. Then adjust the pin to the right entrance.")
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
        if let currentLocationError {
            Text(currentLocationError).font(.footnote).foregroundStyle(.secondary)
        }
        if let locationNotice { Text(locationNotice).font(.footnote).foregroundStyle(.secondary) }
    }

    private var confirmButton: some View {
        MarketplaceFeedbackButton {
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
        .disabled(selectedLocation == nil || pin.isResolving || search.isResolving || waitingForCurrentLocation || !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func select(_ location: DastakDeliveryLocation) {
        haptics?.play(.selection)
        pinTask?.cancel()
        geocoder.cancelGeocode()
        locationWaitTask?.cancel()
        waitingForCurrentLocation = false
        locationNotice = nil
        pin.select(location)
        search.query = ""
        searching = false
        cameraPosition = Self.camera(for: location)
    }

    private func movePin(_ coordinate: CLLocationCoordinate2D) {
        guard let token = pin.beginMove(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return }
        haptics?.play(.selection)
        pinTask?.cancel()
        geocoder.cancelGeocode()
        locationWaitTask?.cancel()
        waitingForCurrentLocation = false
        searching = false
        search.query = ""
        search.cancelResolution()
        pinTask = Task {
            let placemark = try? await geocoder.reverseGeocodeLocation(CLLocation(
                latitude: coordinate.latitude, longitude: coordinate.longitude
            )).first
            guard !Task.isCancelled else { return }
            let address = placemark.map { [$0.name, $0.locality, $0.administrativeArea]
                .compactMap { $0 }.joined(separator: ", ") }
            pin.finishMove(token, address: address)
        }
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
