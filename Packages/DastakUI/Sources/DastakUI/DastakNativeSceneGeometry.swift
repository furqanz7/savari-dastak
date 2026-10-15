import Foundation

/// Deterministic decorative buffers, independent of accounts, catalogues and render engines.
enum DastakNativeSceneGeometry {
    struct Mesh {
        var positions: [Float] = []
        var normals: [Float] = []
        var colors: [Float] = []
        var indices: [Int32] = []
    }
    struct Random {
        var seed: UInt32
        mutating func next() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
    }

    /// One folded-leaf buffer per crown; no leaf-node/billboard/crown-sphere forest.
    static func leaves(count: Int, seed: UInt32, hedge: Bool = false) -> Mesh {
        var random = Random(seed:seed), mesh = Mesh()
        let contour: [(Double,Double,Double)] = [(-1,0,0),(-0.55,-0.25,0),(0,-0.34,0.01),
            (0.55,-0.25,0),(1,0,0),(0.55,0.25,0),(0,0.34,0.01),(-0.55,0.25,0),(0,0,0.055)]
        for _ in 0..<max(0,count) {
            let angle=random.next()*2*Double.pi, h=random.next()*2-1
            let radius=sqrt(max(0,1-h*h))*(0.75+random.next()*0.55)
            let center = hedge ? [random.next()*2.2-1.1,random.next()*2.7,random.next()*0.7-0.35]
                : [cos(angle)*radius,h*1.05,sin(angle)*radius]
            let size=(hedge ? 0.07 : 0.10)+random.next()*0.07
            let yaw=random.next()*2*Double.pi, pitch=(random.next()-0.4)*2.4
            let long=[cos(yaw)*cos(pitch),sin(pitch),sin(yaw)*cos(pitch)]
            let across=[-sin(yaw),0.0,cos(yaw)]
            let normal=[-cos(yaw)*sin(pitch),cos(pitch),-sin(yaw)*sin(pitch)]
            let tint=Float(0.48+random.next()*0.52), offset=Int32(mesh.positions.count/3)
            for (u,v,fold) in contour {
                for axis in 0..<3 {
                    mesh.positions.append(Float(center[axis]+size*(long[axis]*u+across[axis]*v+normal[axis]*fold)))
                    mesh.normals.append(Float(normal[axis]))
                }
                mesh.colors.append(contentsOf:[tint*0.78,tint,tint*0.58,1])
            }
            for j in 0..<8 { mesh.indices.append(contentsOf:[offset+Int32(j),offset+Int32((j+1)%8),offset+8]) }
        }
        return mesh
    }
}
