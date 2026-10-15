import Foundation

/// Approved web exterior coordinates, translated to the native room's doorway.
/// The room stays put so Grocery/billing framing is unaffected by exterior parity.
enum DastakOutsideSceneReference {
    static let webDoorwayZ = -7.16
    static let nativeDoorwayZ = -3.2
    static func z(_ webZ: Double) -> Double { webZ + nativeDoorwayZ-webDoorwayZ }
    static let centerX = -0.5
    static let frontageWidth = 7.5
    static func position(portrait: Bool) -> [Double] { [centerX,1.7,z(portrait ? -19 : -16)] }
    static func target(portrait: Bool) -> [Double] { [centerX,portrait ? 0.35 : 2.45,z(-7)] }
    static func fieldOfView(portrait: Bool) -> Double {
        (portrait ? 2*atan(tan(1.15/2)/0.74) : 1.15)*180 / .pi
    }
}
