import UserNotifications

/// Keeps system notification state aligned with the app's unread state.
/// Opening either Dastak app means its delivered alerts have been seen.
@MainActor
public final class DastakNotificationInbox {
    private let removeDeliveredNotifications: () -> Void
    private let resetBadge: () -> Void

    public convenience init(center: UNUserNotificationCenter = .current()) {
        self.init(
            removeDeliveredNotifications: {
                center.removeAllDeliveredNotifications()
            },
            resetBadge: {
                Task {
                    try? await center.setBadgeCount(0)
                }
            }
        )
    }

    init(
        removeDeliveredNotifications: @escaping () -> Void,
        resetBadge: @escaping () -> Void
    ) {
        self.removeDeliveredNotifications = removeDeliveredNotifications
        self.resetBadge = resetBadge
    }

    public func clear() {
        removeDeliveredNotifications()
        resetBadge()
    }
}
