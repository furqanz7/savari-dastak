import ActivityKit
import DastakLiveTracking
import SwiftUI
import WidgetKit

struct DastakOrderWidget: Widget {
    private let gold = Color(red: 0.91, green: 0.76, blue: 0.46)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DastakOrderActivity.self) { context in
            DastakTrackingCard(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.08))
                .activitySystemActionForegroundColor(gold)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Dastak", systemImage: context.attributes.serviceSymbol)
                        .font(.headline).foregroundStyle(gold)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.isStale ? "arrow.clockwise" : context.state.symbol)
                        .foregroundStyle(gold).font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(context.isStale ? "Open Dastak for an update" : context.state.title)
                                .font(.subheadline.weight(.semibold)).lineLimit(2)
                                .contentTransition(.interpolate)
                            Spacer(minLength: 0)
                            if context.state.canCallRider && !context.isStale, let url = context.attributes.callURL {
                                DastakTrackingCallButton(url: url)
                            }
                        }
                        DastakTrackingJourney(state: context.state, isFood: context.attributes.isFood, stale: context.isStale)
                    }.padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: context.attributes.serviceSymbol).foregroundStyle(gold)
            } compactTrailing: {
                Image(systemName: context.isStale ? "arrow.clockwise" : context.state.symbol)
                    .foregroundStyle(gold).contentTransition(.symbolEffect(.replace))
                    .accessibilityLabel(context.isStale ? "Update needed" : context.state.title)
            } minimal: {
                Image(systemName: context.isStale ? "arrow.clockwise" : context.state.symbol).foregroundStyle(gold)
            }
            .widgetURL(context.attributes.url)
            .keylineTint(gold)
        }
    }
}
