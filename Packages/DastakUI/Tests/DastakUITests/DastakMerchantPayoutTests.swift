import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor final class DastakMerchantPayoutTests: XCTestCase {
    private func model(_ functions:PayoutFunctions,storage:any DastakMerchantPayoutStorage = DastakMerchantMemoryPayoutStore(),
        identity:MerchantJournalTestIdentity? = nil,timeout:Duration = .seconds(1)) -> DastakMerchantEarningsModel {
        .init(services:.init(functions:functions,accountIDProvider:{if let identity {return await identity.id};return payoutID(90)},objectUploader:{_,_,_,_,_ in}),timeout:timeout,storage:storage)
    }
    func testAmountParserDoesNotRoundOverflowsOrAcceptJunk() {
        XCTAssertEqual(DastakMerchantPayoutAmount.paise("12.50"),1250)
        XCTAssertEqual(DastakMerchantPayoutAmount.paise("0.01"),1)
        for bad in ["0","-1","NaN","1e3","1.001","1.000","₹5","1,000","90071992547409.92",""] {XCTAssertNil(DastakMerchantPayoutAmount.paise(bad),bad)}
    }
    func testDestinationValidationMatchesBackendAndOnlySummaryIsDisplayed() throws {
        let bank = DastakMerchantDestinationRequest(organization:payoutID(1),holder:"  Test   Store ",account:"1234 567890",confirmation:"1234567890",ifsc:"hdfc0001234")
        XCTAssertTrue(bank.valid);XCTAssertEqual(bank.holderName,"Test Store");XCTAssertEqual(bank.maskedLabel,"Bank account •••• 7890")
        XCTAssertFalse(DastakMerchantDestinationRequest(organization:payoutID(1),holder:"AB",vpa:"me@bank").valid)
        XCTAssertFalse(DastakMerchantDestinationRequest(organization:payoutID(1),holder:"Test Store-",vpa:"me@bank").valid)
        XCTAssertFalse(DastakMerchantDestinationRequest(organization:payoutID(1),holder:"Test Store",account:"123456",confirmation:"654321",ifsc:"BAD").valid)
        let upi = DastakMerchantDestinationRequest(organization:payoutID(1),holder:"Test Store",vpa:"ME@BANK")
        XCTAssertTrue(upi.valid);XCTAssertEqual(upi.maskedLabel,"UPI • m*@bank")
        let command = DastakMerchantPayoutCommand(accountID:payoutID(90),organizationID:payoutID(1),key:payoutKey(),operation:.destination(bank))
        XCTAssertFalse(command.summary.contains("1234567890"));XCTAssertFalse(command.summary.contains("Test Store"))
        let encoded = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(DastakMerchantPayoutCommand.self,from:encoded),command)
    }
    func testReadOnlyRefreshNeverReplaysSavedFinancialCommand() async throws {
        let functions=PayoutFunctions(),storage=DastakMerchantMemoryPayoutStore()
        let command=DastakMerchantPayoutCommand(accountID:payoutID(90),organizationID:payoutID(1),key:payoutKey(),operation:.withdraw(amount:100,destination:payoutID(20),destinationVersion:1))
        try await storage.replace(command,account:payoutID(90),expectedRevision:nil)
        let merchant=model(functions,storage:storage);await merchant.load();await merchant.load()
        XCTAssertEqual(merchant.pending,command);XCTAssertTrue(merchant.blocksFinancialActions)
        let calls=await functions.mutations;XCTAssertTrue(calls.isEmpty)
    }
    func testLegacyReadFallbackIsReadOnlyAndCannotEnableFinancialControls() async throws {
        let functions=PayoutFunctions();await functions.legacy()
        let merchant=model(functions);await merchant.load()
        XCTAssertTrue(merchant.current);XCTAssertFalse(merchant.canManage(payoutID(1)))
        let subject=try XCTUnwrap(merchant.snapshot?.subjects.first)
        let sent=await merchant.withdraw(subject:subject,amount:100);XCTAssertFalse(sent)
        let calls=await functions.mutations;XCTAssertTrue(calls.isEmpty)
    }
    func testPermissionAvailabilityAndBalanceGateEachOrganization() async throws {
        let functions=PayoutFunctions(),merchant=model(functions);await merchant.load()
        let subject=try XCTUnwrap(merchant.snapshot?.subjects.first)
        XCTAssertTrue(merchant.canWithdraw(subject,amount:100))
        XCTAssertFalse(merchant.canWithdraw(subject,amount:subject.availablePaise+1))
        XCTAssertFalse(merchant.canManage(payoutID(2)))
        await functions.configure(permission:false);await merchant.load();XCTAssertFalse(merchant.canManage(payoutID(1)))
        await functions.configure(permission:true,available:false);await merchant.load()
        let latest=try XCTUnwrap(merchant.snapshot?.subjects.first);XCTAssertFalse(merchant.canWithdraw(latest,amount:100))
        let calls=await functions.mutations;XCTAssertTrue(calls.isEmpty)
    }
    func testWithdrawalIsMerchantScopedBoundToReviewedDestinationAndDurablyAcknowledged() async throws {
        let functions=PayoutFunctions(),storage=DastakMerchantMemoryPayoutStore(),merchant=model(functions,storage:storage)
        await merchant.load();let subject=try XCTUnwrap(merchant.snapshot?.subjects.first)
        let result=await merchant.withdraw(subject:subject,amount:1234)
        XCTAssertTrue(result);XCTAssertNil(merchant.pending)
        let saved=try await storage.load(payoutID(90));XCTAssertNil(saved)
        let calls=await functions.mutations;XCTAssertEqual(calls.count,1)
        let body=try calls[0].object()
        XCTAssertEqual(body["operation"] as? String,"requestMerchantRoyaltyWithdrawal")
        XCTAssertEqual(body["subjectType"] as? String,"MERCHANT_ORGANIZATION")
        XCTAssertEqual(body["subjectId"] as? String,payoutID(1).uuidString)
        XCTAssertEqual(body["destinationId"] as? String,payoutID(20).uuidString)
        XCTAssertEqual(body["destinationVersion"] as? Int,1);XCTAssertNil(body["accountId"])
    }
    func testStaleReviewCannotWithdrawAfterDestinationChanges() async throws {
        let functions=PayoutFunctions(),merchant=model(functions);await merchant.load()
        let reviewed=try XCTUnwrap(merchant.snapshot?.subjects.first)
        await functions.changeDestination();await merchant.load()
        let result=await merchant.withdraw(subject:reviewed,amount:100);XCTAssertFalse(result)
        let calls=await functions.mutations;XCTAssertTrue(calls.isEmpty)
    }
    func testLostWithdrawalResponseRestoresAndReplaysOnlyOriginalKeyAmountAndDestination() async throws {
        let functions=PayoutFunctions(),storage=DastakMerchantMemoryPayoutStore(),first=model(functions,storage:storage)
        await first.load();await functions.mode(.loseAcknowledgement)
        let result=await first.withdraw(subject:try XCTUnwrap(first.snapshot?.subjects.first),amount:1000);XCTAssertFalse(result)
        let original=try XCTUnwrap(first.pending)
        await functions.changeDestination()
        let second=model(functions,storage:storage);await second.load();XCTAssertEqual(second.pending,original)
        let recovered=await second.recover();XCTAssertTrue(recovered);XCTAssertNil(second.pending)
        let calls=await functions.mutations,applied=await functions.applied
        XCTAssertEqual(calls.count,2);XCTAssertEqual(applied,1);XCTAssertEqual(calls[0].body,calls[1].body);XCTAssertEqual(calls[0].key,calls[1].key)
    }
    func testRecordedRetryVersionAdvanceResolvesWithoutAnotherSubmission() async throws {
        let functions=PayoutFunctions(),storage=DastakMerchantMemoryPayoutStore(),first=model(functions,storage:storage)
        await first.load();await functions.mode(.loseAcknowledgement)
        let withdrawal=try XCTUnwrap(first.snapshot?.subjects.first?.withdrawals.first)
        let result=await first.retry(withdrawal,organization:payoutID(1));XCTAssertFalse(result);XCTAssertNotNil(first.pending)
        let second=model(functions,storage:storage);await second.load()
        let recovered=await second.recover();XCTAssertTrue(recovered);XCTAssertNil(second.pending)
        let calls=await functions.mutations;XCTAssertEqual(calls.count,1)
    }
    func testFirstDefinitiveRejectionReleasesButUncertainLaterRejectionDoesNot() async throws {
        let functions=PayoutFunctions(),merchant=model(functions);await merchant.load();await functions.mode(.rejected)
        let result=await merchant.withdraw(subject:try XCTUnwrap(merchant.snapshot?.subjects.first),amount:100);XCTAssertFalse(result);XCTAssertNil(merchant.pending)
        await functions.mode(.offline)
        _=await merchant.withdraw(subject:try XCTUnwrap(merchant.snapshot?.subjects.first),amount:100)
        XCTAssertNotNil(merchant.pending)
        await functions.mode(.rejected);_=await merchant.recover();XCTAssertNotNil(merchant.pending)
    }
    func testSecureStorageFailureBlocksWritesButDoesNotBlockLedgerReads() async throws {
        let functions=PayoutFunctions(),storage=PayoutFaultStore();await storage.failReads()
        let merchant=model(functions,storage:storage);await merchant.load()
        XCTAssertTrue(merchant.current);XCTAssertFalse(merchant.restored);XCTAssertTrue(merchant.blocksFinancialActions)
        let result=await merchant.withdraw(subject:try XCTUnwrap(merchant.snapshot?.subjects.first),amount:100);XCTAssertFalse(result)
        let calls=await functions.mutations;XCTAssertTrue(calls.isEmpty)
    }
    func testFailedSecureWriteNeverSendsFinancialRequest() async throws {
        let functions=PayoutFunctions(),storage=PayoutFaultStore(),merchant=model(functions,storage:storage)
        await merchant.load();await storage.failWrites()
        _=await merchant.withdraw(subject:try XCTUnwrap(merchant.snapshot?.subjects.first),amount:100)
        let calls=await functions.mutations;XCTAssertTrue(calls.isEmpty)
    }
    func testAcknowledgedCleanupFailureNeverRepeatsFinancialSubmission() async throws {
        let functions=PayoutFunctions(),storage=PayoutFaultStore(),first=model(functions,storage:storage)
        await first.load();await storage.failDeletion()
        let result=await first.withdraw(subject:try XCTUnwrap(first.snapshot?.subjects.first),amount:100);XCTAssertFalse(result)
        XCTAssertEqual(first.pending?.acknowledged,true)
        let second=model(functions,storage:storage);await second.load()
        let recovered=await second.recover();XCTAssertTrue(recovered);XCTAssertNil(second.pending)
        let calls=await functions.mutations;XCTAssertEqual(calls.count,1)
    }
    func testDestinationIsExplicitMerchantSubmissionAndUsesOriginalProtectedDetailsOnRecovery() async throws {
        let functions=PayoutFunctions(),storage=DastakMerchantMemoryPayoutStore(),first=model(functions,storage:storage)
        await first.load();await functions.mode(.offline)
        let request=DastakMerchantDestinationRequest(organization:payoutID(1),holder:"Test Store",account:"1234567890",confirmation:"1234567890",ifsc:"HDFC0001234")
        let result=await first.register(request,reviewed:first.snapshot?.subjects.first?.payoutDestination);XCTAssertFalse(result)
        XCTAssertTrue(first.pending?.summary.contains("7890")==true);XCTAssertFalse(first.pending?.summary.contains("1234567890")==true)
        let second=model(functions,storage:storage);await second.load()
        let recovered=await second.recover();XCTAssertTrue(recovered)
        let calls=await functions.mutations
        XCTAssertEqual(calls.count,2);XCTAssertEqual(calls[0].body,calls[1].body);XCTAssertEqual(calls[0].key,calls[1].key)
        XCTAssertEqual(try calls[0].object()["subjectType"] as? String,"MERCHANT_ORGANIZATION")
    }
    func testWrongReplyRetainsJournalInsteadOfClaimingPaymentSuccess() async throws {
        let functions=PayoutFunctions(),merchant=model(functions);await merchant.load();await functions.mode(.wrongReply)
        let result=await merchant.withdraw(subject:try XCTUnwrap(merchant.snapshot?.subjects.first),amount:100)
        XCTAssertFalse(result);XCTAssertNotNil(merchant.pending);XCTAssertFalse(merchant.busy)
    }
    func testUncooperativeWriteReleasesBusyAndLateResultCannotEraseRecovery() async throws {
        let functions=PayoutFunctions(),merchant=model(functions,timeout:.milliseconds(50));await merchant.load()
        await functions.holdNext()
        let subject=try XCTUnwrap(merchant.snapshot?.subjects.first)
        let action=Task {await merchant.withdraw(subject:subject,amount:100)}
        await functions.wait();_=await action.value
        XCTAssertFalse(merchant.busy);XCTAssertNotNil(merchant.pending)
        await functions.release();await Task.yield();XCTAssertNotNil(merchant.pending)
    }
    func testAccountChangeDuringFinancialResponseClearsPresentationNotOriginalSecureRecord() async throws {
        let functions=PayoutFunctions(),storage=DastakMerchantMemoryPayoutStore(),identity=MerchantJournalTestIdentity()
        let original=await identity.id,merchant=model(functions,storage:storage,identity:identity)
        await merchant.load();await functions.holdNext()
        let subject=try XCTUnwrap(merchant.snapshot?.subjects.first)
        let action=Task {await merchant.withdraw(subject:subject,amount:100)}
        await functions.wait();await identity.change();await functions.release();_=await action.value
        XCTAssertNil(merchant.snapshot);XCTAssertNil(merchant.pending)
        let saved=try await storage.load(original);XCTAssertNotNil(saved)
        let replacement=await merchant.withdraw(subject:subject,amount:100);XCTAssertFalse(replacement)
    }
}

