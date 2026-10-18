import DastakLiveTracking
import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
#if canImport(ActivityKit) && os(iOS)
@preconcurrency import ActivityKit
import UIKit
#endif

/// One controller per authenticated Customer model. Never publishes addresses,
/// phone numbers, delivery codes or item names to the Lock Screen.
@MainActor
final class DastakOrderLiveTracking {
    private let functions: any FunctionClient
    private let accountID: @Sendable () async throws -> UUID
    private var revision = UUID()
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    private var knownActivities: Set<String> = []
    private var startedOrders: Set<String> = []
    init(functions: any FunctionClient, accountID: @escaping @Sendable () async throws -> UUID) {
        self.functions = functions; self.accountID = accountID
    }
    deinit {
        tokenTasks.values.forEach { $0.cancel() }
        #if canImport(ActivityKit) && os(iOS)
        let owned = knownActivities
        Task { for activity in Activity<DastakOrderActivity>.activities where owned.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        } }
        #endif
    }

    func sync(_ orders: [DastakV1OrderSnapshot]) async {
        #if canImport(ActivityKit) && os(iOS)
        let generation = UUID(); revision = generation
        guard let account = try? await accountID(), revision == generation else { return }
        let owner = account.uuidString.lowercased()
        for activity in Activity<DastakOrderActivity>.activities where activity.attributes.accountID != owner {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard revision == generation else { return }
        // Limit occupied system surfaces. Existing activities still receive their
        // terminal state even when a newer order has become the visible order.
        let activeIDs = Set(orders.filter { !Self.state($0).terminal }.prefix(2).map { $0.id.uuidString.lowercased() })
        for order in orders {
            guard revision == generation else { return }
            let id = order.id.uuidString.lowercased(), state = Self.state(order)
            let existing = Activity<DastakOrderActivity>.activities.filter { $0.attributes.orderID == id && $0.attributes.accountID == owner }
            for duplicate in existing.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
            let content = ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(180), relevanceScore: state.stage == 3 ? 100 : 50)
            if let activity = existing.first {
                knownActivities.insert(activity.id)
                startedOrders.insert(id)
                guard state.version >= activity.content.state.version else { continue }
                // Mission changes can share the same order version. A late
                // foreground response must not undo a newer arrival push.
                if state.version == activity.content.state.version,
                   state.updatedAt < activity.content.state.updatedAt { continue }
                if state.terminal {
                    await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(300)))
                    tokenTasks.removeValue(forKey: activity.id)?.cancel()
                } else {
                    await activity.update(content)
                    observeToken(activity)
                }
            } else if activeIDs.contains(id), !state.terminal, !startedOrders.contains(id),
                      ActivityAuthorizationInfo().areActivitiesEnabled,
                      UIApplication.shared.applicationState == .active {
                // No historical order is started as a fresh Live Activity.
                guard let created = Self.date(order.createdAt),
                      Date.now.timeIntervalSince(created) < 8 * 3600 else { continue }
                let attributes = DastakOrderActivity(orderID: id, accountID: owner,
                    orderNumber: order.displayOrderNumber, isFood: order.orderType != "RETAIL_ONLY")
                if let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token) {
                    knownActivities.insert(activity.id)
                    startedOrders.insert(id)
                    observeToken(activity)
                }
            }
        }
        #endif
    }

    static func state(_ order: DastakV1OrderSnapshot) -> DastakOrderActivity.ContentState {
        .init(status: DastakOrderActivity.presentationStatus(orderStatus: order.status.rawValue,
                                                           trackingPhase: order.tracking?.phase,
                                                           fulfilmentState: order.fulfilmentProgress?.state), version: order.version,
              updatedAt: max(date(order.updatedAt)?.timeIntervalSince1970 ?? 0,
                             order.tracking.flatMap { date($0.serverTime)?.timeIntervalSince1970 } ?? 0))
    }
    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    #if canImport(ActivityKit) && os(iOS)
    private func observeToken(_ activity: Activity<DastakOrderActivity>) {
        guard tokenTasks[activity.id] == nil else { return }
        let functions = self.functions
        tokenTasks[activity.id] = Task {
            for await bytes in activity.pushTokenUpdates {
                let token = bytes.map { String(format: "%02x", $0) }.joined()
                guard let environment = DastakNotificationPreferences.apnsEnvironment else { continue }
                // Token rotation is registered independently of ordinary APNs tokens.
                var attempt = 0
                while !Task.isCancelled {
                    guard !Task.isCancelled else { return }
                    do {
                        let _: Registration = try await functions.invoke("register-order-live-activity",
                            request: RegistrationRequest(orderId: activity.attributes.orderID,
                                activityId: activity.id, token: token,
                                environment: environment),
                            idempotencyKey: IdempotencyKey(rawValue: UUID().uuidString)!)
                        break
                    } catch {
                        attempt = min(attempt + 1, 12)
                        do { try await Task.sleep(for: .seconds(5 * attempt)) }
                        catch { return }
                    }
                }
            }
        }
    }
    private struct RegistrationRequest: Encodable, Sendable {
        let orderId: String; let activityId: String; let token: String; let environment: String
    }
    private struct Registration: Decodable, Sendable { let registered: Bool }
    #endif
}
