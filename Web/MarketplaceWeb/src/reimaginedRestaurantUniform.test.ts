import { expect,it } from "vitest";
import { NullEngine } from "@babylonjs/core/Engines/nullEngine";
import { Scene } from "@babylonjs/core/scene";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import { PointLight } from "@babylonjs/core/Lights/pointLight";
import { ShadowGenerator } from "@babylonjs/core/Lights/Shadows/shadowGenerator";
import { createRestaurantUniform } from "./reimaginedRestaurantUniform";

it("keeps uniform world fit through the reflected rig and follows chest/head motion",()=>{
  const engine=new NullEngine(),scene=new Scene(engine);
  try{
    const rig=new TransformNode("reflected-rig",scene);rig.scaling.z=-1;
    const chest=new TransformNode("chest",scene),head=new TransformNode("head",scene);
    chest.parent=rig;head.parent=chest;
    const hair=MeshBuilder.CreateBox("short02",{width:.18,height:.12,depth:.19},scene);
    hair.position.set(0,1.74,4.22);hair.computeWorldMatrix(true);
    const key=new PointLight("key",Vector3.Zero(),scene),shadows=new ShadowGenerator(256,key);
    createRestaurantUniform(scene,chest,head,[hair],shadows,key);
    const apron=scene.getMeshByName("waiter-apron")!,cap=scene.getMeshByName("waiter-cap-crown")!;
    expect(apron.parent).toBe(chest);expect(cap.parent).toBe(head);
    cap.computeWorldMatrix(true);const initial=cap.getAbsolutePosition().clone();
    expect(initial.y).toBeCloseTo(1.8-.052);expect(initial.z).toBeCloseTo(4.22);
    cap.refreshBoundingInfo({});
    expect(cap.getBoundingInfo().boundingBox.maximumWorld.y).toBeCloseTo(1.81);
    expect(scene.getMeshByName("waiter-cap-band")).toBeNull();
    expect(scene.getMeshByName("apron-waist-tie")).toBeNull();
    chest.position.y=.015;cap.computeWorldMatrix(true);
    expect(cap.getAbsolutePosition().y-initial.y).toBeCloseTo(.015);
    expect(key.includedOnlyMeshes).toContain(apron);
    expect(shadows.getShadowMap()?.renderList).toContain(cap);
  }finally{scene.dispose();engine.dispose();}
});
