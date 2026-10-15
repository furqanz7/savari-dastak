import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor
final class DastakMerchantRecoveryTests: XCTestCase {
    func testRecoveryFeedPreservesExactSKUQuantityPackAndBranch() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        let offer = try XCTUnwrap(model.recoveryOpportunities.first)
        XCTAssertEqual(offer.requestedQuantity, 3)
        XCTAssertEqual(offer.sku.packSize, "500 ml")
        XCTAssertEqual(offer.sku.variantName, "Full cream")
        XCTAssertEqual(offer.branch.id, recoveryBranch)
        XCTAssertTrue(model.recoveryCurrent)
        XCTAssertTrue(model.fulfilmentsCurrent)
        let reads = await functions.readCount
        XCTAssertEqual(reads, 1, "Normal orders and recovery share one endpoint read.")
    }

    func testMalformedRecoveryRetainsLastGoodRequestsAndDoesNotLoseNormalOrders() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.setFeed(feedData(order: orderFixture(version: 5), offers: "[{}]"))
        await model.refreshV1Fulfilments()
        XCTAssertEqual(model.v1Fulfilments.first?.version, 5)
        XCTAssertEqual(model.recoveryOpportunities.count, 1)
        XCTAssertTrue(model.fulfilmentsCurrent)
        XCTAssertFalse(model.recoveryCurrent)
        XCTAssertTrue(model.orderRefreshFailures.contains("Exact-item recovery"))
        XCTAssertTrue(model.recoveryActionsDisabled)
    }

    func testMalformedNormalLaneDoesNotLoseRecoveryAndMissingRecoveryIsNotEmpty() async {
        let functions = RecoveryFunctions(feed: feedData(order: "{}"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        XCTAssertFalse(model.fulfilmentsCurrent)
        XCTAssertTrue(model.recoveryCurrent)
        XCTAssertEqual(model.recoveryOpportunities.count, 1)
        await functions.setFeed(Data("{\"fulfilments\":[\(orderFixture())]}".utf8))
        await model.refreshV1Fulfilments()
        XCTAssertTrue(model.fulfilmentsCurrent)
        XCTAssertFalse(model.recoveryCurrent)
        XCTAssertEqual(model.recoveryOpportunities.count, 1)
    }

    func testAcceptanceRequiresPhysicalConfirmationValidDeadlineAndPreparation() async throws {
        for (status, expiry, confirmed, minutes) in [
            ("OFFERED", "2099-01-01T00:00:00Z", false, 10),
            ("OFFERED", "2000-01-01T00:00:00Z", true, 10),
            ("OFFERED", "invalid", true, 10),
            ("CLOSED", "2099-01-01T00:00:00Z", true, 10),
            ("OFFERED", "2099-01-01T00:00:00Z", true, 0),
            ("OFFERED", "2099-01-01T00:00:00Z", true, 1441)
        ] {
            let functions = RecoveryFunctions(feed: feedData(offers: "[\(offerFixture(status: status, expiry: expiry))]"))
            let model = makeModel(functions)
            await model.refreshV1Fulfilments()
            let saved = await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: true,
                prepMinutes: minutes, physicallyConfirmed: confirmed)
            XCTAssertFalse(saved)
            let writes = await functions.writes
            XCTAssertTrue(writes.isEmpty)
        }
    }

    func testAcceptSendsOnlyOfferVersionAndPreparationAndChecksExactReceipt() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.enqueue(.data(responseReceipt()))
        let saved = await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: true,
            prepMinutes: 15, physicallyConfirmed: true)
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingRecoveryCommand)
        let body = try await firstBody(functions)
        XCTAssertEqual(body["operation"] as? String, "respondExactSkuRecoveryOffer")
        XCTAssertEqual(body["recoveryOpportunityId"] as? String, recoveryOffer.uuidString)
        XCTAssertEqual(body["expectedVersion"] as? Int, 2)
        XCTAssertEqual(body["promisedPrepMinutes"] as? Int, 15)
        XCTAssertEqual(body["response"] as? String, "ACCEPT")
        for key in ["skuId", "quantity", "price", "accountId", "branchId"] { XCTAssertNil(body[key]) }
    }

    func testUnavailableDoesNotRequireStockOrSendPreparationMinutes() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.enqueue(.data(responseReceipt(accept: false)))
        let saved = await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: false,
            prepMinutes: 99, physicallyConfirmed: false)
        XCTAssertTrue(saved)
        let body = try await firstBody(functions)
        XCTAssertEqual(body["response"] as? String, "UNAVAILABLE")
        XCTAssertNil(body["promisedPrepMinutes"])
    }

    func testTimeoutThenChangedPreparationOrResponseCannotReplacePendingCommand() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        let offer = try XCTUnwrap(model.recoveryOpportunities.first)
        _ = await model.respondToRecovery(offer, accept: true, prepMinutes: 15, physicallyConfirmed: true)
        _ = await model.respondToRecovery(offer, accept: true, prepMinutes: 30, physicallyConfirmed: true)
        _ = await model.respondToRecovery(offer, accept: false, prepMinutes: 0, physicallyConfirmed: false)
        _ = await model.retryRecoveryCommand()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].key, writes[1].key)
        XCTAssertEqual(writes[0].body, writes[1].body)
        XCTAssertEqual(try object(writes[1].body)["promisedPrepMinutes"] as? Int, 15)
        XCTAssertNotNil(model.pendingRecoveryCommand)
    }

    func testExactUnavailableReportTargetsLineAndKeepsPriceServerOwned() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.enqueue(.data(exactReceipt()))
        let saved = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: recoveryLine, reason: "  Item damaged  ")
        XCTAssertTrue(saved)
        let body = try await firstBody(functions)
        XCTAssertEqual(body["operation"] as? String, "reportExactSkuFailure")
        XCTAssertEqual(body["fulfilmentId"] as? String, recoveryFulfilment.uuidString)
        XCTAssertEqual(body["orderLineId"] as? String, recoveryLine.uuidString)
        XCTAssertEqual(body["expectedVersion"] as? Int, 3)
        XCTAssertEqual(body["reason"] as? String, "Item damaged")
        XCTAssertNil(body["quantity"])
        XCTAssertNil(body["refund"])
    }

    func testExactReportRejectsMissingCapabilityPackagesWrongLineAndInvalidReason() async throws {
        for (capability, packages, line, reason) in [
            (false, "null", recoveryLine, "Item damaged"),
            (true, "1", recoveryLine, "Item damaged"),
            (true, "null", UUID(), "Item damaged"),
            (true, "null", recoveryLine, "x"),
            (true, "null", recoveryLine, String(repeating: "x", count: 501))
        ] {
            let functions = RecoveryFunctions(feed: feedData(order: orderFixture(capability: capability, packages: packages)))
            let model = makeModel(functions)
            await model.refreshV1Fulfilments()
            let saved = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: line, reason: reason)
            XCTAssertFalse(saved)
            let writes = await functions.writes
            XCTAssertTrue(writes.isEmpty)
        }
    }

    func testGeneralProblemPreservesReadyAndChecksRecordedReason() async throws {
        let functions = RecoveryFunctions(feed: feedData(order: orderFixture(status: "READY", capability: false, packages: "1")))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        let updated = orderFixture(version: 4, status: "READY", capability: false, packages: "1", reports: "[{\"id\":\"\(UUID())\",\"statusAtReport\":\"READY\",\"reason\":\"Packaging damaged\",\"reportedAt\":\"2026-10-11T00:00:00Z\"}]")
        await functions.enqueue(.data(Data(updated.utf8)))
        await functions.setFeed(feedData(order: updated))
        let saved = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: nil, reason: "Packaging damaged")
        XCTAssertTrue(saved)
        XCTAssertEqual(model.v1Fulfilments.first?.status, "READY")
        XCTAssertEqual(model.v1Fulfilments.first?.problemReports?.count, 1)
        let body = try await firstBody(functions)
        XCTAssertEqual(body["operation"] as? String, "reportFulfilmentProblem")
        XCTAssertNil(body["orderLineId"])
    }

    func testUnknownReportBlocksRelatedReadyAndPackagesAndRetriesOriginalReason() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        let order = try XCTUnwrap(model.v1Fulfilments.first)
        _ = await model.reportRecoveryProblem(order, lineID: recoveryLine, reason: "Item damaged")
        XCTAssertTrue(model.recoveryBlocks(order))
        await model.markV1Ready(order)
        await model.declareV1Packages(order, count: 1)
        _ = await model.reportRecoveryProblem(order, lineID: recoveryLine, reason: "Different reason")
        _ = await model.retryRecoveryCommand()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].body, writes[1].body)
        XCTAssertEqual(writes[0].key, writes[1].key)
    }

    func testDefinitiveRejectionRefreshesAndRequiresNewCurrentVersion() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        let old = try XCTUnwrap(model.v1Fulfilments.first)
        await functions.enqueue(.api(409))
        await functions.setFeed(feedData(order: orderFixture(version: 4)))
        _ = await model.reportRecoveryProblem(old, lineID: recoveryLine, reason: "Item damaged")
        XCTAssertNil(model.pendingRecoveryCommand)
        _ = await model.reportRecoveryProblem(old, lineID: recoveryLine, reason: "Item damaged")
        _ = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: recoveryLine, reason: "Item damaged")
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2)
        XCTAssertNotEqual(writes[0].key, writes[1].key)
        XCTAssertEqual(try object(writes[1].body)["expectedVersion"] as? Int, 4)
    }

    func testUnknownHTTPAndInvalidAcknowledgementsRetainPendingWithoutClaimingSuccess() async throws {
        for reply in [RecoveryFunctions.Reply.api(408), .api(429), .api(500), .data(Data("{}".utf8)),
            .data(responseReceipt(quantity: 1)), .data(responseReceipt(payment: 100)), .data(responseReceipt(offer: UUID()))] {
            let functions = RecoveryFunctions()
            let model = makeModel(functions)
            await model.refreshV1Fulfilments()
            await functions.enqueue(reply)
            let saved = await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: true,
                prepMinutes: 10, physicallyConfirmed: true)
            XCTAssertFalse(saved)
            XCTAssertNotNil(model.pendingRecoveryCommand)
            XCTAssertTrue(model.recoveryActionsDisabled)
        }
    }

    func testAcknowledgedSaveWithReadFailureDoesNotRepeatWriteOrEnableStaleControls() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.enqueue(.data(exactReceipt()))
        await functions.failNextRead()
        let saved = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: recoveryLine, reason: "Item damaged")
        XCTAssertTrue(saved)
        XCTAssertNil(model.pendingRecoveryCommand)
        XCTAssertFalse(model.fulfilmentsCurrent)
        XCTAssertFalse(model.recoveryCurrent)
        XCTAssertNotNil(model.recoveryCommandMessage)
        await model.refreshV1Fulfilments()
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1)
    }

    func testConcurrentRetriesAreBlockedUntilOriginalResponseCompletes() async throws {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        let offer = try XCTUnwrap(model.recoveryOpportunities.first)
        await functions.holdNextWrite()
        let task = Task { await model.respondToRecovery(offer, accept: true, prepMinutes: 10, physicallyConfirmed: true) }
        await functions.waitUntilHeld()
        let retried = await model.retryRecoveryCommand()
        XCTAssertFalse(retried)
        await functions.release(.data(responseReceipt()))
        let saved = await task.value
        XCTAssertTrue(saved)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 1)
    }

    func testInvalidRecoveryQuantitiesFailOnlyRecoveryLane() async {
        let functions = RecoveryFunctions(feed: feedData(offers: "[\(offerFixture(quantity: 0))]"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        XCTAssertTrue(model.fulfilmentsCurrent)
        XCTAssertFalse(model.recoveryCurrent)
        XCTAssertTrue(model.recoveryOpportunities.isEmpty)
    }

    func testLateReadCannotRestoreOldRequestsAfterNewerRefresh() async {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.holdNextRead()
        let oldRead = Task { await model.refreshV1Fulfilments() }
        await functions.waitUntilHeld()
        await functions.setFeed(feedData(order: orderFixture(version: 8), offers: "[]"))
        await model.refreshV1Fulfilments()
        await functions.release(.data(feedData()))
        await oldRead.value
        XCTAssertEqual(model.v1Fulfilments.first?.version, 8)
        XCTAssertTrue(model.recoveryOpportunities.isEmpty)
        XCTAssertTrue(model.recoveryCurrent)
    }

    func testWrongLineOrChangedPaymentExactReceiptDoesNotResolvePendingReport() async throws {
        for receipt in [String(decoding: exactReceipt(), as: UTF8.self)
            .replacingOccurrences(of: recoveryLine.uuidString, with: UUID().uuidString),
            String(decoding: exactReceipt(), as: UTF8.self).replacingOccurrences(of: "\"customerPaymentChanged\":false", with: "\"customerPaymentChanged\":true")] {
            let functions = RecoveryFunctions()
            let model = makeModel(functions)
            await model.refreshV1Fulfilments()
            await functions.enqueue(.data(Data(receipt.utf8)))
            let saved = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: recoveryLine, reason: "Item damaged")
            XCTAssertFalse(saved)
            XCTAssertNotNil(model.pendingRecoveryCommand)
        }
    }

    func testLateSuccessfulReadCannotClearNewerReadFailureWarning() async {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.holdNextRead()
        let oldRead = Task { await model.refreshV1Fulfilments() }
        await functions.waitUntilHeld()
        await functions.failNextRead()
        await model.refreshV1Fulfilments()
        await functions.release(.data(feedData()))
        await oldRead.value
        XCTAssertFalse(model.fulfilmentsCurrent)
        XCTAssertFalse(model.recoveryCurrent)
        XCTAssertTrue(model.orderRefreshFailures.contains("Preparation and pickup"))
        XCTAssertTrue(model.orderRefreshFailures.contains("Exact-item recovery"))
    }

    func testFourOperationLanesShareOneReadWithoutMutation() async throws {
        let functions = RecoveryFunctions(feed: feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        XCTAssertTrue(model.orderRefreshFailures.isEmpty)
        XCTAssertTrue(model.returnsCurrent)
        XCTAssertTrue(model.settlementsCurrent)
        XCTAssertNotNil(model.returnsRefreshedAt)
        XCTAssertEqual(model.returnReceipts.first?.id, recoveryStop)
        XCTAssertEqual(model.settlements.first?.amountPaise, 12345)
        let reads = await functions.readCount
        let writes = await functions.writes
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(writes.isEmpty)
    }

    func testMalformedReturnLaneRetainsLastGoodButHidesCodesAndUpdatesSettlement() async throws {
        let functions = RecoveryFunctions(feed: feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.setFeed(feedData(returns: "[{}]", settlements: "[\(settlementFixture(amount: "-250"))]"))
        await model.refreshV1Fulfilments()
        XCTAssertFalse(model.returnsCurrent)
        XCTAssertEqual(model.returnReceipts.count, 1)
        XCTAssertTrue(model.settlementsCurrent)
        XCTAssertEqual(model.settlements.first?.amountPaise, -250)
        XCTAssertTrue(model.fulfilmentsCurrent)
        XCTAssertTrue(model.recoveryCurrent)
        XCTAssertEqual(model.orderRefreshFailures, ["Return receipts"])
        XCTAssertNil(DastakMerchantReceiptPresentation.returnCode(try XCTUnwrap(model.returnReceipts.first),
            current: model.returnsCurrent, refreshedAt: .now, physicallyConfirmed: true, now: .now))
    }

    func testMalformedSettlementIsNotZeroAndDoesNotLoseOtherLanes() async {
        let functions = RecoveryFunctions(feed: feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.setFeed(feedData(settlements: "[{}]"))
        await model.refreshV1Fulfilments()
        XCTAssertTrue(model.returnsCurrent)
        XCTAssertTrue(model.returnReceipts.isEmpty)
        XCTAssertFalse(model.settlementsCurrent)
        XCTAssertEqual(model.settlements.first?.amountPaise, 12345)
        XCTAssertEqual(model.orderRefreshFailures, ["Settlement status"])
    }

    func testMissingFinancialLanesUnknownButValidEmptyLanesClearHistory() async {
        let functions = RecoveryFunctions(feed: feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.setFeed(Data("{\"fulfilments\":[],\"recoveryOpportunities\":[]}".utf8))
        await model.refreshV1Fulfilments()
        XCTAssertFalse(model.returnsCurrent)
        XCTAssertFalse(model.settlementsCurrent)
        XCTAssertEqual(model.returnReceipts.count, 1)
        XCTAssertEqual(model.settlements.count, 1)
        await functions.setFeed(feedData())
        await model.refreshV1Fulfilments()
        XCTAssertTrue(model.returnReceipts.isEmpty)
        XCTAssertTrue(model.settlements.isEmpty)
        XCTAssertTrue(model.orderRefreshFailures.isEmpty)
    }

    func testTransportFailureRetainsBothFeedsWithIndependentWarnings() async {
        let functions = RecoveryFunctions(feed: feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]"))
        let model = makeModel(functions)
        await model.refreshV1Fulfilments()
        await functions.failNextRead()
        await model.refreshV1Fulfilments()
        XCTAssertFalse(model.returnsCurrent)
        XCTAssertFalse(model.settlementsCurrent)
        XCTAssertEqual(model.returnReceipts.count, 1)
        XCTAssertEqual(model.settlements.count, 1)
        XCTAssertTrue(model.orderRefreshFailures.contains("Return receipts"))
        XCTAssertTrue(model.orderRefreshFailures.contains("Settlement status"))
    }

    func testOlderResponseCannotRestoreConsumedReturnCodeOrSettlementAmount() async {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await functions.holdNextRead()
        let oldRead = Task { await model.refreshV1Fulfilments() }
        await functions.waitUntilHeld()
        await functions.setFeed(feedData(returns: "[\(returnFixture(status: "COMPLETED", verification: "CONSUMED", completed: "\"2026-10-11T01:00:00Z\""))]",
            settlements: "[\(settlementFixture(amount: "-150"))]"))
        await model.refreshV1Fulfilments()
        await functions.release(.data(feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]")))
        await oldRead.value
        XCTAssertEqual(model.returnReceipts.first?.verificationStatus, "CONSUMED")
        XCTAssertEqual(model.settlements.first?.amountPaise, -150)
        XCTAssertTrue(model.orderRefreshFailures.isEmpty)
    }

    func testLatestFailureCannotBeClearedByOldSuccessfulFinancialRead() async {
        let functions = RecoveryFunctions()
        let model = makeModel(functions)
        await functions.holdNextRead()
        let oldRead = Task { await model.refreshV1Fulfilments() }
        await functions.waitUntilHeld()
        await functions.failNextRead()
        await model.refreshV1Fulfilments()
        await functions.release(.data(feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture())]")))
        await oldRead.value
        XCTAssertFalse(model.returnsCurrent)
        XCTAssertFalse(model.settlementsCurrent)
        XCTAssertTrue(model.returnReceipts.isEmpty)
        XCTAssertTrue(model.orderRefreshFailures.contains("Return receipts"))
        XCTAssertTrue(model.orderRefreshFailures.contains("Settlement status"))
    }

    func testReturnCodeRequiresArrivalActiveVerificationPhysicalCheckAndRecentRead() throws {
        let receipt = try JSONDecoder().decode(DastakV1MerchantReturnReceipt.self, from: Data(returnFixture().utf8))
        let now = Date()
        XCTAssertEqual(DastakMerchantReceiptPresentation.returnCode(receipt, current: true,
            refreshedAt: now, physicallyConfirmed: true, now: now), "123456")
        for (fresh, age, confirmed) in [(false, 0.0, true), (true, 0, false), (true, 60, true), (true, -1, true)] {
            XCTAssertNil(DastakMerchantReceiptPresentation.returnCode(receipt, current: fresh,
                refreshedAt: now.addingTimeInterval(-age), physicallyConfirmed: confirmed, now: now))
        }
        XCTAssertNil(DastakMerchantReceiptPresentation.returnCode(receipt, current: true,
            refreshedAt: nil, physicallyConfirmed: true, now: now))
    }

    func testReturnCodeFailsClosedForIncompleteOrFinishedCustody() throws {
        for fixture in [returnFixture(status: "PENDING"), returnFixture(status: "COMPLETED"),
            returnFixture(verification: "CONSUMED"), returnFixture(verification: "BLOCKED"),
            returnFixture(verification: "INACTIVE"), returnFixture(verification: "OVERRIDDEN"),
            returnFixture(verification: "FUTURE_STATUS"), returnFixture(arrived: "null"),
            returnFixture(arrived: "\"invalid\""), returnFixture(completed: "\"2026-10-11T01:00:00Z\""),
            returnFixture(code: "null"), returnFixture(code: "\"  \""), returnFixture(packages: 0)] {
            let receipt = try JSONDecoder().decode(DastakV1MerchantReturnReceipt.self, from: Data(fixture.utf8))
            let now = Date()
            XCTAssertNil(DastakMerchantReceiptPresentation.returnCode(receipt, current: true,
                refreshedAt: now, physicallyConfirmed: true, now: now))
        }
    }

    func testSettlementFormattingDistinguishesUnknownZeroAndDebit() throws {
        func amount(_ value: String, calculation: String = "CALCULATED", currency: String = "INR") throws -> String {
            let entry = try JSONDecoder().decode(DastakV1MerchantSettlement.self,
                from: Data(settlementFixture(amount: value, calculation: calculation, currency: currency).utf8))
            return DastakMerchantReceiptPresentation.amount(entry)
        }
        XCTAssertEqual(try amount("null"), "Amount not calculated")
        XCTAssertEqual(try amount("100", calculation: "SYSTEM_CONFIGURATION_REQUIRED"), "Amount not calculated")
        XCTAssertEqual(try amount("100", calculation: "FUTURE_STATUS"), "Amount not calculated")
        XCTAssertTrue(try amount("0").contains("0.00"))
        XCTAssertTrue(try amount("-250").contains("-"))
        XCTAssertTrue(try amount("-250").contains("2.50"))
        XCTAssertEqual(try amount("100", currency: "USD"), "Amount unavailable · Unsupported currency")
    }

    func testReturnAndSettlementDecoderIsolatesDuplicatesAndInvalidPackages() throws {
        for returns in ["[\(returnFixture()),\(returnFixture())]", "[\(returnFixture(packages: -1))]"] {
            let feeds = try JSONDecoder().decode(DastakV1MerchantRecoveryFeeds.self,
                from: feedData(returns: returns, settlements: "[\(settlementFixture())]"))
            XCTAssertNil(feeds.returnReceipts)
            XCTAssertEqual(feeds.settlements?.count, 1)
            XCTAssertNotNil(feeds.fulfilments)
        }
        let feeds = try JSONDecoder().decode(DastakV1MerchantRecoveryFeeds.self,
            from: feedData(returns: "[\(returnFixture())]", settlements: "[\(settlementFixture()),\(settlementFixture())]"))
        XCTAssertNil(feeds.settlements)
        XCTAssertNotNil(feeds.returnReceipts)
    }

    func testSettlementNullableFulfilmentAndCalculationDoNotDropValidEntry() throws {
        let feeds = try JSONDecoder().decode(DastakV1MerchantRecoveryFeeds.self,
            from: feedData(settlements: "[\(settlementFixture(amount: "null", calculation: "SYSTEM_CONFIGURATION_REQUIRED"))]"))
        let entry = try XCTUnwrap(feeds.settlements?.first)
        XCTAssertNil(entry.fulfilmentId)
        XCTAssertNil(entry.amountPaise)
        XCTAssertNil(entry.eligibleAt)
        XCTAssertNil(entry.settledAt)
    }

    func testRecoverySavedBeforeRPCAndRelaunchKeepsExpiredOriginalOffer() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore(); let accountID = UUID()
        let model = makeModel(functions, storage: store, accountID: accountID)
        await model.refreshV1Fulfilments(); await functions.holdNextWrite()
        let offer = try XCTUnwrap(model.recoveryOpportunities.first)
        let attempt = Task { await model.respondToRecovery(offer, accept: true, prepMinutes: 15, physicallyConfirmed: true) }
        await functions.waitUntilHeld()
        let onDisk = try await store.load(accountID)
        XCTAssertEqual(onDisk?.attempts, 1, "Attempt must be durable while the original RPC is still in flight")
        XCTAssertEqual(onDisk, model.merchantJournal)
        await functions.release(.timeout); _ = await attempt.value
        await functions.setFeed(feedData(offers: "[\(offerFixture(status: "CLOSED", expiry: "2000-01-01T00:00:00Z"))]"))
        let restored = makeModel(functions, storage: store, accountID: accountID)
        await restored.refreshV1Fulfilments()
        XCTAssertNotNil(restored.pendingRecoveryCommand)
        let replacement = await restored.respondToRecovery(offer, accept: false, prepMinutes: 0, physicallyConfirmed: false)
        XCTAssertFalse(replacement)
        await functions.enqueue(.data(responseReceipt()))
        let completed = await restored.retryRecoveryCommand(); XCTAssertTrue(completed)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].body, writes[1].body); XCTAssertEqual(writes[0].key, writes[1].key)
        let cleared = try await store.load(accountID); XCTAssertNil(cleared)
    }
    func testProblemJournalOmitsPickupPINAndTracking() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore()
        let model = makeModel(functions, storage: store)
        await model.refreshV1Fulfilments()
        await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: nil, reason: "Packaging issue")
        let serialized = try JSONEncoder().encode(XCTUnwrap(model.merchantJournal))
        let text = try XCTUnwrap(String(data: serialized, encoding: .utf8))
        XCTAssertFalse(text.contains("pickupCode")); XCTAssertFalse(text.contains("tracking")); XCTAssertFalse(text.contains("customerDestination"))
        XCTAssertTrue(text.contains("Packaging issue"))
    }
    func testRecoveryStorageFailurePreventsReportWrite() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore()
        let model = makeModel(functions, storage: store); await model.refreshV1Fulfilments(); await store.failSave()
        let saved = await model.reportRecoveryProblem(try XCTUnwrap(model.v1Fulfilments.first), lineID: recoveryLine, reason: "No exact item")
        XCTAssertFalse(saved); let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
        XCTAssertFalse(model.merchantJournalRestored); XCTAssertTrue(model.isBusy)
    }
    func testRecoveryAcknowledgementCleanupDoesNotRepeatReport() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore(); let accountID = UUID()
        let model = makeModel(functions, storage: store, accountID: accountID)
        await model.refreshV1Fulfilments(); await store.failRemoval(); await functions.enqueue(.data(responseReceipt()))
        await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: true, prepMinutes: 15, physicallyConfirmed: true)
        XCTAssertTrue(model.merchantJournal?.acknowledged == true)
        let restored = makeModel(functions, storage: store, accountID: accountID); await restored.restoreMerchantCommands()
        let completed = await restored.retryRecoveryCommand(); XCTAssertTrue(completed)
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
        XCTAssertNil(restored.merchantJournal); XCTAssertFalse(restored.isBusy)
    }
    func testLaterPermissionRejectionDoesNotDiscardUncertainRecovery() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore()
        let model = makeModel(functions, storage: store); await model.refreshV1Fulfilments()
        await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: true, prepMinutes: 15, physicallyConfirmed: true)
        await functions.enqueue(.api(403)); await model.retryRecoveryCommand()
        XCTAssertNotNil(model.merchantJournal); XCTAssertEqual(model.merchantJournal?.attempts, 2)
        XCTAssertNotNil(model.pendingRecoveryCommand)
    }
    func testSupersededRecoveryFileDoesNotSendOldRequest() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore(); let accountID = UUID()
        let model = makeModel(functions, storage: store, accountID: accountID); await model.refreshV1Fulfilments()
        await model.respondToRecovery(try XCTUnwrap(model.recoveryOpportunities.first), accept: true, prepMinutes: 15, physicallyConfirmed: true)
        let saved = try XCTUnwrap(model.merchantJournal); var changed = saved; changed.revision = UUID()
        try await store.replace(changed, accountID: accountID, expectedRevision: saved.revision)
        await model.retryRecoveryCommand()
        let writes = await functions.writes; XCTAssertEqual(writes.count, 1)
    }
    func testRestoreFailureHoldsRecoveryAndNormalPreparation() async throws {
        let functions = RecoveryFunctions(); let store = MerchantJournalTestStore(); await store.failLoad()
        let model = makeModel(functions, storage: store); await model.refreshV1Fulfilments()
        XCTAssertFalse(model.merchantJournalRestored); XCTAssertTrue(model.isBusy)
        await model.markV1Ready(try XCTUnwrap(model.v1Fulfilments.first))
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }
    private func makeModel(_ functions: RecoveryFunctions, storage: any DastakMerchantJournalStorage = DastakMerchantMemoryJournal(), accountID: UUID = UUID()) -> DastakMerchantModel {
        return DastakMerchantModel(services: MarketplaceAuthenticatedServices(functions: functions,
            accountIDProvider: { accountID }, objectUploader: { _, _, _, _, _ in }), journalStorage: storage)
    }
    private func firstBody(_ functions: RecoveryFunctions) async throws -> [String: Any] {
        let writes = await functions.writes
        return try object(XCTUnwrap(writes.first).body)
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor RecoveryFunctions: FunctionClient {
    enum Reply: Sendable { case data(Data), timeout, api(Int) }
    struct Call: Sendable { let key: String; let body: Data }
    var writes: [Call] = []
    var readCount = 0
    private var feed: Data
    private var replies: [Reply] = []
    private var readFails = false
    private var shouldHold = false
    private var shouldHoldRead = false
    private var held: CheckedContinuation<Reply, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(feed: Data = feedData()) { self.feed = feed }
    func setFeed(_ data: Data) { feed = data }
    func enqueue(_ reply: Reply) { replies.append(reply) }
    func failNextRead() { readFails = true }
    func holdNextWrite() { shouldHold = true }
    func holdNextRead() { shouldHoldRead = true }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release(_ reply: Reply) { held?.resume(returning: reply); held = nil }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let reply: Reply
        if object?["operation"] as? String == "merchantFulfilments" {
            readCount += 1
            if shouldHoldRead {
                shouldHoldRead = false
                reply = await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
            } else { reply = readFails ? .timeout : .data(feed); readFails = false }
        } else {
            writes.append(Call(key: idempotencyKey.rawValue, body: body))
            if shouldHold {
                shouldHold = false
                reply = await withCheckedContinuation { held = $0; waiter?.resume(); waiter = nil }
            } else { reply = replies.isEmpty ? .timeout : replies.removeFirst() }
        }
        switch reply {
        case let .data(data): return try JSONDecoder().decode(Response.self, from: data)
        case .timeout: throw URLError(.timedOut)
        case let .api(status): throw FunctionClientError.api(statusCode: status, code: "stale_version", message: "Order changed. Review current details.")
        }
    }
}

