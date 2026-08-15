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
    @State private var details: String
    @State private var showingLocationPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case customLabel
        case details
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
            Text(requiresCompletion ? "CHECKOUT" : "SAVED ADDRESS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)

            Text(requiresCompletion ? "Where should we bring it?" : "Your delivery address")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 44))
                .fixedSize(horizontal: false, vertical: true)

            Text(requiresCompletion
                ? "Confirm the pin, then add the detail that helps your delivery partner find the right door."
                : "Keep a precise address ready for faster checkout.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)

            if requiresCompletion {
                HStack(spacing: MarketplaceSpacing.small) {
                    step("1", "Pin location", isComplete: selectedLocation != nil)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                    step("2", "Doorstep", isComplete: !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text(selectedLocation == nil ? "Choose the delivery pin" : "Delivery pin")
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
                        .frame(maxWidth: .infinity, minHeight: 62)
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
                    .onSubmit { focusedField = .details }
            }
        }
    }

    private var addressDetails: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text("Doorstep details")
                .font(.headline)
            Text("House or flat number, floor, building and a nearby landmark.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("For example: Flat 4B, second floor, opposite the post office", text: $details, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3 ... 5)
                .padding(MarketplaceSpacing.medium)
                .marketplaceFlatSurface()
                .focused($focusedField, equals: .details)
                .submitLabel(.done)
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
}
