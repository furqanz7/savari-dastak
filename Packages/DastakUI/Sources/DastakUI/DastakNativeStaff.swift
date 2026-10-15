#if os(iOS)
import SceneKit
import UIKit

/// Baked relaxed CC0 character, real eyelid geometry. No runtime IK/hand targeting.
@MainActor
enum DastakNativeStaff {
    struct Asset: Decodable {
        let version: Int
        let sourceSHA256: String
        let license: String
        let meshes: [Mesh]
        let materials: [Material]
    }
    struct Mesh: Decodable {
        let name: String
        let count, indicesCount, material, positions, normals, uv, indices: Int
        let closed: Int?
    }
    struct Material: Decodable { let texture: String; let normal: String?; let roughness: Double; let masked, doubleSided: Bool }

    static func load() throws -> (SCNNode, [SCNMorpher]) {
        guard let manifest = Bundle.module.url(forResource: "native-staff", withExtension: "json"),
              let buffer = Bundle.module.url(forResource: "native-staff", withExtension: "bin") else { throw CocoaError(.fileReadNoSuchFile) }
        let asset = try JSONDecoder().decode(Asset.self, from: Data(contentsOf: manifest))
        guard asset.version == 1, asset.license == "CC0-1.0" else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: buffer)
        let root = SCNNode(); root.name = "CC0 cashier, relaxed arms"
        // glTF's authored character faces +Z; the native counter looks toward -Z.
        let body = SCNNode(); body.eulerAngles.y = .pi; root.addChildNode(body)
        var morphers: [SCNMorpher] = []
        let materials = asset.materials.map { entry -> SCNMaterial in
            let m = SCNMaterial(); m.lightingModel = .physicallyBased
            if let url = Bundle.module.url(forResource: entry.texture, withExtension: nil) {
                m.diffuse.contents = UIImage(contentsOfFile: url.path)
            }
            if let name = entry.normal, let url = Bundle.module.url(forResource:name,withExtension:nil) { m.normal.contents = UIImage(contentsOfFile:url.path) }
            m.roughness.contents = entry.roughness; m.metalness.contents = 0
            m.isDoubleSided = entry.doubleSided
            if entry.masked { m.transparencyMode = .aOne; m.blendMode = .alpha; m.writesToDepthBuffer = false }
            return m
        }
        for mesh in asset.meshes {
            func source(_ offset: Int, _ semantic: SCNGeometrySource.Semantic, _ components: Int) throws -> SCNGeometrySource {
                guard offset >= 0, mesh.count > 0, offset + mesh.count*components*4 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
                return SCNGeometrySource(data: data, semantic: semantic, vectorCount: mesh.count,
                    usesFloatComponents: true, componentsPerVector: components, bytesPerComponent: 4,
                    dataOffset: offset, dataStride: components*4)
            }
            guard mesh.material < materials.count, mesh.indices + mesh.indicesCount*4 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            let element = SCNGeometryElement(data: data.subdata(in: mesh.indices..<(mesh.indices+mesh.indicesCount*4)),
                primitiveType: .triangles, primitiveCount: mesh.indicesCount/3, bytesPerIndex: 4)
            let normals = try source(mesh.normals, .normal, 3), uv = try source(mesh.uv, .texcoord, 2)
            let geometry = SCNGeometry(sources: [try source(mesh.positions,.vertex,3), normals, uv], elements: [element])
            geometry.materials = [materials[mesh.material]]
            let node = SCNNode(geometry: geometry); node.name = mesh.name
            if let closed = mesh.closed {
                let target = SCNGeometry(sources: [try source(closed,.vertex,3), normals, uv], elements: [element])
                let morpher = SCNMorpher(); morpher.targets = [target]; morpher.calculationMode = .normalized
                node.morpher = morpher; morphers.append(morpher)
            }
            body.addChildNode(node)
        }
        return (root, morphers)
    }
}
#endif