private let recoveryBranch = UUID(uuidString: "94000000-0000-4000-8000-000000000001")!
private let recoveryOffer = UUID(uuidString: "94000000-0000-4000-8000-000000000002")!
private let recoveryCase = UUID(uuidString: "94000000-0000-4000-8000-000000000003")!
private let recoveryOrder = UUID(uuidString: "94000000-0000-4000-8000-000000000004")!
private let recoveryLine = UUID(uuidString: "94000000-0000-4000-8000-000000000005")!
private let recoverySKU = UUID(uuidString: "94000000-0000-4000-8000-000000000006")!
private let recoveryFulfilment = UUID(uuidString: "94000000-0000-4000-8000-000000000007")!

private func offerFixture(status: String = "OFFERED", expiry: String = "2099-01-01T00:00:00Z", quantity: Int = 3) -> String {
    """
    {"id":"\(recoveryOffer)","recoveryCaseId":"\(recoveryCase)","orderId":"\(recoveryOrder)","orderLineId":"\(recoveryLine)","status":"\(status)",
    "requestedQuantity":\(quantity),"startedAt":"2026-10-11T00:00:00Z","expiresAt":"\(expiry)","version":2,
    "branch":{"id":"\(recoveryBranch)","displayName":"Test store"},
    "sku":{"id":"\(recoverySKU)","name":"Milk","variantName":"Full cream","packSize":"500 ml"}}
    """
}
private func orderFixture(version: Int = 3, status: String = "PREPARING", capability: Bool = true,
    packages: String = "null", reports: String = "[]") -> String {
    """
    {"id":"\(recoveryFulfilment)","orderId":"\(recoveryOrder)","displayOrderNumber":"DSK-TEST-001","orderStatus":"PREPARING","status":"\(status)","version":\(version),
    "branch":{"id":"\(recoveryBranch)","displayName":"Test store"},"promisedPrepMinutes":15,"secondsRemaining":120,"runningLate":false,"packageCount":\(packages),
    "evidence":[],"canDeclarePackages":true,"canAddEvidence":true,"canMarkReady":true,"canReportExactSkuFailure":\(capability),"problemReports":\(reports),"recoveryCases":[],
    "lines":[{"orderLineId":"\(recoveryLine)","name":"Milk","quantity":3,"packSize":"500 ml"}]}
    """
}
private func feedData(order: String = orderFixture(), offers: String = "[\(offerFixture())]",
    returns: String = "[]", settlements: String = "[]") -> Data {
    Data("{\"fulfilments\":[\(order)],\"recoveryOpportunities\":\(offers),\"returnReceipts\":\(returns),\"settlements\":\(settlements)}".utf8)
}
private let recoveryStop = UUID(uuidString: "94000000-0000-4000-8000-000000000008")!
private func returnFixture(status: String = "ARRIVED", verification: String = "ACTIVE", packages: Int = 2,
    arrived: String = "\"2026-10-11T00:00:00Z\"", completed: String = "null", code: String = "\"123456\"") -> String {
    """
    {"returnId":"\(recoveryCase)","returnMissionId":"\(recoveryOffer)","returnStopId":"\(recoveryStop)","orderId":"\(recoveryOrder)",
    "status":"\(status)","packageCount":\(packages),"verificationStatus":"\(verification)","receiptCode":\(code),
    "arrivedAt":\(arrived),"completedAt":\(completed),"branch":{"id":"\(recoveryBranch)","displayName":"Test store"}}
    """
}
private func settlementFixture(amount: String = "12345", calculation: String = "CALCULATED", currency: String = "INR") -> String {
    let entryType = amount.hasPrefix("-") ? "DEBIT_ADJUSTMENT" : "EARNING"
    return
    """
    {"id":"\(recoveryLine)","orderId":"\(recoveryOrder)","fulfilmentId":null,"entryType":"\(entryType)","status":"PENDING",
    "calculationStatus":"\(calculation)","amountPaise":\(amount),"currency":"\(currency)","eligibleAt":null,"settledAt":null}
    """
}
private func responseReceipt(accept: Bool = true, quantity: Int = 3, payment: Int = 0, offer: UUID = recoveryOffer) -> Data {
    let extra = accept ? ",\"replacementFulfilmentId\":\"\(UUID())\",\"exactSkuId\":\"\(recoverySKU)\",\"quantity\":\(quantity),\"additionalCustomerPaymentPaise\":\(payment)" : ""
    return Data("{\"recoveryOpportunityId\":\"\(offer)\",\"recoveryCaseId\":\"\(recoveryCase)\",\"status\":\"\(accept ? "RECOVERED" : "DECLINED")\"\(extra)}".utf8)
}
private func exactReceipt() -> Data {
    Data("{\"recoveryCaseId\":\"\(recoveryCase)\",\"orderId\":\"\(recoveryOrder)\",\"orderLineId\":\"\(recoveryLine)\",\"status\":\"SEARCHING_EXACT_SKU\",\"exactSkuId\":\"\(recoverySKU)\",\"quantity\":3,\"customerPaymentChanged\":false}".utf8)
}
