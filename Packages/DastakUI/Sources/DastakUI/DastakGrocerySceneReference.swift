import Foundation

/// Reference values from reimaginedGroceryScene.ts, not catalogue/SKU data.
enum DastakGrocerySceneReference {
    static let shelfCenters = [-1.1, 1.1]
    static let shelfCenterZ = 9.0
    static let shelfLength = 10.0
    static let shelfWidth = 1.0
    static let shelfLevels = (0..<5).map { 0.33 + Double($0) * 0.38 }
    static let endcapZ = 3.75
    static let leftWallX = -3.9
    static let rightWallX = 3.0
    static let ceilingHeight = 3.8
    // Owner-adjusted eye level, preserving the viewing angle.
    static let entrancePosition = [0.2, 1.50, -2.3]
    static let entranceTarget = [0.3, 1.20, 10.0]
    // Web reserves the bottom 26% for controls. Overscan the native full-height
    // scenery to preserve its horizontal coverage without reintroducing a blank band.
    static let portraitFieldOfView = 2 * atan(tan(1.2 / 2) / 0.74) * 180 / .pi
    static let portraitProjectionOffset = -0.26
    static let packageColors: [UInt32] = [0xae7732,0xecd3a0,0xa92923,0x215941,0xecb82d,0xe5eee9,
                                        0x244f8b,0x903657,0xd77828,0x64a441,0x8e5436,0x386e88]
    static let packageNames = ["GRAINS","OATS","SPICE","TEA","CRUNCH","MILK",
                               "COCOA","BLEND","COFFEE","CRACKERS","NUTS","SPRING"]
}
