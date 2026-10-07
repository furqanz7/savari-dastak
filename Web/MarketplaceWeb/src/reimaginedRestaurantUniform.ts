import { Mesh } from "@babylonjs/core/Meshes/mesh";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import { Color3 } from "@babylonjs/core/Maths/math.color";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import type { AbstractMesh } from "@babylonjs/core/Meshes/abstractMesh";
import type { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import type { Scene } from "@babylonjs/core/scene";
import type { ShadowGenerator } from "@babylonjs/core/Lights/Shadows/shadowGenerator";
import type { PointLight } from "@babylonjs/core/Lights/pointLight";

/** Lightweight restaurant-only garments, attached to the breathing/head rig. */
export function createRestaurantUniform(scene:Scene,chest:TransformNode,head:TransformNode,body:AbstractMesh[],shadows:ShadowGenerator,key:PointLight){
  const cloth=new PBRMaterial("restaurant-apron-canvas",scene);
  cloth.albedoColor=Color3.FromHexString("#633c35").toLinearSpace();cloth.roughness=.97;cloth.metallic=0;
  const trim=new PBRMaterial("restaurant-uniform-trim",scene);
  trim.albedoColor=Color3.FromHexString("#373c38").toLinearSpace();trim.roughness=.9;trim.metallic=0;
  const seam=new PBRMaterial("restaurant-apron-stitch",scene);
  seam.albedoColor=Color3.FromHexString("#c4b99a").toLinearSpace();seam.roughness=1;seam.metallic=0;
  function attach(mesh:Mesh,parent:TransformNode,material=cloth){
    mesh.material=material;mesh.isPickable=false;mesh.receiveShadows=true;
    // Preserve world placement through glTF's reflected coordinate system.
    mesh.setParent(parent);shadows.addShadowCaster(mesh);key.includedOnlyMeshes.push(mesh);
    for(const light of scene.lights)if(light!==key&&light.name!=="restaurant-fill")light.excludedMeshes.push(mesh);
    return mesh;
  }
  // Fit cloth to the posed shirt, not a guessed plane through its chest.
  const triangles:Vector3[][]=[];
  for(const shirt of body.filter(m=>m.name.includes("male_casualsuit01")||m.name==="DastakCashierBody")){
    shirt.computeWorldMatrix(true);shirt.skeleton?.prepare(true);
    const data=shirt.getPositionData(true),indices=shirt.getIndices();
    if(data&&indices){
      const vertices=Array.from({length:data.length/3},(_,i)=>Vector3.TransformCoordinates(Vector3.FromArray(data,i*3),shirt.getWorldMatrix()));
      for(let i=0;i<indices.length;i+=3){
        const t=[vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]];
        if(t.some(p=>p.y>.78&&p.y<1.6&&Math.abs(p.x)<.3))triangles.push(t);
      }
    }
  }
  const fitted=(x:number,y:number,fallback:number,clearance=.008)=>{
    let z=Infinity;
    for(const [a,b,c] of triangles){
      const det=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y);
      if(Math.abs(det)<1e-10)continue;
      const u=((b.y-c.y)*(x-c.x)+(c.x-b.x)*(y-c.y))/det;
      const v=((c.y-a.y)*(x-c.x)+(a.x-c.x)*(y-c.y))/det;
      if(u>=0&&v>=0&&u+v<=1)z=Math.min(z,u*a.z+v*b.z+(1-u-v)*c.z);
    }
    return new Vector3(x,y,Number.isFinite(z)?z-clearance:fallback);
  };
  // A lower bib, scooped sides and many rows create a draped garment instead
  // of the previous four-row, wide trapezoid sitting up against the throat.
  const profile=[{y:.84,w:.17,z:4.065},{y:1.12,w:.165,z:4.065},{y:1.26,w:.155,z:4.062},{y:1.36,w:.11,z:4.055},{y:1.46,w:.085,z:4.075}];
  const rows=Array.from({length:25},(_,i)=>{
    const t=i/24*(profile.length-1),a=profile[Math.min(Math.floor(t),profile.length-2)],b=profile[Math.min(Math.floor(t)+1,profile.length-1)],f=i===24?1:t%1;
    return {y:a.y+(b.y-a.y)*f,w:a.w+(b.w-a.w)*f,z:a.z+(b.z-a.z)*f};
  });
  const paths=rows.map((row,j)=>Array.from({length:25},(_,i)=>{
    const u=i/12-1,fold=.004*Math.sin(u*13+j*.16)*(1-u*u);
    const y=row.y-(j===24?.009*(1-u*u):0);
    const p=fitted(u*row.w,Math.max(1.16,y),row.z+.065*u*u,.024+Math.abs(fold));
    // Keep the hanging skirt in front of any lower-shirt folds as well.
    if(y<1.16)p.z=Math.min(p.z,fitted(u*row.w,y,p.z,.024+Math.abs(fold)).z);
    p.y=y;return p;
  }));
  attach(MeshBuilder.CreateRibbon("waiter-apron",{pathArray:paths,sideOrientation:Mesh.DOUBLESIDE},scene),chest);
  const tube=(name:string,path:Vector3[],radius:number,material=cloth)=>attach(MeshBuilder.CreateTube(name,{path,radius,tessellation:8,cap:Mesh.CAP_ALL},scene),chest,material);
  for(const side of [-1,1]){
    // Thin flat woven straps instead of thick round ropes.
    const strap=Array.from({length:10},(_,i)=>new Vector3(side*(.078+i/9*.04),1.455+i/9*.064,4.12));
    attach(MeshBuilder.CreateRibbon("apron-neck-strap",{pathArray:[strap.map(p=>fitted(p.x-.007,p.y,p.z)),strap.map(p=>fitted(p.x+.007,p.y,p.z))],sideOrientation:Mesh.DOUBLESIDE},scene),chest);
    tube("apron-edge-stitch",paths.map(row=>row[side<0?0:24].subtract(new Vector3(0,0,.002))),.0008,seam);
  }
  // A tonal pocket lower on the bib, not a bright square on the chest.
  const pocket=MeshBuilder.CreateRibbon("apron-pocket",{pathArray:[1.24,1.32].map(y=>Array.from({length:13},(_,i)=>fitted(-.06+i*.01,y,4.052,.033))),sideOrientation:Mesh.DOUBLESIDE},scene);
  attach(pocket,chest);
  tube("pocket-top-stitch",Array.from({length:13},(_,i)=>fitted(-.06+i*.01,1.32,4.05,.035)),.0008,seam);
  // Fit the cap to the actual hair bounds, not guessed authoring units.
  const hair=body.find(mesh=>mesh.name.includes("short02"));
  if(hair){
    hair.computeWorldMatrix(true);
    const {minimumWorld:min,maximumWorld:max}=hair.getBoundingInfo().boundingBox;
    const centre=min.add(max).scale(.5),width=(max.x-min.x)*1.045,depth=(max.z-min.z)*1.045;
    // Hair bounds include the sideburns: their height must not determine a
    // towering crown or put the visor over the eyes. Human-scale shallow cap.
    const rimY=max.y-.052,capHeight=.062;
    const rings=Array.from({length:13},(_,j)=>Array.from({length:33},(_,i)=>{
      const phi=j/12*Math.PI/2,theta=i/32*Math.PI*2;
      return new Vector3(Math.cos(theta)*width/2*Math.sin(phi),Math.cos(phi)*capHeight,Math.sin(theta)*depth/2*Math.sin(phi));
    }));
    const crown=MeshBuilder.CreateRibbon("waiter-cap-crown",{pathArray:rings,sideOrientation:Mesh.DOUBLESIDE},scene);
    crown.position.set(centre.x,rimY,centre.z);attach(crown,head,trim);
    const visor=Array.from({length:5},(_,j)=>Array.from({length:25},(_,i)=>{
      const u=i/12-1,t=j/4,arc=Math.sqrt(Math.max(0,1-u*u));
      return new Vector3(centre.x+u*width*.46,rimY-.006-t*.012+u*u*.012,centre.z-depth*.32-arc*(.025+t*.075));
    }));
    attach(MeshBuilder.CreateRibbon("waiter-cap-visor",{pathArray:visor,sideOrientation:Mesh.DOUBLESIDE},scene),head,trim);
  }
}
