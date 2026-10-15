import SwiftUI
import MarketplaceDesignSystem
import MarketplaceInfrastructure

struct DastakDeliveryEarningsView: View {
    @ObservedObject private var model: DastakDeliveryEarningsModel
    @State private var amount = ""
    @State private var review: Review?
    @State private var editingDestination = false
    @State private var bank = false
    @State private var holder = ""
    @State private var vpa = ""
    @State private var account = ""
    @State private var confirmation = ""
    @State private var ifsc = ""
    @Environment(\.scenePhase) private var scenePhase
    private enum Review { case withdraw(DastakDeliveryEarnings.Subject, Int), retry(DastakDeliveryEarnings.Withdrawal), destination(DastakDeliveryDestinationRequest) }
    init(model: DastakDeliveryEarningsModel) { self.model = model }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your earnings balance").font(.title2.bold())
                Spacer()
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh earnings balance").disabled(model.loading || model.busy)
            }
            if let message = model.message { Text(message).font(.footnote).accessibilityIdentifier("delivery.earnings.message") }
            if model.loading { ProgressView("Updating earnings") }
            if !model.current { Label("Balance needs refreshing", systemImage: "wifi.exclamationmark").font(.footnote) }
            if model.pending != nil {
                Button("Recover saved payout request") { Task { await model.recover() } }
                    .disabled(model.busy)
            }
            if let snapshot = model.snapshot {
                VStack(spacing: 12) {
                    money("Available", snapshot.availablePaise)
                    money("Lifetime earned", snapshot.lifetimeEarnedPaise)
                    money("Amount owed", snapshot.negativeBalancePaise)
                }.font(.headline).padding(18).marketplaceFlatSurface()
                if snapshot.subjects.isEmpty { Text("Earning credits and payout records appear after eligible deliveries are settled.") }
                ForEach(snapshot.subjects) { subject in
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Payout destination", systemImage: "building.columns").font(.headline)
                        Text(subject.payoutDestination?.displayLabel ?? "No payout destination saved")
                        if snapshot.payoutAvailability?.destinationRegistrationAvailable == true {
                            Button(editingDestination ? "Close destination form" : "Set or change payout destination") { editingDestination.toggle() }
                                .disabled(model.blocksActions || !model.fresh)
                            if editingDestination { destinationForm(subject) }
                        } else { Text("Payout destination registration is not available right now.").font(.footnote).foregroundStyle(.secondary) }
                        Divider()
                        Label("Withdraw earnings", systemImage: "arrow.up.right.circle").font(.headline)
                        if snapshot.payoutAvailability?.withdrawalExecutionAvailable == true {
                            TextField("Amount in rupees", text: $amount).textFieldStyle(.roundedBorder)
                                .dastakDecimalKeyboard().disabled(model.blocksActions)
                            Button("Review withdrawal") {
                                if let value = Self.paise(amount) { review = .withdraw(subject, value) }
                            }
                            .buttonStyle(MarketplacePrimaryButtonStyle())
                            .disabled(!model.fresh || model.blocksActions || !subject.canWithdraw || subject.payoutDestination == nil || Self.paise(amount).map { $0 > subject.availablePaise } != false)
                        } else { Text("Withdrawals are not available right now. Your ledger remains visible.").font(.footnote) }
                    }.padding(18).marketplaceFlatSurface()
                    records("Earning credits", subject.entries)
                    records("Adjustments", subject.adjustments)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Payout history").font(.title3.bold())
                        if subject.withdrawals.isEmpty { Text("No payout requests yet.").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(subject.withdrawals) { withdrawal in
                            VStack(alignment: .leading, spacing: 6) {
                                money(label(withdrawal.status), withdrawal.amountPaise).font(.headline)
                                Text(withdrawal.destination?.displayLabel ?? "Destination not provided").font(.subheadline)
                                Text(DastakMerchantReceiptPresentation.date(withdrawal.requestedAt)).font(.caption).foregroundStyle(.secondary)
                                if let reconciliation = withdrawal.reconciliationState { Text(label(reconciliation)).font(.caption) }
                                if withdrawal.status == "FAILED_RETRYABLE" && snapshot.payoutAvailability?.withdrawalExecutionAvailable == true {
                                    Button("Review payout retry") { review = .retry(withdrawal) }.disabled(model.blocksActions || !model.fresh)
                                }
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }.padding(18).marketplaceFlatSurface()
                }
            }
        }
        .task { await model.load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if scenePhase == .active { await model.load() }
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value == .active { Task { await model.load() } }
            else { review = nil; account = ""; confirmation = "" }
        }
        .confirmationDialog("Review payout details", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
            if let review {
                Button("Confirm") {
                    Task {
                        switch review {
                        case let .withdraw(subject, value): await model.withdraw(subject: subject, amountPaise: value); amount = ""
                        case let .retry(withdrawal): await model.retryWithdrawal(withdrawal)
                        case let .destination(request):
                            await model.register(request); holder = ""; account = ""; confirmation = ""; ifsc = ""; vpa = ""; editingDestination = false
                        }
                    }
                    self.review = nil
                }
            }
            Button("Cancel", role: .cancel) { review = nil }
        } message: { Text(reviewMessage) }
    }
    private var reviewMessage: String {
        switch review {
        case let .withdraw(subject, value): "Request \(DastakFormatting.money(.init(paise: value))) to \(subject.payoutDestination?.displayLabel ?? "your saved destination")? Processing is not instant settlement."
        case let .retry(withdrawal): "Retry the existing \(DastakFormatting.money(.init(paise: withdrawal.amountPaise))) payout? This does not create a new withdrawal."
        case .destination: "Replace your payout destination with the details you entered? Check the account number or UPI ID carefully."
        case nil: ""
        }
    }
    private func destinationForm(_ subject: DastakDeliveryEarnings.Subject) -> some View {
        VStack(spacing: 12) {
            Toggle("Use a bank account", isOn: $bank)
            TextField("Account holder name", text: $holder)
            if bank {
                SecureField("Account number", text: $account)
                SecureField("Confirm account number", text: $confirmation)
                TextField("IFSC", text: $ifsc)
            } else { TextField("UPI ID", text: $vpa) }
            Button("Review destination") {
                let name = holder.trimmingCharacters(in: .whitespacesAndNewlines)
                review = .destination(bank ? .init(subjectID: subject.id, holderName: name, accountNumber: account, confirmation: confirmation, ifsc: ifsc.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) : .init(subjectID: subject.id, holderName: name, vpa: vpa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))
            }.disabled(!validDestination || model.blocksActions || !model.fresh)
            Text("Account details stay only in this form; saved destinations are shown masked.").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder)
    }
    private var validDestination: Bool {
        let name = holder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(name.count) else { return false }
        if bank { return account == confirmation && account.range(of: "^[0-9]{6,34}$", options: .regularExpression) != nil && ifsc.uppercased().range(of: "^[A-Z]{4}0[A-Z0-9]{6}$", options: .regularExpression) != nil }
        return vpa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().range(of: "^[a-z0-9._-]{2,64}@[a-z0-9.-]{2,64}$", options: .regularExpression) != nil
    }
    static func paise(_ value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: "^[0-9]{1,9}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let amount = Decimal(string: text), amount > 0 else { return nil }
        return NSDecimalNumber(decimal: amount * 100).intValue
    }
    private func label(_ value: String) -> String { DastakMerchantReceiptPresentation.label(value) }
    private func money(_ label: String, _ value: Int) -> some View {
        HStack { Text(label); Spacer(); Text(DastakFormatting.money(.init(paise: value))).monospacedDigit() }
    }
    private func records(_ title: String, _ entries: [DastakDeliveryEarnings.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            if entries.isEmpty { Text("No records yet.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    money(label(entry.type), entry.amountPaise).font(.headline)
                    Text(entry.reason).font(.subheadline)
                    Text(DastakMerchantReceiptPresentation.date(entry.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
        }.padding(18).marketplaceFlatSurface()
    }
}

private extension View {
    @ViewBuilder func dastakDecimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
