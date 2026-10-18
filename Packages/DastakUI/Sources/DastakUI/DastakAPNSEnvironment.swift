import Foundation

/// APNs follows signing, not compiler optimization or the DEBUG condition.
/// Development/ad-hoc apps carry their provisioning profile; App Store and
/// TestFlight installations without one use production APNs (including when
/// their StoreKit receipt is a sandbox receipt).
enum DastakAPNSEnvironment: String, Sendable {
    case sandbox, production

    static var current: Self? {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            return .production
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return resolve(embeddedProfile: data)
        #endif
    }

    static func resolve(embeddedProfile: Data?, isSimulator: Bool = false) -> Self? {
        if isSimulator { return .sandbox }
        guard let embeddedProfile else { return .production }
        // Read only our own signed bundle. Extract the plist from the CMS
        // envelope without private Security APIs or a network/receipt request.
        // A present but unreadable/unrecognized profile must not guess a host.
        guard embeddedProfile.count <= 1_048_576,
              let start = embeddedProfile.range(of: Data("<?xml".utf8)),
              let end = embeddedProfile.range(of: Data("</plist>".utf8),
                  in: start.lowerBound..<embeddedProfile.endIndex),
              let object = try? PropertyListSerialization.propertyList(
                  from: embeddedProfile.subdata(in: start.lowerBound..<end.upperBound),
                  options: [], format: nil),
              let profile = object as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String else { return nil }
        switch environment {
        case "development": return .sandbox
        case "production": return .production
        default: return nil
        }
    }
}
