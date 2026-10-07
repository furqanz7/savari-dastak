import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import { VertexData } from "@babylonjs/core/Meshes/mesh.vertexData";

/** Bevelled solid: shared-face UVs, continuous corner normals, no intersecting boxes. */
export function restaurantBevel(width:number,height:number,depth:number,radius=.035) {
  const half=[width/2,height/2,depth/2];
  const r=Math.min(radius,...half)*.99;
  if (Math.min(...half)<=0 || r<=0) throw new Error("Invalid restaurant geometry dimensions");
  const positions:number[]=[],normals:number[]=[],uvs:number[]=[],indices:number[]=[];
  for(let axis=0;axis<3;axis++)for(const sign of [-1,1]){
    const u=(axis+1)%3,v=(axis+2)%3;
    const samples=(h:number)=>[-h,-h+r*.293,-h+r,h-r,h-r*.293,h];
    const us=samples(half[u]),vs=samples(half[v]);const start=positions.length/3;
    for(let j=0;j<6;j++)for(let i=0;i<6;i++){
      const p=[0,0,0];p[axis]=half[axis]*sign;p[u]=us[i];p[v]=vs[j];
      const inner=p.map((value,k)=>Math.max(-half[k]+r,Math.min(half[k]-r,value)));
      const n=new Vector3(p[0]-inner[0],p[1]-inner[1],p[2]-inner[2]).normalize();
      positions.push(inner[0]+n.x*r,inner[1]+n.y*r,inner[2]+n.z*r);normals.push(n.x,n.y,n.z);
      uvs.push((p[u]/half[u]+1)/2,(p[v]/half[v]+1)/2);
    }
    for(let j=0;j<5;j++)for(let i=0;i<5;i++){
      const a=start+j*6+i,b=a+1,c=a+6,d=c+1;
      indices.push(...(sign>0?[a,c,b,b,c,d]:[a,b,c,b,d,c]));
    }
  }
  const data=new VertexData();data.positions=positions;data.normals=normals;data.uvs=uvs;data.indices=indices;return data;
}

export function restaurantCamera(counter:boolean,mobile:boolean) {
  return {position:counter?[0,1.59,1.55]:[mobile?0:-.35,1.57,mobile?-3.15:-3.65],
    target:counter?[0,1.57,4.22]:[0,1.55,4.5],fov:mobile?(counter?1.08:1.25):.91};
}
