import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Foreground active work only. Never changes the device's Auto-Lock setting.
struct DastakDeliveryScreenAwake: ViewModifier {
    let enabled: Bool
    @State private var previous: Bool?
    func body(content: Content) -> some View {
        content.onAppear { update() }
            .onChange(of: enabled) { _, _ in update() }
            .onDisappear { restore() }
    }
    private func update() {
        #if os(iOS)
        if enabled {
            if previous == nil { previous = UIApplication.shared.isIdleTimerDisabled }
            UIApplication.shared.isIdleTimerDisabled = true
        } else { restore() }
        #endif
    }
    private func restore() {
        #if os(iOS)
        if let previous { UIApplication.shared.isIdleTimerDisabled = previous; self.previous = nil }
        #endif
    }
}
