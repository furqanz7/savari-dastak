import { Engine } from "@babylonjs/core/Engines/engine";
import { Scene } from "@babylonjs/core/scene";
import { FreeCamera } from "@babylonjs/core/Cameras/freeCamera";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import { Color3, Color4 } from "@babylonjs/core/Maths/math.color";
import { HemisphericLight } from "@babylonjs/core/Lights/hemisphericLight";
import { DirectionalLight } from "@babylonjs/core/Lights/directionalLight";
import { PointLight } from "@babylonjs/core/Lights/pointLight";
import { ShadowGenerator } from "@babylonjs/core/Lights/Shadows/shadowGenerator";
import "@babylonjs/core/Lights/Shadows/shadowGeneratorSceneComponent";
import "@babylonjs/core/Shaders/shadowMap.vertex";
import "@babylonjs/core/Shaders/shadowMap.fragment";
import { Mesh } from "@babylonjs/core/Meshes/mesh";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { DynamicTexture } from "@babylonjs/core/Materials/Textures/dynamicTexture";
import { CubeTexture } from "@babylonjs/core/Materials/Textures/cubeTexture";
import { Texture } from "@babylonjs/core/Materials/Textures/texture";
import { restaurantBevel, restaurantCamera } from "./reimaginedRestaurantGeometry";
import burgerUrl from "./assets/reimagined/restaurant-burger.jpg?url";
import friesUrl from "./assets/reimagined/restaurant-fries.jpg?url";
import chickenUrl from "./assets/reimagined/restaurant-chicken.jpg?url";
import { createRestaurantStaff } from "./reimaginedRestaurantStaff";
import woodColor from "./assets/reimagined/wood_floor-color.jpg?url";
import woodNormal from "./assets/reimagined/wood_floor-normal.jpg?url";
import "@babylonjs/core/Shaders/rgbdDecode.fragment";
import lightUrl from "./assets/reimagined/store-light.env?url";

export type CafeScene = { setCounter(value: boolean): void; dispose(): void };
export const cafeCamera = restaurantCamera;

