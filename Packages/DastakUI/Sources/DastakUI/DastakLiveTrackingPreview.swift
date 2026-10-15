#if DEBUG && os(iOS)
@preconcurrency import ActivityKit
import DastakLiveTracking
import SwiftUI

/// Explicit debug launch only. No account, order API, tokens or commerce.
public struct DastakLiveTrackingPreview: View {
    @State private var activity: Activity<DastakOrderActivity>?
    @State private var status = "PREPARING"
    @State private var message = "Local sample · no order placed"
    private let attributes = DastakOrderActivity(orderID: "00000000-0000-0000-0000-000000000032",
        accountID: "preview", orderNumber: "SAMPLE · 032", isFood: ProcessInfo.processInfo.arguments.contains("-DastakFoodTrackingPreview"))
    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            Text("Order tracking").font(.largeTitle.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            DastakTrackingCard(attributes: attributes, state: state)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            ForEach(["PREPARING", "ASSIGNING_RIDER", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY", "RIDER_ARRIVED", "DELIVERED", "CANCELLED"], id: \.self) { value in
                Button(DastakOrderActivity.ContentState(status: value, version: 1, updatedAt: 0).title) {
                    status = value
                    Task { await update() }
                }.buttonStyle(.bordered)
            }
            Button("End sample") { Task { await activity?.end(nil, dismissalPolicy: .immediate); activity = nil } }
            Text("Go to the Home Screen for Dynamic Island. Lock the simulator for the tracking card.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding().preferredColorScheme(.dark)
        .task {
            for previous in Activity<DastakOrderActivity>.activities where previous.attributes.accountID == "preview" {
                await previous.end(nil, dismissalPolicy: .immediate)
            }
            do {
                activity = try Activity.request(attributes: attributes,
                    content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(180)), pushType: nil)
            } catch { message = "Sample could not start: \(error.localizedDescription)" }
        }
    }
    private var state: DastakOrderActivity.ContentState {
        .init(status: status, version: 1, updatedAt: Date.now.timeIntervalSince1970)
    }
    private func update() async {
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(180))
        if state.terminal { await activity?.end(content, dismissalPolicy: .after(.now.addingTimeInterval(60))) }
        else { await activity?.update(content) }
    }
}
#endif
