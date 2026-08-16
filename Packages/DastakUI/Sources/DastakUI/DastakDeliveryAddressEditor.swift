import MapKit
import MarketplaceDesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DastakDeliveryAddressEditor: View {
    private enum AddressKind: String, CaseIterable, Identifiable {
        case home
        case work
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .work: "Work"
            case .custom: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .work: "briefcase.fill"
            case .custom: "mappin.and.ellipse"
            }
        }

        init(savedLabel: String?) {
            switch savedLabel?.lowercased() {
            case "home": self = .home
            case "work": self = .work
            default: self = .custom
            }
        }
    }

    let requiresCompletion: Bool
    let initialLocation: DastakDeliveryLocation?
    let currentLocation: DastakDeliveryLocation?
    let requestCurrentLocation: () -> Void
    let save: (DastakDeliveryLocation) async -> Bool
    let onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocation: DastakDeliveryLocation?
    @State private var addressKind: AddressKind
    @State private var customLabel: String
    @State private var building: String
    @State private var floor: String
    @State private var landmark: String
    @State private var deliveryNotes: String
    @State private var showingLocationPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case customLabel
        case building
        case floor
        case landmark
        case deliveryNotes
    }

    init(
        requiresCompletion: Bool,
        initialLocation: DastakDeliveryLocation?,
        currentLocation: DastakDeliveryLocation?,
        requestCurrentLocation: @escaping () -> Void,
        save: @escaping (DastakDeliveryLocation) async -> Bool,
        onSaved: (() -> Void)? = nil
    ) {
        self.requiresCompletion = requiresCompletion
        self.initialLocation = initialLocation
        self.currentLocation = currentLocation
        self.requestCurrentLocation = requestCurrentLocation
        self.save = save
        self.onSaved = onSaved

        let kind = AddressKind(savedLabel: initialLocation?.label)
        let savedDetails = Self.splitDetails(initialLocation?.details)
        _selectedLocation = State(initialValue: initialLocation)
        _addressKind = State(initialValue: kind)
        _customLabel = State(initialValue: kind == .custom ? initialLocation?.label ?? "" : "")
        _building = State(initialValue: initialLocation?.building ?? savedDetails.building)
        _floor = State(initialValue: initialLocation?.floor ?? "")
        _landmark = State(initialValue: initialLocation?.landmark ?? savedDetails.landmark)
        _deliveryNotes = State(initialValue: initialLocation?.deliveryNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    header
                    locationSelector
                    addressTypePicker
                    addressDetails
                    if let errorMessage {
                        DastakActionNotice(message: errorMessage) {
                            self.errorMessage = nil
                        }
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, MarketplaceSpacing.medium)
                .padding(.top, MarketplaceSpacing.medium)
                .padding(.bottom, 104)
            }
            .scrollIndicators(.hidden)
#if os(iOS)
            .scrollDismissesKeyboard(.interactively)
#endif
            .marketplacePage()
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(MarketplaceSpacing.medium)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
#if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
#endif
            }
        }
        .onTapGesture { dismissKeyboard() }
        .sheet(isPresented: $showingLocationPicker) {
            DastakLocationPicker(
                title: "Choose location",
                currentLocation: selectedLocation ?? currentLocation,
                useLocation: { location in
                    selectedLocation = location
                },
                requestCurrentLocation: requestCurrentLocation
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(requiresCompletion ? "CHECKOUT" : "SAVED ADDRESS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)

            Text(requiresCompletion ? "Where should we bring it?" : "Your delivery address")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 40))
                .fixedSize(horizontal: false, vertical: true)

            Text(requiresCompletion
                ? "Confirm the pin, then add the details that help us find the right door."
                : "Keep a precise address ready for faster checkout.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)

            if requiresCompletion {
                HStack(spacing: MarketplaceSpacing.small) {
                    step("1", "Pin location", isComplete: selectedLocation != nil)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                    step("2", "Doorstep", isComplete: !building.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, MarketplaceSpacing.small)
            }
        }
    }

    private func step(_ number: String, _ title: String, isComplete: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(isComplete ? MarketplaceColors.dastakAccent.color : .secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isComplete ? .primary : .secondary)
        }
        .fixedSize()
    }

    private var locationSelector: some View {
        Group {
            if let selectedLocation {
                VStack(spacing: 0) {
                    Map(
                        initialPosition: Self.camera(for: selectedLocation),
                        interactionModes: []
                    ) {
                        Marker(
                            "Delivery pin",
                            coordinate: CLLocationCoordinate2D(
                                latitude: selectedLocation.point.latitude,
                                longitude: selectedLocation.point.longitude
                            )
                        )
                        .tint(MarketplaceColors.dastakAccent.color)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .frame(height: 154)
                    .allowsHitTesting(false)
                    .id("\(selectedLocation.point.latitude)-\(selectedLocation.point.longitude)")

                    Button {
                        showingLocationPicker = true
                    } label: {
                        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Delivery pin")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(selectedLocation.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: MarketplaceSpacing.small)
                            Text("Change")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        }
                        .padding(MarketplaceSpacing.compact)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .marketplaceFlatSurface()
            } else {
                Button {
                    showingLocationPicker = true
                } label: {
                    HStack(spacing: MarketplaceSpacing.compact) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            .frame(width: 46, height: 46)
                            .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose the delivery pin")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Search any area, street, building or landmark")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: MarketplaceSpacing.small)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(MarketplaceSpacing.medium)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .marketplaceFlatSurface()
            }
        }
        .accessibilityHint("Search for or select your current delivery location")
    }

    private var addressTypePicker: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Save as")
                .font(.headline)

            HStack(spacing: MarketplaceSpacing.small) {
                ForEach(AddressKind.allCases) { kind in
                    Button {
                        addressKind = kind
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.symbol)
                            Text(kind.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(addressKind == kind ? MarketplaceColors.dastakAccent.color : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(
                            addressKind == kind
                                ? MarketplaceColors.dastakAccentSoft.color
                                : MarketplaceColors.dastakSurface.color,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    addressKind == kind ? MarketplaceColors.dastakAccent.color.opacity(0.7) : Color.secondary.opacity(0.16),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if addressKind == .custom {
                TextField("Label, for example Parents' home", text: $customLabel)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, MarketplaceSpacing.compact)
                    .frame(minHeight: 52)
                    .marketplaceFlatSurface()
                    .focused($focusedField, equals: .customLabel)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .building }
            }
        }
    }

    private var addressDetails: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Doorstep details")
                .font(.headline)
            Text("Help the delivery partner find the right entrance without calling.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                TextField("House, flat or building", text: $building)
                    .textContentType(.fullStreetAddress)
                    .focused($focusedField, equals: .building)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .floor }
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .frame(minHeight: 52)

                Divider().padding(.leading, MarketplaceSpacing.medium)

                TextField("Floor or unit (optional)", text: $floor)
                    .focused($focusedField, equals: .floor)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .landmark }
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .frame(minHeight: 52)

                Divider().padding(.leading, MarketplaceSpacing.medium)

                TextField("Nearby landmark (optional)", text: $landmark)
                    .focused($focusedField, equals: .landmark)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .deliveryNotes }
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .frame(minHeight: 52)

                Divider().padding(.leading, MarketplaceSpacing.medium)

                TextField("Gate, bell or hand-off instructions (optional)", text: $deliveryNotes, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .focused($focusedField, equals: .deliveryNotes)
                    .submitLabel(.done)
                    .padding(MarketplaceSpacing.medium)
            }
                .textFieldStyle(.plain)
                .marketplaceFlatSurface()
        }
    }

    private var saveButton: some View {
        Button {
            Task { await saveAddress() }
        } label: {
            if isSaving {
                ProgressView()
                    .tint(MarketplaceColors.primaryActionForeground.color)
            } else {
                HStack {
                    Text(requiresCompletion ? "Save and review order" : "Save address")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
        }
        .buttonStyle(MarketplacePrimaryButtonStyle())
        .disabled(!canSave || isSaving)
    }

    private var canSave: Bool {
        guard selectedLocation != nil,
              !building.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return addressKind != .custom || !customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedLabel: String {
        switch addressKind {
        case .home: "Home"
        case .work: "Work"
        case .custom: customLabel
        }
    }

    private func saveAddress() async {
        guard let selectedLocation, canSave else { return }
        isSaving = true
        let didSave = await save(
            DastakDeliveryLocation(
                addressID: initialLocation?.addressID,
                address: selectedLocation.address,
                point: selectedLocation.point,
                label: resolvedLabel,
                details: resolvedDetails,
                building: building,
                floor: floor,
                landmark: landmark,
                deliveryNotes: deliveryNotes
            )
        )
        isSaving = false
        if didSave {
            errorMessage = nil
            if let onSaved {
                onSaved()
            } else {
                dismiss()
            }
        } else {
            errorMessage = "The address could not be saved. Check your connection and try again."
        }
    }

    @MainActor
    private func dismissKeyboard() {
        focusedField = nil
#if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    private var resolvedDetails: String {
        [building, floor, landmark]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private static func splitDetails(_ details: String?) -> (building: String, landmark: String) {
        guard let details else { return ("", "") }
        let parts = details.components(separatedBy: " • ")
        return (
            parts.first ?? "",
            parts.dropFirst().joined(separator: " • ")
        )
    }

    private static func camera(for location: DastakDeliveryLocation) -> MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: location.point.latitude,
                    longitude: location.point.longitude
                ),
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
        )
    }
}
