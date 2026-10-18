import Foundation
import XCTest
import MarketplaceFoundation
@testable import MarketplaceInfrastructure
@testable import DastakUI

@MainActor final class DastakMerchantMenuDraftTests: XCTestCase {
    func testCleanDraftAdoptsNewerServerFieldsWithoutRemounting() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.reconcile(try menu(version: 2, name: "Server tea", price: 2000))
        XCTAssertEqual(store.records[menuItem]?.value.name, "Server tea")
        XCTAssertEqual(store.records[menuItem]?.baseline.version, 2)
        XCTAssertEqual(store.records[menuItem]?.dirty, false)
        XCTAssertEqual(store.records[menuItem]?.stale, false)
    }
    func testDirtyDraftSurvivesIdenticalRefreshAndCanSaveWithOriginalVersion() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "My tea"); store.reconcile(try menu())
        XCTAssertEqual(store.records[menuItem]?.value.name, "My tea")
        XCTAssertEqual(store.records[menuItem]?.command(branchID: menuBranch)?.expectedVersion, 1)
        XCTAssertEqual(store.dirtyCount, 1)
    }
    func testNewServerVersionPreservesDirtyFieldsAndBlocksAllWrites() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Retained draft")
        store.reconcile(try menu(version: 2, name: "Remote name"))
        let draft = try XCTUnwrap(store.records[menuItem])
        XCTAssertEqual(draft.value.name, "Retained draft"); XCTAssertEqual(draft.latest?.fields.name, "Remote name")
        XCTAssertTrue(draft.stale); XCTAssertNil(draft.command(branchID: menuBranch))
        XCTAssertNil(draft.command(branchID: menuBranch, status: "INACTIVE"))
        XCTAssertEqual(draft.baseline.version, 1)
    }
    func testMediaOnlyChangeAlsoRequiresReviewAndDoesNotLoseText() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.description, "My description")
        store.reconcile(try menu(mediaVersion: 2, image: "photos/new.jpg"))
        XCTAssertTrue(try XCTUnwrap(store.records[menuItem]).stale)
        XCTAssertEqual(store.records[menuItem]?.value.description, "My description")
        XCTAssertNil(store.records[menuItem]?.command(branchID: menuBranch))
    }
    func testExplicitKeepRebasesOnlyAfterReviewAndKeepsLatestMetadata() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "My name")
        store.reconcile(try menu(version: 2, mediaVersion: 2, name: "Server name", image: "photos/new.jpg", tax: 500))
        let latest = try XCTUnwrap(store.records[menuItem]?.latest)
        XCTAssertTrue(store.resolve(menuItem, reviewed: latest, keepText: true))
        let command = try XCTUnwrap(store.records[menuItem]?.command(branchID: menuBranch))
        XCTAssertEqual(command.expectedVersion, 2)
        guard case let .item(category, name, _, image, _, tax, _, _) = command.payload else { return XCTFail() }
        XCTAssertEqual(category, menuCategory); XCTAssertEqual(name, "My name")
        XCTAssertEqual(image, "photos/new.jpg"); XCTAssertEqual(tax, 500)
    }
    func testUseLatestIsExplicitDiscardAndResetsDirtyState() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.price, "99")
        store.reconcile(try menu(version: 2, price: 1500))
        XCTAssertTrue(store.resolve(menuItem, reviewed: try XCTUnwrap(store.records[menuItem]?.latest), keepText: false))
        XCTAssertEqual(store.records[menuItem]?.value.price, "15")
        XCTAssertEqual(store.dirtyCount, 0)
    }
    func testReviewCannotSilentlyAdoptAnotherNewerVersion() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Draft")
        store.reconcile(try menu(version: 2)); let reviewed = try XCTUnwrap(store.records[menuItem]?.latest)
        store.reconcile(try menu(version: 3, name: "Changed again"))
        XCTAssertFalse(store.resolve(menuItem, reviewed: reviewed, keepText: true))
        XCTAssertTrue(try XCTUnwrap(store.records[menuItem]).stale)
    }
    func testOlderRefreshCannotRollbackLatestConflictOrCleanDraft() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Draft"); store.reconcile(try menu(version: 3, name: "Latest"))
        store.reconcile(try menu(version: 2, name: "Old"))
        XCTAssertEqual(store.records[menuItem]?.latest?.version, 3)
        store.useLatest(menuItem); store.reconcile(try menu())
        XCTAssertEqual(store.records[menuItem]?.value.name, "Latest")
    }
    func testAcknowledgementClearsOnlyMatchingSavedDraft() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Saved name")
        let submitted = try XCTUnwrap(store.records[menuItem]?.command(branchID: menuBranch))
        store.reconcile(try menu(version: 2, name: "Saved name"))
        store.acknowledge(entityID: menuItem, expectedVersion: submitted.expectedVersion, payload: submitted.payload)
        XCTAssertEqual(store.dirtyCount, 0); XCTAssertEqual(store.records[menuItem]?.baseline.version, 2)
    }
    func testAcknowledgementDoesNotEraseLaterLocalEdit() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Sent")
        let sent = try XCTUnwrap(store.records[menuItem]?.command(branchID: menuBranch))
        store.edit(menuItem, \.name, "Typed later"); store.reconcile(try menu(version: 2, name: "Sent"))
        store.acknowledge(entityID: menuItem, expectedVersion: sent.expectedVersion, payload: sent.payload)
        XCTAssertEqual(store.records[menuItem]?.value.name, "Typed later")
        XCTAssertTrue(try XCTUnwrap(store.records[menuItem]).stale)
    }
    func testMissingEntryRetainsCopyableDraftButCannotSave() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Keep this text"); store.reconcile(try menu(includeItem: false))
        XCTAssertEqual(store.unavailable.count, 1)
        XCTAssertNil(store.records[menuItem]?.command(branchID: menuBranch))
        store.discardUnavailable(menuItem); XCTAssertNil(store.records[menuItem])
    }
    func testBranchAndAccountContextResetCannotReuseDrafts() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuItem, \.name, "Private draft"); store.editAddition(menuGroup, .init(name: "Sauce"))
        store.reconcile(try menu(branch: UUID()))
        XCTAssertEqual(store.dirtyCount, 0); XCTAssertEqual(store.records[menuItem]?.value.name, "Tea")
        store.reconcile(nil); XCTAssertTrue(store.records.isEmpty); XCTAssertTrue(store.additions.isEmpty); XCTAssertNil(store.branchID)
    }
    func testSearchCoversCategoriesDescriptionsGroupsOptionsAndHiddenItems() throws {
        let categories = try menu().categories
        for query in ["hot drinks", "  TEA  ", "warming", "Milk choice", "Oat", "Hidden cake"] {
            XCTAssertEqual(DastakMerchantMenuSearch.categories(categories, query: query).count, 1, query)
            XCTAssertFalse(DastakMerchantMenuSearch.items(categories[0], query: query).isEmpty, query)
        }
        XCTAssertEqual(DastakMerchantMenuSearch.items(categories[0], query: "Hot drinks").count, 2)
        XCTAssertEqual(DastakMerchantMenuSearch.items(categories[0], query: "Oat").map(\.id), [menuItem])
        XCTAssertTrue(DastakMerchantMenuSearch.categories(categories, query: "No match").isEmpty)
    }
    func testFilteringAndRefreshingDoNotClearExistingOrNewEntryDrafts() throws {
        let store = DastakMerchantMenuDraftStore(); let snapshot = try menu(); store.reconcile(snapshot)
        store.edit(menuOption, \.name, "Oat milk edited"); store.editAddition(menuGroup, .init(name: "Cream", price: "5"))
        _ = DastakMerchantMenuSearch.categories(snapshot.categories, query: "No match")
        store.reconcile(snapshot)
        XCTAssertEqual(store.records[menuOption]?.value.name, "Oat milk edited")
        XCTAssertEqual(store.addition(menuGroup).name, "Cream")
        store.reconcile(try menu(includeItem: false)); XCTAssertEqual(store.unavailableAdditions.count, 1)
    }
    func testAvailabilityChangesDoNotImplicitlySaveDirtyNameOrPrice() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuOption, \.name, "Draft option")
        XCTAssertNil(store.records[menuOption]?.command(branchID: menuBranch, status: "INACTIVE"))
        store.useLatest(menuOption)
        let command = try XCTUnwrap(store.records[menuOption]?.command(branchID: menuBranch, status: "INACTIVE"))
        XCTAssertEqual(command.expectedVersion, 1)
        XCTAssertEqual(command.payload, .option(optionGroupID: menuGroup, name: "Oat", priceDeltaPaise: 0, sortOrder: 0, status: "INACTIVE"))
    }
    func testOptionEditsUseExactIDParentVersionAndZeroPrice() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuOption, \.price, "12.50")
        let command = try XCTUnwrap(store.records[menuOption]?.command(branchID: menuBranch))
        XCTAssertEqual(command.entityID, menuOption); XCTAssertEqual(command.branchID, menuBranch)
        XCTAssertEqual(command.payload, .option(optionGroupID: menuGroup, name: "Oat", priceDeltaPaise: 1250, sortOrder: 0, status: "ACTIVE"))
        store.edit(menuOption, \.price, "0"); XCTAssertNotNil(store.records[menuOption]?.command(branchID: menuBranch))
    }
    func testCustomMaximumIsNotHardcodedToTwentyAndSingleAlwaysUsesOne() {
        var draft = DastakMerchantMenuAddition(name: "Extras", selectionType: "MULTIPLE", maximum: "3")
        XCTAssertEqual(draft.maximumSelections, 3)
        draft.maximum = "25"; XCTAssertEqual(draft.maximumSelections, 25)
        draft.maximum = "2147483647"; XCTAssertEqual(draft.maximumSelections, Int(Int32.max))
        for invalid in ["0", "-1", "1.5", "", "abc", "2147483648"] { draft.maximum = invalid; XCTAssertNil(draft.maximumSelections, invalid) }
        draft.selectionType = "SINGLE"; XCTAssertEqual(draft.maximumSelections, 1)
    }
    func testPriceAndNameValidationExplainsAndBlocksInvalidInput() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        for invalid in ["-1", "0", "1.001", "1.000", "1e2", "12abc", "NaN", "₹5"] {
            store.edit(menuItem, \.price, invalid)
            XCTAssertNotNil(store.records[menuItem]?.validation, invalid)
            XCTAssertNil(store.records[menuItem]?.command(branchID: menuBranch), invalid)
        }
        store.useLatest(menuItem); store.edit(menuItem, \.name, " "); XCTAssertNotNil(store.records[menuItem]?.validation)
        store.useLatest(menuItem); store.edit(menuItem, \.description, String(repeating: "a", count: 1001)); XCTAssertNotNil(store.records[menuItem]?.validation)
        XCTAssertNil(DastakMerchantPriceParser.optionalNonnegativePaise(from: "5abc"))
        XCTAssertNil(DastakMerchantPriceParser.optionalNonnegativePaise(from: "1.000"))
    }
    func testAdditionAcknowledgementCannotEraseNewerTyping() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        let submitted = DastakMerchantMenuAddition(name: "Sent")
        store.editAddition(menuGroup, submitted); store.editAddition(menuGroup, .init(name: "Typed later"))
        store.clearAddition(menuGroup, submitted: submitted)
        XCTAssertEqual(store.addition(menuGroup).name, "Typed later")
    }
    func testRecoveredCreationClearsOnlyMatchingOriginalFormNotLaterTyping() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.editAddition(menuGroup, .init(name: "Cream", price: "5.00"))
        store.acknowledgeCreation(.option(optionGroupID: menuGroup, name: "Cream", priceDeltaPaise: 500, sortOrder: 0, status: "ACTIVE"))
        XCTAssertFalse(store.addition(menuGroup).dirty)
        store.editAddition(menuItem, .init(name: "Newer group", selectionType: "MULTIPLE", maximum: "3"))
        store.acknowledgeCreation(.optionGroup(menuItemID: menuItem, name: "Old group", selectionType: "MULTIPLE", minimumSelections: 0, maximumSelections: 3, sortOrder: 0, status: "ACTIVE"))
        XCTAssertEqual(store.addition(menuItem).name, "Newer group")
        store.acknowledgeCreation(.optionGroup(menuItemID: menuItem, name: "Newer group", selectionType: "MULTIPLE", minimumSelections: 0, maximumSelections: 3, sortOrder: 0, status: "ACTIVE"))
        XCTAssertFalse(store.addition(menuItem).dirty)
    }
    func testModelLoadsDraftsAndSavesAnExistingOptionThroughProtectedCommand() async throws {
        let functions = MenuEditFunctions(), model = model(functions)
        await model.refreshRestaurantMenu()
        model.menuDrafts.edit(menuOption, \.name, "Oat milk")
        model.menuDrafts.edit(menuOption, \.price, "12.50")
        let command = try XCTUnwrap(model.menuDrafts.records[menuOption]?.command(branchID: menuBranch))
        let saved = await model.saveRestaurantEntity(entityID: command.entityID, expectedVersion: command.expectedVersion, payload: command.payload, branchID: command.branchID)
        XCTAssertTrue(saved); XCTAssertNil(model.pendingRestaurantCommand)
        XCTAssertEqual(model.menuDrafts.records[menuOption]?.baseline.version, 2)
        XCTAssertEqual(model.menuDrafts.records[menuOption]?.dirty, false)
        let calls = await functions.writes
        XCTAssertEqual(calls.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[0].data) as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "upsertRestaurantMenuEntity")
        XCTAssertEqual(body["entityId"] as? String, menuOption.uuidString)
        XCTAssertEqual(body["branchId"] as? String, menuBranch.uuidString)
        XCTAssertEqual(body["expectedVersion"] as? Int, 1)
        XCTAssertEqual((body["payload"] as? [String: Any])?["optionGroupId"] as? String, menuGroup.uuidString)
    }
    func testRefreshConflictCannotSendOldDraftWithNewVersionUntilReviewed() async throws {
        let functions = MenuEditFunctions(), model = model(functions)
        await model.refreshRestaurantMenu(); model.menuDrafts.edit(menuOption, \.name, "Local name")
        await functions.updateOption(name: "Remote name", version: 2); await model.refreshRestaurantMenu()
        XCTAssertNil(model.menuDrafts.records[menuOption]?.command(branchID: menuBranch))
        let blocked = await model.saveRestaurantEntity(entityID: menuOption, expectedVersion: 1,
            payload: .option(optionGroupID: menuGroup, name: "Local name", priceDeltaPaise: 0, sortOrder: 0, status: "ACTIVE"), branchID: menuBranch)
        XCTAssertFalse(blocked)
        let before = await functions.writes; XCTAssertTrue(before.isEmpty)
        let reviewed = try XCTUnwrap(model.menuDrafts.records[menuOption]?.latest)
        XCTAssertTrue(model.menuDrafts.resolve(menuOption, reviewed: reviewed, keepText: true))
        let command = try XCTUnwrap(model.menuDrafts.records[menuOption]?.command(branchID: menuBranch))
        XCTAssertEqual(command.expectedVersion, 2)
        let saved = await model.saveRestaurantEntity(entityID: command.entityID, expectedVersion: command.expectedVersion, payload: command.payload, branchID: menuBranch)
        XCTAssertTrue(saved)
    }
    func testOptionTimeoutKeepsOriginalKeyPayloadAndBlocksReplacementEdits() async throws {
        let functions = MenuEditFunctions(), model = model(functions)
        await model.refreshRestaurantMenu(); await functions.failNextWrite()
        model.menuDrafts.edit(menuOption, \.name, "Original option")
        let command = try XCTUnwrap(model.menuDrafts.records[menuOption]?.command(branchID: menuBranch))
        let result = await model.saveRestaurantEntity(entityID: menuOption, expectedVersion: 1, payload: command.payload, branchID: menuBranch)
        XCTAssertFalse(result); XCTAssertNotNil(model.pendingRestaurantCommand)
        let replacement = await model.saveRestaurantEntity(entityID: menuOption, expectedVersion: 1,
            payload: .option(optionGroupID: menuGroup, name: "Replacement", priceDeltaPaise: 500, sortOrder: 0, status: "ACTIVE"), branchID: menuBranch)
        XCTAssertFalse(replacement)
        let recovered = await model.retryRestaurantCommand(); XCTAssertTrue(recovered)
        let writes = await functions.writes
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].data, writes[1].data); XCTAssertEqual(writes[0].key, writes[1].key)
        XCTAssertNil(model.pendingRestaurantCommand); XCTAssertEqual(model.menuDrafts.records[menuOption]?.dirty, false)
    }
    func testCategoryEditorRetainsDescriptionOrderStatusAndExactVersion() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuCategory,\.name,"Tea & coffee"); store.edit(menuCategory,\.description,"Freshly brewed")
        store.edit(menuCategory,\.order,"-2")
        let command = try XCTUnwrap(store.records[menuCategory]?.command(branchID: menuBranch))
        XCTAssertEqual(command.entityID,menuCategory); XCTAssertEqual(command.expectedVersion,1)
        XCTAssertEqual(command.payload,.category(name:"Tea & coffee",description:"Freshly brewed",sortOrder:-2,status:"ACTIVE"))
        XCTAssertNil(store.records[menuCategory]?.command(branchID: menuBranch,status:"INACTIVE"))
        store.edit(menuCategory,\.description,String(repeating:"a",count:501)); XCTAssertNotNil(store.records[menuCategory]?.validation)
        store.useLatest(menuCategory)
        for value in ["1.5","2147483648","-2147483649",""] { store.edit(menuCategory,\.order,value); XCTAssertNil(store.records[menuCategory]?.command(branchID:menuBranch)) }
    }
    func testChoiceGroupEditorSupportsRequiredRulesAndDisplayOrderWithoutChangingParent() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuGroup,\.name,"Choose your milk"); store.edit(menuGroup,\.selectionType,"MULTIPLE")
        store.edit(menuGroup,\.minimum,"1"); store.edit(menuGroup,\.maximum,"3"); store.edit(menuGroup,\.order,"4")
        let command = try XCTUnwrap(store.records[menuGroup]?.command(branchID:menuBranch))
        XCTAssertEqual(command.payload,.optionGroup(menuItemID:menuItem,name:"Choose your milk",selectionType:"MULTIPLE",minimumSelections:1,maximumSelections:3,sortOrder:4,status:"ACTIVE"))
        for (min,max,type) in [("2","1","MULTIPLE"),("-1","2","MULTIPLE"),("0","0","MULTIPLE"),("0","2147483648","MULTIPLE"),("0","2","SINGLE"),("1.5","2","MULTIPLE")] {
            store.edit(menuGroup,\.minimum,min); store.edit(menuGroup,\.maximum,max); store.edit(menuGroup,\.selectionType,type)
            XCTAssertNil(store.records[menuGroup]?.command(branchID:menuBranch))
        }
        store.useLatest(menuGroup)
        XCTAssertNotNil(store.records[menuGroup]?.command(branchID:menuBranch,status:"INACTIVE"))
    }
    func testCategoryAndGroupConflictsPreserveEditsUntilExactLatestReview() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.edit(menuCategory,\.description,"Local category note"); store.edit(menuGroup,\.maximum,"1")
        store.edit(menuGroup,\.minimum,"1")
        store.reconcile(try structureMenu(version:2))
        for id in [menuCategory,menuGroup] {
            XCTAssertTrue(try XCTUnwrap(store.records[id]).stale)
            XCTAssertNil(store.records[id]?.command(branchID:menuBranch))
            let latest = try XCTUnwrap(store.records[id]?.latest)
            XCTAssertTrue(store.resolve(id,reviewed:latest,keepText:true))
            XCTAssertEqual(store.records[id]?.command(branchID:menuBranch)?.expectedVersion,2)
        }
        XCTAssertEqual(store.records[menuCategory]?.value.description,"Local category note")
        XCTAssertEqual(store.records[menuGroup]?.value.minimum,"1")
    }
    func testEveryDraftKindAndNewEntryComposerSurviveRelaunchOnlyWithinAccountAndStore() throws {
        let storage = MenuDraftFixtureStorage(), store = DastakMerchantMenuDraftStore(storage:storage)
        store.setAccount(menuActor); store.reconcile(try menu())
        for id in [menuCategory,menuItem,menuGroup,menuOption] { store.edit(id,\.name,"Draft \(id)") }
        store.editAddition(menuGroup,.init(name:"New extra",price:"5"))
        store.editAddition(menuItem,.init(name:"New group",selectionType:"MULTIPLE",maximum:"3"))
        let composer = DastakMerchantMenuComposer(categoryName:"Desserts",itemName:"Cake",itemPrice:"50",itemCategoryID:menuCategory)
        store.editComposer(composer)
        let restored = DastakMerchantMenuDraftStore(storage:storage)
        XCTAssertTrue(restored.records.isEmpty,"No archive is restored before verified context.")
        restored.setAccount(menuActor); restored.reconcile(try menu())
        XCTAssertEqual(restored.dirtyCount,7); XCTAssertEqual(restored.composer,composer)
        XCTAssertEqual(restored.addition(menuGroup).name,"New extra")
        XCTAssertEqual(restored.records[menuCategory]?.command(branchID:menuBranch)?.expectedVersion,1)
        restored.setAccount(UUID()); restored.reconcile(try menu()); XCTAssertEqual(restored.dirtyCount,0)
        restored.setAccount(menuActor); restored.reconcile(try menu(branch:UUID())); XCTAssertEqual(restored.dirtyCount,0)
        restored.reconcile(try menu()); XCTAssertEqual(restored.dirtyCount,7)
    }
    func testRestoredDraftChecksNewerVersionsAndMissingEntriesBeforeEnablingSave() throws {
        let storage = MenuDraftFixtureStorage(), first = DastakMerchantMenuDraftStore(storage:storage)
        first.setAccount(menuActor); first.reconcile(try menu()); first.edit(menuItem,\.name,"Retained")
        first.edit(menuGroup,\.name,"Group draft")
        let restored = DastakMerchantMenuDraftStore(storage:storage); restored.setAccount(menuActor)
        restored.reconcile(try menu(version:2,name:"Remote"))
        XCTAssertTrue(try XCTUnwrap(restored.records[menuItem]).stale)
        XCTAssertNil(restored.records[menuItem]?.command(branchID:menuBranch))
        restored.reconcile(try menu(includeItem:false))
        XCTAssertEqual(restored.unavailable.count,2)
        XCTAssertNil(restored.records[menuGroup]?.command(branchID:menuBranch))
    }
    func testComposerAcknowledgementClearsOnlyMatchingCreationNotLaterTyping() throws {
        let store = DastakMerchantMenuDraftStore(); store.reconcile(try menu())
        store.editComposer(.init(categoryName:"Desserts",itemName:"Cake",itemPrice:"10",itemCategoryID:menuCategory))
        store.acknowledgeCreation(.category(name:"Old name",description:"",sortOrder:0,status:"ACTIVE"))
        XCTAssertEqual(store.composer.categoryName,"Desserts")
        store.acknowledgeCreation(.category(name:"Desserts",description:"",sortOrder:0,status:"ACTIVE"))
        XCTAssertEqual(store.composer.categoryName,""); XCTAssertEqual(store.composer.itemName,"Cake")
        store.acknowledgeCreation(.item(categoryID:menuCategory,name:"Cake",description:"",imageKey:"",basePricePaise:1000,taxRateBps:0,logisticsAttributes:.init(),status:"ACTIVE"))
        XCTAssertFalse(store.composer.dirty)
    }
    func testStorageFailureIsVisibleAndRetryPersistsTheRetainedDraft() throws {
        let storage = MenuDraftFixtureStorage(), store = DastakMerchantMenuDraftStore(storage:storage)
        store.setAccount(menuActor); store.reconcile(try menu()); storage.failWrites = true
        store.edit(menuItem,\.name,"Keep despite disk failure")
        XCTAssertNotNil(store.persistenceFailure); XCTAssertThrowsError(try store.flush())
        XCTAssertEqual(store.records[menuItem]?.value.name,"Keep despite disk failure")
        storage.failWrites = false; store.retryPersistence(); XCTAssertNil(store.persistenceFailure)
        let second = DastakMerchantMenuDraftStore(storage:storage); second.setAccount(menuActor); second.reconcile(try menu())
        XCTAssertEqual(second.records[menuItem]?.value.name,"Keep despite disk failure")
    }
    func testUnreadableStorageIsNotOverwrittenAndExplicitDiscardIsStoreScoped() throws {
        let storage = MenuDraftFixtureStorage(), store = DastakMerchantMenuDraftStore(storage:storage)
        store.setAccount(menuActor); store.reconcile(try menu()); store.edit(menuItem,\.name,"Stored")
        let otherBranch = UUID(); store.reconcile(try menu(branch:otherBranch)); store.edit(menuItem,\.name,"Other store")
        storage.failReads = true
        let second = DastakMerchantMenuDraftStore(storage:storage); second.setAccount(menuActor); second.reconcile(try menu())
        XCTAssertNotNil(second.persistenceFailure)
        second.edit(menuItem,\.name,"New typing"); XCTAssertThrowsError(try second.flush())
        storage.failReads = false
        second.discardLocalDrafts(try menu()); XCTAssertEqual(second.dirtyCount,0); XCTAssertNil(second.persistenceFailure)
        second.reconcile(try menu(branch:otherBranch)); XCTAssertEqual(second.records[menuItem]?.value.name,"Other store")
    }
    func testConcurrentWorkspaceCannotSilentlyOverwriteNewerLocalDrafts() throws {
        let storage = MenuDraftFixtureStorage(), first = DastakMerchantMenuDraftStore(storage:storage), second = DastakMerchantMenuDraftStore(storage:storage)
        first.setAccount(menuActor); first.reconcile(try menu()); first.edit(menuItem,\.name,"First")
        second.setAccount(menuActor); second.reconcile(try menu())
        first.edit(menuItem,\.name,"Newer first workspace")
        second.edit(menuItem,\.name,"Stale second workspace"); XCTAssertNotNil(second.persistenceFailure)
        let third = DastakMerchantMenuDraftStore(storage:storage); third.setAccount(menuActor); third.reconcile(try menu())
        XCTAssertEqual(third.records[menuItem]?.value.name,"Newer first workspace")
    }
    func testExplicitReadRetryRestoresStorageAfterUnlockButCannotOverwriteNewTyping() throws {
        let storage = MenuDraftFixtureStorage(), first = DastakMerchantMenuDraftStore(storage:storage)
        first.setAccount(menuActor); first.reconcile(try menu()); first.edit(menuItem,\.name,"Stored before lock")
        storage.failReads = true
        let second = DastakMerchantMenuDraftStore(storage:storage); second.setAccount(menuActor); second.reconcile(try menu())
        XCTAssertTrue(second.needsRestoreRetry)
        storage.failReads = false; second.retryRestoring(try menu())
        XCTAssertFalse(second.needsRestoreRetry); XCTAssertEqual(second.records[menuItem]?.value.name,"Stored before lock")
        storage.failReads = true
        let third = DastakMerchantMenuDraftStore(storage:storage); third.setAccount(menuActor); third.reconcile(try menu())
        third.edit(menuItem,\.name,"Do not overwrite typing")
        storage.failReads = false; third.retryRestoring(try menu())
        XCTAssertTrue(third.needsRestoreRetry); XCTAssertEqual(third.records[menuItem]?.value.name,"Do not overwrite typing")
    }
    func testFileDraftStorageIsBoundedProtectedScopedAndRevisionChecked() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let storage = DastakMerchantMenuFileDraftStorage(directory:directory)
        let first = DastakMerchantMenuDraftArchive(accountID:menuActor,branchID:menuBranch,records:[:],additions:[:],composer:.init(categoryName:"Private draft"))
        try storage.replace(first,expectedRevision:nil)
        XCTAssertEqual(try storage.load(account:menuActor,branch:menuBranch)?.composer.categoryName,"Private draft")
        XCTAssertNil(try storage.load(account:UUID(),branch:menuBranch))
        XCTAssertThrowsError(try storage.replace(first,expectedRevision:nil))
        let file = directory.appendingPathComponent(menuActor.uuidString.lowercased()+"-"+menuBranch.uuidString.lowercased()+".json")
        let permissions = try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue,0o600)
        var invalid = first; invalid.formatVersion = 99
        try JSONEncoder().encode(invalid).write(to:file)
        XCTAssertThrowsError(try storage.load(account:menuActor,branch:menuBranch))
        let foreign = DastakMerchantMenuDraftArchive(accountID:UUID(),branchID:menuBranch,records:[:],additions:[:],composer:.init())
        try JSONEncoder().encode(foreign).write(to:file)
        XCTAssertThrowsError(try storage.load(account:menuActor,branch:menuBranch))
        try Data(repeating:0,count:2*1_024*1_024+1).write(to:file)
        XCTAssertThrowsError(try storage.load(account:menuActor,branch:menuBranch))
        try storage.discard(account:menuActor,branch:menuBranch); XCTAssertNil(try storage.load(account:menuActor,branch:menuBranch))
    }
    func testNewCategoryAndChoiceEditsSaveThroughVersionedJournal() async throws {
        let functions = MenuEditFunctions(), model = model(functions)
        await model.refreshRestaurantMenu()
        for (id,field,value) in [(menuCategory,\DastakMerchantMenuFields.description,"Category note"),(menuGroup,\.minimum,"1")] {
            model.menuDrafts.edit(id,field,value)
            let command = try XCTUnwrap(model.menuDrafts.records[id]?.command(branchID:menuBranch))
            let saved = await model.saveRestaurantEntity(entityID:id,expectedVersion:command.expectedVersion,payload:command.payload,branchID:menuBranch)
            XCTAssertTrue(saved); XCTAssertNil(model.pendingRestaurantCommand)
            XCTAssertEqual(model.menuDrafts.records[id]?.dirty,false)
            XCTAssertEqual(model.menuDrafts.records[id]?.baseline.version,2)
        }
    }
    func testDraftCleanupFailureKeepsOriginalJournalUntilPersistenceRecovers() async throws {
        let functions = MenuEditFunctions(), storage = MenuDraftFixtureStorage(), journal = DastakMerchantMemoryJournal()
        let first = model(functions,storage:storage,journal:journal); await first.refreshRestaurantMenu()
        first.menuDrafts.edit(menuOption,\.name,"Saved option")
        let command = try XCTUnwrap(first.menuDrafts.records[menuOption]?.command(branchID:menuBranch))
        storage.failWrites = true
        let result = await first.saveRestaurantEntity(entityID:menuOption,expectedVersion:1,payload:command.payload,branchID:menuBranch)
        XCTAssertFalse(result); XCTAssertNotNil(first.pendingRestaurantCommand)
        XCTAssertNotNil(first.menuDrafts.persistenceFailure)
        storage.failWrites = false
        let second = model(functions,storage:storage,journal:journal); await second.refreshRestaurantMenu()
        let recovered = await second.retryRestaurantCommand(); XCTAssertTrue(recovered)
        XCTAssertNil(second.pendingRestaurantCommand); XCTAssertEqual(second.menuDrafts.records[menuOption]?.dirty,false)
        let writes = await functions.writes
        XCTAssertEqual(writes.count,2); XCTAssertEqual(writes[0].key,writes[1].key); XCTAssertEqual(writes[0].data,writes[1].data)
    }
    func testNewCategoryLostAcknowledgementReplaysExactCreationIDAndClearsPersistedComposer() async throws {
        let functions = MenuEditFunctions(), storage = MenuDraftFixtureStorage(), journal = DastakMerchantMemoryJournal()
        let first = model(functions,storage:storage,journal:journal); await first.refreshRestaurantMenu()
        first.menuDrafts.editComposer(.init(categoryName:"Desserts"))
        await functions.loseNextAcknowledgement()
        let payload = DastakV1RestaurantMenuPayload.category(name:"Desserts",description:"",sortOrder:1,status:"ACTIVE")
        let result = await first.saveRestaurantEntity(entityID:nil,expectedVersion:0,payload:payload,branchID:menuBranch)
        XCTAssertFalse(result)
        let pending = try XCTUnwrap(first.pendingRestaurantCommand); XCTAssertNotNil(pending.creationEntityID)
        let second = model(functions,storage:storage,journal:journal); await second.refreshRestaurantMenu()
        XCTAssertEqual(second.pendingRestaurantCommand,pending)
        let recovered = await second.retryRestaurantCommand(); XCTAssertTrue(recovered)
        XCTAssertEqual(second.menuDrafts.composer.categoryName,""); XCTAssertNil(second.pendingRestaurantCommand)
        let writes = await functions.writes, applied = await functions.appliedWrites
        XCTAssertEqual(writes.count,2); XCTAssertEqual(applied,1)
        XCTAssertEqual(writes[0].data,writes[1].data); XCTAssertEqual(writes[0].key,writes[1].key)
        let body = try JSONSerialization.jsonObject(with:writes[0].data) as! [String:Any]
        XCTAssertEqual(body["entityId"] as? String,pending.creationEntityID?.uuidString)
        let reopened = DastakMerchantMenuDraftStore(storage:storage); reopened.setAccount(menuActor); reopened.reconcile(try menu())
        XCTAssertEqual(reopened.composer.categoryName,"")
    }
    func testUnreadableDraftCleanupCanBeExplicitlyDiscardedWithoutDeletingSavedCommand() async throws {
        let functions = MenuEditFunctions(), storage = MenuDraftFixtureStorage(), journal = DastakMerchantMemoryJournal()
        storage.failReads = true
        let merchant = model(functions,storage:storage,journal:journal); await merchant.refreshRestaurantMenu()
        let payload = DastakV1RestaurantMenuPayload.option(optionGroupID:menuGroup,name:"Saved",priceDeltaPaise:0,sortOrder:0,status:"ACTIVE")
        let result = await merchant.saveRestaurantEntity(entityID:menuOption,expectedVersion:1,payload:payload,branchID:menuBranch)
        XCTAssertFalse(result); let saved = try XCTUnwrap(merchant.pendingRestaurantCommand)
        storage.failReads = false
        merchant.menuDrafts.discardLocalDrafts(try XCTUnwrap(merchant.restaurantMenu))
        XCTAssertEqual(merchant.pendingRestaurantCommand,saved)
        let record = try await journal.load(menuActor); XCTAssertNotNil(record)
        let recovered = await merchant.retryRestaurantCommand(); XCTAssertTrue(recovered)
        let applied = await functions.appliedWrites; XCTAssertEqual(applied,1)
    }
    func testOldRestaurantJournalWithoutCreationIDStillDecodesWithoutInventingNewPayload() throws {
        let original = DastakMerchantRestaurantCommand(branchID:menuBranch,key:IdempotencyKey(rawValue:UUID().uuidString)!,operation:.menu(entityID:nil,expectedVersion:0,payload:.category(name:"Old",description:"",sortOrder:0,status:"ACTIVE")))
        var object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
        object.removeValue(forKey:"creationEntityID")
        let old = try JSONDecoder().decode(DastakMerchantRestaurantCommand.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(old.creationEntityID); XCTAssertTrue(old.valid); XCTAssertEqual(old.operation,original.operation)
    }
    func testActorChangeDuringFreshMenuReadDoesNotRestoreOrExposeOldDrafts() async throws {
        let functions = MenuEditFunctions(), identity = MerchantJournalTestIdentity(), storage = MenuDraftFixtureStorage()
        let originalActor = await identity.id
        let merchant = DastakMerchantModel(services:.init(functions:functions,accountIDProvider:{ await identity.id },objectUploader:{ _,_,_,_,_ in }),journalStorage:DastakMerchantMemoryJournal(),menuDraftStorage:storage)
        await merchant.refreshRestaurantMenu(); merchant.menuDrafts.edit(menuItem,\.name,"Private old actor draft")
        await functions.holdNextRead()
        let read = Task { await merchant.refreshRestaurantMenu() }
        await functions.waitForRead(); await identity.change(); await functions.releaseRead(); _ = await read.value
        XCTAssertNil(merchant.restaurantMenu); XCTAssertTrue(merchant.menuDrafts.records.isEmpty)
        XCTAssertTrue(merchant.sessionNeedsAttention)
        XCTAssertEqual(try storage.load(account:originalActor,branch:menuBranch)?.records[menuItem]?.value.name,"Private old actor draft")
        let writes = await functions.writes; XCTAssertTrue(writes.isEmpty)
    }
    private func structureMenu(version:Int) throws -> DastakV1RestaurantMenu {
        var root = try JSONSerialization.jsonObject(with:menuDraftData()) as! [String:Any]
        var categories = root["categories"] as! [[String:Any]], items = categories[0]["items"] as! [[String:Any]]
        var groups = items[0]["optionGroups"] as! [[String:Any]]
        categories[0]["version"] = version; categories[0]["description"] = "Remote category"
        groups[0]["version"] = version; groups[0]["name"] = "Remote choices"
        items[0]["optionGroups"] = groups; categories[0]["items"] = items; root["categories"] = categories
        return try JSONDecoder().decode(DastakV1RestaurantMenu.self,from:JSONSerialization.data(withJSONObject:root))
    }
    private func model(_ functions: MenuEditFunctions, storage: (any DastakMerchantMenuDraftStorage)? = nil,
        journal: any DastakMerchantJournalStorage = DastakMerchantMemoryJournal()) -> DastakMerchantModel {
        .init(services: .init(functions: functions, accountIDProvider: { menuActor }, objectUploader: { _, _, _, _, _ in }), journalStorage: journal,menuDraftStorage:storage)
    }
    private func menu(version: Int = 1, mediaVersion: Int = 1, name: String = "Tea", price: Int = 1000, image: String = "photos/old.jpg", tax: Int = 0, branch: UUID = menuBranch, includeItem: Bool = true) throws -> DastakV1RestaurantMenu {
        try JSONDecoder().decode(DastakV1RestaurantMenu.self, from: menuDraftData(version: version, mediaVersion: mediaVersion, name: name, price: price, image: image, tax: tax, branch: branch, includeItem: includeItem))
    }
}

