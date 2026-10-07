import { LoadAssetContainerAsync } from "@babylonjs/core/Loading/sceneLoader";
import "@babylonjs/loaders/glTF";
import { Scene } from "@babylonjs/core/scene";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { Mesh } from "@babylonjs/core/Meshes/mesh";
import { Vector3, Quaternion } from "@babylonjs/core/Maths/math.vector";
import { createRelaxedStaffPose } from "./reimaginedStaffPose";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import type { ShadowGenerator } from "@babylonjs/core/Lights/Shadows/shadowGenerator";
import { PointLight } from "@babylonjs/core/Lights/pointLight";
import { Color3 } from "@babylonjs/core/Maths/math.color";
import { createBlinkPlayback, createEyelidBuffer } from "./reimaginedCashierBlink";
import { createRestaurantUniform } from "./reimaginedRestaurantUniform";
import staffUrl from "./assets/reimagined/staff-makehuman.glb?url";

// Reuse the CC0-authored asset, never the uncleared historical RPM character.
export async function createRestaurantStaff(scene: Scene, shadows: ShadowGenerator, canvas: HTMLCanvasElement, cancelled: () => boolean) {
  const container = await LoadAssetContainerAsync(staffUrl, scene);
  if (cancelled()) { container.dispose(); return undefined; }
  try {
    let lastBlink = 0;
    container.addAllToScene();
    container.animationGroups.forEach(group => group.stop());
    // These low-resolution lash cards produce opaque spikes at the eyelid rim.
    // Keep the skinned eyelids; do not animate broken cards over the eyeballs.
    for (const mesh of container.meshes) if (mesh.name.includes("eyelashes01")) mesh.setEnabled(false);
    const root = new TransformNode("cashier", scene);
    container.rootNodes.forEach(node => { node.parent = root; });
    // Normalize from geometry bounds, independent of authoring units.
    const bounds = root.getHierarchyBoundingVectors(true);
    const factor = 1.8 / (bounds.max.y - bounds.min.y);
    root.scaling.setAll(factor);
    root.position.set(0, -bounds.min.y * factor, 4.22);
    root.rotation.y = Math.PI;

    for (const mesh of container.meshes) { mesh.isPickable = false; mesh.receiveShadows = true; if (mesh.getTotalVertices()) shadows.addShadowCaster(mesh); }
    // The room's brighter architectural lights must not bleach the skin.
    for(const light of scene.lights)if(light.name!=="restaurant-fill")light.excludedMeshes.push(...container.meshes);
    const staffKey=new PointLight("restaurant-staff-key",new Vector3(-.6,2.35,3.2),scene);
    staffKey.intensity=3.2;staffKey.range=3;staffKey.diffuse=new Color3(1,.91,.8);
    staffKey.includedOnlyMeshes.push(...container.meshes);
    for (const mat of container.materials) {
      if (!(mat instanceof PBRMaterial)) continue;
      // Preserve the authored texture/folds. A cloth response should not shine
      // like skin, and skin should not share the garment's dry roughness.
      if (mat.name.endsWith(".male_casualsuit01")) {
        // Keep the authored collar, buttons and fabric shading. Removing the
        // texture made the sleeves look like flat white plastic.
        mat.albedoColor = Color3.FromHexString("#e1e1dc").toLinearSpace();
        mat.roughness = .96; mat.metallicF0Factor = .45;
      } else if (mat.name.endsWith(".body")) {
        mat.roughness = .7; mat.metallicF0Factor = .65;
      } else if (mat.name.endsWith(".low-poly")) {
        mat.roughness = .28;
      }
    }
    // Staff should receive the actual checkout lights, not the first two
    // ceiling lamps in scene insertion order. Keep the four-light budget.
    for (const lamp of scene.lights) {
      if (lamp.name.startsWith("ceiling-bounce-")) lamp.excludedMeshes.push(...container.meshes);
    }
    for (const mat of container.materials) if (mat instanceof PBRMaterial) mat.maxSimultaneousLights = 4;
    const rigNames: Record<string, string> = {
      Spine2: "spine_03", Neck: "neck_01", Head: "head",
      LeftArm: "upperarm_l", RightArm: "upperarm_r",
      LeftForeArm: "lowerarm_l", RightForeArm: "lowerarm_r",
      LeftHand: "hand_l", RightHand: "hand_r",
      LeftHandMiddle1: "middle_01_l", RightHandMiddle1: "middle_01_r",
      LeftHandIndex1: "index_01_l", RightHandIndex1: "index_01_r",
      LeftHandPinky1: "pinky_01_l", RightHandPinky1: "pinky_01_r",
    };
    const node = (suffix: string) => container.transformNodes.find(n => n.name === rigNames[suffix]);
    if (Object.keys(rigNames).some(name => !node(name))) throw new Error("Cashier rig is incomplete");
    const chest = node("Spine2"), neck = node("Neck"), head = node("Head");
    const chestRest = chest?.rotationQuaternion?.clone() ?? Quaternion.Identity();
    const neckRest = neck?.rotationQuaternion?.clone() ?? Quaternion.Identity();
    const headRest = head?.rotationQuaternion?.clone() ?? Quaternion.Identity();
    const chestOffset = Quaternion.Identity(), neckOffset = Quaternion.Identity(), headOffset = Quaternion.Identity();
    if (chest) chest.rotationQuaternion ??= Quaternion.Identity();
    if (neck) neck.rotationQuaternion ??= Quaternion.Identity();
    if (head) head.rotationQuaternion ??= Quaternion.Identity();
    const relaxArms = createRelaxedStaffPose(container.transformNodes);
    relaxArms();
    createRestaurantUniform(scene, chest!, head!, container.meshes, shadows, staffKey);

    const eyelidUpdates = container.meshes.flatMap(mesh => {
      const manager = mesh.morphTargetManager;
      if (!manager) return [];
      const targets = Array.from({ length: manager.numTargets }, (_, i) => manager.getTarget(i))
        .filter(target => /^eyeBlink(Left|Right)$/.test(target.name));
      // Brows remain neutral; the faulty lash cards stay disabled. None of
      // these meshes should retain a GPU morph-texture shader variant.
      mesh.morphTargetManager = null;
      if (/eyebrow|eyelashes/.test(mesh.name) || !targets.length) return [];

      const buffers = ["position", "normal"].flatMap(kind => {
        const base = mesh.getVerticesData(kind);
        const values = targets.map(target => kind === "position" ? target.getPositions() : target.getNormals());
        if (!base || values.some(value => !value)) return [];
        const buffer = createEyelidBuffer(base, values as Float32Array[]);
        // Babylon's software skinning mutates its output array in place.
        // Never let that output alias our unskinned eyelid working buffer.
        const upload = buffer.data.slice();
        mesh.setVerticesData(kind, upload, true);
        return [{ kind, upload, ...buffer }];
      });

      let previous = -1;
      let previousGpu: boolean | undefined;
      return [(weight: number) => {
        const gpu = mesh.computeBonesUsingShaders;
        if (weight === previous && gpu === previousGpu) return;
        previous = weight;
        previousGpu = gpu;
        for (const buffer of buffers) {
          buffer.update(weight);
          if (!gpu && mesh instanceof Mesh) {
            // Software skinning overwrites the output vertex buffer each
            // frame. Deform its bind-pose INPUT, not the skinned output.
            const source = buffer.kind === "position"
              ? mesh.setPositionsForCPUSkinning() : mesh.setNormalsForCPUSkinning();
            if (!source) throw new Error(`Cashier CPU skinning is missing ${buffer.kind} input`);
            source.set(buffer.data);
          } else {
            buffer.upload.set(buffer.data);
            mesh.updateVerticesData(buffer.kind, buffer.upload, false, false);
          }
        }
      }];
    });
    canvas.dataset.staffDeformation = "sparse-eyelids-before-skinning";
    const blinkPlayback = createBlinkPlayback(true);
    let lastStaffTime = 0;

    const cashierBody = container.meshes.find(mesh => mesh.name === "DastakCashierBody");
    if (cashierBody instanceof Mesh) cashierBody.onAfterRenderObservable.add(() => { if (lastBlink > .95) blinkPlayback.markClosedRendered(lastStaffTime); });
    // A small chest/neck cycle, rather than scaling the whole person, gives
    // an understated breathing idle; the relaxed arm pose follows afterward.
    const update = (time: number) => {
      lastStaffTime = time;
      const breath = Math.sin(time * Math.PI * 2 / 5.4);
      if (chest) {
        Quaternion.RotationAxisToRef(Vector3.RightReadOnly, .012 + breath * .006, chestOffset);
        chestRest.multiplyToRef(chestOffset, chest.rotationQuaternion!);
      }
      if (neck) {
        Quaternion.RotationAxisToRef(Vector3.RightReadOnly, .025 + breath * .002, neckOffset);
        neckRest.multiplyToRef(neckOffset, neck.rotationQuaternion!);
      }
      if (head) {
        Quaternion.RotationYawPitchRollToRef(Math.sin(time * .31) * .008, .12 + Math.sin(time * .19) * .003, Math.sin(time * .23) * .004, headOffset);
        headRest.multiplyToRef(headOffset, head.rotationQuaternion!);
      }
      const wrists=relaxArms();
      canvas.dataset.leftWristHeight=wrists[0].y.toFixed(3);
      canvas.dataset.rightWristHeight=wrists[1].y.toFixed(3);
      // Smooth quick closure, short hold, slower opening. No sharp triangular
      // velocity reversal at full closure; both lids remain synchronized.
      const blink = blinkPlayback(time);
      lastBlink = blink;
      for (const update of eyelidUpdates) update(blink);
      canvas.dataset.blinkWeight = blink.toFixed(3);
    };

    update(0);
    canvas.dataset.staffPose = "arms-at-sides";
    canvas.dataset.staff = "ready";
    return update;
  } catch (error) { container.dispose(); throw error; }
}
