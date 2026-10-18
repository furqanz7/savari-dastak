import SwiftUI
import MarketplaceDesignSystem
import MarketplaceInfrastructure

struct DastakMerchantEarningsView: View {
    @ObservedObject var model: DastakMerchantEarningsModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var accent: Color { MarketplaceColors.accent(for: scheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading
                    DastakMerchantPayoutRecoveryView(model:model)
                    if let failure = model.failure {
                        Label(failure, systemImage: "wifi.exclamationmark")
                            .font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading).marketplaceFlatSurface()
                            .accessibilityIdentifier("merchant.earnings.failure")
                    }
                    if model.loading { ProgressView("Checking business earnings") }
                    if let snapshot = model.snapshot {
                        if !model.current { Label("Last-known amounts · refresh to verify", systemImage: "clock.badge.exclamationmark").font(.footnote).foregroundStyle(.secondary) }
                        summary(snapshot)
                        if snapshot.subjects.count > 1 {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Business account", selection: $model.selectedOrganizationID) {
                                    Text("All business accounts").tag(nil as UUID?)
                                    ForEach(snapshot.subjects) { subject in Text("Business · \(shortID(subject.id))").tag(subject.id as UUID?) }
                                }
                                .disabled(model.busy || model.pending != nil)
                                Text("Each account is a separate merchant organization. Store selection does not change these balances.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(model.visibleSubjects) { subject in
                            DastakMerchantRoyaltyAccountView(model:model,subject: subject, snapshot: snapshot, current: model.current)
                        }
                        if let checkedAt = model.checkedAt {
                            Label("Checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !model.loading {
                        DastakEmptyState(symbol: "wallet.bifold", title: "Earnings unavailable",
                            message: "Refresh to check your business ledger. An unavailable balance is not a zero balance.")
                    }
                    Button { Task { await model.load() } } label: {
                        Label("Check earnings", systemImage: "arrow.clockwise").frame(minHeight: 44).frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).disabled(model.loading)
                    Text("Financial actions require explicit review and current business permission. Opening, refreshing or returning to this screen never requests a payout or automatically retries destination setup.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: MarketplaceMetrics.contentMaxWidth).padding(20).padding(.bottom, 20).frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
            .navigationTitle("Earnings").dastakInlineNavigationTitle()
            .modifier(DastakMerchantKeyboardDismiss())
        }
        .marketplacePage()
        .task(id: phase) {
            guard phase == .active else { model.invalidate(); return }
            while !Task.isCancelled {
                await model.load()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onDisappear { model.invalidate() }
    }
    private var heading: some View {
        DastakMerchantHeading(eyebrow: "YOUR BUSINESS", title: "Every credit, clearly.",
            subtitle: "Your Royalty ledger, adjustments and payout history. Organization-wide, across your stores.", symbol: "chart.line.uptrend.xyaxis")
    }
    private func summary(_ snapshot: DastakMerchantRoyalty) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Label("Available balance", systemImage: "wallet.bifold.fill"); Spacer(); Image(systemName: "sparkle").foregroundStyle(accent) }
                    .font(.subheadline.weight(.semibold))
                Text(amount(snapshot.availablePaise)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    .accessibilityIdentifier("merchant.earnings.available")
                Text("Ledger availability—not a bank balance or confirmation that withdrawals are active.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [accent.opacity(0.24), accent.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(accent.opacity(0.25), lineWidth: 1))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                metric("Lifetime earned", snapshot.lifetimeEarnedPaise, "chart.bar.fill")
                metric("Amount owed", snapshot.negativeBalancePaise, "arrow.down.circle", warning: snapshot.negativeBalancePaise > 0)
            }
            if snapshot.subjects.count > 1 {
                Text("Summary covers all \(snapshot.subjects.count) authorized business accounts. Available and owed amounts stay separate; one organization’s balance does not settle another’s.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func metric(_ title: String, _ value: Int, _ symbol: String, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(amount(value)).font(.title3.bold()).monospacedDigit()
            if warning { Text("Deductions exceed credits").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(18).marketplaceFlatSurface()
    }
    private func amount(_ value: Int) -> String { DastakFormatting.money(.init(paise: value)) }
    private func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }
}

private struct DastakMerchantRoyaltyAccountView: View {
    @ObservedObject var model: DastakMerchantEarningsModel
    let subject: DastakMerchantRoyalty.Subject
    let snapshot: DastakMerchantRoyalty
    let current: Bool
    @State private var filter: DastakMerchantEarningsPresentation.LedgerFilter = .all
    @State private var query = ""
    @State private var limit = 30
    @State private var payoutLimit = 20
    @State private var retryReview: DastakMerchantRoyalty.Withdrawal?
    private var entries: [DastakMerchantRoyalty.Entry] { DastakMerchantEarningsPresentation.entries(subject, filter: filter, query: query) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label(snapshot.subjects.count > 1 ? "Business · \(subject.id.uuidString.prefix(8).lowercased())" : "Your business account", systemImage: "building.2")
                    .font(.title3.bold())
                row("Ledger balance", subject.balancePaise)
                row("Available", subject.availablePaise)
                row("Lifetime earned", subject.lifetimeEarnedPaise)
                row("Amount owed", subject.negativeBalancePaise)
                Text("Business account ID: \(subject.id.uuidString.lowercased())").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(18).marketplaceFlatSurface()
            VStack(alignment: .leading, spacing: 10) {
                Label("Payout status", systemImage: "building.columns").font(.headline)
                Text(current ? DastakMerchantEarningsPresentation.payoutStatus(snapshot, subject: subject) : "Payout status needs a fresh check.")
                    .font(.subheadline)
                Text(subject.payoutDestination?.displayLabel ?? "No registered payout destination in this snapshot.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let availability = snapshot.payoutAvailability, current {
                    Text(availability.destinationRegistrationAvailable ? "The server reports payout setup available, subject to this business's permission." : "Payout setup is not available right now.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(18).marketplaceFlatSurface()
            DastakMerchantPayoutControls(model:model,subject:subject).padding(18).marketplaceFlatSurface()
            VStack(alignment: .leading, spacing: 14) {
                Text("Ledger activity").font(.title3.bold())
                Text("Credits and deductions as returned by the ledger. Adjustments are already included—not extra money to add to the balance.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Ledger records", selection: $filter) { ForEach(DastakMerchantEarningsPresentation.LedgerFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu)
                TextField("Search reason or order ID", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("merchant.earnings.search")
                if entries.isEmpty { Text(query.isEmpty ? "No matching ledger records yet." : "No matching records in this account’s loaded ledger.").font(.subheadline).foregroundStyle(.secondary) }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries.prefix(limit)) { entry in entryRow(entry) }
                }
                if entries.count > limit {
                    Button("Show more activity (\(min(limit, entries.count)) of \(entries.count))") { limit += 30 }.frame(minHeight: 44)
                }
            }.padding(18).marketplaceFlatSurface()
            VStack(alignment: .leading, spacing: 14) {
                Text("Payout history").font(.title3.bold())
                Text("A requested or processing payout is not a bank receipt. Records below show the server’s recorded status.")
                    .font(.caption).foregroundStyle(.secondary)
                if subject.withdrawals.isEmpty { Text("No payout requests recorded.").font(.subheadline).foregroundStyle(.secondary) }
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(subject.withdrawals.prefix(payoutLimit)) { withdrawal in payoutRow(withdrawal) }
                }
                if subject.withdrawals.count > payoutLimit { Button("Show more payouts") { payoutLimit += 20 }.frame(minHeight: 44) }
            }.padding(18).marketplaceFlatSurface()
        }
        .onChange(of: filter) { _, _ in limit = 30 }
        .onChange(of: query) { _, _ in limit = 30 }
        .onChange(of:current) { _,value in if !value {retryReview = nil} }
        .confirmationDialog("Check or retry the existing payout?",isPresented:Binding(get:{retryReview != nil},set:{if !$0 {retryReview = nil}}),titleVisibility:.visible) {
            if let withdrawal = retryReview {
                Button("Check / retry this payout") { retryReview = nil;Task { _ = await model.retry(withdrawal,organization:subject.id) } }
                    .disabled(!model.canRetry(withdrawal,organization:subject.id))
            }
            Button("Cancel",role:.cancel) {retryReview = nil}
        } message: {
            Text("This checks or retries the same existing payout, not a new withdrawal. Its original destination and external payout identity remain unchanged.")
        }
    }
    private func entryRow(_ entry: DastakMerchantRoyalty.Entry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            row(DastakMerchantEarningsPresentation.label(entry.type), entry.amountPaise, signed: true).font(.subheadline.bold())
            if !entry.reason.isEmpty { Text(entry.reason).font(.subheadline) }
            Text(DastakMerchantReceiptPresentation.date(entry.createdAt)).font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Reference details") {
                reference("Ledger entry", entry.id)
                if let id = entry.orderId { reference("Order", id) }
                if let id = entry.fulfilmentId { reference("Fulfilment", id) }
                if let id = entry.refundId { reference("Refund", id) }
                if let id = entry.withdrawalId { reference("Withdrawal", id) }
            }.font(.caption)
            Divider()
        }
    }
    private func payoutRow(_ withdrawal: DastakMerchantRoyalty.Withdrawal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            row(DastakMerchantEarningsPresentation.label(withdrawal.status), withdrawal.amountPaise).font(.subheadline.bold())
            Text(withdrawal.destination?.displayLabel ?? "Destination not provided").font(.subheadline)
            Text("Requested · \(DastakMerchantReceiptPresentation.date(withdrawal.requestedAt))").font(.caption).foregroundStyle(.secondary)
            if let paidAt = withdrawal.paidAt { Text("Recorded paid · \(DastakMerchantReceiptPresentation.date(paidAt))").font(.caption).foregroundStyle(.secondary) }
            if let failedAt = withdrawal.failedAt { Text("Recorded failure · \(DastakMerchantReceiptPresentation.date(failedAt))").font(.caption).foregroundStyle(.secondary) }
            if let state = withdrawal.reconciliationState { Text("Reconciliation · \(DastakMerchantEarningsPresentation.label(state))").font(.caption) }
            if model.canRetry(withdrawal,organization:subject.id) {
                Button("Review payout check / retry") {retryReview = withdrawal}.frame(minHeight:44)
            }
            DisclosureGroup("Payout reference") { reference("Withdrawal", withdrawal.id) }.font(.caption)
            Divider()
        }
    }
    private func row(_ title: String, _ paise: Int, signed: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { Text(title); Spacer(minLength: 16); value(paise, signed: signed) }
            VStack(alignment: .leading, spacing: 5) { Text(title); value(paise, signed: signed) }
        }
    }
    private func value(_ paise: Int, signed: Bool) -> some View {
        Text((signed && paise > 0 ? "+" : "") + DastakFormatting.money(.init(paise: paise))).monospacedDigit().fixedSize(horizontal: true, vertical: false)
    }
    private func reference(_ title: String, _ id: UUID) -> some View {
        Text("\(title) · \(id.uuidString.lowercased())").textSelection(.enabled).padding(.vertical, 5)
    }
}