private let menuBranch = UUID(uuidString: "96000000-0000-4000-8000-000000000001")!
private let menuCategory = UUID(uuidString: "96000000-0000-4000-8000-000000000002")!
private let menuItem = UUID(uuidString: "96000000-0000-4000-8000-000000000003")!
private let menuGroup = UUID(uuidString: "96000000-0000-4000-8000-000000000004")!
private let menuOption = UUID(uuidString: "96000000-0000-4000-8000-000000000005")!
private let menuActor = UUID(uuidString: "96000000-0000-4000-8000-000000000009")!
private func menuDraftData(version: Int = 1, mediaVersion: Int = 1, name: String = "Tea", price: Int = 1000, image: String = "photos/old.jpg", tax: Int = 0, branch: UUID = menuBranch, includeItem: Bool = true) throws -> Data {
    let option: [String: Any] = ["id": menuOption.uuidString, "name": "Oat", "priceDeltaPaise": 0, "sortOrder": 0, "status": "ACTIVE", "version": 1]
    let group: [String: Any] = ["id": menuGroup.uuidString, "name": "Milk choice", "selectionType": "SINGLE", "minimumSelections": 0, "maximumSelections": 1, "sortOrder": 0, "status": "ACTIVE", "version": 1, "options": [option]]
    let item: [String: Any] = ["id": menuItem.uuidString, "name": name, "description": "Warming tea", "imageKey": image, "mediaVersion": mediaVersion, "basePricePaise": price, "currencyCode": "INR", "taxRateBps": tax, "logisticsAttributes": [:], "status": "ACTIVE", "version": version, "optionGroups": [group]]
    let hidden: [String: Any] = ["id": "96000000-0000-4000-8000-000000000006", "name": "Hidden cake", "basePricePaise": 2000, "currencyCode": "INR", "taxRateBps": 0, "logisticsAttributes": [:], "status": "INACTIVE", "version": 1, "optionGroups": []]
    return try JSONSerialization.data(withJSONObject: ["restaurant": ["organizationId": "96000000-0000-4000-8000-000000000007", "branchId": branch.uuidString, "name": "Test Kitchen", "branchName": "Test", "isOpen": true, "acceptingOrders": true, "operationalVersion": 1, "branchStatus": "ACTIVE", "merchantType": "RESTAURANT_CAFE", "softActiveOrderThreshold": 10, "activeOrderCount": 0],
        "categories": [["id": menuCategory.uuidString, "name": "Hot drinks", "sortOrder": 0, "status": "ACTIVE", "version": 1, "items": includeItem ? [item, hidden] : []]]])
}

