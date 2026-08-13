import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakEarningsCard: View {
    let earnings: DastakEarningsSnapshot
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            Label(title, systemImage: "indianrupeesign.circle")
                .font(.headline)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DastakFormatting.money(.init(paise: earnings.completedPaise)))
                        .font(.title2.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("This week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DastakFormatting.money(.init(paise: earnings.thisWeekPaise)))
                        .font(.headline.monospacedDigit())
                }
            }
            if earnings.pendingPaise > 0 {
                Text("\(DastakFormatting.money(.init(paise: earnings.pendingPaise))) in progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }
}
