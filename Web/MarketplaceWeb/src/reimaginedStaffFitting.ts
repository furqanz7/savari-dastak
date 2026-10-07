// Local-only full-body inspection: counters cannot conceal elbow/wrist defects.
import {Engine} from "@babylonjs/core/Engines/engine";
import {Scene} from "@babylonjs/core/scene";
import {FreeCamera} from "@babylonjs/core/Cameras/freeCamera";
import {Vector3} from "@babylonjs/core/Maths/math.vector";
import {Color4} from "@babylonjs/core/Maths/math.color";
import {HemisphericLight} from "@babylonjs/core/Lights/hemisphericLight";
import {DirectionalLight} from "@babylonjs/core/Lights/directionalLight";
import {ShadowGenerator} from "@babylonjs/core/Lights/Shadows/shadowGenerator";
import "@babylonjs/core/Lights/Shadows/shadowGeneratorSceneComponent";
import {createRestaurantStaff} from "./reimaginedRestaurantStaff";
if(import.meta.env.DEV){
  const canvas=document.querySelector<HTMLCanvasElement>("#fit")!,engine=new Engine(canvas,true),scene=new Scene(engine);
  scene.clearColor=new Color4(.16,.19,.20,1);
  const camera=new FreeCamera("fit-camera",new Vector3(0,1.12,1.75),scene);camera.setTarget(new Vector3(0,1.07,4.22));camera.fov=.85;
  const fill=new HemisphericLight("restaurant-fill",Vector3.Up(),scene);fill.intensity=.8;
  const sun=new DirectionalLight("fit-sun",new Vector3(0,-1,1),scene);const shadows=new ShadowGenerator(512,sun);
  let update:((time:number)=>void)|undefined;
  void createRestaurantStaff(scene,shadows,canvas,()=>false).then(fn=>{update=fn;document.querySelector("#status")!.textContent="Full-body fit · arms at sides";});
  document.querySelector("#front")!.addEventListener("click",()=>{camera.position.set(0,1.12,1.75);camera.setTarget(new Vector3(0,1.07,4.22));});
  document.querySelector("#side")!.addEventListener("click",()=>{camera.position.set(2.5,1.12,4.22);camera.setTarget(new Vector3(0,1.07,4.22));});
  engine.runRenderLoop(()=>{update?.(performance.now()/1000);scene.render();});
  window.addEventListener("resize",()=>engine.resize());
}
