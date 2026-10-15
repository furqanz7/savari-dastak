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
                                        0x244f8b,0x903657,0xd77828,0x64a441,0x8e5436,0x386e88,
                                        0xf0f3e9,0x9ebdc8,0xe3b0ac,0xe5a54b,0x719c79,0xc9d9cf]
    static let packageNames = ["GRAINS","OATS","SPICE","TEA","CRUNCH","PASTA",
                               "COCOA","BLEND","COFFEE","CRACKERS","NUTS","SPRING",
                               "MILK","DAIRY","YOGHURT","ORANGE","APPLE","KEFIR"]

    enum PackShape { case carton, pouch, jar, bottle, tin, tub }
    static let packageShapes: [PackShape] = [.pouch,.carton,.jar,.tin,.pouch,.carton,
        .tin,.bottle,.jar,.carton,.pouch,.bottle,.carton,.bottle,.tub,.carton,.bottle,.bottle]

    /// Stable merchandising, not live inventory. Small facings remain grouped, but
    /// neighbouring bays, shelf levels and sides do not repeat the same stripe.
    static func stockFamily(slot: Int, level: Int, bay: Int, chilled: Bool = false) -> Int {
        if chilled {
            let sections = [[12,13,14,12,15], [15,16,15,17,14], [13,12,17,14,16]]
            return sections[bay % sections.count][(level + (slot >= 3 ? 1 : 0)) % 5]
        }
        let groups = [0,0,1,1,1,2,2,3,3,3,3]
        let assortment = [0,5,2,8,3,6,1,9,10,4,7,11]
        return assortment[(groups[slot % groups.count] + (slot / groups.count)*4 + level*5 + bay*3) % assortment.count]
    }

    static func stockSize(slot: Int, level: Int, bay: Int) -> Double {
        // Under the 0.38 m shelf pitch, including bottle caps and pouch seals.
        0.235 + Double((slot / 2 + level*3 + bay) % 5)*0.014
    }
}
