import { Scene } from "@babylonjs/core/scene";
import { Mesh } from "@babylonjs/core/Meshes/mesh";
import { VertexData } from "@babylonjs/core/Meshes/mesh.vertexData";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import type { Material } from "@babylonjs/core/Materials/material";

export function plantingRandom(seed: number) {
  return () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
}

// Folded, pointed leaves, not opaque crown blobs or camera-facing billboards.
// One vertex buffer/draw per crown, with deterministic variation and no textures.
export function leafSpray(scene: Scene, name: string, material: Material, count: number,
  seed: number, sample: (random: () => number) => { center: Vector3; size: number }) {
  const random = plantingRandom(seed), positions: number[] = [], indices: number[] = [], colors: number[] = [];
  for (let i = 0; i < count; i++) {
    const { center, size } = sample(random);
    const angle = random() * Math.PI * 2, pitch = (random() - .4) * 2.4;
    const long = new Vector3(Math.cos(angle) * Math.cos(pitch), Math.sin(pitch), Math.sin(angle) * Math.cos(pitch));
    const across = Vector3.Cross(long, Vector3.Up()).normalize();
    const normal = Vector3.Cross(across, long).normalize();
    const offset = positions.length / 3, tint = .48 + random() * .52;
    for (const [u, v, fold] of [[-1, 0, 0], [-.55, -.25, 0], [0, -.34, .01], [.55, -.25, 0], [1, 0, 0], [.55, .25, 0], [0, .34, .01], [-.55, .25, 0], [0, 0, .055]]) {
      const p = center.add(long.scale(u * size)).add(across.scale(v * size)).add(normal.scale(fold * size));
      positions.push(p.x, p.y, p.z);
      colors.push(tint * (.78 + center.y * .025), tint, tint * .58, 1);
    }
    for (let j = 0; j < 8; j++) indices.push(offset + j, offset + (j + 1) % 8, offset + 8);
  }
  const data = new VertexData(); data.positions = positions; data.indices = indices; data.colors = colors;
  const normals: number[] = []; VertexData.ComputeNormals(positions, indices, normals); data.normals = normals;
  const mesh = new Mesh(name, scene); data.applyToMesh(mesh); mesh.material = material;
  mesh.isPickable = false; mesh.receiveShadows = true;
  return mesh;
}