@MainActor private final class MenuDraftFixtureStorage: DastakMerchantMenuDraftStorage {
    private var values: [String:DastakMerchantMenuDraftArchive] = [:]
    var failWrites = false, failReads = false
    private func key(_ account:UUID,_ branch:UUID) -> String { account.uuidString+branch.uuidString }
    func load(account:UUID,branch:UUID) throws -> DastakMerchantMenuDraftArchive? {
        if failReads { throw DastakAdminExecutionError.invalid }; return values[key(account,branch)]
    }
    func replace(_ archive:DastakMerchantMenuDraftArchive,expectedRevision:UUID?) throws {
        guard !failWrites, values[key(archive.accountID,archive.branchID)]?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        values[key(archive.accountID,archive.branchID)] = archive
    }
    func discard(account:UUID,branch:UUID) throws { values[key(account,branch)] = nil }
}

private actor MenuEditFunctions: FunctionClient {
    struct Write: Sendable { let data: Data; let key: IdempotencyKey }
    var writes: [Write] = []
    private var fail = false
    private var optionName = "Oat", optionPrice = 0, optionStatus = "ACTIVE", optionVersion = 1
    private var categoryPayload: Data?, groupPayload: Data?
    private var receipts: [String:Data] = [:]
    private var newCategory: Data?
    private var loseAcknowledgement = false
    private(set) var appliedWrites = 0
    func loseNextAcknowledgement() { loseAcknowledgement = true }
    private var holding = false
    private var continuation: CheckedContinuation<Void,Never>?, started: CheckedContinuation<Void,Never>?
    func holdNextRead() { holding = true }
    func waitForRead() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func releaseRead() { continuation?.resume(); continuation = nil }
    func failNextWrite() { fail = true }
    func updateOption(name: String, version: Int) { optionName = name; optionVersion = version }
    private func snapshot() throws -> [String: Any] {
        var root = try JSONSerialization.jsonObject(with: menuDraftData()) as! [String: Any]
        var categories = root["categories"] as! [[String: Any]], items = categories[0]["items"] as! [[String: Any]]
        var groups = items[0]["optionGroups"] as! [[String: Any]], options = groups[0]["options"] as! [[String: Any]]
        options[0]["name"] = optionName; options[0]["priceDeltaPaise"] = optionPrice; options[0]["status"] = optionStatus; options[0]["version"] = optionVersion
        if let categoryPayload, let payload = try JSONSerialization.jsonObject(with:categoryPayload) as? [String:Any] {
            for (key,value) in payload { categories[0][key] = value }; categories[0]["version"] = 2
        }
        if let groupPayload, let payload = try JSONSerialization.jsonObject(with:groupPayload) as? [String:Any] {
            for (key,value) in payload { groups[0][key] = value }; groups[0]["version"] = 2
        }
        groups[0]["options"] = options; items[0]["optionGroups"] = groups; categories[0]["items"] = items
        if let newCategory { categories.append(try JSONSerialization.jsonObject(with:newCategory) as! [String:Any]) }
        root["categories"] = categories
        return root
    }
    func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(_ name: String, request: Request, idempotencyKey: IdempotencyKey) async throws -> Response {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(request), body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let result: [String: Any]
        if body["operation"] as? String == "merchantRestaurantMenu" {
            if holding { holding = false; await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
            result = try snapshot()
        }
        else {
            writes.append(.init(data: data, key: idempotencyKey))
            if let receipt = receipts[idempotencyKey.rawValue] { return try JSONDecoder().decode(Response.self,from:receipt) }
            if fail { fail = false; throw URLError(.timedOut) }
            guard body["operation"] as? String == "upsertRestaurantMenuEntity", let payload = body["payload"] as? [String: Any] else { throw FunctionClientError.invalidResponse }
            let id = body["entityId"] as? String, version = body["expectedVersion"] as? Int
            if id == menuOption.uuidString, version == optionVersion {
                optionName = payload["name"] as! String; optionPrice = payload["priceDeltaPaise"] as! Int; optionStatus = payload["status"] as! String; optionVersion += 1
            } else if version == 0, body["entityType"] as? String == "CATEGORY", let id {
                var value = payload; value["id"] = id; value["version"] = 1; value["items"] = [] as [String]
                newCategory = try JSONSerialization.data(withJSONObject:value)
            } else if id == menuCategory.uuidString, version == 1 { categoryPayload = try JSONSerialization.data(withJSONObject:payload) }
            else if id == menuGroup.uuidString, version == 1 { groupPayload = try JSONSerialization.data(withJSONObject:payload) }
            else { throw FunctionClientError.invalidResponse }
            result = ["entityId":id!,"entityType":body["entityType"]!,"menu":try snapshot()]
            receipts[idempotencyKey.rawValue] = try JSONSerialization.data(withJSONObject:result)
            appliedWrites += 1
            if loseAcknowledgement { loseAcknowledgement = false; throw URLError(.timedOut) }
        }
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: result))
    }
}
