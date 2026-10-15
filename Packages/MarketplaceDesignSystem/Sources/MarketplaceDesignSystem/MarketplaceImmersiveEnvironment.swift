import SwiftUI

private struct ImmersiveEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}
private struct AuthenticationBackdropKey: EnvironmentKey {
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
}
