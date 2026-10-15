import Foundation
import XCTest
@testable import DastakUI

final class DastakEnvironmentTests: XCTestCase {
    func testOutsideUsesWebCompositionWithDoorwayTranslationOnly() {
        let r = DastakOutsideSceneReference.self
        XCTAssertEqual(r.z(-7.16),-3.2,accuracy:0.0001)
        XCTAssertEqual(r.position(portrait:true)[2]-r.nativeDoorwayZ,-19-(-7.16),accuracy:0.0001)
        XCTAssertEqual(r.position(portrait:false)[2]-r.nativeDoorwayZ,-16-(-7.16),accuracy:0.0001)
        XCTAssertEqual(r.target(portrait:true)[1],0.35)
        XCTAssertEqual(r.fieldOfView(portrait:false),1.15*180 / .pi,accuracy:0.0001)
        XCTAssertGreaterThan(r.fieldOfView(portrait:true),r.fieldOfView(portrait:false))
        XCTAssertEqual(r.frontageWidth,7.5)
    }
    func testSlowFirstFrameCannotSkipEntireCameraMove() {
        let step = DastakEnvironmentTransition.frameStep
        XCTAssertEqual(step(-1),0)
        XCTAssertEqual(step(1.0/30),1.0/30)
        XCTAssertEqual(step(2),1.0/15)
        XCTAssertLessThan(DastakEnvironmentTransition.progress(step(2)/0.85),0.01)
    }
    func testCameraGlidesWithinEachStoreAndOutsideEntrance() {
        for pair: (DastakEnvironmentPlace,DastakEnvironmentPlace) in [(.outside,.grocery),(.grocery,.outside),
            (.grocery,.groceryBilling),(.groceryBilling,.grocery),(.cafe,.cafeCounter),(.cafeCounter,.cafe)] {
            let transition = DastakEnvironmentTransition(from:pair.0,to:pair.1,reducedMotion:false,active:true)
            XCTAssertEqual(transition.duration,0.85)
            XCTAssertFalse(transition.dissolves)
        }
    }
    func testDifferentStoresDissolveInBothDirections() {
        for pair: (DastakEnvironmentPlace,DastakEnvironmentPlace) in [(.grocery,.cafe),(.cafe,.grocery),
            (.groceryBilling,.cafeCounter),(.cafeCounter,.groceryBilling),(.outside,.cafe),(.cafe,.outside)] {
            let transition = DastakEnvironmentTransition(from:pair.0,to:pair.1,reducedMotion:false,active:true)
            XCTAssertEqual(transition.duration,0.7)
            XCTAssertTrue(transition.dissolves)
        }
    }
    func testInitialInactiveAndReducedMotionDoNotAnimate() {
        for transition in [DastakEnvironmentTransition(from:nil,to:.grocery,reducedMotion:false,active:true),
            .init(from:.grocery,to:.cafe,reducedMotion:true,active:true),
            .init(from:.cafe,to:.grocery,reducedMotion:false,active:false)] {
            XCTAssertEqual(transition.duration,0)
            XCTAssertFalse(transition.dissolves)
        }
    }
    func testTransitionEasingIsBoundedMonotonicAndSoftAtBothEnds() {
        let progress = DastakEnvironmentTransition.progress
        XCTAssertEqual(progress(-1),0); XCTAssertEqual(progress(2),1)
        XCTAssertEqual(progress(0.5),0.5)
        XCTAssertLessThan(progress(0.01),0.0001)
        XCTAssertGreaterThan(progress(0.99),0.9999)
        var previous = 0.0
        for i in 0...100 {
            let value = progress(Double(i)/100)
            XCTAssertGreaterThanOrEqual(value,previous)
            XCTAssertTrue((0...1).contains(value)); previous = value
        }
    }
    func testRendererPausesInBackgroundAndResumesWithSameBudget() {
        let active=DastakEnvironmentRenderPolicy(active:true,reducedMotion:false,lowPower:false,thermalLimited:false)
        XCTAssertTrue(active.animates)
        XCTAssertEqual(active.framesPerSecond,30)
        XCTAssertFalse(DastakEnvironmentRenderPolicy(active:false,reducedMotion:false,lowPower:false,thermalLimited:false).animates)
        XCTAssertEqual(active,DastakEnvironmentRenderPolicy(active:true,reducedMotion:false,lowPower:false,thermalLimited:false))
    }
    func testReducedMotionKeepsSceneStaticInForeground() {
        XCTAssertFalse(DastakEnvironmentRenderPolicy(active:true,reducedMotion:true,lowPower:false,thermalLimited:false).animates)
    }
    func testThermalBudgetTakesPriorityOverLowPower() {
        XCTAssertEqual(DastakEnvironmentRenderPolicy(active:true,reducedMotion:false,lowPower:true,thermalLimited:false).framesPerSecond,20)
        XCTAssertEqual(DastakEnvironmentRenderPolicy(active:true,reducedMotion:false,lowPower:true,thermalLimited:true).framesPerSecond,15)
    }
    func testFoldedLeafBuffersAreDeterministicAndHaveValidIndices() {
        let a=DastakNativeSceneGeometry.leaves(count:30,seed:674)
        let b=DastakNativeSceneGeometry.leaves(count:30,seed:674)
        XCTAssertEqual(a.positions,b.positions)
        XCTAssertEqual(a.colors,b.colors)
        XCTAssertEqual(a.positions.count,30*9*3)
        XCTAssertEqual(a.normals.count,a.positions.count)
        XCTAssertEqual(a.colors.count,30*9*4)
        XCTAssertEqual(a.indices.count,30*8*3)
        XCTAssertTrue(a.indices.allSatisfy { $0>=0 && $0<Int32(a.positions.count/3) })
        XCTAssertTrue(a.positions.allSatisfy(\.isFinite))
        XCTAssertTrue(a.colors.allSatisfy { (0...1).contains($0) })
        XCTAssertNotEqual(a.positions,DastakNativeSceneGeometry.leaves(count:30,seed:675).positions)
    }
    func testLeafNormalsAreUnitLengthAndCrownIsBounded() {
        let mesh=DastakNativeSceneGeometry.leaves(count:100,seed:200)
        for i in stride(from:0,to:mesh.positions.count,by:3) {
            XCTAssertLessThan(abs(mesh.positions[i]),1.5)
            XCTAssertLessThan(abs(mesh.positions[i+1]),1.25)
            XCTAssertLessThan(abs(mesh.positions[i+2]),1.5)
            let n=mesh.normals
            XCTAssertEqual(n[i]*n[i]+n[i+1]*n[i+1]+n[i+2]*n[i+2],1,accuracy:0.00001)
        }
    }
    func testHedgeLeavesFillSideScreenAndNonPositiveCountsAreEmpty() {
        let mesh=DastakNativeSceneGeometry.leaves(count:200,seed:90,hedge:true)
        let heights=stride(from:1,to:mesh.positions.count,by:3).map { mesh.positions[$0] }
        XCTAssertLessThan(heights.min() ?? 1,0.2)
        XCTAssertGreaterThan(heights.max() ?? 0,2.5)
        XCTAssertTrue(DastakNativeSceneGeometry.leaves(count:0,seed:0).positions.isEmpty)
        XCTAssertTrue(DastakNativeSceneGeometry.leaves(count:-1,seed:0).indices.isEmpty)
    }
    func testGroceryCameraChangesOnlyOnExplicitCartPresentation() {
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:false),.grocery)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:true),.groceryBilling)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:false),.grocery)
    }
    func testFoodReturnsHomeAfterBasketDismissal() {
        // Basket contents must never select the camera; only presentation does.
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:false),.cafe)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:true),.cafeCounter)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:false),.cafe)
    }
    func testGroceryReferenceRetainsWebEntranceLayoutAndDecorativeFamilies() {
        let reference = DastakGrocerySceneReference.self
        XCTAssertEqual(reference.shelfCenters,[-1.1,1.1])
        XCTAssertEqual(reference.shelfCenterZ,9)
        XCTAssertEqual(reference.shelfLength,10)
        XCTAssertEqual(reference.endcapZ,3.75)
        XCTAssertEqual(reference.entrancePosition,[0.2,1.50,-2.3])
        XCTAssertEqual(reference.entranceTarget,[0.3,1.20,10])
        XCTAssertEqual(reference.entrancePosition[1] - reference.entranceTarget[1],0.3,accuracy:0.0001)
        XCTAssertEqual(reference.shelfLevels.count,5)
        XCTAssertEqual(reference.packageNames.count,12)
        XCTAssertEqual(reference.packageColors.count,reference.packageNames.count)
        XCTAssertEqual(reference.portraitFieldOfView,2*atan(tan(0.6)/0.74)*180 / .pi,accuracy:0.0001)
        XCTAssertEqual(reference.portraitProjectionOffset,-0.26)
        XCTAssertGreaterThan(reference.portraitFieldOfView,68)
        XCTAssertLessThan(reference.portraitFieldOfView,90)
    }
    func testServiceSwitchUsesItsOwnHomeOrBillingScene() {
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:true),.cafeCounter)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:true),.groceryBilling)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:false),.cafe)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:false),.grocery)
    }
    func testPresentedBasketSelectsBillingWithoutChangingHomeScene() {
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:true,basketService:.grocery),.groceryBilling)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:true,basketService:.food),.cafeCounter)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.food,cartPresented:false,basketService:.grocery),.cafe)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:.grocery,cartPresented:false,basketService:.food),.grocery)
    }
    func testFirstBasketOpeningUsesBrowsingServiceInsteadOfRememberedBasket() {
        var navigation = DastakCustomerNavigation()
        navigation.selectService(.food)
        let foodBasket = navigation.service.basketService
        XCTAssertEqual(foodBasket,.food)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:navigation.service,
            cartPresented:true,basketService:foodBasket),.cafeCounter)
        navigation.selectService(.grocery)
        XCTAssertEqual(navigation.service.basketService,.grocery)
        XCTAssertEqual(DastakEnvironmentPlace.customer(service:navigation.service,
            cartPresented:true,basketService:navigation.service.basketService),.groceryBilling)
    }
    func testDeviceClockFallbackIsDayAtNoonAndNightAtMidnight() throws {
        var cal=Calendar(identifier:.gregorian); cal.timeZone=try XCTUnwrap(TimeZone(secondsFromGMT:0))
        let noon=try XCTUnwrap(cal.date(from:DateComponents(year:2026,month:10,day:11,hour:12)))
        let night=try XCTUnwrap(cal.date(from:DateComponents(year:2026,month:10,day:11,hour:0)))
        XCTAssertEqual(DastakEnvironmentWeather.localClock(noon,calendar:cal).daylight,1)
        XCTAssertEqual(DastakEnvironmentWeather.localClock(night,calendar:cal).daylight,0)
        XCTAssertEqual(DastakEnvironmentWeather.localClock(noon,calendar:cal).precipitation,0)
    }
    func testNativeStaffResourcesContainRelaxedPoseAndActualBlinkGeometry() throws {
        let url=try XCTUnwrap(DastakEnvironmentResources.url("native-staff",extension:"json"))
        let root=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        XCTAssertEqual(root["license"] as? String,"CC0-1.0")
        XCTAssertEqual(root["sourceSHA256"] as? String,"adf9f73504acff6a6747901fb804d3157c92bc37544bb3843af25e5cb838151f")
        let meshes=try XCTUnwrap(root["meshes"] as? [[String:Any]])
        XCTAssertEqual(meshes.count,6)
        XCTAssertEqual(meshes.filter { $0["closed"] != nil }.count,3)
        let bytes=try Data(contentsOf:XCTUnwrap(DastakEnvironmentResources.url("native-staff",extension:"bin")))
        for m in meshes {
            let count=try XCTUnwrap(m["count"] as? Int)
            let start=try XCTUnwrap(m["positions"] as? Int)
            XCTAssertLessThanOrEqual(start+count*12,bytes.count)
            if let closed=m["closed"] as? Int {
                XCTAssertLessThanOrEqual(closed+count*12,bytes.count)
                XCTAssertNotEqual(bytes.subdata(in:start..<(start+count*12)),bytes.subdata(in:closed..<(closed+count*12)))
            }
        }
        let hands=try XCTUnwrap(root["hands"] as? [[Double]])
        XCTAssertTrue(hands.allSatisfy { $0[1] < 0.95 && abs($0[0]) < 0.3 })
    }
}
