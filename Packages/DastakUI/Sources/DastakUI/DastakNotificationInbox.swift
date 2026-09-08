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
                Task { @MainActor in
                    // APNs can finish applying a badge just after an app becomes
                    // active. Clear immediately, then reassert after the launch
                    // transition so a late payload cannot leave stale state.
                    try? await center.setBadgeCount(0)

                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    center.removeAllDeliveredNotifications()
                    try? await center.setBadgeCount(0)

                    try? await Task.sleep(for: .milliseconds(750))
                    guard !Task.isCancelled else { return }
                    center.removeAllDeliveredNotifications()
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
