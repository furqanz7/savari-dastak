import Foundation
import XCTest
@testable import DastakUI

@MainActor
final class DastakSceneWeatherChoiceTests: XCTestCase {
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
