import { Matrix,Quaternion,Vector3 } from "@babylonjs/core/Maths/math.vector";
import type { TransformNode } from "@babylonjs/core/Meshes/transformNode";

/** Segment directions, not unreachable desk targets; shared by both staff. */
export function createRelaxedStaffPose(nodes:TransformNode[]){
  const find=(name:string)=>{const n=nodes.find(n=>n.name===name);if(!n)throw new Error(`Missing staff joint: ${name}`);return n;};
  const left=find("upperarm_l"),right=find("upperarm_r");
  const across=left.computeWorldMatrix(true).getTranslation().subtract(right.computeWorldMatrix(true).getTranslation()).normalize();
  const forward=Vector3.Cross(Vector3.UpReadOnly,across).normalize();
  const inverse=Matrix.Identity(),current=Vector3.Zero(),desired=Vector3.Zero(),axis=Vector3.Zero(),delta=Quaternion.Identity();
  const direction=(joint:TransformNode,child:TransformNode,world:Vector3)=>{
    joint.computeWorldMatrix(true).invertToRef(inverse);
    Vector3.TransformCoordinatesToRef(child.computeWorldMatrix(true).getTranslation(),inverse,current);current.normalize();
    Vector3.TransformNormalToRef(world,inverse,desired);desired.normalize();
    Vector3.CrossToRef(current,desired,axis);
    if(axis.lengthSquared()<1e-10)return;
    Quaternion.RotationAxisToRef(axis.normalize(),Math.acos(Math.max(-1,Math.min(1,Vector3.Dot(current,desired)))),delta);
    joint.rotationQuaternion!.multiplyInPlace(delta);
  };
  const arms=["l","r"].map((side,i)=>{
    const arm=find(`upperarm_${side}`),fore=find(`lowerarm_${side}`),hand=find(`hand_${side}`);
    const middle=find(`middle_01_${side}`),index=find(`index_01_${side}`),pinky=find(`pinky_01_${side}`);
    const joints=[arm,fore,hand];joints.forEach(n=>n.rotationQuaternion??=Quaternion.Identity());
    const rests=joints.map(n=>n.rotationQuaternion!.clone()),sign=i===0?1:-1;
    const upper=Vector3.Down().add(across.scale(sign*.075)).add(forward.scale(-.025)).normalize();
    const lower=Vector3.Down().add(across.scale(sign*.025)).add(forward.scale(.095)).normalize();
    const fingers=Vector3.Down().add(forward.scale(.055)).normalize();
    const thumbSide=forward.scale(sign);
    return {hand,solve(){
      joints.forEach((n,j)=>n.rotationQuaternion!.copyFrom(rests[j]));
      direction(arm,fore,upper);direction(fore,hand,lower);direction(hand,middle,fingers);
      // Constrain palm roll too: thumbs forward, palms inward, not flat on a desk.
      const actual=index.computeWorldMatrix(true).getTranslation().subtract(pinky.computeWorldMatrix(true).getTranslation());
      actual.subtractInPlace(fingers.scale(Vector3.Dot(actual,fingers))).normalize();
      const wanted=thumbSide.subtract(fingers.scale(Vector3.Dot(thumbSide,fingers))).normalize();
      const angle=Math.atan2(Vector3.Dot(Vector3.Cross(actual,wanted),fingers),Vector3.Dot(actual,wanted));
      hand.computeWorldMatrix(true).invertToRef(inverse);
      Vector3.TransformNormalToRef(fingers,inverse,axis);axis.normalize();
      Quaternion.RotationAxisToRef(axis,angle*(inverse.determinant()<0?-1:1),delta);
      hand.rotationQuaternion!.multiplyInPlace(delta);
    }};
  });
  return ()=>{arms.forEach(a=>a.solve());return arms.map(a=>a.hand.computeWorldMatrix(true).getTranslation());};
}
