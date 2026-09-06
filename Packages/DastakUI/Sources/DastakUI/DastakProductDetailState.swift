import Foundation

/// Kept independent of rendering so stock and gesture rules can be regression tested.
enum DastakProductDetailInteraction {
    struct PickerPose {
        let scale: Double
        let opacity: Double
        let rotation: Double
        let drop: Double
    }

    static func pickerPose(distance: Double) -> PickerPose {
        let depth = min(2.5, abs(distance))
        return PickerPose(scale: 1 - min(depth, 2) * 0.12,
                          opacity: 1 - min(depth, 2) * 0.25,
                          rotation: distance * 9,
                          drop: min(42, depth * depth * 10))
    }

    static func swipeStep(horizontal: Double, vertical: Double) -> Int? {
        guard abs(horizontal) >= 56, abs(horizontal) > abs(vertical) * 1.5 else { return nil }
        return horizontal < 0 ? 1 : -1
    }

    static func nextIndex(current: Int, count: Int, step: Int) -> Int? {
        let next = current + step
        return current >= 0 && current < count && next >= 0 && next < count ? next : nil
    }
}

struct DastakProductStockDraft {
    let text: String
    let currentQuantity: Int?
    let reserved: Int
    let selected: Bool
    let addingEmptySKU: Bool
    let stale: Bool
    let busy: Bool
    let active: Bool

    var quantity: Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), value >= 0, value <= max(0, 1_000_000 - reserved) else { return nil }
        return value
    }
    var isStockMode: Bool { selected || addingEmptySKU }
    var canEdit: Bool { isStockMode && active && !busy && !stale }
    var canSubmit: Bool {
        guard active, !busy, !stale else { return false }
        if !isStockMode { return true }
        guard let quantity, quantity != currentQuantity else { return false }
        return !addingEmptySKU || quantity > 0
    }
    var actionTitle: String { isStockMode ? "Save Stock" : "Add" }
}
