import MarketplaceDesignSystem
import SwiftUI

struct DastakMerchantJournalBanner: View {
    @ObservedObject var model: DastakMerchantModel
    @Environment(\.colorScheme) private var scheme
    private var label: String {
        if model.merchantJournal?.acknowledged == true { return "Finish local recovery" }
        return model.merchantJournal == nil ? "Check recovery storage" : "Retry original saved action"
    }
    var body: some View {
        if !model.merchantJournalRestored || model.merchantJournal != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Merchant action recovery").font(.headline)
                Text(model.merchantJournalMessage ?? "Checking saved actions before enabling changes.").font(.caption)
                if let command = model.pendingRecoveryCommand { Text(command.description).font(.caption) }
                if let command = model.pendingRestaurantCommand { Text(command.description).font(.caption) }
                Button(label) { Task { await model.retryMerchantJournal() } }
                    .disabled(model.busyIdentity != nil || model.isRestoringMerchantJournal)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(MarketplaceColors.surface(for: scheme))
                .accessibilityIdentifier("merchant.journal.recovery")
        }
    }
}
