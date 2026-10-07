import { Scene } from "@babylonjs/core/scene";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder";
import { Mesh } from "@babylonjs/core/Meshes/mesh";
import "@babylonjs/core/Meshes/instancedMesh";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { ShaderMaterial } from "@babylonjs/core/Materials/shaderMaterial";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { Color3 } from "@babylonjs/core/Maths/math.color";
import { Vector2, Vector3 } from "@babylonjs/core/Maths/math.vector";
import { daylightAt, weatherDescription, WEATHER_MAX_AGE, type OutdoorWeather } from "./reimaginedWeather";
import { leafSpray } from "./reimaginedPlanting";
import { createPrecipitation } from "./reimaginedPrecipitation";

// Local preview only: batched planting screens, wind-driven crowns and capped rain.
export function createOutdoor(scene: Scene, parent: TransformNode) {
  const sky = MeshBuilder.CreateSphere("weather-sky", { diameter: 110, segments: 24, sideOrientation: Mesh.BACKSIDE }, scene);
  sky.parent = parent; sky.isPickable = false; sky.infiniteDistance = true;
  const skyMaterial = new ShaderMaterial("time-and-weather-sky", scene, {
    vertexSource: `precision highp float;
      attribute vec3 position; uniform mat4 worldViewProjection; varying vec3 direction;
      void main(){ direction=position; gl_Position=worldViewProjection*vec4(position,1.0); }`,
    fragmentSource: `precision highp float;
      varying vec3 direction; uniform float daylight; uniform float cloud; uniform float drift; uniform vec2 windDirection;
      float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
      float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
      void main(){
        vec3 d=normalize(direction); float height=clamp(d.y,0.0,1.0);
        vec3 day=mix(vec3(.72,.84,.91),vec3(.10,.37,.70),pow(height,.45));
        vec3 night=mix(vec3(.065,.085,.14),vec3(.006,.012,.035),height);
        vec3 color=mix(night,day,daylight);
        float twilight=4.0*daylight*(1.0-daylight);
        color+=vec3(.27,.085,.012)*twilight*pow(1.0-height,5.0);
        vec2 uv=d.xz/max(.18,d.y+.2)*2.2;
        vec2 flow=windDirection*drift;
        float n=noise(uv+flow)*.58+noise(uv*2.1+flow*.72)*.28+noise(uv*4.3+flow*1.12)*.14;
        float cover=smoothstep(.84-cloud*.64,.99-cloud*.54,n)*smoothstep(-.05,.2,d.y);
        color=mix(color,mix(vec3(.10,.12,.17),vec3(.86-cloud*.27),daylight),cover);
        float stars=step(.999,hash(floor(d.xz/max(.1,d.y)*180.0)))*smoothstep(.1,.6,d.y)*(1.0-daylight)*(1.0-cover)*(1.0-cloud);
        color+=vec3(stars*.28);
        // Decorative moon, not an astronomical position or phase calculation.
        vec3 moonDir=normalize(vec3(-.1,.45,1.0));
        color+=vec3(.025,.032,.045)*pow(max(0.0,dot(d,moonDir)),900.0)*(1.0-daylight)*(1.0-cover);
        color+=vec3(.60,.65,.73)*smoothstep(.99995,.999985,dot(d,moonDir))*(1.0-daylight)*(1.0-cover);
        gl_FragColor=vec4(color,1.0);
      }`,
  }, { attributes: ["position"], uniforms: ["worldViewProjection", "daylight", "cloud", "drift", "windDirection"] });
  skyMaterial.backFaceCulling = false; skyMaterial.disableDepthWrite = true; sky.material = skyMaterial;
  const bark = new PBRMaterial("outdoor-bark", scene); bark.albedoColor = Color3.FromHexString("#625448"); bark.roughness = 1;
  const leaves = new PBRMaterial("outdoor-leaves", scene); leaves.albedoColor = Color3.FromHexString("#779957").toLinearSpace(); leaves.roughness = .83;
  leaves.metallic = 0; leaves.backFaceCulling = false; leaves.twoSidedLighting = true;
  const grass = new PBRMaterial("outdoor-ground", scene); grass.albedoColor = Color3.FromHexString("#697b50"); grass.roughness = 1;
  const land = MeshBuilder.CreateGround("landscape-beyond-store", { width: 100, height: 100 }, scene);
  land.position.set(0, -.25, 0); land.material = grass; land.parent = parent; land.isPickable = false;
  const trees: TransformNode[] = [];
  const foliage: { node: TransformNode; phase: number; strength: number }[] = [];
  for (const [index, point] of [[-6.2,-5], [5.5,-4], [-8.5,3], [8,4], [-11,13], [11,15]].entries()) {
    const root = new TransformNode(`wind-tree-${index}`, scene); root.parent = parent; root.position.set(point[0], 0, point[1]); trees.push(root);
    const trunk = MeshBuilder.CreateCylinder("tree-trunk", { height: 3.8, diameterBottom: .36, diameterTop: .13, tessellation: 8 }, scene);
    trunk.position.y = 1.9; trunk.material = bark; trunk.parent = root;
    for (let section = 0; section < 3; section++) {
      const crown = leafSpray(scene, `tree-canopy-${index}-${section}`, leaves, 800, 200 + index * 9 + section, r => {
        const a = r() * Math.PI * 2, h = r() * 2 - 1, radius = Math.sqrt(1 - h * h) * (1.1 + r() * .5);
        return { center: new Vector3(Math.sin(a) * radius, 3.8 + h * 1.45 + section * .12, Math.cos(a) * radius), size: .09 + r() * .09 };
      });
      crown.parent=root;
      crown.setPivotPoint(new Vector3(0,2.8,0));
      foliage.push({node:crown,phase:index*1.71+section*2.1,strength:1+section*.17});
    }
    trunk.isPickable = false;
  }
  // Continuous evergreen banks block horizon/sky gaps beside the shop, even
  // between trunks or while the upper crowns sway. Keep the doorway clear.
  const hedgeMaterial = new PBRMaterial("dense-evergreen-screen", scene);
  hedgeMaterial.albedoColor = Color3.FromHexString("#354927").toLinearSpace(); hedgeMaterial.roughness = 1; hedgeMaterial.metallic = 0;
  for (const side of [-1, 1]) {
    const innerEdge = side < 0 ? -4.28 : 3.28;
    const core = MeshBuilder.CreateBox("evergreen-screen-core", { width: 24, height: 3.5, depth: 2.4 }, scene);
    core.position.set(innerEdge + side * 12, 1.65, -5.7); core.material = hedgeMaterial;
    const screen = core;
    screen.name = side < 0 ? "left-evergreen-screen" : "right-evergreen-screen";
    screen.parent = parent; screen.isPickable = false; screen.receiveShadows = true; screen.freezeWorldMatrix();
    for (let index = 0; index < 4; index++) {
      const top = leafSpray(scene, `hedge-top-${side}-${index}`, leaves, index === 0 ? 12000 : 2000, 80 + index * 3 + side, r => {
        const along = index * 6 + r() * 6;
        const height = 3.75 + Math.sin(along * 1.9) * .3 + Math.sin(along * 4.2) * .13;
        return { center: new Vector3(innerEdge + side * (.12 + along), r() * height, -7.2 - r() * .7), size: .045 + r() * .065 };
      });
      top.parent=parent;
      top.setPivotPoint(new Vector3(innerEdge+side*(3.05+index*6),2.7,-7));
      foliage.push({node:top,phase:index*1.3+side*2,strength:.3});
    }
  }
  const precipitation = createPrecipitation(scene, parent);
  const rippleMaterial=new PBRMaterial("rain-ripple-material",scene);
  rippleMaterial.albedoColor=new Color3(.42,.51,.57);rippleMaterial.alpha=.22;rippleMaterial.roughness=.3;
  const ripple=MeshBuilder.CreateTorus("rain-ripple",{diameter:1,thickness:.014,tessellation:20},scene);
  ripple.material=rippleMaterial;
  // Shared geometry, separate mesh visibility so each ring can fade independently.
  const ripples=[ripple,...Array.from({length:15},(_,i)=>ripple.clone(`rain-ripple-${i}`)!)];
  ripples.forEach((r,i)=>{r.parent=parent;r.isPickable=false;r.position.set(-3.6+(i*1.618)%6.1,.013,-9-(i*1.31)%4.6);r.setEnabled(false);});
  let windTime = 0;
  let cloudDrift=0;
  const cloudDirection=new Vector2(0,0);
  let windX=0,windZ=0,windStrength=0;
  const wrap=(n:number,span:number)=>(n%span+span)%span;
  return {
    update(now: number, dt: number, weather: OutdoorWeather | null, reduced: boolean) {
      // Parent transforms disable Babylon's automatic infinite-distance offset.
      // Keep the dome camera-centred so its far side cannot cross maxZ and
      // expose a pale clipped arc directly above the storefront.
      if (scene.activeCamera) sky.position.copyFrom(scene.activeCamera.position);
      const current = weather && now - weather.observedAt <= WEATHER_MAX_AGE ? weather : null;
      const daylight = daylightAt(now, current); const cloud = current?.cloud ?? .15;
      const wind = Math.min(current?.wind ?? 0, 80); const gust = Math.min(current?.gust ?? wind, 100);
      const step=Number.isFinite(dt)?Math.max(0,Math.min(dt,.1)):0;
      if (!reduced) windTime += step;
      const direction = ((current?.direction ?? 225) + 180) * Math.PI / 180;
      // Ease new readings, with multi-frequency gusts rather than a metronome.
      const blend=reduced?0:1-Math.exp(-step*1.8);
      const gustPulse=Math.pow(.5+.5*Math.sin(windTime*.37)+.12*Math.sin(windTime*.83),2);
      const force=wind+Math.max(0,gust-wind)*Math.min(1,gustPulse);
      windStrength+=(force-windStrength)*blend;
      windX+=(Math.sin(direction)-windX)*blend;windZ+=(Math.cos(direction)-windZ)*blend;
      if(!reduced)cloudDrift+=step*(.0015+windStrength*.0007);
      skyMaterial.setFloat("daylight", daylight); skyMaterial.setFloat("cloud", cloud);
      skyMaterial.setFloat("drift", cloudDrift);
      cloudDirection.set(windX,windZ);skyMaterial.setVector2("windDirection",cloudDirection);
      trees.forEach((tree, i) => {
        const sway=reduced?0:windStrength*.00012*(.6+.4*Math.sin(windTime*.61+i*1.7));
        tree.rotation.z=-sway*windX;tree.rotation.x=sway*windZ;
      });
      foliage.forEach(({node,phase,strength})=>{
        const wave=Math.sin(windTime*1.1+phase)*.55+Math.sin(windTime*2.31+phase*1.7)*.25+Math.sin(windTime*.47+phase)*.2;
        const bend=reduced?0:strength*(.004+windStrength*.0008)*(.4+wave);
        node.rotation.z=-bend*windX;node.rotation.x=bend*windZ;
        node.rotation.y=reduced?0:Math.sin(windTime*1.73+phase)*strength*(.002+windStrength*.00013);
      });
      const snow = current && weatherDescription(current.code) === "Snow";
      const amount = precipitation.update(step, current ? snow ? "snow" : "rain" : null,
        current?.precipitation ?? 0, windStrength * windX, windStrength * windZ, daylight, reduced);
      ripples.forEach((r,i)=>{
        const active=amount>0&&!snow&&i<Math.ceil(amount/18);r.setEnabled(active);
        if(!active)return;
        const phase=wrap(windTime*1.45+i*.618,1),size=.03+phase*.34;
        r.scaling.set(size,Math.max(.01,(1-phase)*.55),size);
        r.visibility=(1-phase)*.65;
      });
      return { daylight, cloud, fog: current && [45,48].includes(current.code), wet: !snow && (current?.precipitation ?? 0) > 0, wind,
        precipitation: amount ? snow ? "snow" : "rain" : "none", particleCount: amount };
    },
    reset() { [...trees,...foliage.map(f=>f.node)].forEach(t => t.rotation.setAll(0)); precipitation.reset();ripples.forEach(r=>r.setEnabled(false)); },
  };
}
