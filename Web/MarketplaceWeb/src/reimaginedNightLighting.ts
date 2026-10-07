import { Scene } from "@babylonjs/core/scene";
import { PointLight } from "@babylonjs/core/Lights/pointLight";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { Color3 } from "@babylonjs/core/Maths/math.color";
import { Vector3 } from "@babylonjs/core/Maths/math.vector";
import type { TransformNode } from "@babylonjs/core/Meshes/transformNode";

// Fixtures affect exterior PBR surfaces only; the approved interior lighting
// remains unchanged. Three local lights + sun/sky = five bounded light slots.
export function createNightLighting(scene: Scene, exterior: TransformNode) {
  const meshes = exterior.getChildMeshes().filter(mesh => mesh.material instanceof PBRMaterial
    && !/^(tree-|hedge-|left-evergreen|right-evergreen|landscape-)/.test(mesh.name));
  const existingLights = [...scene.lights];
  // Decorative spill lamps should light the entrance, not draw bright discs
  // on its panes. Keep the shared glass material and sky reflections intact.
  const panes = meshes.filter(mesh => /^(storefront-window|sliding-door-glass)$/.test(mesh.name));
  const receivers = meshes.filter(mesh => !panes.includes(mesh));
  for (const mesh of meshes) {
    (mesh.material as PBRMaterial).maxSimultaneousLights = 5;
    for (const light of existingLights) {
      if (!["entrance-daylight", "soft-skylight"].includes(light.name)) light.excludedMeshes.push(mesh);
    }
  }
  const specs = [
    { name: "canopy-night-spill", position: new Vector3(-.5, 2.55, -8.12), intensity: 15, range: 9, color: "#fff0d7" },
    { name: "left-path-night-spill", position: new Vector3(-3.85, .68, -12.35), intensity: 4.5, range: 7, color: "#ffdcb0" },
    { name: "right-path-night-spill", position: new Vector3(2.85, .68, -12.35), intensity: 4.5, range: 7, color: "#ffdcb0" },
  ];
  const lamps = specs.map(spec => {
    const lamp = new PointLight(spec.name, spec.position, scene);
    lamp.diffuse = Color3.FromHexString(spec.color); lamp.range = spec.range; lamp.radius = .35;
    lamp.specular = new Color3(.16, .14, .12);
    lamp.includedOnlyMeshes = receivers;
    lamp.excludedMeshes = panes; lamp.intensity = 0;
    return lamp;
  });
  return {
    update(daylight: number, outside: boolean) {
      const dusk = Math.max(0, Math.min(1, ( .65 - daylight) / .65));
      const level = outside ? dusk * dusk * (3 - 2 * dusk) : 0;
      lamps.forEach((lamp, i) => { lamp.intensity = specs[i].intensity * level; });
      return level;
    },
  };
}
