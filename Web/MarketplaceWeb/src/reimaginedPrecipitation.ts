import { Scene } from "@babylonjs/core/scene";
import { Mesh } from "@babylonjs/core/Meshes/mesh";
import { VertexData } from "@babylonjs/core/Meshes/mesh.vertexData";
import { VertexBuffer } from "@babylonjs/core/Buffers/buffer";
import { ShaderMaterial } from "@babylonjs/core/Materials/shaderMaterial";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import type { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { plantingRandom } from "./reimaginedPlanting";

// Bounded, preallocated billboard batches. No texture downloads or per-drop
// meshes. The vertex shader faces flakes to the camera and aligns rain to wind.
export function createPrecipitation(scene: Scene, parent: TransformNode) {
  const makeBatch = (name: string, count: number, streak: boolean) => {
    const positions = new Float32Array(count * 12), colors: number[] = [], uvs: number[] = [], indices: number[] = [];
    const random = plantingRandom(streak ? 91 : 318);
    const splash = name === "rain-ground-splashes";
    const particles = Array.from({ length: count }, () => ({ x: -8 + random() * 16, y: random() * 7,
      z: -20 + random() * 11.3, size: random(), phase: random() * Math.PI * 2 }));
    particles.forEach((p, i) => {
      for (const [x, y] of [[-1,-1], [1,-1], [1,1], [-1,1]]) {
        const radius = splash ? .004 + p.size * .006 : .014 + p.size * .031;
        uvs.push(x, y); colors.push(streak ? .005 + p.size * .005 : radius,
          streak ? .085 + p.size * .10 : radius, .45 + p.size * .45, 1);
      }
      indices.push(i*4, i*4+1, i*4+2, i*4, i*4+2, i*4+3);
    });
    const mesh = new Mesh(name, scene), data = new VertexData();
    data.positions = positions; data.colors = colors; data.uvs = uvs; data.indices = indices; data.applyToMesh(mesh, true);
    const material = new ShaderMaterial(`${name}-soft-material`, scene, {
      vertexSource: `precision highp float;
        attribute vec3 position; attribute vec2 uv; attribute vec4 color;
        uniform mat4 worldView; uniform mat4 projection; uniform mat4 view;
        uniform vec3 fallDirection; uniform float streak; varying vec2 vUv; varying float opacity;
        void main(){
          vec4 p=worldView*vec4(position,1.0);
          vec2 along=normalize((view*vec4(fallDirection,0.0)).xy+vec2(.0001));
          vec2 across=vec2(-along.y,along.x);
          vec2 offset=mix(uv*color.xy,across*uv.x*color.x+along*uv.y*color.y,streak);
          p.xy+=offset; gl_Position=projection*p; vUv=uv;
          opacity=color.z*smoothstep(.35,1.2,p.z);
        }`,
      fragmentSource: `precision highp float; varying vec2 vUv; varying float opacity;
        uniform float streak; uniform float daylight;
        void main(){
          float flake=(1.0-smoothstep(.25,1.0,length(vUv)));
          float line=(1.0-smoothstep(.1,1.0,abs(vUv.x)))*(1.0-smoothstep(.5,1.0,abs(vUv.y)));
          float alpha=mix(flake,line*.58,streak)*opacity;
          if(alpha<.015) discard;
          gl_FragColor=vec4(mix(vec3(.48,.55,.65),vec3(.94,.97,1.0),daylight),alpha);
        }`,
    }, { attributes: ["position", "uv", "color"], uniforms: ["worldView", "projection", "view", "fallDirection", "streak", "daylight"], needAlphaBlending: true });
    material.backFaceCulling = false; material.disableDepthWrite = true; material.setFloat("streak", streak ? 1 : 0);
    mesh.material = material; mesh.parent = parent; mesh.isPickable = false; mesh.alwaysSelectAsActiveMesh = true; mesh.setEnabled(false);
    return { mesh, material, positions, particles };
  };
  const rain = makeBatch("weather-precipitation", 360, true);
  const snow = makeBatch("weather-snowflakes", 280, false);
  const splashes = makeBatch("rain-ground-splashes", 36, false);
  let time = 0;
  const fallDirection = new Vector3();
  const wrap = (n: number, span: number) => (n % span + span) % span;
  const disable = () => [rain,snow,splashes].forEach(b => { b.mesh.setEnabled(false); b.mesh.metadata = { activeCount: 0 }; });
  return {
    update(dt: number, kind: "rain" | "snow" | null, intensity: number, windX: number, windZ: number, daylight: number, reduced: boolean) {
      if (!kind || intensity <= 0 || reduced) { disable(); return 0; }
      const step = Number.isFinite(dt) ? Math.max(0, Math.min(.1, dt)) : 0; time += step;
      const batch = kind === "snow" ? snow : rain, isSnow = kind === "snow";
      const count = Math.min(batch.particles.length, Math.round(130 + intensity * 65));
      const inactive = isSnow ? rain : snow;
      inactive.mesh.setEnabled(false); inactive.mesh.metadata = { activeCount: 0 };
      batch.mesh.setEnabled(true); batch.mesh.metadata = { activeCount: count, kind };
      fallDirection.set(windX * .025, -7, windZ * .025);
      batch.material.setVector3("fallDirection", fallDirection); batch.material.setFloat("daylight", .35 + daylight * .65);
      batch.particles.forEach((p, i) => {
        const speed = isSnow ? .38 + p.size * .4 : 6.2 + p.size * 2.8;
        p.y -= step * speed;
        p.x = -8 + wrap(p.x + 8 + step * (windX * .025 + (isSnow ? Math.sin(time * .9 + p.phase) * .25 : 0)), 16);
        p.z = -20 + wrap(p.z + 20 + step * windZ * .025, 11.3);
        if (p.y < .015) p.y = 7 + p.y;
        for (let v = 0; v < 4; v++) {
          const offset = i * 12 + v * 3;
          batch.positions[offset] = p.x; batch.positions[offset+1] = i < count ? p.y : -100; batch.positions[offset+2] = p.z;
        }
      });
      batch.mesh.updateVerticesData(VertexBuffer.PositionKind, batch.positions, false, false);
      splashes.mesh.setEnabled(!isSnow);
      if (isSnow) splashes.mesh.metadata = { activeCount: 0 };
      if (!isSnow) {
        splashes.material.setFloat("daylight", .35 + daylight * .65); splashes.material.setVector3("fallDirection", fallDirection);
        splashes.mesh.metadata = { activeCount: 36 };
        splashes.particles.forEach((p,i) => {
          const phase = wrap(time * 1.8 + i * .618, 1), active = phase < .32;
          for (let v=0; v<4; v++) {
            const offset=i*12+v*3;
            splashes.positions[offset]=-3.6+wrap(i*1.618,6.1)+Math.sin(p.phase)*phase*.25;
            splashes.positions[offset+1]=active ? .015 + Math.sin(phase/.32*Math.PI)*.075 : -100;
            splashes.positions[offset+2]=-9-wrap(i*1.31,8)+Math.cos(p.phase)*phase*.25;
          }
        });
        splashes.mesh.updateVerticesData(VertexBuffer.PositionKind, splashes.positions, false, false);
      }
      return count;
    },
    reset: disable,
  };
}
