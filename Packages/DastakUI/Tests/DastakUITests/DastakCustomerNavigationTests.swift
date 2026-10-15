import XCTest
import MarketplaceInfrastructure
@testable import DastakUI

final class DastakCustomerNavigationTests: XCTestCase {
    func testSearchShortcutOpensHomeSearchAndKeepsSelectedService() {
        for service in [DastakCustomerService.grocery, .food] {
            var state = DastakCustomerNavigation(service: service)
            state.navigate(.settings)
            XCTAssertEqual(state.apply(.search, basketHasItems: false), .home)
            XCTAssertEqual(state.section, .home)
            XCTAssertEqual(state.service, service)
            XCTAssertTrue(state.startsWithSearch)
            let revision = service == .grocery ? state.groceryHomeRevision : state.foodHomeRevision
            _ = state.apply(.search, basketHasItems: false)
            XCTAssertGreaterThan(service == .grocery ? state.groceryHomeRevision : state.foodHomeRevision, revision)
        }
    }

    func testSearchShortcutDoesNotReopenAfterNormalNavigation() {
        var state = DastakCustomerNavigation()
        _ = state.apply(.search, basketHasItems: false)
        state.navigate(.orders)
        XCTAssertFalse(state.startsWithSearch)
        state.navigate(.home)
        XCTAssertFalse(state.startsWithSearch)
        _ = state.apply(.search, basketHasItems: false)
        state.selectService(.food)
        XCTAssertFalse(state.startsWithSearch)
        _ = state.apply(.search, basketHasItems: false)
        _ = state.apply(.basket, basketHasItems: false)
        XCTAssertFalse(state.startsWithSearch)
        state.selectService(.grocery)
        _ = state.apply(.search, basketHasItems: false)
        _ = state.openDirectory("milk", allowedKeys: ["milk"])
        XCTAssertFalse(state.startsWithSearch)
    }
    func testGroceryAndFoodShortcutsSelectTheCorrectServiceFromAccountScreens() {
        var state = DastakCustomerNavigation(service: .food)
        state.navigate(.settings)
        XCTAssertEqual(state.apply(.grocery, basketHasItems: false), .home)
        XCTAssertEqual(state.service, .grocery)
        XCTAssertEqual(state.section, .home)
        state.navigate(.profile)
        XCTAssertEqual(state.apply(.food, basketHasItems: true), .home)
        XCTAssertEqual(state.service, .food)
        XCTAssertEqual(state.section, .home)
    }

    func testBasketShortcutPreservesServiceAndRejectsEmptyBasket() {
        for service in [DastakCustomerService.grocery, .food] {
            var state = DastakCustomerNavigation(service: service)
            XCTAssertEqual(state.apply(.basket, basketHasItems: false), .emptyBasket)
            XCTAssertEqual(state.service, service)
            XCTAssertEqual(state.apply(.basket, basketHasItems: true), .basket)
            XCTAssertEqual(state.service, service)
        }
    }

    func testTrackingShortcutOpensOrdersWithoutChangingService() {
        var state = DastakCustomerNavigation(service: .food)
        XCTAssertEqual(state.apply(.tracking, basketHasItems: false), .tracking)
        XCTAssertEqual(state.section, .orders)
        XCTAssertEqual(state.service, .food)
    }

    func testInvalidRememberedServiceFallsBackToGrocery() {
        XCTAssertEqual(DastakCustomerNavigation(service: .parcel).service, .grocery)
        XCTAssertEqual(DastakCustomerNavigation(service: .print).service, .grocery)
    }

    func testSystemActionResetsBothOutgoingAndIncomingExploration() {
        var state = DastakCustomerNavigation()
        _ = state.openDirectory("milk", allowedKeys: ["milk"])
        XCTAssertEqual(state.apply(.food, basketHasItems: false), .home)
        XCTAssertNil(state.directoryKey)
        XCTAssertGreaterThan(state.groceryHomeRevision, 0)
        XCTAssertGreaterThan(state.foodHomeRevision, 0)
        let revision = state.foodHomeRevision
        _ = state.apply(.tracking, basketHasItems: false)
        XCTAssertGreaterThan(state.foodHomeRevision, revision)
    }
    func testDirectoryReadsValidatedSectionRootsNotInventedNodeKinds() throws {
        let map = try JSONDecoder().decode(DastakV1CatalogueBrowseMap.self, from: Data("""
        {"version":1,"nodes":[
        {"key":"fresh","kind":"SECTION","label":"Fresh Items","sortOrder":1,"sources":[]},
        {"key":"grocery","kind":"SECTION","label":"Grocery & Kitchen","sortOrder":2,"sources":[]},
        {"key":"milk","parentKey":"fresh","kind":"DESTINATION","label":"Dairy","sortOrder":1,"sources":[]},
        {"key":"rail","parentKey":"milk","kind":"RAIL","label":"Milk","sortOrder":1,"sources":[]}]}
        """.utf8))
        XCTAssertTrue(map.isValid)
        XCTAssertEqual(DastakCustomerNavigation.directorySections(map).map(\.key), ["fresh", "grocery"])
        XCTAssertEqual(map.children(of: "fresh").map(\.key), ["milk"])
    }
    func testDefaultsMatchBriefAndEnglishOnlyNavigation() {
        let state = DastakCustomerNavigation()
        XCTAssertEqual(state.section, .home)
        XCTAssertEqual(state.service, .grocery)
        XCTAssertEqual(DastakCustomerSection.allCases.map(\.rawValue), ["Home", "Orders", "Profile", "Settings"])
        XCTAssertEqual(DastakCustomerService.allCases.map(\.rawValue), ["Food", "Grocery", "Parcel", "Print"])
    }

