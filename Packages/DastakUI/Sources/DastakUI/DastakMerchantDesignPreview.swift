#if DEBUG
import SwiftUI
import MarketplaceDesignSystem
import MarketplaceInfrastructure

/// Explicit simulator-only entry in the Merchant app. Static local data, no
/// authenticated services, server writes, device-token registration or orders.
public struct DastakMerchantDesignPreview: View {
    @State private var queue: DastakMerchantQueue = .all
    @State private var section = ProcessInfo.processInfo.arguments.contains("-MerchantStorePreview") ? "Store" : "Orders"
    @State private var message: String?
    public init() {}
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if section == "Orders" {
                        DastakMerchantStoreHeading(name: "The Corner Kitchen", service: "Restaurant / Café",
                            symbol: "fork.knife", presentation: .orders, refresh: {})
                        Label("Local design sample · no live orders", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                        DastakMerchantDeskOverview(incoming: 2, preparing: 3, ready: 1, selection: $queue)
                        DastakMerchantQueuePicker(selection: $queue)
                        if let order = try? DastakMerchantDesignSamples.fulfilment() {
                            if queue == .preparing {
                                DastakV1MerchantFulfilmentCard(fulfilment: order, busy: false,
                                    declarePackages: { _ in message = "Sample only. No packages declared." }, captureEvidence: { _, _, _ in },
                                    markReady: { message = "Sample only. No order changed." }, reportError: { message = $0 },
                                    openDetail: { message = "Read-only detail navigation sample." })
                            } else {
                                Text("Needs your response").font(.headline)
                                DastakMerchantIncomingCard(number: "DSK-SAMPLE-001", branch: "The Corner Kitchen", lines: order.lines,
                                    productSubtotalPaise: order.productSubtotalPaise, expiresAt: nil, prepOptions: [10,15,20,30],
                                    isFood: true, subset: false, busy: false, canRespond: true,
                                    openDetail: { message = "Read-only detail navigation sample." }) { _, _, _ in
                                        message = "Sample only. No order accepted or declined."
                                    }
                            }
                        }
                    } else {
                        DastakMerchantStoreHeading(name: "The Corner Kitchen", service: "Restaurant / Café",
                            symbol: "fork.knife", presentation: .menu, refresh: {})
                        DastakMerchantMediaPicker(title: "Restaurant banner", message: "Shown at the top of your restaurant and menu. Use a clear landscape photo without text.", imageKey: nil, busy: true) { _ in false }
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Dish details").font(.headline)
                            TextField("Dish name", text: .constant("Cardamom cappuccino")).textFieldStyle(.roundedBorder)
                            TextField("Description", text: .constant("Fresh espresso, steamed milk and a little cardamom."), axis: .vertical).textFieldStyle(.roundedBorder)
                            TextField("Price in rupees", text: .constant("125.00")).textFieldStyle(.roundedBorder)
                            Button("Save dish changes") { message = "Sample only. No menu changes saved." }.buttonStyle(DastakMerchantActionStyle(primary: true))
                            Text("Local design sample · no live menu").font(.caption).foregroundStyle(.secondary)
                        }.padding(20).marketplaceFlatSurface()
                    }
                }.padding(18).frame(maxWidth: MarketplaceMetrics.contentMaxWidth).frame(maxWidth: .infinity)
            }.modifier(DastakMerchantKeyboardDismiss())
                .navigationTitle("Merchant · Design sample").dastakInlineNavigationTitle()
                .safeAreaInset(edge: .bottom) {
                    Picker("Sample workspace", selection: $section) { Text("Orders").tag("Orders"); Text("Store").tag("Store") }
                        .pickerStyle(.segmented).padding(16).background(.regularMaterial)
                }
        }.marketplacePage().marketplaceHaptics()
            .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("-MerchantAccessibility") ? .accessibility3 : .large)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-MerchantLightPreview") ? .light : nil)
            .alert("Local sample", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Done") { message = nil }
            } message: { Text(message ?? "") }
    }
}

enum DastakMerchantDesignSamples {
    static func fulfilment() throws -> DastakV1MerchantFulfilment {
        let id = "93000000-0000-4000-8000-000000000001"
        let lines: [[String: Any]] = [
            ["orderLineId": id, "name": "Cardamom cappuccino", "quantity": 2, "variant": "Regular", "packSize": "250 ml", "lineSubtotalPaise": 25000],
            ["orderLineId": "93000000-0000-4000-8000-000000000002", "name": "Almond croissant", "quantity": 1, "lineSubtotalPaise": 11000],
            ["orderLineId": "93000000-0000-4000-8000-000000000003", "name": "Grilled vegetable sandwich", "quantity": 1, "lineSubtotalPaise": 15000],
            ["orderLineId": "93000000-0000-4000-8000-000000000004", "name": "Chocolate cookie", "quantity": 2, "lineSubtotalPaise": 8000],
        ]
        let object: [String: Any] = ["id": id, "orderId": id, "displayOrderNumber": "DSK-SAMPLE-001", "orderStatus": "PREPARING",
            "status": "PREPARING", "version": 1, "branch": ["id": id, "displayName": "The Corner Kitchen"],
            "promisedPrepMinutes": 15, "secondsRemaining": 720, "runningLate": false, "packageCount": 2,
            "evidence": [], "lines": lines, "productSubtotalPaise": 59000,
            "canDeclarePackages": true, "canAddEvidence": true, "canMarkReady": false]
        return try JSONDecoder().decode(DastakV1MerchantFulfilment.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
