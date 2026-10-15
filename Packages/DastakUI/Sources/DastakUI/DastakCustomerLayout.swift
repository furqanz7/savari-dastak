import Foundation

/// Space available after system safe areas/keyboard avoidance, not a device-name list.
struct DastakCustomerLayout: Equatable {
    let usesCompactControls: Bool
    let inlineChromeHeight: Double
    let sceneryRevealHeight: Double
    let panelHorizontalInset: Double
    let panelDownshift: Double

    init(width: Double, height: Double, largerText: Bool) {
        // Phone-width content uses the same reachable controls as the narrow
        // preview. Expanded navigation is reserved for tablet-width space.
        usesCompactControls = largerText || width < 600 || height < 620
        inlineChromeHeight = min(264, max(0, height) * 0.5)
        // Reveal scenery above the panel while keeping the cart at the bottom.
        // Give that space back when the keyboard or larger text needs it.
        sceneryRevealHeight = !largerText && height >= 620 ? min(128, height * 0.16) : 0
        panelHorizontalInset = width >= 350 ? 24 : 16
        // Move the former 10-point trailing stack gap and 8-point bottom inset
        // above the panel, preserving its height on normal portrait layouts.
        panelDownshift = sceneryRevealHeight > 0 ? sceneryRevealHeight + 18 : 0
    }
}

enum DastakCustomerControlSheet: String, Identifiable {
    case navigation, services
    var id: String { rawValue }
    var title: String { self == .navigation ? "Dastak navigation" : "Services and aisles" }
}
