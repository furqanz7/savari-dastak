import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

final class DastakCustomerLifecycleTests: XCTestCase {
    func testCustomerOnboardingNeverRequiresDeliveryAddress() {
        XCTAssertEqual(
            DastakCustomerOnboardingStep.next(
                hasCompleted: false,
                notificationState: .notRequested
            ),
            .notifications
        )
        XCTAssertNil(
            DastakCustomerOnboardingStep.next(
                hasCompleted: true,
                notificationState: .notRequested
            )
        )
        XCTAssertNil(DastakCustomerOnboardingStep.next(hasCompleted: false, notificationState: .enabled))
        XCTAssertNil(DastakCustomerOnboardingStep.next(hasCompleted: false, notificationState: .disabled))
        XCTAssertNil(DastakCustomerOnboardingStep.next(hasCompleted: false, notificationState: .unavailable))
    }

    func testDiscoveryLocationNeverRetainsDoorstepDetails() {
        let savedAddress = DastakDeliveryLocation(
            address: "128 Mandi Street",
            point: GeoPoint(latitude: 12.6819, longitude: 78.6201),
            label: "Home",
            details: "Second floor"
        )

        let discovery = DastakCustomerModel.discoveryLocation(from: savedAddress)

        XCTAssertEqual(discovery.address, savedAddress.address)
        XCTAssertEqual(discovery.point, savedAddress.point)
        XCTAssertNil(discovery.label)
        XCTAssertNil(discovery.details)
    }

    func testAccountDeletionRetryUsesOneDurableKeyUntilConfirmed() throws {
        let suiteName = "DastakCustomerLifecycleTests.accountDeletion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var firstLaunch = DastakAccountDeletionAttempt(defaults: defaults)
        let firstKey = firstLaunch.key(scope: "customer-1")
        var nextLaunch = DastakAccountDeletionAttempt(defaults: defaults)
        XCTAssertEqual(nextLaunch.key(scope: "customer-1"), firstKey)

        nextLaunch.complete(scope: "customer-1")
        XCTAssertNotEqual(nextLaunch.key(scope: "customer-1"), firstKey)
    }

    func testEveryMerchantOrderStateHasOneHumanLabelAndPrimaryAction() {
        let expected: [(MerchantOrderStatus, String, DastakCustomerPrimaryAction)] = [
            (.paymentPending, "Payment pending", .pay),
            (.paid, "Sent to store", .cancel),
            (.merchantAccepted, "Being prepared", .requestCancellation),
            (.ready, "Ready for pickup", .requestCancellation),
            (.assigned, "Partner assigned", .requestCancellation),
            (.enRouteToPickup, "Heading to store", .requestCancellation),
            (.atStore, "At the store", .requestCancellation),
            (.pickedUp, "Picked up", .requestCancellation),
            (.inTransit, "Arriving soon", .requestCancellation),
            (.delivered, "Delivered", .none),
            (.cancelled, "Cancelled", .none),
            (.returningToMerchant, "Returning to store", .none),
        ]

        XCTAssertEqual(Set(expected.map(\.0.rawValue)), Set(MerchantOrderStatus.allCases.map(\.rawValue)))
        for (status, title, action) in expected {
            let presentation = DastakCustomerLifecycle.merchantOrder(
                status: status,
                paymentState: status == .paymentPending ? .paymentPending : .paid
            )
            XCTAssertEqual(presentation.title, title)
            XCTAssertEqual(presentation.primaryAction, action)
        }
    }

    func testEveryParcelStateHasOneHumanLabelAndPrimaryAction() {
        let expected: [(ParcelDeliveryStatus, String, DastakCustomerPrimaryAction)] = [
            (.paymentPending, "Payment pending", .pay),
            (.paid, "Finding a partner", .cancel),
            (.assigned, "Partner assigned", .cancel),
            (.enRouteToPickup, "Heading to pickup", .cancel),
            (.pickedUp, "Picked up", .none),
            (.inTransit, "Arriving soon", .none),
            (.delivered, "Delivered", .none),
            (.cancelled, "Cancelled", .none),
        ]

        XCTAssertEqual(Set(expected.map(\.0.rawValue)), Set(ParcelDeliveryStatus.allCases.map(\.rawValue)))
        for (status, title, action) in expected {
            let presentation = DastakCustomerLifecycle.parcel(
                status: status,
                paymentStatus: status == .paymentPending ? .pending : .paid,
                audience: .sender
            )
            XCTAssertEqual(presentation.title, title)
            XCTAssertEqual(presentation.primaryAction, action)
        }
    }