private func payoutID(_ number:Int)->UUID {UUID(uuidString:String(format:"97000000-0000-4000-8000-%012d",number))!}
private func payoutKey()->IdempotencyKey {IdempotencyKey(rawValue:UUID().uuidString)!}
private actor PayoutFaultStore:DastakMerchantPayoutStorage {
    var value:DastakMerchantPayoutCommand?
    private var readFailure=false,writeFailure=false,deleteFailure=false
    func failReads(){readFailure=true};func failWrites(){writeFailure=true};func failDeletion(){deleteFailure=true}
    func load(_ account:UUID)throws->DastakMerchantPayoutCommand? {if readFailure {throw DastakAdminExecutionError.invalid};return value}
    func replace(_ command:DastakMerchantPayoutCommand?,account:UUID,expectedRevision:UUID?)throws {
        guard !writeFailure,value?.revision==expectedRevision else {throw DastakAdminExecutionError.changed}
        if command == nil && deleteFailure {deleteFailure=false;throw DastakAdminExecutionError.changed};value=command
    }
}
private actor PayoutFunctions:FunctionClient {
    enum Mode {case normal,offline,rejected,loseAcknowledgement,wrongReply}
    struct Call:Sendable {let body:Data;let key:IdempotencyKey;func object()throws->[String:Any] {try JSONSerialization.jsonObject(with:body) as! [String:Any]}}
    var mutations:[Call]=[]
    private(set) var applied=0
    private var legacyMode=false,permission=true,available=true,balance=10_000,destinationID=payoutID(20),destinationType="UPI",destinationLabel="UPI • me***@bank"
    private var behavior:Mode = .normal,receipts:[String:Data]=[:],withdrawalVersion=1
    private var holding=false,continuation:CheckedContinuation<Void,Never>?,started:CheckedContinuation<Void,Never>?
    func legacy(){legacyMode=true};func configure(permission:Bool,available:Bool=true){self.permission=permission;self.available=available}
    func mode(_ value:Mode){behavior=value};func changeDestination(){destinationID=payoutID(21)}
    func holdNext(){holding=true};func wait()async {if continuation==nil {await withCheckedContinuation{started=$0}}};func release(){continuation?.resume();continuation=nil}
    private func snapshot()throws->Data {
        let withdrawal:[String:Any]=["id":payoutID(30).uuidString,"amountPaise":500,"currency":"INR","status":withdrawalVersion==1 ? "REQUESTED":"PROCESSING","reconciliationState":"PENDING","version":withdrawalVersion,"requestedAt":"2026-10-18T10:00:00Z"]
        var subject:[String:Any]=["subjectType":"MERCHANT_ORGANIZATION","subjectId":payoutID(1).uuidString,"currency":"INR","balancePaise":balance,"availablePaise":balance,"negativeBalancePaise":0,"lifetimeEarnedPaise":20_000,"canWithdraw":true,"canManagePayouts":permission,
          "payoutDestination":["id":destinationID.uuidString,"type":destinationType,"displayLabel":destinationLabel,"status":"ACTIVE","version":1],"entries":[] as [String],"adjustments":[] as [String],"withdrawals":[withdrawal]]
        var availability:[String:Any]=["destinationRegistrationAvailable":available,"withdrawalExecutionAvailable":available,"merchantControlsAvailable":true]
        if legacyMode {subject.removeValue(forKey:"canManagePayouts");availability.removeValue(forKey:"merchantControlsAvailable")}
        return try JSONSerialization.data(withJSONObject:["currency":"INR","balancePaise":balance,"availablePaise":balance,"negativeBalancePaise":0,"lifetimeEarnedPaise":20_000,"subjects":[subject],"payoutAvailability":availability])
    }
    func invoke<Request:Encodable & Sendable,Response:Decodable & Sendable>(_ name:String,request:Request,idempotencyKey:IdempotencyKey)async throws->Response {
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let data=try encoder.encode(request),body=try JSONSerialization.jsonObject(with:data) as! [String:Any],operation=body["operation"] as! String
        if operation=="merchantRoyaltyControlsSnapshot" || operation=="merchantRoyaltySnapshot" {
            if legacyMode && operation=="merchantRoyaltyControlsSnapshot" {throw FunctionClientError.api(statusCode:400,code:"invalid_operation",message:"Old server")}
            return try JSONDecoder().decode(Response.self,from:snapshot())
        }
        mutations.append(.init(body:data,key:idempotencyKey))
        let mode=behavior;behavior = .normal
        if holding {holding=false;await withCheckedContinuation{continuation=$0;started?.resume();started=nil}}
        if mode == .offline {throw URLError(.notConnectedToInternet)}
        if mode == .rejected {throw FunctionClientError.api(statusCode:409,code:"rejected",message:"Rejected")}
        if let receipt=receipts[idempotencyKey.rawValue] {return try JSONDecoder().decode(Response.self,from:receipt)}
        let value:[String:Any]
        if operation=="requestMerchantRoyaltyWithdrawal" {
            let amount=body["amountPaise"] as! Int;balance-=amount
            value=["withdrawalId":payoutID(40).uuidString,"amountPaise":amount,"status":"PROCESSING"]
        } else if operation=="retryRoyaltyWithdrawal" {
            withdrawalVersion+=1;value=["withdrawalId":payoutID(30).uuidString,"status":"PROCESSING"]
        } else if operation=="registerRoyaltyPayoutDestination" {
            let parsed=try JSONDecoder().decode(DastakMerchantDestinationRequest.self,from:data)
            destinationID=payoutID(22);destinationType=parsed.destinationType;destinationLabel=parsed.maskedLabel
            value=["destinationId":destinationID.uuidString,"status":"ACTIVE","version":1,"type":destinationType,"displayLabel":destinationLabel]
        } else {throw FunctionClientError.invalidResponse}
        applied+=1;let receipt=try JSONSerialization.data(withJSONObject:value);receipts[idempotencyKey.rawValue]=receipt
        if mode == .loseAcknowledgement {throw URLError(.timedOut)}
        if mode == .wrongReply {return try JSONDecoder().decode(Response.self,from:JSONSerialization.data(withJSONObject:["withdrawalId":payoutID(99).uuidString,"amountPaise":-1,"status":"PAID"]))}
        return try JSONDecoder().decode(Response.self,from:receipt)
    }
}
