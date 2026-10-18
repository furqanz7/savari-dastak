import MarketplaceDesignSystem
import SwiftUI

struct DastakMerchantJournalBanner: View {
    @ObservedObject var model: DastakMerchantModel
    @Environment(\.colorScheme) private var scheme
    @State private var showingDetails = false
    private var label: String {
        if model.merchantJournal?.acknowledged == true { return "Finish local recovery" }
        return model.merchantJournal == nil ? "Check recovery storage" : "Retry original saved action"
    }
    var body: some View {
        if model.sessionNeedsAttention {
            VStack(alignment: .leading, spacing: 6) {
                Label("Reconnect your Merchant session", systemImage: "person.crop.circle.badge.exclamationmark").font(.subheadline.bold())
                Text("Saved actions remain protected. Reconnect, or sign out and sign in again from Account.").font(.caption)
                Button("Reconnect session") { Task { await model.reconnectSession() } }
                    .frame(minHeight: 44)
                    .disabled(model.busyIdentity != nil)
            }.padding(12)
        }
        if !model.merchantJournalRestored || model.merchantJournal != nil {
            VStack(alignment: .leading, spacing: 6) {
                Label("A saved action needs attention", systemImage: "lock.shield").font(.subheadline.bold())
                Text("New changes stay paused. Recovery checks the original action; it does not create a replacement.").font(.caption).foregroundStyle(.secondary)
                Button("Original action & recovery details") { showingDetails = true }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
                Button(label) { Task { await model.retryMerchantJournal() } }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .disabled(model.busyIdentity != nil || model.isRestoringMerchantJournal)
            }.padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(MarketplaceColors.surface(for: scheme))
                .accessibilityIdentifier("merchant.journal.recovery")
                .sheet(isPresented: $showingDetails) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                Label("Your original action is protected", systemImage: "lock.shield").font(.title2.bold())
                                Text(model.merchantJournalMessage ?? "Checking saved actions before enabling changes.")
                                if let command = model.pendingRecoveryCommand { Text(command.description); Text(command.detail) }
                                if let command = model.pendingRestaurantCommand { Text(command.description) }
                                if let command = model.pendingOperationCommand { Text(command.description) }
                                Text("Retry checks the same saved details and original key. Do not recreate this action while its result is uncertain.").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(20).frame(maxWidth: MarketplaceMetrics.contentMaxWidth).frame(maxWidth: .infinity, alignment: .leading)
                        }.navigationTitle("Saved action").dastakInlineNavigationTitle()
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDetails = false } } }
                    }.marketplacePage()
                }
        }
    }
}
