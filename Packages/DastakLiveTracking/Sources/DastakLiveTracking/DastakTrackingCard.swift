import SwiftUI

/// Shared with the widget extension so the local preview renders the actual card.
public struct DastakTrackingCard: View {
    public let attributes: DastakOrderActivity
    public let state: DastakOrderActivity.ContentState
    public var stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = Color(red: 0.91, green: 0.76, blue: 0.46)
    public init(attributes: DastakOrderActivity, state: DastakOrderActivity.ContentState, stale: Bool = false) {
        self.attributes = attributes; self.state = state; self.stale = stale
    }
    public var body: some View {
        // Lock Screen Live Activities are truncated above 160 points. Keep the
        // action in the status row rather than adding a fourth full-height row.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Label("Dastak", systemImage: attributes.serviceSymbol)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(gold)
                Spacer()
                Text(attributes.serviceName).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stale ? "Waiting for an update" : state.title)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.interpolate)
                    Text(stale ? "Open Dastak to reconnect" : state.detail)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.canCallRider && !stale, let url = attributes.callURL {
                    DastakTrackingCallButton(url: url)
                        .fixedSize(horizontal: true, vertical: true)
                } else {
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(gold)
                }
            }
            DastakTrackingJourney(state: state, isFood: attributes.isFood, stale: stale)
            Text(attributes.orderNumber).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.17, blue: 0.15), Color(red: 0.06, green: 0.08, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: state.status)
        .accessibilityElement(children: .contain)
    }
}

/// Milestone illustration, not an inferred GPS position or invented ETA.
public struct DastakTrackingJourney: View {
    public let state: DastakOrderActivity.ContentState
    public let isFood: Bool
    public let stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = Color(red: 0.94, green: 0.78, blue: 0.48)
    private let mint = Color(red: 0.65, green: 0.86, blue: 0.75)
    public init(state: DastakOrderActivity.ContentState, isFood: Bool, stale: Bool = false) {
        self.state = state; self.isFood = isFood; self.stale = stale
    }
    public var body: some View {
        GeometryReader { geometry in
            let span = max(0, geometry.size.width - 38)
            let progress = state.journeyProgress
            let atDoor = state.status == "RIDER_ARRIVED" || state.status == "DELIVERED"
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1)).frame(height: 3).padding(.horizontal, 19)
                Capsule().fill(LinearGradient(colors: [gold.opacity(0.35), mint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, span * progress), height: 3).offset(x: 19)
                HStack {
                    Image(systemName: isFood ? "takeoutbag.and.cup.and.straw.fill" : "storefront.fill")
                        .frame(width: 38, height: 34)
                    Spacer()
                    // One stable destination. Arrival highlights this door;
                    // the moving courier badge never becomes another door.
                    Image(systemName: "door.left.hand.open")
                        .foregroundStyle(atDoor ? Color(red: 0.08, green: 0.15, blue: 0.12) : .white.opacity(0.45))
                        .frame(width: 38, height: 34)
                        .background(atDoor ? mint : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.font(.system(size: 16)).foregroundStyle(gold.opacity(0.7))
                HStack(spacing: 2) {
                    if state.status == "OUT_FOR_DELIVERY" && !stale {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 9)).opacity(0.65)
                    }
                    Image(systemName: stale ? "arrow.clockwise" : state.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.12))
                .frame(width: 38, height: 34)
                .background(state.status == "RIDER_ARRIVED" || state.status == "DELIVERED" ? mint : gold,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: gold.opacity(0.15), radius: 6, y: 2)
                .offset(x: span * progress)
                .opacity(atDoor ? 0 : 1)
            }.frame(height: 34)
        }
        .frame(height: 34).opacity(stale ? 0.5 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 1.2), value: state.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stale ? "Status needs refreshing" : state.title)
    }
}

public struct DastakTrackingCallButton: View {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var body: some View {
        Link(destination: url) {
            Label("Call rider", systemImage: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.06, green: 0.12, blue: 0.09))
                .padding(.horizontal, 12).frame(minHeight: 32)
                .background(Color(red: 0.65, green: 0.86, blue: 0.75), in: Capsule())
        }.accessibilityLabel("Call your delivery partner")
    }
}
