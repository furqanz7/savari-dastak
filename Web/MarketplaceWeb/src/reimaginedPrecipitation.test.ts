import { expect, it } from "vitest";
import { NullEngine } from "@babylonjs/core/Engines/nullEngine";
import { Scene } from "@babylonjs/core/scene";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { createPrecipitation } from "./reimaginedPrecipitation";

it("uses separate bounded batches, wind-driven rain and slower snow; clears all effects", () => {
  const engine = new NullEngine(), scene = new Scene(engine);
  try {
    const effect = createPrecipitation(scene, new TransformNode("outside", scene));
    const rain = scene.getMeshByName("weather-precipitation")!, snow = scene.getMeshByName("weather-snowflakes")!;
    const splashes = scene.getMeshByName("rain-ground-splashes")!;
    expect(scene.meshes).toHaveLength(3);
    expect(effect.update(0,"rain",2,20,0,1,false)).toBe(260);
    const before = Array.from(rain.getVerticesData("position")!);
    effect.update(.01,"rain",2,20,0,1,false);
    const after = rain.getVerticesData("position")!;
    expect(after[0]-before[0]).toBeCloseTo(.005,4);
    expect(before[1]-after[1]).toBeGreaterThan(.06);
    expect(splashes.isEnabled()).toBe(true);
    effect.update(0,"snow",1,0,0,1,false);
    const snowBefore = Array.from(snow.getVerticesData("position")!);
    effect.update(.01,"snow",1,0,0,1,false);
    expect(snowBefore[1]-snow.getVerticesData("position")![1]).toBeLessThan(.009);
    expect(snowBefore[1]-snow.getVerticesData("position")![1]).toBeGreaterThan(.003);
    expect(rain.isEnabled()).toBe(false); expect(splashes.isEnabled()).toBe(false);
    expect(effect.update(.1,"snow",100,0,0,1,false)).toBe(280);
    for(let i=0;i<300;i++) effect.update(1/60,"rain",2,-35,8,1,false);
    expect(scene.meshes).toHaveLength(3);
    expect(effect.update(.1,"rain",2,0,0,1,true)).toBe(0);
    expect(scene.meshes.every(m=>!m.isEnabled())).toBe(true);
    effect.update(.1,"snow",1,0,0,1,false); effect.reset();
    expect(scene.meshes.every(m=>!m.isEnabled())).toBe(true);
    expect(effect.update(.1,null,2,0,0,1,false)).toBe(0);
    expect(effect.update(.1,"snow",0,0,0,1,false)).toBe(0);
  } finally { scene.dispose(); engine.dispose(); }
});

it("caps suspended-tab steps and keeps precipitation outside the canopy", () => {
  const engine = new NullEngine(), scene = new Scene(engine);
  try {
    const a=createPrecipitation(scene,new TransformNode("a",scene)), b=createPrecipitation(scene,new TransformNode("b",scene));
    a.update(600,"rain",100,30,10,1,false); b.update(.1,"rain",100,30,10,1,false);
    const rains=scene.meshes.filter(m=>m.name==="weather-precipitation");
    expect(rains[0].getVerticesData("position")).toEqual(rains[1].getVerticesData("position"));
    const positions=rains[0].getVerticesData("position")!;
    for(let i=2;i<positions.length;i+=3) expect(positions[i]).toBeLessThanOrEqual(-8.7);
  } finally { scene.dispose(); engine.dispose(); }
});
