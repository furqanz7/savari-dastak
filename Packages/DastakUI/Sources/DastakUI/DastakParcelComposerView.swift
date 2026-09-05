import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakParcelComposerView: View {
    @ObservedObject var model: DastakCustomerModel
    let currentLocation: DastakDeliveryLocation?
    let requestCurrentLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickup: DastakDeliveryLocation?
    @State private var dropoff: DastakDeliveryLocation?
    @State private var deliveryMethod: DeliveryMethod = .bike
    @State private var recipientName = ""
    @State private var recipientPhone = ""
    @State private var contents = ""
    @State private var declaredValue = ""
    @State private var choosingPickup = false
    @State private var choosingDropoff = false

    var body: some View {
        NavigationStack {
            Form {
                routeSection
                recipientSection
                parcelSection
                fareSection
                if let errorMessage = model.parcelErrorMessage {
                    Section {
                        DastakActionNotice(message: errorMessage) {
                            model.parcelErrorMessage = nil
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                actionSection
            }
            .scrollContentBackground(.hidden)
            .marketplacePage()
            .navigationTitle("Send a parcel")
            .dastakInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                pickup = model.selectedLocation ?? currentLocation
            }
            .onChange(of: pickup) { _, _ in model.resetParcelQuote() }
            .onChange(of: dropoff) { _, _ in model.resetParcelQuote() }
            .onChange(of: deliveryMethod) { _, _ in model.resetParcelQuote() }
            .sheet(isPresented: $choosingPickup) {
                DastakLocationPicker(
                    title: "Pickup location",
                    currentLocation: currentLocation,
                    useLocation: { pickup = $0 },
                    requestCurrentLocation: requestCurrentLocation
                )
            }
            .sheet(isPresented: $choosingDropoff) {
                DastakLocationPicker(
                    title: "Drop-off location",
                    currentLocation: currentLocation,
                    useLocation: { dropoff = $0 },
                    requestCurrentLocation: requestCurrentLocation
                )
            }
        }
    }

    private var routeSection: some View {
        Section("Route") {
            locationButton(
                title: "Pickup",
                location: pickup,
                symbol: "circle.circle.fill",
                action: { choosingPickup = true }
            )
            locationButton(
                title: "Drop-off",
                location: dropoff,
                symbol: "mappin.circle.fill",
                action: { choosingDropoff = true }
            )

            Picker("Delivery method", selection: $deliveryMethod) {
                Label("Walking", systemImage: "figure.walk").tag(DeliveryMethod.walking)
                Label("Bicycle", systemImage: "bicycle").tag(DeliveryMethod.bicycle)
                Label("Motorbike", systemImage: "motorcycle").tag(DeliveryMethod.bike)
                Label("Auto", systemImage: "car.side").tag(DeliveryMethod.auto)
            }
            .pickerStyle(.segmented)
        }
    }

    private var recipientSection: some View {
        Section("Recipient") {
            TextField("Full name", text: $recipientName)
                .textContentType(.name)
            TextField("Phone number", text: $recipientPhone)
                .textContentType(.telephoneNumber)
                .dastakPhoneKeyboard()
        }
    }

    private var parcelSection: some View {
        Section("Parcel") {
            TextField("What are you sending?", text: $contents, axis: .vertical)
            TextField("Declared value in rupees", text: $declaredValue)
                .dastakNumberKeyboard()
        }
    }

    @ViewBuilder
    private var fareSection: some View {
        if let quote = model.parcelQuote {
            Section("Fare") {
                LabeledContent(
                    "Distance",
                    value: distance(quote.routeDistanceMeters)
                )
                LabeledContent(
                    "Estimated time",
                    value: duration(quote.routeDurationSeconds)
                )
                LabeledContent(
                    "Delivery fee",
                    value: DastakFormatting.money(quote.deliveryFee)
                )
                .fontWeight(.semibold)
            }
        }
    }

    private var actionSection: some View {
        Section {
            actionButton
        }
        .listRowBackground(Color.clear)
    }

    private func locationButton(
        title: String,
        location: DastakDeliveryLocation?,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(location?.address ?? "Choose address")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.isCheckingOut {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 52)
        } else if model.parcelQuote == nil {
            Button("Calculate fare") {
                guard let pickup, let dropoff else { return }
                Task {
                    await model.prepareParcelQuote(
                        deliveryMethod: deliveryMethod,
                        pickup: pickup,
                        dropoff: dropoff
                    )
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(pickup == nil || dropoff == nil)
        } else {
            Button("Pay and request delivery") {
                Task {
                    let paise = (Int(declaredValue) ?? 0) * 100
                    guard await model.createParcelAndCheckout(
                        recipientName: recipientName,
                        recipientPhoneNumber: recipientPhone,
                        declaredContents: contents,
                        declaredValuePaise: paise
                    ) != nil else { return }
                    dismiss()
                }
            }
            .buttonStyle(MarketplacePrimaryButtonStyle())
            .disabled(!detailsAreValid)
        }
    }

    private var detailsAreValid: Bool {
        recipientName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
            recipientPhone.filter(\.isNumber).count >= 10 &&
            !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (Int(declaredValue) ?? 0) > 0
    }

    private func distance(_ meters: Int) -> String {
        Measurement(value: Double(meters), unit: UnitLength.meters)
            .converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes]))
    }
}