    func testRecipientNeverReceivesPaymentOrCancellationAction() {
        for status in ParcelDeliveryStatus.allCases {
            XCTAssertEqual(
                DastakCustomerLifecycle.parcel(
                    status: status,
                    paymentStatus: .pending,
                    audience: .recipient
                ).primaryAction,
                .none
            )
        }
    }

    func testFailedParcelPaymentCanBeRetried() {
        XCTAssertEqual(
            DastakCustomerLifecycle.parcel(
                status: .paymentPending,
                paymentStatus: .failed,
                audience: .sender
            ).primaryAction,
            .pay
        )
    }

    func testEveryMoneyStateHasAnExactLabel() {
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(MerchantOrderPaymentState.paymentPending), "Payment pending")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(MerchantOrderPaymentState.paid), "Paid")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(MerchantOrderPaymentState.notCollected), "Not charged")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(MerchantOrderPaymentState.refundPending), "Refund processing")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(MerchantOrderPaymentState.refunded), "Refunded")

        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(ParcelPaymentStatus.pending), "Payment pending")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(ParcelPaymentStatus.paid), "Paid")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(ParcelPaymentStatus.failed), "Payment failed")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(ParcelPaymentStatus.refundPending), "Refund processing")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(ParcelPaymentStatus.refunded), "Refunded")
        XCTAssertEqual(DastakCustomerLifecycle.paymentTitle(ParcelPaymentStatus.cancelled), "Not charged")
    }

    func testPlacementAttemptReusesKeyUntilQuoteChanges() throws {
        let firstQuote = UUID()
        let nextQuote = UUID()
        let firstKey = try XCTUnwrap(IdempotencyKey(rawValue: "first-key"))
        let nextKey = try XCTUnwrap(IdempotencyKey(rawValue: "next-key"))
        var keys = [firstKey, nextKey].makeIterator()
        var attempt = DastakOrderPlacementAttempt()

        XCTAssertEqual(attempt.key(for: firstQuote, makeKey: { keys.next()! }), firstKey)
        XCTAssertEqual(attempt.key(for: firstQuote, makeKey: { keys.next()! }), firstKey)
        XCTAssertEqual(attempt.key(for: nextQuote, makeKey: { keys.next()! }), nextKey)
    }

    func testNotificationPayloadRoutesToExactEntity() throws {
        let orderID = UUID()
        let parcelID = UUID()

        XCTAssertEqual(
            DastakCustomerDestination(notificationPayload: [
                "entityType": "dastakV1Order",
                "orderId": orderID.uuidString,
            ]),
            .dastakV1Order(orderID)
        )
        XCTAssertEqual(
            DastakCustomerDestination(notificationPayload: [
                "entityType": "dastakV1Order",
                "entityId": orderID.uuidString,
            ]),
            .dastakV1Order(orderID)
        )
        XCTAssertEqual(
            DastakCustomerDestination(notificationPayload: ["orderId": orderID.uuidString]),
            .merchantOrder(orderID)
        )
        XCTAssertEqual(
            DastakCustomerDestination(notificationPayload: ["entityType": "parcel", "parcelId": parcelID.uuidString]),
            .parcel(parcelID)
        )
        XCTAssertEqual(
            DastakCustomerDestination(notificationPayload: ["entityType": "parcel", "entityId": parcelID.uuidString]),
            .parcel(parcelID)
        )
        XCTAssertNil(DastakCustomerDestination(notificationPayload: ["orderId": "invalid"]))
    }
}

private extension MerchantOrderStatus {
    static var allCases: [MerchantOrderStatus] {
        [
            .paymentPending, .paid, .merchantAccepted, .ready, .assigned,
            .enRouteToPickup, .atStore, .pickedUp, .inTransit, .delivered,
            .cancelled, .returningToMerchant,
        ]
    }
}

private extension ParcelDeliveryStatus {
    static var allCases: [ParcelDeliveryStatus] {
        [
            .paymentPending, .paid, .assigned, .enRouteToPickup,
            .pickedUp, .inTransit, .delivered, .cancelled,
        ]
    }
}
