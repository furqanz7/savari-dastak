import Foundation
import XCTest
@testable import DastakUI

final class DastakAPNSEnvironmentTests: XCTestCase {
    func testDevelopmentSigningSelectsSandboxRegardlessOfReleaseOptimization() throws {
        XCTAssertEqual(DastakAPNSEnvironment.resolve(embeddedProfile: try profile("development")), .sandbox)
    }

    func testDistributionSigningSelectsProductionRegardlessOfDebugCompilation() throws {
        XCTAssertEqual(DastakAPNSEnvironment.resolve(embeddedProfile: try profile("production")), .production)
    }

    func testAppStoreAndTestFlightWithoutEmbeddedProfileUseProduction() {
        XCTAssertEqual(DastakAPNSEnvironment.resolve(embeddedProfile: nil), .production)
    }

    func testSimulatorUsesSandboxWithoutInferringFromCompilerCondition() throws {
        XCTAssertEqual(DastakAPNSEnvironment.resolve(embeddedProfile: nil, isSimulator: true), .sandbox)
        XCTAssertEqual(DastakAPNSEnvironment.resolve(embeddedProfile: try profile("production"), isSimulator: true), .sandbox)
    }

    func testPresentProfileWithMissingUnknownOrWrongTypedEntitlementFailsClosed() throws {
        for value: Any? in [nil, "sandbox", "", "Development", true, 1] {
            XCTAssertNil(DastakAPNSEnvironment.resolve(embeddedProfile: try profile(value)))
        }
    }

    func testMalformedTruncatedAndOversizedProfilesFailClosed() throws {
        for data in [Data(), Data("not a profile".utf8), Data("<?xml version=\"1.0\"?><plist>".utf8),
                     Data(repeating: 0, count: 1_048_577)] {
            XCTAssertNil(DastakAPNSEnvironment.resolve(embeddedProfile: data))
        }
    }

    func testXMLInsideBinaryEnvelopePreservesEnvironment() throws {
        let data = Data([0x30, 0x82, 0xff, 0x00]) + (try profile("development")) + Data([0x00, 0xff])
        XCTAssertEqual(DastakAPNSEnvironment.resolve(embeddedProfile: data), .sandbox)
    }

    private func profile(_ environment: Any?) throws -> Data {
        let entitlements: [String: Any] = environment.map { ["aps-environment": $0] } ?? [:]
        return try PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements],
            format: .xml, options: 0)
    }
}
