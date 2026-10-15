#if os(iOS)
import SceneKit
import UIKit

/// Fit the café apron and shallow cap to the existing baked character, as on the web.
@MainActor
enum DastakNativeUniform {
    static func attach(to root: SCNNode) {
        var triangles: [[SCNVector3]] = []
        var hairBounds: (SCNVector3,SCNVector3)?
        root.enumerateChildNodes { mesh,_ in
            if mesh.name == "short02" {
                let (lo,hi)=mesh.boundingBox
                hairBounds=(SCNVector3(-hi.x,lo.y,-hi.z),SCNVector3(-lo.x,hi.y,-lo.z))
            }
            guard mesh.name == "male_casualsuit01", let geometry=mesh.geometry,
                  let source=geometry.sources(for:.vertex).first else { return }
            let vertices=(0..<source.vectorCount).map { index -> SCNVector3 in
                let offset=source.dataOffset+index*source.dataStride
                func value(_ axis:Int)->Float {
                    source.data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:offset+axis*4,as:Float.self) }
                }
                return SCNVector3(-value(0),value(1),-value(2))
            }
            for element in geometry.elements {
                guard element.primitiveType == .triangles, element.bytesPerIndex == 4 else { continue }
                let indices=element.data.withUnsafeBytes { bytes in
                    (0..<element.primitiveCount*3).map { Int(bytes.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)) }
                }
                for i in stride(from:0,to:indices.count,by:3) {
                    guard indices[i..<i+3].allSatisfy({vertices.indices.contains($0)}) else { continue }
                    let t=indices[i..<i+3].map { vertices[$0] }
                    if t.contains(where:{$0.y>0.72 && $0.y<1.5 && abs($0.x)<0.3}) { triangles.append(t) }
                }
            }
        }
        func fitted(_ x:Float,_ y:Float,_ clearance:Float=0.018)->SCNVector3 {
            var z=Float.infinity
            for t in triangles {
                let a=t[0],b=t[1],c=t[2]
                let det=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
                guard abs(det)>1e-9 else { continue }
                let u=((b.y-c.y)*(x-c.x)+(c.x-b.x)*(y-c.y))/det
                let v=((c.y-a.y)*(x-c.x)+(a.x-c.x)*(y-c.y))/det
                if u>=0 && v>=0 && u+v<=1 { z=min(z,u*a.z+v*b.z+(1-u-v)*c.z) }
            }
            return SCNVector3(x,y,(z.isFinite ? z : -0.12)-clearance)
        }
        let cloth=SCNMaterial(); cloth.lightingModel = .physicallyBased
        cloth.diffuse.contents=UIColor(red:0.39,green:0.235,blue:0.21,alpha:1)
        cloth.roughness.contents=0.97; cloth.isDoubleSided=true
        let trim=SCNMaterial(); trim.lightingModel = .physicallyBased
        trim.diffuse.contents=UIColor(red:0.21,green:0.235,blue:0.22,alpha:1)
        trim.roughness.contents=0.9; trim.isDoubleSided=true
        func ribbon(_ name:String,_ rows:[[SCNVector3]],_ material:SCNMaterial) {
            guard let first=rows.first,first.count>1,rows.count>1 else { return }
            var indices:[Int32]=[]
            for r in 0..<rows.count-1 { for c in 0..<first.count-1 {
                let a=Int32(r*first.count+c),b=a+1,d=a+Int32(first.count),e=d+1
                indices.append(contentsOf:[a,d,b,b,d,e])
            } }
            let vertices=rows.flatMap{$0}
            var normals=Array(repeating:SCNVector3Zero,count:vertices.count)
            for i in stride(from:0,to:indices.count,by:3) {
                let a=Int(indices[i]),b=Int(indices[i+1]),c=Int(indices[i+2])
                let p=vertices[a],q=vertices[b],r=vertices[c]
                let ux=q.x-p.x,uy=q.y-p.y,uz=q.z-p.z,vx=r.x-p.x,vy=r.y-p.y,vz=r.z-p.z
                let n=SCNVector3(uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx)
                for index in [a,b,c] { normals[index]=SCNVector3(normals[index].x+n.x,normals[index].y+n.y,normals[index].z+n.z) }
            }
            normals=normals.map { n in
                let length=sqrt(n.x*n.x+n.y*n.y+n.z*n.z)
                return length>1e-8 ? SCNVector3(n.x/length,n.y/length,n.z/length) : SCNVector3(0,0,-1)
            }
            let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],
                elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
            geometry.materials=[material]
            let node=SCNNode(geometry:geometry); node.name=name; root.addChildNode(node)
        }
        let profile:[(Float,Float)]=[(0.78,0.158),(1.04,0.154),(1.18,0.144),(1.26,0.103),(1.36,0.079)]
        let rows=(0..<25).map { j -> [SCNVector3] in
            let t=Float(j)/24*4, k=min(3,Int(t)), f=t-Float(k)
            let y=profile[k].0+(profile[k+1].0-profile[k].0)*f
            let width=profile[k].1+(profile[k+1].1-profile[k].1)*f
            return (0..<25).map { i in
                let u=Float(i)/12-1,fold=0.004*sin(u*13+Float(j)*0.16)*(1-u*u)
                var p=fitted(u*width,max(1.07,y),0.02+abs(fold))
                if y<1.07 { p.z=min(p.z,fitted(u*width,y,0.02+abs(fold)).z) }
                p.y=y; return p
            }
        }
        ribbon("fitted canvas apron",rows,cloth)
        ribbon("tonal apron pocket",[1.13,1.20].map { y in (0..<13).map { fitted(-0.055+Float($0)*0.009,y,0.034) } },cloth)
        for side:Float in [-1,1] {
            ribbon("flat woven apron strap",(0..<10).map { i in
                let t=Float(i)/9,x=side*(0.074+t*0.038),y=1.355+t*0.065
                return [fitted(x-0.006,y),fitted(x+0.006,y)]
            },cloth)
        }
        if let (lo,hi)=hairBounds {
            let cx=(lo.x+hi.x)/2,cz=(lo.z+hi.z)/2,rx=(hi.x-lo.x)*0.525,rz=(hi.z-lo.z)*0.525,rim=hi.y-0.048
            ribbon("hair-fitted shallow cap",(0..<13).map { j in
                let phi=Float(j)/12*Float.pi/2
                return (0..<33).map { i in
                    let theta=Float(i)/32*2*Float.pi
                    return SCNVector3(cx+cos(theta)*rx*sin(phi),rim+cos(phi)*0.058,cz+sin(theta)*rz*sin(phi))
                }
            },trim)
            ribbon("curved cap visor",(0..<5).map { j in (0..<25).map { i in
                let u=Float(i)/12-1,t=Float(j)/4,arc=sqrt(max(0,1-u*u))
                return SCNVector3(cx+u*rx*0.92,rim-0.006-t*0.012+u*u*0.012,cz-rz*0.64-arc*(0.025+t*0.07))
            } },trim)
        }
    }
}
#endif
