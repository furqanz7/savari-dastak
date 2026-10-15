import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

public enum MarketplaceHapticEvent: Int, CaseIterable, Sendable {
    case tap, selection, itemRemoved, itemAdded, basketPickup, success, warning, error
}

/// One meaningful pulse per action: a semantic result replaces the fallback tap.
/// No press-state/scroll observer is used; cancelled touches stay silent.
public struct MarketplaceHapticBatch: Sendable {
    public private(set) var pending: MarketplaceHapticEvent?
    public init() {}
    public mutating func enqueue(_ event: MarketplaceHapticEvent) {
        if pending == nil || event.rawValue > pending!.rawValue { pending = event }
    }
    public mutating func take(enabled: Bool, active: Bool) -> MarketplaceHapticEvent? {
        defer { pending = nil }
        return enabled && active ? pending : nil
    }
}

@MainActor
public final class MarketplaceHapticScope: ObservableObject {
    public static let preferenceKey = "dastak.customer.hapticsEnabled"
    public var isActive = false {
        didSet { if !isActive { cancel() } }
    }
    private var batch = MarketplaceHapticBatch()
    private var task: Task<Void, Never>?
    private let output: @MainActor (MarketplaceHapticEvent) -> Void
    private let enabled: @MainActor () -> Bool
    private let foreground: @MainActor () -> Bool

    public init(output: @escaping @MainActor (MarketplaceHapticEvent) -> Void = MarketplaceHapticScope.hardware,
                enabled: @escaping @MainActor () -> Bool = {
                    UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
                }, foreground: @escaping @MainActor () -> Bool = MarketplaceHapticScope.isForeground) {
        self.output = output; self.enabled = enabled; self.foreground = foreground
    }

    public func play(_ event: MarketplaceHapticEvent) {
        guard isActive, enabled(), foreground() else { cancel(); return }
        batch.enqueue(event)
        guard task == nil else { return }
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            guard let self else { return }
            self.task = nil
            if let event = self.batch.take(enabled: self.enabled(), active: self.isActive && self.foreground()) {
                self.output(event)
            }
        }
    }

    deinit { task?.cancel() }

    private func cancel() {
        task?.cancel(); task = nil
        _ = batch.take(enabled: false, active: false)
    }

    public static func isForeground() -> Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        false
        #endif
    }

    public static func hardware(_ event: MarketplaceHapticEvent) {
        // The simulator cannot validate physical vibration. UIKit gracefully
        // honours device/system support; no audio or fallback vibration is used.
        #if os(iOS) && !targetEnvironment(simulator)
        switch event {
        case .selection:
            MarketplaceHapticHardware.selection.selectionChanged()
        case .tap, .itemRemoved:
            MarketplaceHapticHardware.soft.impactOccurred(intensity: 0.5)
        case .itemAdded:
            MarketplaceHapticHardware.light.impactOccurred(intensity: 0.65)
        case .basketPickup:
            MarketplaceHapticHardware.medium.impactOccurred(intensity: 0.7)
        case .success:
            MarketplaceHapticHardware.notification.notificationOccurred(.success)
        case .warning:
            MarketplaceHapticHardware.notification.notificationOccurred(.warning)
        case .error:
            MarketplaceHapticHardware.notification.notificationOccurred(.error)
        }
        #endif
    }
}

#if os(iOS) && !targetEnvironment(simulator)
@MainActor
private enum MarketplaceHapticHardware {
    static let selection = UISelectionFeedbackGenerator()
    static let soft = UIImpactFeedbackGenerator(style: .soft)
    static let light = UIImpactFeedbackGenerator(style: .light)
    static let medium = UIImpactFeedbackGenerator(style: .medium)
    static let notification = UINotificationFeedbackGenerator()
}
#endif

private struct MarketplaceHapticScopeKey: EnvironmentKey {
    static let defaultValue: MarketplaceHapticScope? = nil
}

public extension EnvironmentValues {
    var marketplaceHapticScope: MarketplaceHapticScope? {
        get { self[MarketplaceHapticScopeKey.self] }
        set { self[MarketplaceHapticScopeKey.self] = newValue }
    }
}

/// A normal SwiftUI Button: retains styles, disabled state, roles and VoiceOver.
/// Feedback happens only when its action is actually invoked.
public struct MarketplaceFeedbackButton<Label: View>: View {
    private let role: ButtonRole?
    private let event: MarketplaceHapticEvent
    private let action: () -> Void
    private let label: Label
    @Environment(\.marketplaceHapticScope) private var haptics

    public init(role: ButtonRole? = nil, haptic: MarketplaceHapticEvent = .tap,
                action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = role; event = haptic; self.action = action; self.label = label()
    }

    public var body: some View {
        Button(role: role) {
            action()
            haptics?.play(role == .destructive ? .warning : event)
        } label: { label }
    }
}

public extension MarketplaceFeedbackButton where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, haptic: MarketplaceHapticEvent = .tap,
         action: @escaping () -> Void) {
        self.init(role: role, haptic: haptic, action: action) { Text(title) }
    }
}

/// Retains native navigation-link behaviour and emits only on activation,
/// never when its destination reappears after backgrounding or navigating back.
public struct MarketplaceFeedbackNavigationLink<Destination: View, Label: View>: View {
    private let destination: () -> Destination
    private let label: Label
    @State private var presented = false
    @Environment(\.marketplaceHapticScope) private var haptics
    public init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination; self.label = label()
    }
    public var body: some View {
        NavigationLink(isActive: Binding(get: { presented }, set: { next in
            if next && !presented { haptics?.play(.tap) }
            presented = next
        }), destination: destination, label: { label })
    }
}

private struct MarketplaceSelectionFeedback<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.marketplaceHapticScope) private var haptics
    func body(content: Content) -> some View {
        content.onChange(of: value) { _ in haptics?.play(.selection) }
    }
}

private struct MarketplaceHapticsModifier: ViewModifier {
    let enabled: Bool
    @StateObject private var scope = MarketplaceHapticScope()
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.environment(\.marketplaceHapticScope, scope)
            .onAppear { scope.isActive = enabled && phase == .active }
            .onChange(of: phase) { phase in scope.isActive = enabled && phase == .active }
            .onChange(of: enabled) { enabled in scope.isActive = enabled && phase == .active }
    }
}

public extension View {
    func marketplaceHaptics(enabled: Bool = true) -> some View {
        modifier(MarketplaceHapticsModifier(enabled: enabled))
    }
    func marketplaceSelectionFeedback<Value: Equatable>(_ value: Value) -> some View {
        modifier(MarketplaceSelectionFeedback(value: value))
    }
}
