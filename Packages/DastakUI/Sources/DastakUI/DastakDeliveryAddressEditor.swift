import MarketplaceDesignSystem
import SwiftUI

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

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocation: DastakDeliveryLocation?
    @State private var addressKind: AddressKind
    @State private var customLabel: String
    @State private var details: String
    @State private var showingLocationPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        requiresCompletion: Bool,
        initialLocation: DastakDeliveryLocation?,
        currentLocation: DastakDeliveryLocation?,
        requestCurrentLocation: @escaping () -> Void,
        save: @escaping (DastakDeliveryLocation) async -> Bool
    ) {
        self.requiresCompletion = requiresCompletion
        self.initialLocation = initialLocation
        self.currentLocation = currentLocation
        self.requestCurrentLocation = requestCurrentLocation
        self.save = save

        let kind = AddressKind(savedLabel: initialLocation?.label)
        _selectedLocation = State(initialValue: initialLocation)
        _addressKind = State(initialValue: kind)
        _customLabel = State(initialValue: kind == .custom ? initialLocation?.label ?? "" : "")
        _details = State(initialValue: initialLocation?.details ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
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
                .padding(.top, MarketplaceSpacing.large)
                .padding(.bottom, 104)
            }
            .scrollIndicators(.hidden)
            .marketplacePage()
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding(MarketplaceSpacing.medium)
                    .background(.bar)
            }
            .toolbar {
                if !requiresCompletion {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            DastakLocationPicker(
                title: "Choose location",
                currentLocation: currentLocation,
                useLocation: { location in
                    selectedLocation = location
                },
                requestCurrentLocation: requestCurrentLocation
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text(requiresCompletion ? "Add delivery address" : "Delivery address")
                .font(.largeTitle.bold())
            Text(requiresCompletion ? "This is where your order will be delivered." : "Update the address for future orders.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
        }
    }

    private var locationSelector: some View {
        Button {
            showingLocationPicker = true
        } label: {
            HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 34, height: 34)
                    .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedLocation == nil ? "Choose location" : "Delivery location")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(selectedLocation?.address ?? "Search an area, street or landmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: MarketplaceSpacing.small)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .padding(MarketplaceSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .marketplaceFlatSurface()
        .accessibilityHint("Search for or select your current delivery location")
    }

    private var addressTypePicker: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Address type")
                .font(.headline)

            Picker("Address type", selection: $addressKind) {
                ForEach(AddressKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if addressKind == .custom {
                TextField("Address label", text: $customLabel)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, MarketplaceSpacing.compact)
                    .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
                    .marketplaceFlatSurface()
            }
        }
    }

    private var addressDetails: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("House, flat or landmark")
                .font(.headline)
            TextField("For example: 128 Mandi Street, second floor", text: $details, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2 ... 4)
                .padding(MarketplaceSpacing.compact)
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
                Text(requiresCompletion ? "Continue" : "Save address")
            }
        }
        .buttonStyle(MarketplacePrimaryButtonStyle())
        .disabled(!canSave || isSaving)
    }

    private var canSave: Bool {
        guard selectedLocation != nil,
              !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
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
                address: selectedLocation.address,
                point: selectedLocation.point,
                label: resolvedLabel,
                details: details
            )
        )
        isSaving = false
        if didSave {
            errorMessage = nil
            dismiss()
        } else {
            errorMessage = "The address could not be saved. Check your connection and try again."
        }
    }
}
