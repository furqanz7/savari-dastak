import Foundation
import CoreLocation
import XCTest
@testable import DastakUI

@MainActor
final class DastakSceneWeatherChoiceTests: XCTestCase {
    func testAppleWeatherReceivesOnlyRoundedAreaCoordinates() {
        let source = CLLocation(latitude:12.683847,longitude:78.627682)
        let area = DastakSceneWeather.weatherLocation(source)
        XCTAssertEqual(area.coordinate.latitude,12.68,accuracy:0.000001)
        XCTAssertEqual(area.coordinate.longitude,78.63,accuracy:0.000001)
        let western = DastakSceneWeather.weatherLocation(CLLocation(latitude:-12.683847,longitude:-78.627682))
        XCTAssertEqual(western.coordinate.latitude,-12.68,accuracy:0.000001)
        XCTAssertEqual(western.coordinate.longitude,-78.63,accuracy:0.000001)
    }
    func testFirstInstallAsksOnceAndNotNowSurvivesRelaunch() throws {
        let suite = "dastak.weather-test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let weather = DastakSceneWeather(defaults: defaults)
        XCTAssertTrue(weather.needsFirstLaunchChoice)
        XCTAssertFalse(weather.enabled)
        weather.skipFirstLaunchWeather()
        let relaunched = DastakSceneWeather(defaults: defaults)
        XCTAssertFalse(relaunched.needsFirstLaunchChoice)
        XCTAssertFalse(relaunched.enabled)
    }

    func testConnectedChoiceRestoresAndDisconnectPersists() throws {
        let suite = "dastak.weather-test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Restore a prior opt-in without requesting location or fetching weather in a test.
        defaults.set(DastakSceneWeatherChoice.connected.rawValue, forKey: DastakSceneWeatherChoice.key)
        let weather = DastakSceneWeather(defaults: defaults)
        XCTAssertFalse(weather.needsFirstLaunchChoice)
        XCTAssertTrue(weather.enabled)
        weather.disable()
        let relaunched = DastakSceneWeather(defaults: defaults)
        XCTAssertFalse(relaunched.needsFirstLaunchChoice)
        XCTAssertFalse(relaunched.enabled)
    }
}
