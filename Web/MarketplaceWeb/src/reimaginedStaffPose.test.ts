import { readFileSync } from "node:fs";
import { expect,it } from "vitest";
import { NullEngine } from "@babylonjs/core/Engines/nullEngine";
import { Scene } from "@babylonjs/core/scene";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { Quaternion,Vector3 } from "@babylonjs/core/Maths/math.vector";
import { createRelaxedStaffPose } from "./reimaginedStaffPose";

it.each([0,Math.PI/2])("keeps the real imported rig's elbows and fingers down at station rotation %s",rotation=>{
  const blob=readFileSync(new URL("./assets/reimagined/staff-makehuman.glb",import.meta.url));
  const gltf=JSON.parse(blob.subarray(20,20+blob.readUInt32LE(12)).toString()) as {nodes:{name:string;translation?:number[];rotation?:number[];scale?:number[];children?:number[]}[]};
  const engine=new NullEngine(),scene=new Scene(engine);
  try{
    const root=new TransformNode("station",scene);root.rotation.y=rotation;
    const reflection=new TransformNode("gltf-conversion",scene);reflection.scaling.z=-1;reflection.parent=root;
    const nodes=gltf.nodes.map(n=>{const t=new TransformNode(n.name,scene);t.position.copyFromFloats(...(n.translation??[0,0,0]) as [number,number,number]);t.scaling.copyFromFloats(...(n.scale??[1,1,1]) as [number,number,number]);t.rotationQuaternion=Quaternion.FromArray(n.rotation??[0,0,0,1]);t.parent=reflection;return t;});
    gltf.nodes.forEach((n,i)=>n.children?.forEach(j=>nodes[j].parent=nodes[i]));
    const solve=createRelaxedStaffPose(nodes);solve();
    const snapshot=nodes.map(n=>n.rotationQuaternion!.clone());
    for(let frame=0;frame<200;frame++)solve();
    nodes.forEach((n,i)=>expect(Math.abs(Quaternion.Dot(n.rotationQuaternion!,snapshot[i]))).toBeCloseTo(1,5));
    const p=(name:string)=>nodes.find(n=>n.name===name)!.computeWorldMatrix(true).getTranslation();
    for(const side of ["l","r"]){
      for(const [a,b] of [[`upperarm_${side}`,`lowerarm_${side}`],[`lowerarm_${side}`,`hand_${side}`],[`hand_${side}`,`middle_01_${side}`]]){
        expect(Vector3.Dot(p(b).subtract(p(a)).normalize(),Vector3.Down())).toBeGreaterThan(.98);
      }
      expect(p(`hand_${side}`).y).toBeLessThan(p("pelvis").y);
    }
  }finally{scene.dispose();engine.dispose();}
});