// Local visual study only. Decorative menus must not become catalogue data.
export function createCafeScene(canvas:HTMLCanvasElement,atCounter:boolean,onStatus:(text:string)=>void):CafeScene {
  const engine=new Engine(canvas,true,{powerPreference:"low-power",stencil:true});
  try {
    const scene=new Scene(engine);
    const mobile=matchMedia("(max-width: 720px)"),reduced=matchMedia("(prefers-reduced-motion: reduce)");
    engine.setHardwareScalingLevel(1/Math.min(devicePixelRatio||1,mobile.matches?1.5:1.75));
    scene.clearColor=Color4.FromHexString("#242424ff");
    scene.environmentTexture=CubeTexture.CreateFromPrefilteredData(lightUrl,scene);
    scene.environmentIntensity=.42;
    scene.imageProcessingConfiguration.toneMappingEnabled=true;
    scene.imageProcessingConfiguration.exposure=1.15;
    scene.imageProcessingConfiguration.contrast=1.15;
    const camera=new FreeCamera("restaurant-customer",Vector3.Zero(),scene);
    camera.minZ=.06;camera.maxZ=35;
    const fill=new HemisphericLight("restaurant-fill",new Vector3(0,1,0),scene);
    fill.intensity=.38;fill.groundColor=new Color3(.16,.13,.1);
    const sun=new DirectionalLight("restaurant-window-light",new Vector3(.65,-.8,.35),scene);
    sun.position.set(-4,6,-3);sun.intensity=2.4;sun.diffuse=new Color3(1,.94,.83);
    const shadows=new ShadowGenerator(mobile.matches?1024:1536,sun);
    shadows.usePercentageCloserFiltering=true;shadows.normalBias=.018;shadows.bias=.001;shadows.darkness=.12;
    const task=new PointLight("restaurant-counter-light",new Vector3(0,2.7,3),scene);
    task.intensity=15;task.range=7;task.diffuse=new Color3(1,.86,.68);
    const dining=new PointLight("restaurant-dining-light",new Vector3(-1.6,2.6,.5),scene);
    dining.intensity=9;dining.range=5;dining.diffuse=new Color3(1,.8,.58);
    let disposed=false,dirty=true,counter=atCounter;
    const meshes:Mesh[]=[];
    const color=(hex:string)=>Color3.FromHexString(hex).toLinearSpace();
    function material(name:string,hex:string,roughness=.65,metallic=0){
      const m=new PBRMaterial(name,scene);m.albedoColor=color(hex);m.roughness=roughness;m.metallic=metallic;
      m.maxSimultaneousLights=4;return m;
    }
    const ivory=material("warm-mineral-plaster","#d9d4c7",.9);
    const black=material("powdercoated-charcoal","#252825",.57);
    const steel=material("brushed-stainless","#a1a6a3",.32,.85);
    const red=material("oxblood-upholstery","#8f2025",.75);
    const tomato=material("dastak-tomato","#be3025",.6);
    const oak=material("natural-oak","#ffffff",.7);
    oak.albedoTexture=new Texture(woodColor,scene);oak.bumpTexture=new Texture(woodNormal,scene);oak.bumpTexture.level=.2;
    const warmMetal=material("champagne-metal","#ad8960",.32,.7);
    const tile=material("glazed-charcoal-tile","#283330",.23);
    const cream=material("paper-and-porcelain","#eee9de",.48);
    const amber=material("ochre-upholstery","#b67d31",.74);
    const led=material("warm-diffuser","#fff1d7",.4);led.emissiveColor=new Color3(1,.75,.42);
    let seed=674;
    const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
    function grain(name:string,base:string,colors:string[],count:number){
      const tex=new DynamicTexture(name,{width:512,height:512},scene,false);
      const c=tex.getContext() as unknown as CanvasRenderingContext2D;c.fillStyle=base;c.fillRect(0,0,512,512);
      for(let i=0;i<count;i++){c.fillStyle=colors[i%colors.length];c.fillRect(random()*512,random()*512,1+random()*2,1+random()*2);}
      tex.update();return tex;
    }
    const floor=material("limestone-floor","#ffffff",.6);
    floor.albedoTexture=grain("stone-grain","#bfb9ab",["#c6c0b2","#b7b1a3","#cec7b9"],5000);
    const worktop=material("speckled-quartz","#ffffff",.32);
    worktop.albedoTexture=grain("quartz-grain","#d9d4c9",["#c3bdb2","#efeadd","#b4b1a5"],14000);
    function track(mesh:Mesh,m:PBRMaterial,cast=true){
      mesh.material=m;mesh.isPickable=false;mesh.receiveShadows=true;mesh.metadata={cast};
      meshes.push(mesh);return mesh;
    }
    function box(name:string,x:number,y:number,z:number,w:number,h:number,d:number,m:PBRMaterial,cast=true){
      const mesh=MeshBuilder.CreateBox(name,{width:w,height:h,depth:d},scene);mesh.position.set(x,y,z);return track(mesh,m,cast);
    }
    function soft(name:string,x:number,y:number,z:number,w:number,h:number,d:number,m:PBRMaterial,r=.035){
      const mesh=new Mesh(name,scene);restaurantBevel(w,h,d,r).applyToMesh(mesh);mesh.position.set(x,y,z);return track(mesh,m);
    }
    function cyl(name:string,x:number,y:number,z:number,d:number,h:number,m:PBRMaterial,top=d){
      const mesh=MeshBuilder.CreateCylinder(name,{diameterBottom:d,diameterTop:top,height:h,tessellation:24},scene);
      mesh.position.set(x,y,z);return track(mesh,m);
    }
    function tube(name:string,points:Vector3[],radius:number,m:PBRMaterial){
      return track(MeshBuilder.CreateTube(name,{path:points,radius,tessellation:10,cap:Mesh.CAP_ALL},scene),m);
    }
    function face(name:string,x:number,y:number,z:number,w:number,h:number,m:PBRMaterial){
      const mesh=MeshBuilder.CreatePlane(name,{width:w,height:h},scene);mesh.position.set(x,y,z);return track(mesh,m,false);
    }
    function label(name:string,x:number,y:number,z:number,w:number,h:number,title:string,sub="",background="#232822",foreground="#f8f0dd"){
      const height=Math.max(64,Math.round(1024*h/w));
      const tex=new DynamicTexture(name,{width:1024,height},scene,false),c=tex.getContext() as unknown as CanvasRenderingContext2D;
      c.fillStyle=background;c.fillRect(0,0,1024,height);c.textAlign="center";c.fillStyle=foreground;
      c.font="600 "+Math.round(height*(sub?.37:.46))+"px sans-serif";
      c.fillText(title,512,height*(sub?.46:.65),950);
      if(sub){c.fillStyle="#b9ad95";c.font="400 "+Math.round(height*.19)+"px sans-serif";c.fillText(sub,512,height*.79,930);}
      tex.update();const m=material(name,"#ffffff",.8);m.unlit=true;m.albedoTexture=tex;
      return face(name,x,y,z,w,h,m);
    }
    const photoMaterials=[burgerUrl,friesUrl,chickenUrl].map((url,i)=>{
      const m=material("food-photo-"+i,"#ffffff");m.unlit=true;m.albedoTexture=new Texture(url,scene,false,true,Texture.TRILINEAR_SAMPLINGMODE,()=>{dirty=true;});
      // Cover a 3:2 panel with the portrait chicken image; no raster copy is edited.
      if(i===2){const t=m.albedoTexture as Texture;t.vScale=4/9;t.vOffset=.26;}return m;
    });
    function photo(name:string,x:number,y:number,z:number,w:number,h:number,i:number){return face(name,x,y,z,w,h,photoMaterials[i]);}

    // Narrow, human-scale room. All architecture stays outside the camera path.
    box("subfloor",0,-.09,1.3,5.6,.17,10.4,black,false);
    const floors=[floor,material("limestone-alternate","#c1baab",.61)];
    for(let x=-2.8;x<2.8;x+=.8)for(let z=-3.8;z<6.5;z+=.8)
      box("limestone-slab",x+.398,-.007,z+.398,.794,.03,.794,floors[(Math.round(x*5)+Math.round(z*5))%3===0?1:0],false);
    box("left-wall",-2.84,1.72,1.3,.12,3.44,10.4,ivory,false);
    box("right-wall",2.84,1.72,1.3,.12,3.44,10.4,ivory,false);
    box("rear-wall",0,1.72,6.45,5.7,3.44,.12,ivory,false);
    box("ceiling",0,3.48,1.3,5.7,.12,10.4,black,false);
    for(const x of [-2.5,2.5])box("oak-skirting",x/2.5*2.77,.065,1.3,.055,.13,10.4,black,false);
    for(let z=-3;z<6.4;z+=1.2)box("ceiling-seam",0,3.4,z,5.5,.025,.025,steel,false);
    // Slim warm-light tracks, instead of the previous heavy ceiling beams.
    for(const x of [-1.7,1.7]){
      box("ceiling-track",x,3.38,1.3,.065,.06,9.9,black,false);
      for(const z of [-1.5,1,3.6,5.7]){
        cyl("spot-cylinder",x,3.28,z,.14,.2,black);
        cyl("spot-lens",x,3.173,z,.1,.012,led);
      }
    }
    // Oak wall band, window bays and booth alcoves on the left.
    box("seating-oak-band",-2.75,.65,.4,.07,1.3,6.5,oak,false);
    const daylight=material("frosted-window","#c6d5c4",.8);daylight.emissiveColor=new Color3(.22,.27,.2);
    for(const z of [-1.7,.45,2.6]){
      box("window",-2.755,2.14,z,.04,1.55,1.75,daylight,false);
      box("window-reveal-top",-2.65,2.93,z,.25,.055,1.86,black,false);
      for(const dz of [-.91,.91])box("window-frame",-2.68,2.14,z+dz,.15,1.63,.045,black,false);
      box("window-sill",-2.61,1.33,z,.32,.05,1.9,oak,false);
    }
    for(const z of [-.2,1.9]){
      soft("booth-base",-2.38,.25,z,.65,.5,1.72,black,.07);
      soft("booth-seat",-2.32,.51,z,.7,.18,1.74,red,.075);
      soft("booth-back",-2.62,.92,z,.19,.75,1.76,red,.065);
      // Vertical upholstered channels and thin piping.
      for(let dz=-.75;dz<.8;dz+=.25)soft("booth-channel",-2.505,.94,z+dz,.035,.58,.19,red,.017);
      soft("oak-table",-1.7,.78,z,1.08,.055,.72,oak,.06);
      cyl("table-leg",-1.7,.38,z,.07,.73,black);
      soft("table-foot",-1.7,.033,z,.5,.055,.46,black,.025);
      // Curved bentwood chair shell, with four slender tubular legs.
      soft("chair-seat",-.99,.465,z,.44,.06,.46,amber,.045);
      const back:Vector3[]=[];
      for(let i=0;i<=16;i++){const a=-1.05+i*2.1/16;back.push(new Vector3(-.99+.27*Math.cos(a),.76,z+.27*Math.sin(a)));}
      const shell=MeshBuilder.CreateRibbon("curved-chair-back",{pathArray:[back.map(p=>p.add(new Vector3(0,-.14,0))),back.map(p=>p.add(new Vector3(0,.14,0)))],sideOrientation:Mesh.DOUBLESIDE},scene);
      track(shell,oak);tube("chair-top-rim",back.map(p=>p.add(new Vector3(0,.14,0))),.015,oak);
      for(const dx of [-.16,.16])for(const dz of [-.17,.17])
        tube("chair-leg",[new Vector3(-.99+dx*1.15,.04,z+dz*1.15),new Vector3(-.99+dx,.445,z+dz)],.014,black);
      soft("table-tray",-1.7,.824,z,.4,.018,.28,black,.015);
      cyl("drink",-1.78,.94,z,.10,.21,tomato,.13);cyl("drink-lid",-1.78,1.05,z,.14,.015,cream);
      cyl("drink-straw",-1.78,1.12,z,.008,.14,cream);
      label("table-number",-1.65,.96,z-.12,.14,.19,z<1?"01":"02","","#eee8d8","#34372e");
    }
    // Counter is only 4.45m wide, 85cm deep: a person can reach its equipment.
    soft("counter-body",.08,.59,3.62,4.45,1.05,.81,black,.1);
    soft("counter-worktop",.08,1.165,3.62,4.58,.08,.96,worktop,.035);
    box("counter-foot-recess",.08,.08,3.65,4.28,.15,.7,black);
    for(let x=-2.07;x<2.28;x+=.078)soft("oak-front-fins",x,.62,3.188,.043,.87,.035,oak,.01);
    box("counter-underlight",.08,1.112,3.161,4.25,.013,.014,led,false);
    label("counter-order",-1.25,.7,3.153,.98,.26,"ORDER","FRESHLY PREPARED");
    label("counter-pickup",1.42,.7,3.153,.98,.26,"PICK UP","MADE FOR YOU");
    // Back-bar kitchen: tile, extraction, pass, warm racks, stacked packaging.
    box("kitchen-tile-backing",0,1.44,6.33,5.5,2.7,.06,black,false);
    for(let x=-2.7;x<2.7;x+=.3)for(let y=.3;y<2.65;y+=.15)
      soft("glazed-subway-tile",x+.147,y+.071,6.281,.291,.142,.025,tile,.01);
    soft("pass-prep-counter",.2,.9,5.88,3.6,.085,.7,steel,.02);
    for(const x of [-1.45,1.8])box("prep-counter-leg",x,.45,5.92,.05,.85,.05,steel);
    box("pass-dark-recess",0,1.5,6.235,2.5,.72,.045,black,false);
    soft("hood",0,2.02,5.96,2.65,.28,.62,steel,.035);
    for(let x=-1.2;x<1.3;x+=.055)box("hood-louvre",x,1.89,5.67,.024,.045,.2,black);
    box("pass-warm-strip",0,1.854,5.88,2.3,.015,.025,led,false);
    for(const x of [-.8,0,.8]){
      soft("pass-warmer",x,1.02,5.88,.63,.16,.46,steel,.025);
      soft("pass-tray",x,1.115,5.84,.57,.016,.4,black,.015);
    }
    for(let i=0;i<6;i++)soft("takeaway-box-stack",2.2,1.03+i*.055,5.85,.42,.05,.32,cream,.012);
    // Menu screens move BEHIND the staff, with a lower visual weight.
    box("menu-oak-canopy",0,2.78,5.46,5.28,.85,.22,oak,false);
    box("menu-lower-trim",0,2.34,5.33,5.3,.035,.03,warmMetal,false);
    const titles=["SIGNATURE BURGERS","GOLDEN FRIES","CRISPY CHICKEN"];
    for(let i=0;i<3;i++){
      const x=-1.5+i*1.5;
      soft("menu-display-frame",x,2.77,5.292,1.43,.81,.065,black,.025);
      photo("menu-food-"+i,x,2.85,5.251,1.34,.54,i);
      label("menu-label-"+i,x,2.48,5.25,1.34,.18,titles[i],"","#202521","#f5edda");
    }
    label("brand-sign",0,3.29,5.31,3.75,.25,"DASTAK  /  KITCHEN","","#242a25","#f4e8cf");
    // Ordering point: screen is off-centre so it cannot cover the staff's face.
    soft("pos-base",.56,1.22,3.69,.29,.035,.25,black,.016);
    cyl("pos-neck",.56,1.36,3.75,.045,.26,steel);
    soft("pos-housing",.56,1.51,3.76,.43,.285,.045,black,.017);
    label("pos-display",.56,1.51,3.733,.39,.245,"WELCOME","LET'S ORDER");
    soft("card-reader",.83,1.25,3.38,.13,.065,.21,black,.017);
    label("reader-screen",.83,1.29,3.3,.09,.045,"TAP","","#1e3b34","#cad9be");
    soft("keyboard",0,1.218,3.94,.46,.025,.18,black,.01);
    for(let row=0;row<4;row++)for(let col=0;col<13;col++)box("key",-.215+col*.035,1.235,3.885+row*.035,.027,.006,.027,steel);
    soft("receipt-printer",-.52,1.3,3.76,.25,.21,.28,black,.025);
    box("receipt",-.52,1.412,3.735,.14,.004,.17,cream);
    soft("pickup-tray",1.53,1.223,3.65,.63,.022,.46,black,.02);
    for(const x of [1.38,1.61]){
      cyl("pickup-cup",x,1.36,3.68,.13,.25,tomato,.17);cyl("pickup-lid",x,1.49,3.68,.18,.018,cream);
      cyl("pickup-straw",x,1.59,3.68,.009,.19,cream);
    }
    soft("paper-bag",1.98,1.39,3.72,.24,.35,.17,oak,.017);
    label("bag-stamp",1.98,1.4,3.63,.12,.12,"D","","#b58b56","#3b3227");
    // One integrated kiosk, not two oversized totems obstructing the entrance.
    soft("kiosk-base",1.82,.04,1.45,.6,.07,.48,black,.025);
    soft("kiosk-stem",1.82,.65,1.45,.17,1.2,.15,black,.027);
    soft("kiosk-shell",1.82,1.51,1.45,.56,.91,.1,cream,.05);
    soft("kiosk-bezel",1.82,1.53,1.392,.5,.81,.015,black,.025);
    photo("kiosk-food",1.82,1.59,1.38,.44,.3,0);
    label("kiosk-header",1.82,1.87,1.379,.43,.08,"ORDER HERE","","#212921","#f4ebd4");
    label("kiosk-start",1.82,1.31,1.379,.43,.16,"START ORDER","LOCAL PREVIEW","#aa2a23","#ffffff");
    soft("kiosk-reader",2.16,1.17,1.4,.12,.18,.075,black,.015);
    // Keep the complete kiosk inside the portrait entrance composition.
    for(const mesh of meshes)if(mesh.name.startsWith("kiosk-")){mesh.position.x-=.22;mesh.position.z+=.6;}
    // Right wall: oak lower panels, a restrained red accent and framed food artwork.
    box("right-oak-panelling",2.76,.65,.3,.055,1.3,6.25,oak,false);
    box("right-red-panel",2.758,2.03,1.2,.06,1.38,4.25,tomato,false);
    const wallPoster=photo("wall-food-poster",2.719,2.03,.65,1.5,1,0);wallPoster.rotation.y=Math.PI/2;
    for(const z of [-.18,1.48])box("poster-side-frame",2.68,2.03,z,.055,1.1,.045,black);
    for(const y of [1.48,2.58])box("poster-frame",2.68,y,.65,.055,.045,1.7,black);
    // Pendant lamps over dining, with a lathed shade rather than a simple cone.
    for(const z of [-.2,1.9]){
      cyl("pendant-wire",-1.7,2.99,z,.01,.84,black);
      const shade=MeshBuilder.CreateLathe("pendant-shade",{shape:[new Vector3(.055,0,0),new Vector3(.065,-.05,0),new Vector3(.12,-.13,0),new Vector3(.23,-.20,0),new Vector3(.24,-.235,0)],radius:1,tessellation:32,sideOrientation:Mesh.DOUBLESIDE},scene);
      shade.position.set(-1.7,2.6,z);track(shade,black);cyl("pendant-glow",-1.7,2.367,z,.43,.009,led);
    }
    // Material batches remain static; the skeletal staff is not merged.
    const batches=new Map<string,Mesh[]>();
    for(const mesh of meshes){const key=mesh.material!.uniqueId+":"+String(mesh.metadata.cast);const group=batches.get(key)??[];group.push(mesh);batches.set(key,group);}
    for(const group of batches.values()){
      const cast=group[0].metadata.cast;const merged=Mesh.MergeMeshes(group,true,true)!;merged.isPickable=false;merged.receiveShadows=true;merged.freezeWorldMatrix();
      if(cast)shadows.addShadowCaster(merged);
    }
    let staffUpdate:((time:number)=>void)|undefined,staffState="Loading staff",lastStatus="";
    let clock=0,previousTime=performance.now();
    void createRestaurantStaff(scene,shadows,canvas,()=>disposed).then(update=>{
      if(disposed)return;staffUpdate=update;staffState=update?"Staff ready":"Staff unavailable";dirty=true;
    }).catch(()=>{if(!disposed){staffState="Staff unavailable";canvas.dataset.staff="unavailable";dirty=true;}});
    const destination=Vector3.Zero(),target=Vector3.Zero(),gaze=Vector3.Zero();
    function frame(){
      const view=restaurantCamera(counter,mobile.matches);destination.copyFromFloats(...view.position as [number,number,number]);
      target.copyFromFloats(...view.target as [number,number,number]);camera.fov=view.fov;
      // Render behind the floating controls too. Preserve the old upper-frame
      // composition by widening vertically and lowering the optical target.
      if(mobile.matches){
        const halfHeight=Math.tan(view.fov/2);
        camera.fov=2*Math.atan(halfHeight/.82);
        target.y-=Vector3.Distance(destination,target)*halfHeight*.18/.82;
      }
      dirty=true;
    }
    frame();camera.position.copyFrom(destination);gaze.copyFrom(target);camera.setTarget(gaze);
    const resize=()=>{frame();engine.resize();};const observer=new ResizeObserver(resize);observer.observe(canvas);
    const render=()=>{
      if(disposed||document.hidden)return;
      const now=performance.now(),elapsed=Math.min((now-previousTime)/1000,.1);previousTime=now;
      if(!dirty&&scene.isReady()&&(!staffUpdate||reduced.matches))return;
      if(!reduced.matches)clock+=elapsed;staffUpdate?.(clock);
      const blend=reduced.matches?1:1-Math.exp(-Math.min(engine.getDeltaTime()/1000,.05)*4);
      Vector3.LerpToRef(camera.position,destination,blend,camera.position);Vector3.LerpToRef(gaze,target,blend,gaze);camera.setTarget(gaze);
      const ready=scene.isReady();scene.render();
      dirty=!ready||Vector3.Distance(camera.position,destination)>.002||Vector3.Distance(gaze,target)>.002;
      canvas.dataset.view=counter?"cafe-counter":"cafe-entrance";canvas.dataset.sceneReady=String(ready);
      const status="Restaurant study 02 · "+staffState+(reduced.matches?" · reduced motion":"");
      if(ready&&status!==lastStatus){lastStatus=status;onStatus(status);}
    };
    const visibility=()=>{if(document.hidden)engine.stopRenderLoop(render);else{previousTime=performance.now();dirty=true;engine.runRenderLoop(render);}};
    document.addEventListener("visibilitychange",visibility);mobile.addEventListener("change",resize);reduced.addEventListener("change",resize);engine.runRenderLoop(render);
    return {setCounter(value){counter=value;frame();},dispose(){
      disposed=true;observer.disconnect();document.removeEventListener("visibilitychange",visibility);mobile.removeEventListener("change",resize);reduced.removeEventListener("change",resize);
      engine.stopRenderLoop(render);scene.dispose();engine.dispose();
    }};
  } catch(error){engine.dispose();throw error;}
}
