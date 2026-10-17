import Combine
import DastakLiveTracking
import Foundation
import MarketplaceInfrastructure

#if os(iOS)
  @preconcurrency import ActivityKit
  import UserNotifications
  import UIKit
#endif

/// Owns only the explicitly requested sample system surfaces. No device token,
/// push registration, production routing or shared activity reconciliation.
@MainActor final class DastakDemoSystemPresentation: ObservableObject {
  @Published private(set) var message: String?
  private var enabled = false
  private var revision = UUID()
  private var statuses: [UUID: String] = [:]
  private let sessionID = UUID().uuidString
  private var notificationIDs: [String] = []
  #if os(iOS)
    private var activity: Activity<DastakOrderActivity>?
  #endif

  func enable() async {
    let generation = revision
    #if os(iOS)
      let granted =
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound,
        ])) == true
      guard generation == revision, !Task.isCancelled else { return }
      enabled = true
      message =
        granted
        ? "Local sample alerts enabled. Remote APNs delivery is not part of the demo."
        : "Sample Live Activities enabled where allowed. Notification permission is off."
    #else
      message = "System previews require iPhone or iPad."
    #endif
  }

  func sync(_ orders: [DastakV1OrderSnapshot]) async {
    guard enabled, let order = orders.first else { return }
    let generation = revision
    let state = DastakOrderLiveTracking.state(order)
    let changed = statuses[order.id] != state.status
    statuses[order.id] = state.status
    #if os(iOS)
      if changed {
        let id = "dastak-demo-" + sessionID + "-" + UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "Demo · " + state.title
        content.body = "Sample Dastak order. No real delivery or payment."
        content.sound = .default
        content.userInfo = ["dastakReviewDemo": true]
        notificationIDs.append(id)
        try? await UNUserNotificationCenter.current().add(
          .init(identifier: id, content: content, trigger: nil))
        guard enabled, generation == revision, !Task.isCancelled else {
          UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
          UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
          return
        }
      }
      if let previous = activity, previous.attributes.orderID != order.id.uuidString.lowercased() {
        await previous.end(nil, dismissalPolicy: .immediate)
        activity = nil
      }
      guard enabled, generation == revision, !Task.isCancelled else { return }
      let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(180))
      if let activity {
        if state.terminal {
          await activity.end(content, dismissalPolicy: .immediate)
          self.activity = nil
        } else {
          await activity.update(content)
        }
      } else if !state.terminal, ActivityAuthorizationInfo().areActivitiesEnabled,
        UIApplication.shared.applicationState == .active
      {
        activity = try? Activity.request(
          attributes: DastakOrderActivity(
            orderID: order.id.uuidString.lowercased(),
            accountID: DastakReviewDemoClient.accountID.uuidString.lowercased(),
            orderNumber: "DEMO · " + order.displayOrderNumber,
            isFood: order.orderType == "FOOD_ONLY"), content: content, pushType: nil)
      }
    #endif
  }

  func stop() {
    revision = UUID()
    enabled = false
    #if os(iOS)
      if let activity { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
      activity = nil
      UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: notificationIDs)
      UNUserNotificationCenter.current().removeDeliveredNotifications(
        withIdentifiers: notificationIDs)
    #endif
    notificationIDs = []
  }
}
