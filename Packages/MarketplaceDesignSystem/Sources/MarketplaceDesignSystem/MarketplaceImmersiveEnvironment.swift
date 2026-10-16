import SwiftUI

private struct ImmersiveEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}
private struct AuthenticationBackdropKey: EnvironmentKey {
    static var defaultValue: (@MainActor () -> AnyView)? { nil }
}
private struct AuthenticationFooterKey: EnvironmentKey {
    static var defaultValue: (@MainActor () -> AnyView)? { nil }
}
public extension EnvironmentValues {
    /// Opt-in only; other marketplace apps retain their existing page canvas.
    var marketplaceImmersiveEnvironment: Bool {
        get { self[ImmersiveEnvironmentKey.self] }
        set { self[ImmersiveEnvironmentKey.self] = newValue }
    }
    var marketplaceAuthenticationBackdrop: (@MainActor () -> AnyView)? {
        get { self[AuthenticationBackdropKey.self] }
        set { self[AuthenticationBackdropKey.self] = newValue }
    }
    /// Optional credit content above the Customer sign-in legal links. Kept in
    /// the footer layout, never overlaid on top of consent or authentication.
    var marketplaceAuthenticationFooter: (@MainActor () -> AnyView)? {
        get { self[AuthenticationFooterKey.self] }
        set { self[AuthenticationFooterKey.self] = newValue }
    }
}
