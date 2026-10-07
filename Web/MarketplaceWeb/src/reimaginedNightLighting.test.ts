import { it, expect } from "vitest";
import { NullEngine } from "@babylonjs/core/Engines/nullEngine";
import { Scene } from "@babylonjs/core/scene";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { PointLight } from "@babylonjs/core/Lights/pointLight";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import { createNightLighting } from "./reimaginedNightLighting";

it("fades exterior fixtures at dusk without lighting the interior or competing with its lamps", () => {
  const engine = new NullEngine(), scene = new Scene(engine);
  try {
    const exterior = new TransformNode("exterior", scene);
    const paving = MeshBuilder.CreateGround("paving", {}, scene); paving.parent = exterior;
    paving.material = new PBRMaterial("paving", scene);
    const interior = MeshBuilder.CreateBox("interior", {}, scene);
    const existing = new PointLight("ceiling-bounce-test", Vector3.Zero(), scene);
    const lighting = createNightLighting(scene, exterior);
    const lamps = scene.lights.filter(l => l.name.includes("night-spill"));
    expect(lamps).toHaveLength(3);
    expect(existing.excludedMeshes).toContain(paving);
    expect(lamps.every(l => l.includedOnlyMeshes.includes(paving) && !l.includedOnlyMeshes.includes(interior))).toBe(true);
    expect(lighting.update(1,true)).toBe(0);
    expect(lamps.every(l=>l.intensity===0)).toBe(true);
    expect(lighting.update(.325,true)).toBeCloseTo(.5);
    expect(lighting.update(0,true)).toBe(1);
    expect(lamps.every(l=>l.intensity>0)).toBe(true);
    expect(lighting.update(0,false)).toBe(0);
    expect(lamps.every(l=>l.intensity===0)).toBe(true);
  } finally { scene.dispose(); engine.dispose(); }
});

it("keeps night spill off storefront panes without changing glass or sky lighting", () => {
  const engine = new NullEngine(), scene = new Scene(engine);
  try {
    const exterior = new TransformNode("exterior", scene);
    const glass = new PBRMaterial("shared-glass", scene);
    glass.alpha = .3; glass.roughness = .2;
    const panes = ["storefront-window", "sliding-door-glass"].map(name => {
      const pane = MeshBuilder.CreateBox(name, {}, scene);
      pane.parent = exterior; pane.material = glass; return pane;
    });
    const fridge = MeshBuilder.CreateBox("fridge", {}, scene); fridge.material = glass;
    const paving = MeshBuilder.CreateGround("paving", {}, scene);
    paving.parent = exterior; paving.material = new PBRMaterial("paving", scene);
    const sky = new PointLight("soft-skylight", Vector3.Zero(), scene);
    const lighting = createNightLighting(scene, exterior);
    lighting.update(0, true);
    const lamps = scene.lights.filter(lamp => lamp.name.includes("night-spill"));
    expect(lamps).toHaveLength(3);
    for (const lamp of lamps) {
      expect(lamp.canAffectMesh(paving)).toBe(true);
      expect(lamp.canAffectMesh(fridge)).toBe(false);
      for (const pane of panes) expect(lamp.canAffectMesh(pane)).toBe(false);
    }
    for (const pane of panes) expect(sky.canAffectMesh(pane)).toBe(true);
    expect(glass.alpha).toBe(.3);
    expect(glass.roughness).toBe(.2);
    expect(glass.directIntensity).toBe(1);
    expect(glass.environmentIntensity).toBe(1);
  } finally { scene.dispose(); engine.dispose(); }
});
