import Foundation

/// Preserve the approved dark glass; avoid a white platter in normal light appearance.
enum DastakPanelReadability {
    enum Surface: Equatable { case adaptiveGlass, clearGlass, opaque }
    static let lightGlassTintOpacity = 0.08
    static let lightNoticeOpacity = 0.40

    static func surface(isDark: Bool, supportsNativeGlass: Bool, reduceTransparency: Bool,
                        increasedContrast: Bool) -> Surface {
        guard supportsNativeGlass && !reduceTransparency && !increasedContrast else { return .opaque }
        return isDark ? .adaptiveGlass : .clearGlass
    }
}
