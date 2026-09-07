import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

private struct DastakAppNotificationsKey: EnvironmentKey {
    static let defaultValue: DastakMerchantNotifications? = nil
}

extension EnvironmentValues {
    var dastakAppNotifications: DastakMerchantNotifications? {
        get { self[DastakAppNotificationsKey.self] }
        set { self[DastakAppNotificationsKey.self] = newValue }
    }
}

/// Lives above the Customer / Delivery mode switch so both modes register the
/// same app token with the current authenticated account, never a disk cache.
private struct DastakAppNotificationRegistration: ViewModifier {
    @StateObject private var notifications: DastakMerchantNotifications
    @Environment(\.scenePhase) private var scenePhase

    init(functions: any FunctionClient) {
        _notifications = StateObject(wrappedValue: DastakMerchantNotifications(
            functions: functions, applicationID: "com.dastak.app"
        ))
    }

    func body(content: Content) -> some View {
        content
            .environment(\.dastakAppNotifications, notifications)
            .task { await notifications.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await notifications.refresh() } }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("dastak.notification.deviceTokenRegistered")
            )) { event in
                guard let token = event.object as? String else { return }
                Task { await notifications.receiveDeviceToken(token) }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("dastak.notification.deviceTokenFailed")
            )) { _ in notifications.registrationFailed() }
    }
}

public extension View {
    func dastakAppNotifications(functions: any FunctionClient) -> some View {
        modifier(DastakAppNotificationRegistration(functions: functions))
    }
}

struct DastakAppNotificationStatus: View {
    @Environment(\.dastakAppNotifications) private var notifications
    var body: some View {
        if let notifications { DastakAppNotificationStatusContent(notifications: notifications) }
    }
}

private struct DastakAppNotificationStatusContent: View {
    @ObservedObject var notifications: DastakMerchantNotifications
    var body: some View {
        if notifications.needsAttention {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(notifications.isConnecting ? "Connecting alerts…" : "Keep delivery alerts on")
                        .font(.subheadline.weight(.semibold))
                    Text(notifications.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if notifications.isConnecting { ProgressView() }
                else {
                    Button(notifications.actionTitle) { Task { await notifications.enable() } }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
            .padding(16)
            .marketplaceFlatSurface()
        }
    }
}
