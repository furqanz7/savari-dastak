import { expect, it } from "vitest";
import { NullEngine } from "@babylonjs/core/Engines/nullEngine";
import { Scene } from "@babylonjs/core/scene";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import { leafSpray } from "./reimaginedPlanting";

it("batches deterministic, finite leaf geometry without per-leaf meshes", () => {
  const engine = new NullEngine(), scene = new Scene(engine);
  try {
    const material = new PBRMaterial("leaves", scene);
    const sample = (r: () => number) => ({ center: new Vector3(r(), r(), r()), size: .1 });
    const a = leafSpray(scene, "a", material, 100, 42, sample);
    const b = leafSpray(scene, "b", material, 100, 42, sample);
    expect(scene.meshes).toHaveLength(2);
    expect(a.getTotalVertices()).toBe(900);
    expect(a.getIndices()).toHaveLength(2400);
    expect(a.getVerticesData("position")).toEqual(b.getVerticesData("position"));
    expect(a.getVerticesData("normal")!.every(Number.isFinite)).toBe(true);
    expect(a.isPickable).toBe(false);
    expect(a.receiveShadows).toBe(true);
  } finally { scene.dispose(); engine.dispose(); }
});