    func testSoonServicesAreInertEvenIfActionInvokedDirectly() {
        var state = DastakCustomerNavigation()
        state.navigate(.settings)
        let before = state
        XCTAssertFalse(state.selectService(.parcel))
        XCTAssertFalse(state.selectService(.print))
        XCTAssertEqual(state, before)
    }

    func testAccountSectionsDoNotResetExploration() {
        var state = DastakCustomerNavigation()
        _ = state.openDirectory("milk", allowedKeys: ["milk"])
        state.navigate(.profile)
        state.navigate(.settings)
        state.navigate(.orders)
        XCTAssertEqual(state.directoryKey, "milk")
        XCTAssertEqual(state.groceryHomeRevision, 0)
    }

    func testHomeResetsCurrentServiceIncludingRepeatedHomeTaps() {
        var state = DastakCustomerNavigation()
        _ = state.openDirectory("atta", allowedKeys: ["atta"])
        state.navigate(.home)
        state.navigate(.home)
        XCTAssertNil(state.directoryKey)
        XCTAssertEqual(state.groceryHomeRevision, 2)
        XCTAssertEqual(state.foodHomeRevision, 0)
    }

    func testSwitchServiceReturnsHomeButRetainsOtherExploration() {
        var state = DastakCustomerNavigation()
        _ = state.openDirectory("rice", allowedKeys: ["rice"])
        state.navigate(.settings)
        XCTAssertTrue(state.selectService(.food))
        XCTAssertEqual(state.section, .home)
        state.navigate(.home)
        XCTAssertEqual(state.foodHomeRevision, 1)
        XCTAssertEqual(state.groceryHomeRevision, 0)
        XCTAssertTrue(state.selectService(.grocery))
        XCTAssertEqual(state.directoryKey, "rice")
        XCTAssertEqual(state.groceryHomeRevision, 0)
    }

    func testSelectedServiceResetsOnlyItself() {
        var state = DastakCustomerNavigation()
        _ = state.openDirectory("rice", allowedKeys: ["rice"])
        _ = state.selectService(.grocery)
        XCTAssertNil(state.directoryKey)
        XCTAssertEqual(state.groceryHomeRevision, 1)
        _ = state.selectService(.food)
        _ = state.selectService(.food)
        XCTAssertEqual(state.foodHomeRevision, 1)
        XCTAssertEqual(state.groceryHomeRevision, 1)
    }

    func testDirectoryUsesExactKnownKeysAndRepeatedSelectionIsObservable() {
        var state = DastakCustomerNavigation()
        state.navigate(.profile)
        let before = state
        XCTAssertFalse(state.openDirectory("unknown", allowedKeys: ["milk"]))
        XCTAssertEqual(state, before)
        XCTAssertTrue(state.openDirectory("milk", allowedKeys: ["milk"]))
        XCTAssertTrue(state.openDirectory("milk", allowedKeys: ["milk"]))
        XCTAssertEqual(state.section, .home)
        XCTAssertEqual(state.directoryRevision, 2)
        _ = state.selectService(.food)
        let food = state
        XCTAssertFalse(state.openDirectory("milk", allowedKeys: ["milk"]))
        XCTAssertEqual(state, food)
    }

    func testProfileSettingsSeparationRetainsAllExistingControls() {
        let profile = DastakCustomerAccountPanel.profile.sections
        let settings = DastakCustomerAccountPanel.settings.sections
        XCTAssertEqual(profile, [.details, .addresses, .shopping])
        XCTAssertEqual(settings, [.preferences, .identity, .actions, .support, .partners])
        XCTAssertTrue(Set(profile).isDisjoint(with: Set(settings)))
        XCTAssertEqual(Set(profile + settings), Set(DastakCustomerAccountPanel.combined.sections))
        XCTAssertEqual(DastakCustomerAccountPanel.profile.title, "Profile")
        XCTAssertEqual(DastakCustomerAccountPanel.settings.title, "Settings")
    }

    func testCentreBrowseUpdatesHighlightWithoutIssuingAnotherBrowseIntent() {
        var state = DastakCustomerNavigation()
        _ = state.openDirectory("milk", allowedKeys: ["milk", "rice"])
        let revision = state.directoryRevision
        state.updateDirectoryHighlight("rice", allowedKeys: ["milk", "rice"])
        XCTAssertEqual(state.directoryKey, "rice")
        XCTAssertEqual(state.directoryRevision, revision)
        state.updateDirectoryHighlight("unknown", allowedKeys: ["milk", "rice"])
        XCTAssertEqual(state.directoryKey, "rice")
        state.updateDirectoryHighlight(nil, allowedKeys: [])
        XCTAssertNil(state.directoryKey)
    }
}
