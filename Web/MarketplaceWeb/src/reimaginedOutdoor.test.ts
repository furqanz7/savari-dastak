import { expect, it } from "vitest";
import { NullEngine } from "@babylonjs/core/Engines/nullEngine";
import { Scene } from "@babylonjs/core/scene";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { createOutdoor } from "./reimaginedOutdoor";
import type { OutdoorWeather } from "./reimaginedWeather";

it("drives tree sway and rain from weather, respects reduced motion and drops stale conditions", () => {
  const engine = new NullEngine(); const scene = new Scene(engine);
  try {
    const exterior = new TransformNode("exterior", scene); const outdoor = createOutdoor(scene, exterior);
    for (const name of ["left-evergreen-screen", "right-evergreen-screen"]) {
      const screen = scene.getMeshByName(name)!;
      expect(screen.parent).toBe(exterior);
      const bounds = screen.getBoundingInfo().boundingBox;
      expect(bounds.maximumWorld.y).toBeGreaterThan(3.3);
      expect(bounds.minimumWorld.y).toBeLessThan(0);
    }
    const now = Date.parse("2026-10-03T12:00:00Z");
    const weather: OutdoorWeather = { observedAt: now, fetchedAt: now, temperature: 24, cloud: .8, precipitation: 2, code: 61, wind: 30, gust: 45, direction: 0, isDay: true, sunrise: [now - 6 * 3600_000], sunset: [now + 6 * 3600_000], timezone: "UTC" };
    expect(outdoor.update(now, 1, weather, false)).toMatchObject({ daylight: 1, wet: true, wind: 30 });
    const tree = scene.getTransformNodeByName("wind-tree-0")!;
    expect(tree.rotation.length()).toBeGreaterThan(0);
    const canopy=scene.getMeshByName("tree-canopy-0-0")!,otherCanopy=scene.getMeshByName("tree-canopy-0-1")!;
    expect(canopy.rotation.length()).toBeGreaterThan(tree.rotation.length());
    expect(canopy.rotation.equals(otherCanopy.rotation)).toBe(false);
    expect(scene.getMeshByName("hedge-top--1-0")!.rotation.length()).toBeGreaterThan(0);
    expect(scene.getMeshByName("weather-precipitation")?.isEnabled()).toBe(true);
    expect(scene.getMeshByName("rain-ripple")?.isEnabled()).toBe(true);
    const count=scene.meshes.length;
    for(let i=0;i<100;i++)outdoor.update(now,1/60,weather,false);
    expect(scene.meshes.length).toBe(count);
    outdoor.update(now, 1, weather, true);
    expect(tree.rotation.z).toBeCloseTo(0);
    expect(canopy.rotation.length()).toBe(0);
    expect(scene.getMeshByName("rain-ripple")?.isEnabled()).toBe(false);
    expect(scene.getMeshByName("weather-precipitation")?.isEnabled()).toBe(false);
    expect(outdoor.update(now + 3600_000, 1, weather, false)).toMatchObject({ wet: false, wind: 0 });
    expect(scene.getMeshByName("weather-precipitation")?.isEnabled()).toBe(false);
  } finally { scene.dispose(); engine.dispose(); }
});

it("keeps gentle idle foliage without inventing rain, directs precipitation with wind, and caps suspended-tab steps",()=>{
  const engine=new NullEngine(),scene=new Scene(engine);
  try{
    const outdoor=createOutdoor(scene,new TransformNode("exterior",scene)),now=Date.now();
    outdoor.update(now,1/60,null,false);
    expect(scene.getMeshByName("tree-canopy-0-0")!.rotation.length()).toBeGreaterThan(0);
    expect(scene.getMeshByName("weather-precipitation")!.isEnabled()).toBe(false);
    const weather:OutdoorWeather={observedAt:now,fetchedAt:now,temperature:20,cloud:.8,precipitation:2,code:61,wind:35,gust:50,direction:90,isDay:true,sunrise:[now-3600000],sunset:[now+3600000],timezone:"UTC"};
    for(let i=0;i<120;i++)outdoor.update(now,1/60,weather,false);
    const rain=scene.getMeshByName("weather-precipitation")!;
    const before=Array.from(rain.getVerticesData("position")!);outdoor.update(now,600,weather,false);
    expect(rain.getVerticesData("position")).not.toEqual(before);
    expect(rain.getVerticesData("position")!.every(Number.isFinite)).toBe(true);
    for(let i=0;i<240;i++)outdoor.update(now,1/60,{...weather,direction:270},false);
    expect(rain.metadata.activeCount).toBe(260);
    expect(outdoor.update(now,1/60,{...weather,code:73},false)).toMatchObject({wet:false,precipitation:"snow"});
    expect(rain.isEnabled()).toBe(false);
    expect(scene.getMeshByName("weather-snowflakes")!.isEnabled()).toBe(true);
    expect(scene.getMeshByName("rain-ripple")!.isEnabled()).toBe(false);
    outdoor.reset();expect(rain.isEnabled()).toBe(false);
    expect(scene.getMeshByName("weather-snowflakes")!.isEnabled()).toBe(false);
    expect(scene.getMeshByName("tree-canopy-0-0")!.rotation.length()).toBe(0);
  }finally{scene.dispose();engine.dispose();}
});
