import SwiftUI
import MarketplaceInfrastructure
import MarketplaceDesignSystem

struct DastakMerchantPayoutRecoveryView: View {
    @ObservedObject var model: DastakMerchantEarningsModel
    @State private var reviewing = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let message = model.payoutMessage { Text(message).font(.footnote).accessibilityIdentifier("merchant.payout.message") }
            if model.busy { ProgressView("Securing financial action") }
            if let pending = model.pending {
                Label("Saved financial action",systemImage:"lock.shield").font(.headline)
                Text(pending.summary).font(.subheadline)
                Text("Original business · \(pending.organizationID.uuidString.lowercased())").font(.caption).textSelection(.enabled)
                Button(pending.acknowledged ? "Review local cleanup" : "Review saved-action recovery") { reviewing = true }
                    .buttonStyle(DastakMerchantActionStyle()).disabled(model.busy || model.loading)
            }
        }.confirmationDialog("Recover the original financial action?",isPresented:$reviewing,titleVisibility:.visible) {
            Button("Recover original action") { Task { _ = await model.recover() } }.disabled(model.busy || phase != .active)
            Button("Cancel",role:.cancel) {}
        } message: {
            Text("The original account, business, amount and details stay unchanged. A destination setup may resubmit its original details; it does not request money. A payout retry uses the existing payout identity. An acknowledged action only finishes local cleanup.")
        }.onChange(of:phase) { _,new in if new != .active { reviewing = false } }
    }
}

struct DastakMerchantPayoutControls: View {
    @ObservedObject var model: DastakMerchantEarningsModel
    let subject: DastakMerchantRoyalty.Subject
    @State private var amount = ""
    @State private var editing = false
    @State private var bank = true
    @State private var holder = ""
    @State private var account = ""
    @State private var confirmation = ""
    @State private var ifsc = ""
    @State private var vpa = ""
    @State private var review: Review?
    @Environment(\.scenePhase) private var phase
    private enum Review { case withdrawal(Int),destination(DastakMerchantDestinationRequest) }
    private var registrationAvailable: Bool { model.snapshot?.payoutAvailability?.destinationRegistrationAvailable == true }
    private var request: DastakMerchantDestinationRequest {
        bank ? .init(organization:subject.id,holder:holder,account:account,confirmation:confirmation,ifsc:ifsc)
            : .init(organization:subject.id,holder:holder,vpa:vpa)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Payout controls",systemImage:"building.columns").font(.headline)
            if model.snapshot?.payoutAvailability?.merchantControlsAvailable != true {
                Text("This server has not enabled the reviewed Merchant payout controls. Earnings remain readable; no withdrawal can be requested from this version.").font(.footnote)
            } else if subject.canManagePayouts != true {
                Text("This account can read these earnings but does not currently have this business's payout-management permission.").font(.footnote)
            }
            if registrationAvailable {
                Button(editing ? "Close destination form" : "Set or change payout destination") {
                    editing.toggle(); if !editing { clearSensitive() }
                }.frame(minHeight:44).disabled(!model.canManage(subject.id))
                if editing { destinationForm }
            } else { Text("Destination setup is not available from the payout service right now.").font(.footnote).foregroundStyle(.secondary) }
            Divider()
            Text("Request a withdrawal").font(.headline)
            Text("Available for this business · \(DastakFormatting.money(.init(paise:subject.availablePaise)))").font(.subheadline)
            TextField("Amount in rupees",text:$amount).textFieldStyle(.roundedBorder).merchantPayoutDecimalKeyboard()
                .disabled(!model.canManage(subject.id))
            Text("Use up to two decimal places, without commas or currency symbols. A request reserves funds; it is not a bank receipt.").font(.caption).foregroundStyle(.secondary)
            Button("Review withdrawal") { if let value = DastakMerchantPayoutAmount.paise(amount) { review = .withdrawal(value) } }
                .buttonStyle(DastakMerchantActionStyle(primary:true))
                .disabled(DastakMerchantPayoutAmount.paise(amount).map { !model.canWithdraw(subject,amount:$0) } ?? true)
            if model.snapshot?.payoutAvailability?.withdrawalExecutionAvailable != true {
                Text("Withdrawals are unavailable right now. A positive ledger balance does not activate the payout service.").font(.footnote).foregroundStyle(.secondary)
            }
            if !model.fresh { Text("Refresh to verify the balance, destination and permissions before making financial changes.").font(.caption).foregroundStyle(.secondary) }
        }
        .confirmationDialog("Review business payout details",isPresented:Binding(get:{review != nil},set:{if !$0 {review = nil}}),titleVisibility:.visible) {
            if let selected = review {
                Button("Confirm financial action") {
                    review = nil; clearSensitive(); editing = false
                    Task {
                        switch selected {
                        case let .withdrawal(value): _ = await model.withdraw(subject:subject,amount:value); amount = ""
                        case let .destination(request): _ = await model.register(request,reviewed:subject.payoutDestination)
                        }
                    }
                }.disabled(!model.canManage(subject.id) || phase != .active)
            }
            Button("Cancel",role:.cancel) { review = nil }
        } message: { Text(reviewMessage) }
        .onChange(of:phase) { _,new in if new != .active { review = nil; clearSensitive(); editing = false } }
        .onChange(of:model.current) { _,current in if !current { review = nil } }
        .onDisappear { review = nil; clearSensitive() }
    }
    private var destinationForm: some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Payout method",selection:$bank) { Text("Indian bank account").tag(true);Text("UPI ID").tag(false) }.pickerStyle(.menu)
                .onChange(of:bank) { _,_ in account = "";confirmation = "";ifsc = "";vpa = "";review = nil }
            TextField("Registered account holder name",text:$holder).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            if bank {
                SecureField("Account number",text:$account).textFieldStyle(.roundedBorder)
                SecureField("Confirm account number",text:$confirmation).textFieldStyle(.roundedBorder)
                TextField("IFSC",text:$ifsc).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            } else { TextField("UPI ID",text:$vpa).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
            Text("Use the registered holder name (3–50 supported letters/numbers). Bank numbers must match; IFSC has 11 characters. UPI uses name@handle.").font(.caption).foregroundStyle(.secondary)
            Text("For manual recovery, your original setup details will be held in this app's device-only Keychain until acknowledged and cleaned up. They are not placed in menu drafts or synced to iCloud. Clear this form to discard unsent details.").font(.caption).foregroundStyle(.secondary)
            Button("Review destination setup") { review = .destination(request) }.buttonStyle(DastakMerchantActionStyle())
                .disabled(!request.valid || !model.canManage(subject.id))
        }.disabled(model.blocksFinancialActions)
    }
    private var reviewMessage: String {
        let business = "Business " + subject.id.uuidString.lowercased() + ". "
        switch review {
        case let .withdrawal(amount): return business + "Request " + DastakFormatting.money(.init(paise:amount)) + " to " + (subject.payoutDestination?.displayLabel ?? "destination unavailable") + ". The server will reject a changed destination. Processing is not confirmation of bank receipt."
        case let .destination(request): return business + "Set " + request.maskedLabel + "? Check the holder and entered details carefully. The original details are held in device-only Keychain for manual recovery until confirmed cleanup. No money is requested by setup."
        case nil: return ""
        }
    }
    private func clearSensitive() { holder = "";account = "";confirmation = "";ifsc = "";vpa = "" }
}
private extension View {
    @ViewBuilder func merchantPayoutDecimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
