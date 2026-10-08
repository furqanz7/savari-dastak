import { Engine } from "@babylonjs/core/Engines/engine";
import { Scene } from "@babylonjs/core/scene";
import { Color3, Color4 } from "@babylonjs/core/Maths/math.color";
import { Vector3, Quaternion } from "@babylonjs/core/Maths/math.vector";
import { createRelaxedStaffPose } from "./reimaginedStaffPose";
import { Viewport } from "@babylonjs/core/Maths/math.viewport";
import { FreeCamera } from "@babylonjs/core/Cameras/freeCamera";
import { HemisphericLight } from "@babylonjs/core/Lights/hemisphericLight";
import { DirectionalLight } from "@babylonjs/core/Lights/directionalLight";
import { PointLight } from "@babylonjs/core/Lights/pointLight";
import { ShadowGenerator } from "@babylonjs/core/Lights/Shadows/shadowGenerator";
import "@babylonjs/core/Lights/Shadows/shadowGeneratorSceneComponent";
import { MeshBuilder } from "@babylonjs/core/Meshes/meshBuilder";
import { Mesh } from "@babylonjs/core/Meshes/mesh";
import { VertexData } from "@babylonjs/core/Meshes/mesh.vertexData";
import { TransformNode } from "@babylonjs/core/Meshes/transformNode";
import { PBRMaterial } from "@babylonjs/core/Materials/PBR/pbrMaterial";
import { DynamicTexture } from "@babylonjs/core/Materials/Textures/dynamicTexture";
import { Texture } from "@babylonjs/core/Materials/Textures/texture";
import { CubeTexture } from "@babylonjs/core/Materials/Textures/cubeTexture";
import { DefaultRenderingPipeline } from "@babylonjs/core/PostProcesses/RenderPipeline/Pipelines/defaultRenderingPipeline";
import { SSAO2RenderingPipeline } from "@babylonjs/core/PostProcesses/RenderPipeline/Pipelines/ssao2RenderingPipeline";
import { LoadAssetContainerAsync } from "@babylonjs/core/Loading/sceneLoader";
import "@babylonjs/core/Shaders/postprocess.vertex";
import "@babylonjs/core/Shaders/rgbdDecode.fragment";
// Register GLSL before pipeline construction. Safari can compile an effect
// before its deferred shader import finishes; missing entries otherwise fall
// back to .fx requests that Vite answers with HTML, not shader source.
import "@babylonjs/core/Shaders/pass.fragment";
import "@babylonjs/core/Shaders/ssao2.fragment";
import "@babylonjs/core/Shaders/ssaoCombine.fragment";
import "@babylonjs/core/Shaders/extractHighlights.fragment";
import "@babylonjs/core/Shaders/bloomMerge.fragment";
import "@babylonjs/core/Shaders/kernelBlur.vertex";
import "@babylonjs/core/Shaders/kernelBlur.fragment";
import "@babylonjs/core/Shaders/fxaa.vertex";
import "@babylonjs/core/Shaders/fxaa.fragment";
import "@babylonjs/core/Shaders/imageProcessing.fragment";
import "@babylonjs/core/Shaders/shadowMap.vertex";
import "@babylonjs/core/Shaders/shadowMap.fragment";
import "@babylonjs/loaders/glTF";
import lightUrl from "./assets/reimagined/store-light.env?url";
import bundledStaffUrl from "./assets/reimagined/staff-makehuman.glb?url";
import pavementColorUrl from "./assets/reimagined/exterior-pavement-color.jpg?url";
import pavementNormalUrl from "./assets/reimagined/exterior-pavement-normal.jpg?url";
import pavementArmUrl from "./assets/reimagined/exterior-pavement-arm.jpg?url";
import woodColorUrl from "./assets/reimagined/wood_floor-color.jpg?url";
import woodNormalUrl from "./assets/reimagined/wood_floor-normal.jpg?url";
import { createBlinkPlayback, createEyelidBuffer } from "./reimaginedCashierBlink";
import { createOutdoor } from "./reimaginedOutdoor";
import { leafSpray } from "./reimaginedPlanting";
import { createNightLighting } from "./reimaginedNightLighting";
import type { OutdoorWeather } from "./reimaginedWeather";
// Ship only the CC0-authored replacement; historical RPM candidates stay unused.
// Fingerprint of the current local GLB, so older same-path character assets
// cannot silently survive a preview revision in a browser cache.
const staffUrl = import.meta.env.DEV ? "/src/assets/reimagined/staff-makehuman.glb?rev=adf9f73504acff6a" : bundledStaffUrl;

export type GroceryScene = { setWeather: (value: OutdoorWeather | null) => void; setCounter: (value: boolean) => void; setOutside: (value: boolean) => void; setStaffPlayback: (value: boolean) => void; setEyesClosed: (value: boolean) => void; testBlink: () => void; dispose: () => void };
type Options = { weather?: OutdoorWeather | null; counter: boolean; outside?: boolean; playStaff?: boolean; eyesClosed?: boolean; onStatus: (status: string) => void; onReady?: () => void };

// Entirely decorative. No catalogue, pricing, authentication or order state lives here.
export function createGroceryScene(canvas: HTMLCanvasElement, options: Options): GroceryScene {
  const mobile = window.matchMedia("(max-width: 720px)");
  const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const engine = new Engine(canvas, true, { stencil: true, preserveDrawingBuffer: false, powerPreference: "low-power" }, true);
  try {
  engine.setHardwareScalingLevel(1 / Math.min(window.devicePixelRatio || 1, mobile.matches ? 1.25 : 1.5));
  const scene = new Scene(engine);
  scene.clearColor = new Color4(.075, .083, .075, 1);
  scene.ambientColor = new Color3(.42, .44, .46);
  scene.environmentTexture = CubeTexture.CreateFromPrefilteredData(lightUrl, scene);
  scene.environmentIntensity = .58;
  scene.imageProcessingConfiguration.toneMappingEnabled = true;
  scene.imageProcessingConfiguration.toneMappingType = 1;
  scene.imageProcessingConfiguration.exposure = 1.24;
  scene.imageProcessingConfiguration.contrast = 1.22;
  scene.fogMode = Scene.FOGMODE_EXP2;
  scene.fogDensity = .005;
  scene.fogColor = new Color3(.65, .68, .7);
  let disposed = false;
  let atCounter = options.counter;
  let outside = Boolean(options.outside);
  let firstFrameReady = false;
  let weather = options.weather ?? null;
  let outdoorMinute = -1;
  let clock = 0;
  let lastFrameTime = performance.now();
  let frames = 0;
  let dirty = true;
  let blinkTestStarted = -Infinity;
  let staffPlaybackRequested = import.meta.env.DEV && Boolean(options.playStaff);
  const staffPlaying = () => !motion.matches || staffPlaybackRequested;
  let renderedBlinks = 0;
  let sawClosedEyes = false;
  let reportedSecond = -1;
  let bodyDrawnThisFrame = false;
  let bodyDrawFrames = 0;
  let eyesClosed = import.meta.env.DEV && Boolean(options.eyesClosed);
  let eyelidGeometryReady = false;
  let confirmClosedDraw: (() => void) | undefined;
  let staffUpdate: ((time: number) => void) | undefined;
  const camera = new FreeCamera("entrance-camera", new Vector3(-.6, 1.72, -5.8), scene);
  camera.minZ = .08;
  camera.maxZ = 65;
  camera.fov = .92;
  const gaze = new Vector3(.6, 1.45, 6.5);
  camera.setTarget(gaze);
  const fill = new HemisphericLight("soft-skylight", new Vector3(0, 1, -.2), scene);
  fill.intensity = .22;
  fill.diffuse = new Color3(.94, .96, 1);
  fill.groundColor = new Color3(.28, .3, .32);
  const sun = new DirectionalLight("entrance-daylight", new Vector3(.45, -1, .7), scene);
  sun.position = new Vector3(-5, 9, -5);
  sun.intensity = 1.35;
  sun.diffuse = new Color3(1, .98, .95);
  const shadows = new ShadowGenerator(mobile.matches ? 512 : 1024, sun);
  shadows.usePercentageCloserFiltering = true;
  shadows.bias = .001;
  shadows.normalBias = .025;
  shadows.darkness = .08;
  // Half-resolution contact shading only on desktop WebGL2. Phone layouts keep
  // the cheaper material/shadow path; no second geometry pass is forced.
  const contactShading = !mobile.matches && SSAO2RenderingPipeline.IsSupported
    ? new SSAO2RenderingPipeline("store-contact", scene, { ssaoRatio: .5, blurRatio: .5 }, [camera]) : undefined;
  if (contactShading) {
    contactShading.radius = .32; contactShading.totalStrength = .85;
    contactShading.samples = 8; contactShading.textureSamples = 1;
    contactShading.maxZ = 22; contactShading.bilateralSamples = 8;
  }
  canvas.dataset.contactShading = contactShading ? "ssao-half" : "lightweight";
  const pipeline = new DefaultRenderingPipeline("store-film", true, scene, [camera]);
  pipeline.fxaaEnabled = true;
  pipeline.samples = 1;
  pipeline.bloomEnabled = !mobile.matches;
  pipeline.bloomThreshold = 1.15;
  pipeline.bloomWeight = .08;
  pipeline.bloomKernel = 32;

  const color = (hex: string) => Color3.FromHexString(hex);
  function material(name: string, hex: string, roughness = .65, metallic = 0) {
    const m = new PBRMaterial(name, scene);
    m.albedoColor = color(hex).toLinearSpace(); m.roughness = roughness; m.metallic = metallic; m.maxSimultaneousLights = 4;
    return m;
  }
  const charcoal = material("powder-coated-steel", "#15191e", .5, .15);
  const dark = material("rubber-and-cables", "#121519", .9);
  const brass = material("anodized-trim", "#969da2", .32, .75);
  const steel = material("brushed-stainless", "#b5bbc0", .24, .9);
  const plaster = material("white-retail-panels", "#eceeed", .74);
  const ceiling = material("exposed-charcoal-ceiling", "#171c21", .98);
  const shelfFinish = material("shelf-enamel", "#e5e8e8", .4, .18);
  const accent = material("checkout-red", "#972127", .32, .08);
  accent.clearCoat.isEnabled = true; accent.clearCoat.intensity = .45; accent.clearCoat.roughness = .23;
  const light = material("neutral-led-diffuser", "#ffffff", .35);
  light.emissiveColor = new Color3(3.2, 3.2, 3.2);
  const coolLight = material("fridge-led", "#e3fff6", .3);
  coolLight.emissiveColor = new Color3(1.5, 2.6, 2.5);
  const glass = material("fridge-glass", "#a8d2c6", .12, .15);
  glass.alpha = .15;
  glass.backFaceCulling = false;
  const floor = material("polished-porcelain", "#ffffff", .3);
  // Deterministic local textures; no image-generation calls or remote asset requests.
  let seed = 7193;
  const random = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
  function texture(name: string, width: number, height: number, paint: (ctx: CanvasRenderingContext2D) => void) {
    const t = new DynamicTexture(name, { width, height }, scene, true);
    paint(t.getContext() as unknown as CanvasRenderingContext2D); t.update(); return t;
  }
  // Fine horizontal brushing separates metal from plastic without another render pass.
  steel.albedoTexture = texture("stainless-brush", 256, 128, ctx => {
    ctx.fillStyle = "#e1e4e6"; ctx.fillRect(0, 0, 256, 128);
    for (let y = 0; y < 128; y++) {
      ctx.fillStyle = `rgba(66,76,88,${.025 + random() * .075})`;
      ctx.fillRect(0, y, 256, 1);
    }
  });
  const tiles = texture("porcelain-tile-grid", 512, 512, ctx => {
    const tileShade = ctx.createLinearGradient(0, 0, 512, 512);
    tileShade.addColorStop(0, "#d2d3cc"); tileShade.addColorStop(.55, "#dedfd8"); tileShade.addColorStop(1, "#d6d7d0");
    ctx.fillStyle = tileShade; ctx.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 5000; i++) {
      ctx.fillStyle = `rgba(110,117,121,${random() * .035})`;
      ctx.fillRect(random() * 512, random() * 512, 1, 1);
    }
    ctx.fillStyle = "#969b98"; ctx.fillRect(0, 0, 2, 512); ctx.fillRect(0, 0, 512, 2);
    ctx.fillStyle = "#efefe7"; ctx.fillRect(2, 2, 1, 510); ctx.fillRect(2, 2, 510, 1);
  });
  tiles.uScale = 14 / 1.2; tiles.vScale = 26 / 1.2;
  tiles.wrapU = Texture.WRAP_ADDRESSMODE; tiles.wrapV = Texture.WRAP_ADDRESSMODE;
  tiles.anisotropicFilteringLevel = mobile.matches ? 4 : 8;
  floor.albedoTexture = tiles;
  const tileSurface = texture("porcelain-microsurface", 256, 256, ctx => {
    // PBR packed channels: red AO, green roughness, blue metalness (zero).
    ctx.fillStyle = "rgb(255,165,0)"; ctx.fillRect(0, 0, 256, 256);
    for (let n = 0; n < 1600; n++) {
      ctx.fillStyle = `rgb(255,${150 + Math.floor(random() * 35)},0)`;
      ctx.fillRect(random() * 256, random() * 256, 3, 3);
    }
    ctx.fillStyle = "rgb(255,255,0)"; ctx.fillRect(0, 0, 1, 256); ctx.fillRect(0, 0, 256, 1);
  });
  tileSurface.uScale = tiles.uScale; tileSurface.vScale = tiles.vScale;
  tileSurface.wrapU = Texture.WRAP_ADDRESSMODE; tileSurface.wrapV = Texture.WRAP_ADDRESSMODE;
  floor.metallicTexture = tileSurface; floor.metallic = 0;
  floor.useRoughnessFromMetallicTextureAlpha = false;
  floor.useRoughnessFromMetallicTextureGreen = true;
  floor.clearCoat.isEnabled = true; floor.clearCoat.intensity = .5; floor.clearCoat.roughness = .15;
  const stone = material("honed-charcoal-stone", "#ffffff", .38);
  stone.albedoTexture = texture("stone-mineral-grain", 512, 512, ctx => {
    ctx.fillStyle = "#303438"; ctx.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 16000; i++) {
      const shade = random() > .65 ? "186,192,196" : "12,17,22";
      ctx.fillStyle = `rgba(${shade},${.04 + random() * .18})`;
      ctx.fillRect(random() * 512, random() * 512, .4 + random() * 1.1, .4 + random() * 1.1);
    }
  });
  stone.bumpTexture = texture("stone-fine-normal", 128, 128, ctx => {
    ctx.fillStyle = "rgb(128,128,255)"; ctx.fillRect(0, 0, 128, 128);
    for (let i = 0; i < 5000; i++) {
      ctx.fillStyle = `rgb(${122 + Math.floor(random() * 12)},${122 + Math.floor(random() * 12)},255)`;
      ctx.fillRect(random() * 128, random() * 128, 1, 1);
    }
  });
  stone.bumpTexture.gammaSpace = false; stone.bumpTexture.level = .2;
  stone.clearCoat.isEnabled = true; stone.clearCoat.intensity = .26; stone.clearCoat.roughness = .24;
  const staticMeshes: Mesh[] = [];
  function box(name: string, x: number, y: number, z: number, w: number, h: number, d: number, mat: PBRMaterial, shadow = false) {
    const m = MeshBuilder.CreateBox(name, { width: w, height: h, depth: d }, scene);
    m.position.set(x, y, z); m.material = mat; m.isPickable = false; m.receiveShadows = true;
    m.metadata = { castsStoreShadow: shadow };
    staticMeshes.push(m); return m;
  }
  function cylinder(name: string, x: number, y: number, z: number, diameter: number, height: number, mat: PBRMaterial) {
    const m = MeshBuilder.CreateCylinder(name, { diameter, height, tessellation: 16 }, scene);
    m.position.set(x, y, z); m.material = mat; m.isPickable = false; staticMeshes.push(m); return m;
  }
  function beveledBox(name: string, x: number, y: number, z: number, w: number, h: number, d: number, bevel: number, mat: PBRMaterial) {
    const mesh = new Mesh(name, scene);
    const positions: number[] = [], indices: number[] = [], normals: number[] = [], uvs: number[] = [];
    const ring = (inset: number, height: number) => {
      const a = w / 2 - inset, b = d / 2 - inset, r = bevel;
      for (const [px, pz] of [[-a + r, -b], [a - r, -b], [a, -b + r], [a, b - r], [a - r, b], [-a + r, b], [-a, b - r], [-a, -b + r]]) {
        positions.push(px, height, pz); uvs.push(px / w + .5, pz / d + .5);
      }
    };
    ring(bevel, -h / 2); ring(0, -h / 2 + bevel);
    ring(0, h / 2 - bevel); ring(bevel, h / 2);
    for (let level = 0; level < 3; level++) for (let i = 0; i < 8; i++) {
      const a = level * 8 + i, b = level * 8 + (i + 1) % 8;
      indices.push(a, b + 8, b, a, a + 8, b + 8);
    }
    positions.push(0, -h / 2, 0, 0, h / 2, 0); uvs.push(.5, .5, .5, .5);
    for (let i = 0; i < 8; i++) indices.push(32, i, (i + 1) % 8, 33, 24 + (i + 1) % 8, 24 + i);
    // Babylon's default left-handed winding is opposite this ring traversal.
    // Reverse every face so caps and chamfers face out, not into the solid.
    for (let i = 0; i < indices.length; i += 3) [indices[i + 1], indices[i + 2]] = [indices[i + 2], indices[i + 1]];
    VertexData.ComputeNormals(positions, indices, normals);
    const data = new VertexData(); data.positions = positions; data.indices = indices; data.normals = normals; data.uvs = uvs; data.applyToMesh(mesh);
    mesh.position.set(x, y, z); mesh.material = mat; mesh.isPickable = false;
    mesh.metadata = { castsStoreShadow: true }; staticMeshes.push(mesh); return mesh;
  }
  function sign(name: string, text: string, subtitle: string, x: number, y: number, z: number, width: number, height: number, bg = "#1d242b") {
    const t = texture(name, 1024, 256, ctx => {
      ctx.fillStyle = bg; ctx.fillRect(0, 0, 1024, 256);
      ctx.fillStyle = "#ffffff"; ctx.textAlign = "center"; ctx.font = "bold 76px sans-serif"; ctx.fillText(text, 512, 123, 950);
      ctx.fillStyle = "#cbd3da"; ctx.font = "24px sans-serif"; ctx.fillText(subtitle, 512, 188, 950);
      ctx.fillStyle = "#d74345"; ctx.fillRect(0, 244, 1024, 12);
    });
    const mat = material(name, "#ffffff", .75); mat.albedoTexture = t; mat.emissiveColor = new Color3(.1, .1, .1);
    return box(name, x, y, z, width, height, .035, mat);
  }
  box("floor", 0, -.08, 6, 14, .15, 26, floor);
  // Small baked-style contact patches ground the hero fixtures on phone too.
  // Shared 128px alpha texture, no extra scene render or screen-space pass.
  const contact = material("fixture-contact-occlusion", "#172026", 1);
  contact.unlit = true; contact.disableDepthWrite = true;
  contact.albedoTexture = texture("soft-rectangular-contact", 128, 128, ctx => {
    const pixels = ctx.createImageData(128, 128);
    for (let y = 0; y < 128; y++) for (let x = 0; x < 128; x++) {
      const edge = Math.max(Math.abs(x - 63.5), Math.abs(y - 63.5)) / 63.5;
      const falloff = Math.max(0, Math.min(1, (1 - edge) / .32));
      pixels.data[(y * 128 + x) * 4 + 3] = Math.round(70 * falloff * falloff);
    }
    ctx.putImageData(pixels, 0, 0);
  });
  contact.albedoTexture.hasAlpha = true; contact.useAlphaFromAlbedoTexture = true;
  function contactPatch(name: string, x: number, z: number, width: number, height: number) {
    const mesh = MeshBuilder.CreateGround(name, { width, height }, scene);
    mesh.position.set(x, -.003, z); mesh.material = contact; mesh.isPickable = false;
    mesh.freezeWorldMatrix();
  }
  contactPatch("checkout-ground-contact", 3.45, -.3, 3.95, 1.65);
  const shelfCenters = [-1.1, 1.1];
  const heroShelfX = shelfCenters[1];
  for (const x of shelfCenters) contactPatch("aisle-ground-contact", x, 8.5, 1.38, 11.45);
  box("ceiling", 0, 3.8, 6, 14, .18, 26, ceiling);
  box("back-wall", 0, 1.8, 18, 14, 3.6, .25, plaster);
  // Enclose the room directly behind the fridge bank; the old wall left
  // a wide unused side bay visible through the storefront glazing.
  box("left-wall", -3.9, 1.8, 6, .2, 3.6, 26, charcoal);
  const rightWallX = 3;
  box("right-wall", rightWallX, 1.8, 6, .2, 3.6, 26, plaster);
  // Retail wall panels, a darker impact rail and a continuous luminous reveal
  // give the checkout a finished architectural backdrop instead of a blank wall.
  const wallBase = material("retail-wall-base", "#636e75", .7);
  box("right-wall-plinth", rightWallX - .125, .19, 6, .055, .38, 26, wallBase);
  box("right-wall-impact-rail", rightWallX - .16, .91, 6, .06, .075, 26, steel);
  for (let z = -5; z < 18; z += 1.5) {
    box("wall-panel-reveal", rightWallX - .111, 1.87, z, .012, 2.96, .012, wallBase);
  }
  box("perimeter-light-channel", rightWallX - .17, 3.19, 6, .16, .12, 26, charcoal);
  box("perimeter-light-diffuser", rightWallX - .26, 3.17, 6, .025, .038, 26, light);
  // Open checkout sightline into the shop, with exposed beams and services.
  for (let z = -4; z < 18; z += 3.2) {
    box("exposed-ceiling-beam", 0, 3.57, z, 13.8, .23, .14, charcoal);
    const pipe = cylinder("ceiling-service-pipe", 0, 3.64, z + .65, .08, 13.8, steel);
    pipe.rotation.z = Math.PI / 2;
  }
  for (const x of [-3.8, 3.8]) box("ventilation-duct", x, 3.61, 6, .38, .19, 23, charcoal);
  for (const x of [-5.5, -2.2, 1.3, 5]) {
    box("lighting-track", x, 3.43, 6, .065, .08, 23, charcoal);
    for (let z = -3; z < 18; z += 3.2) {
      box("linear-light-housing", x, 3.35, z, .22, .1, 3.1, shelfFinish);
      box("linear-diffuser", x, 3.29, z, .17, .025, 3, light);
    }
  }
  for (let z = 0; z < 17; z += 6) {
    const lamp = new PointLight(`ceiling-bounce-${z}`, new Vector3(0, 3.1, z), scene);
    lamp.diffuse = new Color3(1, 1, 1); lamp.intensity = 8; lamp.range = 9;
  }
  sign("back-brand", "DASTAK", "GOOD THINGS, CLOSE TO HOME", 0, 2.85, 17.8, 4.2, 1);

  // Batched shelf stock: printed fictional packaging represents ambience, not SKUs.
  const palette = ["#ae7732", "#ecd3a0", "#a92923", "#215941", "#ecb82d", "#e5eee9", "#244f8b", "#903657", "#d77828", "#64a441", "#8e5436", "#386e88"];
  const labels = ["GRAINS", "OATS", "SPICE", "TEA", "CRUNCH", "MILK", "COCOA", "BLEND", "COFFEE", "CRACKERS", "NUTS", "SPRING"];
  const prototypes: Mesh[] = palette.map((hex, i) => {
    const t = texture(`pack-label-${i}`, 128, 256, ctx => {
      ctx.fillStyle = hex; ctx.fillRect(0, 0, 128, 256);
      const ink = i % 4 === 1 ? "#23362c" : "#fff6e4";
      ctx.fillStyle = i % 2 ? "#ffffee" : "#182e27"; ctx.fillRect(0, 0, 128, 26);
      ctx.fillStyle = i % 2 ? "#243629" : "#ffffff";
      ctx.textAlign = "center"; ctx.font = "bold 10px sans-serif"; ctx.fillText("DASTAK PANTRY", 64, 17);
      ctx.fillStyle = ink; ctx.font = "bold 23px sans-serif"; ctx.fillText(labels[i], 64, 63, 118);
      ctx.font = "10px sans-serif"; ctx.fillText(i % 2 ? "EVERYDAY ESSENTIALS" : "SELECT COLLECTION", 64, 81);
      // Distinct illustration blocks, not one repeated label on every family.
      ctx.fillStyle = "#f2dfb4"; ctx.beginPath(); ctx.ellipse(64, 149, 43, 34, 0, 0, Math.PI * 2); ctx.fill();
      for (let n = 0; n < 17; n++) {
        const a = n * 2.4, r = 6 + Math.sqrt(n) * 6;
        ctx.fillStyle = n % 3 ? (i % 2 ? "#a77a39" : "#654c2c") : "#dbb864";
        ctx.beginPath(); ctx.ellipse(64 + Math.cos(a) * r, 145 + Math.sin(a) * r * .6, i % 3 === 0 ? 3 : 6, 3, a, 0, Math.PI * 2); ctx.fill();
      }
      ctx.fillStyle = ink; ctx.fillRect(10, 205, 108, 2);
      ctx.font = "9px sans-serif"; ctx.fillText("LOCAL SCENERY", 64, 222);
      ctx.fillStyle = "#fffdf5"; ctx.fillRect(88, 231, 29, 18);
      ctx.fillStyle = "#263027"; for (let n = 0; n < 11; n++) ctx.fillRect(90 + n * 2, 234, n % 3 === 0 ? 2 : 1, 12);
    });
    const mat = material(`pack-${i}`, "#ffffff", i % 4 === 2 ? .38 : .65); mat.albedoTexture = t;
    const parts: Mesh[] = [];
    const shape = i % 4;
    if (shape === 0 || shape === 3) {
      const body = MeshBuilder.CreateCylinder(`stock-body-${i}`, { diameter: shape === 3 ? .66 : .84, height: .84, tessellation: 16 }, scene);
      body.position.y = -.08; body.material = mat; parts.push(body);
      const cap = MeshBuilder.CreateCylinder(`stock-cap-${i}`, { diameter: shape === 3 ? .34 : .88, height: .12, tessellation: 16 }, scene);
      cap.position.y = .4; cap.material = shape === 3 ? brass : steel; parts.push(cap);
      if (shape === 3) {
        const shoulder = MeshBuilder.CreateCylinder(`stock-shoulder-${i}`, { diameterBottom: .66, diameterTop: .32, height: .16, tessellation: 16 }, scene);
        shoulder.position.y = .32; shoulder.material = mat; parts.push(shoulder);
      }
    } else {
      const body = MeshBuilder.CreateBox(`stock-body-${i}`, { width: .95, height: 1, depth: shape === 1 ? .65 : .85, updatable: shape === 2 }, scene);
      if (shape === 2) {
        // Pinch the top of flexible pouches rather than drawing a rigid carton
        // with a seam. Deform the shared prototype once, never its instances.
        const positions = body.getVerticesData("position")!;
        for (let n = 0; n < positions.length; n += 3) {
          if (positions[n + 1] > 0) { positions[n] *= .87; positions[n + 2] *= .18; }
        }
        body.updateVerticesData("position", positions);
        body.createNormals(true);
      }
      body.material = mat; parts.push(body);
      if (shape === 2) {
        const seam = MeshBuilder.CreateBox(`stock-seam-${i}`, { width: .84, height: .045, depth: .17 }, scene);
        seam.position.y = .49; seam.material = mat; parts.push(seam);
      }
    }
    const m = Mesh.MergeMeshes(parts, true, true, undefined, false, true)!;
    m.name = `stock-prototype-${i}`; m.isVisible = false; return m;
  });
  let packNumber = 0;
  let heroPackCount = 0;
  function pack(x: number, y: number, z: number, i: number, rotation = 0, size = .3, hero = false) {
    const m = prototypes[i % prototypes.length].createInstance(`pack-${packNumber++}`);
    const height = size * (1 + (i % 4) * .07) * (hero ? .97 + (packNumber % 5) * .012 : 1);
    m.position.set(x, y + height / 2, z);
    m.scaling.set(size * (.62 + (i % 3) * .045), height, size * .5);
    m.rotation.y = rotation + Math.sin(packNumber * 9.7) * .035;
    if (hero) { m.rotation.y += Math.sin(packNumber * 3.1) * .06; heroPackCount++; }
    m.isPickable = false; m.freezeWorldMatrix();
  }
  const ticket = material("shelf-label-holder", "#ffffff", .78);
  ticket.albedoTexture = texture("decorative-shelf-ticket", 256, 64, ctx => {
    ctx.fillStyle = "#f7f4e7"; ctx.fillRect(0, 0, 256, 64);
    ctx.fillStyle = "#ead44c"; ctx.fillRect(0, 0, 42, 64);
    ctx.fillStyle = "#283530"; ctx.font = "bold 15px sans-serif"; ctx.fillText("PANTRY", 54, 24);
    for (let n = 0; n < 29; n++) ctx.fillRect(56 + n * 4, 35, n % 3 ? 1 : 3, 17);
  });
  function shelf(x: number, z: number, width: number, length: number) {
    box("gondola-back", x, 1.12, z, .06, 2.1, length, charcoal, true);
    box("gondola-plinth", x, .15, z, width, .28, length, charcoal, true);
    for (const end of [-1, 1]) box("gondola-upright", x, 1.15, z + end * length / 2, .09, 2.3, .09, steel);
    for (let level = 0; level < 5; level++) {
      const y = .33 + level * .38;
      box("shelf-board", x, y, z, width, .045, length, steel);
      for (const side of [-1, 1]) {
        box("shelf-ticket-rail", x + side * width / 2, y + .02, z, .018, .058, length, shelfFinish);
        for (let tag = 0; tag < length / 1.2; tag++) box("shelf-label", x + side * (width / 2 + .012), y + .026, z - length / 2 + .4 + tag * 1.2, .008, .052, .21, ticket);
        for (let n = 0; n < length / .24 - 1; n++) {
          const group = (Math.floor(n / 5) + level * 3 + Math.round(x + 10)) % palette.length;
          const hero = x === heroShelfX && n < 13;
          const packZ = z - length / 2 + .2 + n * .24;
          const setback = hero ? .025 + (n % 4) * .018 : n % 7 === 0 ? .035 : 0;
          // Sparse front gaps expose a second row, not an empty cardboard wall.
          if (!hero || (n + level * 3) % 11 !== 4) {
            pack(x + side * (width / 2 - .14 - setback), y + .025, packZ, group, side * Math.PI / 2, .24 + (group % 3) * .014, hero);
          }
          if (hero && n % 2 === 0) pack(x + side * .13, y + .025, packZ + .025, group, side * Math.PI / 2, .24, true);
        }
      }
    }
  }
  for (const [aisleIndex, x] of shelfCenters.entries()) {
    shelf(x, 9, 1, 10);
    if (x === heroShelfX) {
      cylinder("hero-endcap-plinth", x, .14, 3.75, 1.07, .27, charcoal);
      for (const dx of [-.31, .31]) {
        box("hero-endcap-upright", x + dx, 1.14, 3.94, .065, 2.16, .065, steel, true);
        for (let y = .46; y < 2.1; y += .12) box("upright-adjustment-slot", x + dx, y, 3.903, .018, .036, .005, dark);
      }
      sign("hero-aisle-header", "PANTRY PICKS", "EVERYDAY ESSENTIALS", x, 2.25, 3.69, 1.08, .22, "#244438");
    }
    // Endcaps face the entrance and communicate store depth.
    for (let level = 0; level < 5; level++) {
      const y = .33 + level * .38;
      cylinder("rounded-endcap", x, y, 3.75, 1.1, .055, charcoal);
      for (let n = 0; n < 7; n++) {
        const angle = -Math.PI / 2 + n * Math.PI / 6;
        const hero = x === heroShelfX;
        if (hero && level === 2 && n === 4) continue;
        pack(x + Math.sin(angle) * .41, y + .03, 3.75 - Math.cos(angle) * .41 + (hero && n % 3 === 0 ? .035 : 0), level + Math.round(x + 4), -angle, .28, hero);
      }
      if (x === heroShelfX) {
        // Real front-facing ticket pockets and side dividers, kept in static batches.
        box("endcap-ticket-pocket", x, y - .005, 3.19, .36, .065, .012, shelfFinish);
        box("endcap-ticket-insert", x, y - .003, 3.18, .29, .043, .005, ticket);
        for (const dx of [-.22, .22]) box("endcap-stock-divider", x + dx, y + .052, 3.53, .012, .06, .36, shelfFinish);
      }
    }
    const index = `0${aisleIndex + 1}`;
    sign(`aisle-${index}`, index + "   /   " + (aisleIndex === 0 ? "Grocery" : "Snacks & home"), "DASTAK  /  EVERYDAY ESSENTIALS", x, 2.9, 4.8, 1.85, .56);
    for (const offset of [-.75, .75]) cylinder("sign-cable", x + offset, 3.33, 4.8, .013, .6, dark);
  }
  // Single-sided wall stock starts beyond checkout, keeping the cashier bay clear.
  const wallShelfFront = rightWallX - .67;
  const wallShelfCenterZ = 8.6;
  const wallShelfLength = 11.2;
  box("wall-stock-back", rightWallX - .13, 1.13, wallShelfCenterZ, .04, 2.2, wallShelfLength, charcoal);
  box("wall-stock-plinth", rightWallX - .4, .14, wallShelfCenterZ, .54, .28, wallShelfLength, charcoal);
  for (let z = 3; z <= 14.2; z += 1.4) {
    box("wall-stock-upright", rightWallX - .18, 1.16, z, .07, 2.32, .065, steel);
  }
  for (let level = 0; level < 5; level++) {
    const y = .33 + level * .38;
    box("wall-stock-shelf", rightWallX - .4, y, wallShelfCenterZ, .54, .045, wallShelfLength, steel);
    box("wall-stock-ticket-rail", wallShelfFront, y + .02, wallShelfCenterZ, .018, .058, wallShelfLength, shelfFinish);
    for (let n = 0; n < 44; n++) {
      const z = 3.18 + n * .25;
      const family = (Math.floor(n / 5) + level * 3) % palette.length;
      pack(wallShelfFront + .15, y + .025, z, family, -Math.PI / 2, .25);
      if (n % 5 === 0) box("wall-stock-price-ticket", wallShelfFront - .012, y + .026, z, .008, .052, .21, ticket);
    }
  }
  // Illuminated refrigerated wall with separate doors, handles and stocked shelves.
  const fridgeOffset = 3.2;
  for (let z = 2.5; z < 17; z += 1.25) {
    box("fridge-cabinet", -6.45 + fridgeOffset, 1.23, z, 1.05, 2.46, 1.22, charcoal);
    box("fridge-interior", -5.905 + fridgeOffset, 1.27, z, .012, 2.15, 1.12, plaster);
    for (let level = 0; level < 5; level++) {
      box("fridge-shelf", -5.9 + fridgeOffset, .36 + level * .4, z, .45, .025, 1.13, steel);
      for (let n = 0; n < 4; n++) pack(-5.78 + fridgeOffset, .38 + level * .4, z - .4 + n * .24, level + n, Math.PI / 2, .29);
    }
    box("glass-door", -5.57 + fridgeOffset, 1.27, z, .018, 2.2, 1.15, glass);
    for (const end of [-1, 1]) {
      box("door-frame", -5.55 + fridgeOffset, 1.25, z + end * .59, .05, 2.35, .035, steel);
      box("fridge-light-strip", -5.65 + fridgeOffset, 1.3, z + end * .56, .024, 2.12, .024, coolLight);
    }
    box("door-handle", -5.48 + fridgeOffset, 1.15, z - .43, .06, .63, .028, steel);
  }
  sign("fresh-sign", "Fresh, every day.", "CHILLED • DAIRY • FRESH", -5.4 + fridgeOffset, 2.9, 3.5, 2, .48).rotation.y = -Math.PI / 2;
  canvas.dataset.heroPackCount = String(heroPackCount);

  // The right-hand checkout is a real destination in the room, not a zoomed photograph.
  const counterStart = staticMeshes.length;
  const checkoutWall = material("checkout-satin-panels", "#ffffff", .58);
  checkoutWall.albedoTexture = texture("checkout-panel-light-falloff", 128, 256, ctx => {
    const wash = ctx.createLinearGradient(0, 0, 0, 256);
    wash.addColorStop(0, "#f8f9f6"); wash.addColorStop(.5, "#e4e9e5"); wash.addColorStop(1, "#b7c2bc");
    ctx.fillStyle = wash; ctx.fillRect(0, 0, 128, 256);
    for (let i = 0; i < 1500; i++) {
      ctx.fillStyle = "rgba(59,79,69,.025)"; ctx.fillRect(random() * 128, random() * 256, 1, 1);
    }
  });
  const featureTrim = material("checkout-feature-trim", "#304c43", .38, .2);
  // Match the feature panels to the inset wall after the checkout's left turn.
  const backdropDepth = rightWallX - .8 - .125;
  box("checkout-backdrop-frame", 3.83, 1.53, backdropDepth, 3.68, 2.88, .09, featureTrim);
  for (let panel = 0; panel < 3; panel++) {
    beveledBox("checkout-satin-panel", 2.63 + panel * 1.2, 1.53, backdropDepth - .06, 1.18, 2.80, .045, .01, checkoutWall);
  }
  for (const x of [2.02, 5.64]) box("checkout-wall-light-reveal", x, 1.53, backdropDepth - .065, .025, 2.75, .012, light);
  box("checkout-light-panel-frame", 3.45, 3.2, -.35, 2.7, .08, .8, charcoal);
  box("checkout-light-panel", 3.45, 3.152, -.35, 2.58, .012, .68, light);
  const deskStart = staticMeshes.length;
  box("counter-body", 3.65, .49, -.3, 2.7, .98, 1.2, charcoal, true);
  box("counter-enamel-front", 3.65, .51, -.925, 2.7, .89, .055, shelfFinish);
  box("checkout-bumper", 3.65, .25, -.972, 2.75, .065, .07, charcoal);
  box("checkout-red-fascia", 3.65, .83, -.96, 2.7, .09, .03, accent);
  for (const x of [2.55, 4.28]) box("counter-panel-joint", x, .49, -.956, .006, .57, .003, charcoal);
  beveledBox("counter-stone-top", 3.65, 1.015, -.3, 2.85, .065, 1.32, .014, stone);
  sign("counter-wordmark", "DASTAK", "CHECKOUT  /  01", 3.4, .53, -.987, .96, .26);
  // Equipment detail is constructed locally and still batched by material.
  // No displayed device is an interactive payment or checkout control.
  const conveyorStart = staticMeshes.length;
  const belt = material("woven-conveyor-rubber", "#ffffff", .92);
  belt.albedoTexture = texture("belt-weave", 256, 256, ctx => {
    ctx.fillStyle = "#25282c"; ctx.fillRect(0, 0, 256, 256);
    for (let n = 0; n < 256; n += 4) {
      ctx.fillStyle = "#303339"; ctx.fillRect(n, 0, 1, 256);
      ctx.fillStyle = "#1c2025"; ctx.fillRect(0, n, 256, 1);
    }
    ctx.fillStyle = "#484b4f"; ctx.fillRect(0, 125, 256, 2);
  });
  beveledBox("conveyor-rim", 2.32, 1.075, -.3, 1.16, .055, 1.08, .015, steel);
  box("conveyor", 2.32, 1.106, -.3, 1.02, .009, .94, belt);
  for (const x of [1.785, 2.855]) {
    box("conveyor-guide", x, 1.14, -.3, .045, .045, 1, steel);
    const roller = cylinder("belt-end-roller", x, 1.108, -.3, .043, .93, charcoal);
    roller.rotation.x = Math.PI / 2;
  }
  box("basket-divider", 2.14, 1.145, -.47, .034, .065, .58, accent);
  for (const part of staticMeshes.slice(conveyorStart)) {
    part.position.x = 2.63 + (part.position.x - 2.32) * .56;
    part.scaling.x *= .56;
  }
  beveledBox("scanner-inset", 3.12, 1.078, -.3, .44, .039, .53, .012, steel);
  const scanGlass = material("scanner-optical-glass", "#111921", .11, .12);
  box("scanner-glass", 3.12, 1.1, -.3, .3, .007, .34, scanGlass);
  const scannerBody = beveledBox("scanner-upright", 3.12, 1.265, .003, .37, .32, .13, .014, charcoal);
  scannerBody.rotation.x = -.12;
  box("scanner-facing-window", 3.12, 1.27, -.069, .25, .21, .008, scanGlass);
  const indicator = material("device-status-led", "#82cda2", .4);
  indicator.emissiveColor = new Color3(.15, .65, .32);
  box("scanner-ready-led", 3.25, 1.405, -.07, .022, .011, .007, indicator);
  cylinder("pos-base", 3.82, 1.095, -.16, .32, .04, charcoal);
  cylinder("pos-stand", 3.82, 1.18, -.16, .045, .17, steel);
  const terminal = new TransformNode("billing-terminal", scene);
  terminal.position.set(3.82, 1.285, -.16); terminal.rotation.x = -.28;
  terminal.scaling.set(.85, .78, 1);
  const screenCase = beveledBox("pos-case", 0, 0, 0, .53, .34, .045, .009, charcoal); screenCase.parent = terminal;
  for (let i = 0; i < 7; i++) {
    const vent = box("terminal-rear-vent", -.1 + i * .034, -.09, -.024, .018, .05, .003, dark); vent.parent = terminal;
  }
  const rearLogo = sign("terminal-rear-brand", "DASTAK", "POINT OF SALE", 0, .035, -.025, .17, .048);
  rearLogo.parent = terminal;
  const screenMat = material("pos-display", "#ffffff", .45);
  const screenTex = texture("pos-interface", 512, 320, ctx => {
    ctx.fillStyle = "#14251e"; ctx.fillRect(0, 0, 512, 320);
    ctx.fillStyle = "#c7ba83"; ctx.font = "bold 32px sans-serif"; ctx.fillText("DASTAK", 28, 48);
    ctx.fillStyle = "#d6e8da"; ctx.font = "16px sans-serif"; ctx.fillText("BILLING TERMINAL  /  01", 28, 78);
    [110, 154, 198].forEach(y => { ctx.fillStyle = "#294537"; ctx.fillRect(25, y, 460, 32); ctx.fillStyle = "#a8c8b3"; ctx.fillRect(38, y + 12, 150, 7); ctx.fillRect(401, y + 12, 65, 7); });
    ctx.fillStyle = "#b7c992"; ctx.fillRect(25, 253, 460, 44); ctx.fillStyle = "#24352b"; ctx.fillText("READY FOR YOUR BASKET", 137, 280);
  });
  screenMat.albedoTexture = screenTex; screenMat.emissiveTexture = screenTex; screenMat.emissiveColor = new Color3(.55, .7, .6);
  const display = box("staff-facing-screen", 0, 0, .028, .48, .29, .008, screenMat); display.parent = terminal;
  // Customer display and PIN pad sit outside the cashier's keyboard workspace.
  cylinder("customer-display-base", 4.23, 1.083, -.51, .19, .035, charcoal);
  cylinder("customer-display-pole", 4.23, 1.23, -.51, .026, .28, steel);
  beveledBox("customer-display-housing", 4.23, 1.39, -.51, .31, .145, .045, .008, charcoal);
  const customerDisplay = material("customer-display", "#ffffff", .5);
  customerDisplay.albedoTexture = texture("customer-welcome-display", 512, 192, ctx => {
    ctx.fillStyle = "#12221e"; ctx.fillRect(0, 0, 512, 192);
    ctx.fillStyle = "#dcebe1"; ctx.textAlign = "center";
    ctx.font = "bold 44px sans-serif"; ctx.fillText("WELCOME", 256, 83);
    ctx.font = "27px sans-serif"; ctx.fillText("DASTAK  /  01", 256, 137);
  });
  customerDisplay.emissiveTexture = customerDisplay.albedoTexture;
  customerDisplay.emissiveColor = new Color3(.22, .35, .28);
  box("customer-display-face", 4.23, 1.39, -.535, .276, .111, .003, customerDisplay);
  beveledBox("receipt-printer", 4.62, 1.173, -.03, .3, .22, .32, .013, charcoal);
  box("printer-lid-joint", 4.62, 1.24, -.194, .278, .006, .002, dark);
  box("printer-paper-slot", 4.62, 1.257, -.194, .204, .015, .004, dark);
  box("printer-feed-button", 4.726, 1.283, -.109, .03, .005, .038, dark);
  box("printer-ready-led", 4.69, 1.284, -.109, .012, .003, .012, indicator);
  const paper = material("receipt-stock", "#ffffff", .93);
  paper.albedoTexture = texture("decorative-receipt", 128, 256, ctx => {
    ctx.fillStyle = "#f4f0e6"; ctx.fillRect(0, 0, 128, 256);
    ctx.fillStyle = "#4e5350"; ctx.textAlign = "center";
    ctx.font = "bold 15px monospace"; ctx.fillText("DASTAK", 64, 31);
    for (let line = 0; line < 7; line++) ctx.fillRect(17, 56 + line * 16, line % 2 ? 71 : 94, 2);
    for (let bar = 0; bar < 31; bar++) ctx.fillRect(17 + bar * 3, 192, bar % 3 ? 1 : 2, 31);
  });
  const receipt = box("receipt-paper", 4.62, 1.266, -.265, .177, .002, .16, paper);
  receipt.rotation.x = -.18;
  const paymentDevice = new TransformNode("decorative-pin-pad", scene);
  paymentDevice.position.set(4.63, 1.137, -.67); paymentDevice.rotation.x = -.22;
  const pad = beveledBox("pin-pad-body", 0, 0, 0, .19, .075, .29, .009, charcoal); pad.parent = paymentDevice;
  const padScreen = box("pin-pad-screen", 0, .041, .063, .13, .003, .082, scanGlass); padScreen.parent = paymentDevice;
  for (let row = 0; row < 4; row++) for (let col = 0; col < 3; col++) {
    const key = box("pin-pad-key", -.045 + col * .045, .043, -.083 + row * .03, .032, .008, .018, row === 0 && col === 2 ? accent : shelfFinish);
    key.parent = paymentDevice;
  }
  box("printer-cable-trunk", 4.86, 1.072, -.08, .02, .018, .36, dark);
  box("checkout-access-panel", 4.48, .48, -.96, .74, .39, .012, shelfFinish);
  box("access-panel-handle", 4.72, .61, -.977, .13, .018, .016, steel);
  box("pos-keyboard", 3.82, 1.08, .2, .62, .035, .18, charcoal);
  for (let row = 0; row < 3; row++) for (let col = 0; col < 12; col++) box("keyboard-key", 3.55 + col * .049, 1.102, .14 + row * .047, .038, .008, .032, dark);
  // Compact the furniture/equipment footprint around the keyboard; leave
  // the standing adult, countertop height and architectural backdrop alone.
  const deskScale = .4;
  const deskOffsetZ = .23; // Station-local depth is screen-right at the entrance.
  const deskParts = new Set<TransformNode>();
  for (const mesh of staticMeshes.slice(deskStart)) deskParts.add(mesh.parent instanceof TransformNode ? mesh.parent : mesh);
  for (const part of deskParts) {
    part.position.x = 3.83 + (part.position.x - 3.83) * deskScale;
    part.position.z = .2 + (part.position.z - .2) * deskScale + deskOffsetZ;
    part.scaling.x *= deskScale;
    part.scaling.z *= deskScale;
  }
  const taskLight = new PointLight("counter-softbox", new Vector3(3.25, 3.05, -.55), scene);
  taskLight.diffuse = new Color3(1, .97, .92); taskLight.intensity = 6; taskLight.range = 4;
  const terminalLight = new PointLight("terminal-spill", new Vector3(3.82, 1.55, .15), scene);
  terminalLight.diffuse = new Color3(.8, .94, 1); terminalLight.intensity = .04; terminalLight.range = 1;
  for (const x of [3.25, 4.41]) cylinder("checkout-sign-suspension", x, 2.94, .6, .012, 1.03, steel);
  sign("checkout-sign", "01  /  CHECKOUT", "WELCOME TO DASTAK", 3.83, 2.3, .6, 1.65, .25);
  const counterMeshes = new Set(staticMeshes.slice(counterStart));
  // Turn the entire billing station left as one assembly, including devices,
  // lighting and the cashier's keyboard targets. Do this before static batching.
  const checkoutRoot = new TransformNode("left-facing-checkout", scene);
  checkoutRoot.position.set(3.45, 0, -.3);
  const checkoutParts = new Set<TransformNode>();
  for (const mesh of counterMeshes) checkoutParts.add(mesh.parent instanceof TransformNode ? mesh.parent : mesh);
  const checkoutContact = scene.getMeshByName("checkout-ground-contact")!;
  checkoutContact.unfreezeWorldMatrix(); checkoutContact.position.x = 3.83 + (3.65 - 3.83) * deskScale; checkoutContact.position.z = .2 + (-.3 - .2) * deskScale + deskOffsetZ; checkoutContact.scaling.x = .82 * deskScale; checkoutContact.scaling.z = deskScale; checkoutParts.add(checkoutContact);
  checkoutParts.forEach(part => part.setParent(checkoutRoot));
  for (const lamp of [taskLight, terminalLight]) {
    lamp.position.subtractInPlace(checkoutRoot.position); lamp.parent = checkoutRoot;
  }
  checkoutRoot.rotation.y = Math.PI / 2;
  // Put checkout ahead of the right shelf, close to the entrance, rather
  // than behind its endcap. Billing and staff share this station transform.
  checkoutRoot.position.set(.5, 0, .9);
  checkoutRoot.computeWorldMatrix(true);
  screenCase.computeWorldMatrix(true);
  canvas.dataset.monitorTop = screenCase.getBoundingInfo().boundingBox.maximumWorld.y.toFixed(3);
  checkoutContact.computeWorldMatrix(true); checkoutContact.freezeWorldMatrix();
  const checkoutPoint = (x: number, y: number, z: number) => Vector3.TransformCoordinates(
    new Vector3(x - 3.45, y, z + .3), checkoutRoot.getWorldMatrix(),
  );
  canvas.dataset.checkoutFacing = Vector3.TransformNormal(new Vector3(0, 0, -1), checkoutRoot.getWorldMatrix()).asArray().map(v => v.toFixed(3)).join(",");
  // Exterior is kept out of interior static batches so
  // switching views never changes the approved shop layout or rebuilds WebGL.
  const exterior = new TransformNode("storefront-study", scene);
  const exteriorCasters: Mesh[] = [];
  let exteriorPavement: PBRMaterial | undefined;
  let outdoor: ReturnType<typeof createOutdoor> | null = null;
  let nightLighting: ReturnType<typeof createNightLighting> | null = null;
  // Build the exterior only when requested, including in production. Interior
  // shoppers need not allocate trees, weather particles or pavement textures.
  function ensureExterior() {
    if (outdoor) return;
    outdoor = createOutdoor(scene, exterior);
    const exteriorStart = staticMeshes.length;
    const pavement = material("exterior-limestone", "#ffffff", .91);
    exteriorPavement = pavement;
    const pavementMap = (url: string, linear = false) => {
      const map = new Texture(url, scene);
      map.uScale = 10; map.vScale = 14 / 3; map.gammaSpace = !linear; map.anisotropicFilteringLevel = 8;
      return map;
    };
    pavement.albedoTexture = pavementMap(pavementColorUrl);
    pavement.bumpTexture = pavementMap(pavementNormalUrl, true); pavement.bumpTexture.level = .55;
    pavement.metallicTexture = pavementMap(pavementArmUrl, true);
    pavement.useRoughnessFromMetallicTextureAlpha = false;
    pavement.useRoughnessFromMetallicTextureGreen = true;
    pavement.useMetallnessFromMetallicTextureBlue = true;
    pavement.useAmbientOcclusionFromMetallicTextureRed = true;
    const facade = material("exterior-warm-stone", "#e6e1d5", .8);
    const brand = material("storefront-deep-green", "#203e34", .47, .12);
    const wood = material("storefront-oak", "#967553", .8);
    wood.albedoColor.set(1, 1, 1);
    wood.albedoTexture = new Texture(woodColorUrl, scene);
    wood.bumpTexture = new Texture(woodNormalUrl, scene);
    wood.bumpTexture.level = .22;
    wood.bumpTexture.gammaSpace = false;
    const foliage = material("storefront-leaves", "#87a961", .79);
    foliage.backFaceCulling = false; foliage.twoSidedLighting = true;
    facade.albedoTexture = texture("facade-stone-grain", 256, 256, ctx => {
      ctx.fillStyle = "#e6e1d5"; ctx.fillRect(0, 0, 256, 256);
      for (let i = 0; i < 1600; i++) {
        ctx.fillStyle = i % 2 ? "rgba(70,58,42,.045)" : "rgba(255,255,255,.15)";
        ctx.fillRect(random() * 256, random() * 256, 1, 1);
      }
    });
    const paving = MeshBuilder.CreateGround("forecourt", { width: 30, height: 14 }, scene);
    paving.position.set(-.5, -.025, -14); paving.material = pavement; staticMeshes.push(paving);
    for (const x of [-1.75, .75]) box("entry-path-border", x, -.009, -13.9, .055, .006, 12.3, brand);
    box("entrance-drain-channel", -.5, -.005, -8.7, 7.5, .025, .11, charcoal);
    for (let x = -4; x < 3; x += .1) box("drain-grating", x, .01, -8.7, .012, .006, .1, steel);
    // Standalone shop: nothing built above or alongside the approved frontage.
    box("entry-threshold", -.5, -.005, -7.1, 7.4, .06, .42, steel);
    box("storefront-fascia", -.5, 3.25, -7.16, 7.5, 1.2, .35, brand);
    const fasciaTrim = material("storefront-bronze-detail", "#b6a477", .36, .65);
    box("fascia-upper-reveal", -.5, 3.82, -7.36, 7.5, .035, .025, fasciaTrim);
    box("fascia-lower-reveal", -.5, 2.68, -7.36, 7.5, .025, .025, fasciaTrim);
    const brandSign = sign("dastak-storefront-sign", "DASTAK", "GOOD THINGS, CLOSE TO HOME", -.5, 3.27, -7.36, 4.4, .96, "#203e34");
    (brandSign.material as PBRMaterial).emissiveTexture = (brandSign.material as PBRMaterial).albedoTexture;
    (brandSign.material as PBRMaterial).emissiveColor = new Color3(.4, .4, .4);
    box("storefront-canopy", -.5, 2.7, -7.65, 7.65, .13, 1.25, charcoal);
    box("canopy-light", -.5, 2.625, -8.12, 6.95, .025, .035, light);
    for (const x of [-4.05, 3.05]) {
      box("storefront-pier", x, 1.31, -7.16, .45, 2.62, .4, facade);
      for (let i = 0; i < 6; i++) box("pier-oak-slat", x - .18 + i * .072, 1.3, -7.39, .035, 2.5, .06, wood);
    }
    // A clear central entry with glazed sliding leaves parked to either side.
    for (const x of [-2.47, 1.47]) {
      box("storefront-window", x, 1.3, -7.18, 2.54, 2.5, .025, glass);
      for (const dx of [-1.28, 1.28])
        box("window-mullion", x + dx, 1.3, -7.22, .045, 2.6, .06, charcoal);
      box("window-safety-strip", x, .99, -7.2, 2.5, .025, .015, shelfFinish);
    }
    for (const x of [-1.65, .65]) {
      box("sliding-door-glass", x, 1.27, -7.31, .86, 2.45, .018, glass);
      box("sliding-door-edge", x + (x < 0 ? .44 : -.44), 1.27, -7.33, .026, 2.45, .035, steel);
    }
    box("entry-mat", -.5, .018, -7.85, 1.9, .035, 1.1, dark);
    sign("welcome-entry", "WELCOME IN", "FRESH PICKS • EVERY DAY", -.5, 2.43, -7.25, 1.72, .24, "#203e34");
    for (const x of [-3.5, 2.5]) {
      beveledBox("storefront-planter", x, .25, -8.2, .65, .5, .65, .035, brand);
      const plant = leafSpray(scene, "storefront-plant", foliage, 480, x < 0 ? 21 : 34, r => {
        const a = r() * Math.PI * 2, h = r(), radius = .26 * Math.sqrt(1 - h * h);
        return { center: new Vector3(x + Math.sin(a) * radius, .5 + h * .65, -8.2 + Math.cos(a) * radius), size: .055 + r() * .055 };
      });
      staticMeshes.push(plant);
    }
    // Side seating and planted borders frame the pedestrian approach without
    // blocking the central route or placing the viewer in a vacant car park.
    for (const x of [-3.85, 2.85]) {
      beveledBox("forecourt-planter", x, .29, -10.75, .65, .58, 2.4, .035, brand);
      const border = leafSpray(scene, "border-shrub", foliage, 1100, x < 0 ? 41 : 73, r => ({
        center: new Vector3(x + (r() - .5) * .48, .58 + r() * .37, -11.85 + r() * 2.2), size: .055 + r() * .06,
      }));
      staticMeshes.push(border);
      const seatX = x + (x < -.5 ? .64 : -.64);
      for (const dx of [-.17, 0, .17]) box("bench-oak-slat", seatX + dx, .46, -10.55, .145, .06, 1.6, wood);
      for (const z of [-11.13, -9.97]) box("bench-leg", seatX, .23, z, .48, .46, .07, charcoal);
      cylinder("path-bollard", x, .37, -12.35, .13, .74, brand);
      cylinder("bollard-light-ring", x, .64, -12.35, .135, .04, light);
    }
    // Batch the additional architecture by material to keep the phone view cheap.
    const exteriorBatches = new Map<PBRMaterial, Mesh[]>();
    for (const mesh of staticMeshes.splice(exteriorStart)) {
      if (mesh.material === glass) { mesh.parent = exterior; mesh.freezeWorldMatrix(); continue; }
      const mat = mesh.material as PBRMaterial;
      const group = exteriorBatches.get(mat) ?? []; group.push(mesh); exteriorBatches.set(mat, group);
    }
    for (const meshes of exteriorBatches.values()) {
      const merged = Mesh.MergeMeshes(meshes, true, true);
      if (merged) {
        merged.parent = exterior; merged.isPickable = false; merged.receiveShadows = true; merged.freezeWorldMatrix();
        if (merged.material !== pavement) exteriorCasters.push(merged);
      }
    }
    exteriorCasters.forEach(mesh => shadows.addShadowCaster(mesh));
    nightLighting = createNightLighting(scene, exterior);
  }
  exterior.setEnabled(outside);
  const ceilingLamps = scene.lights.filter(lamp => lamp.name.startsWith("ceiling-bounce-"));
  // Merge architectural parts by material: dozens of render submissions rather
  // than one per ceiling slat, rail or light. Transparent doors stay separate.
  const batches = new Map<string, Mesh[]>();
  for (const m of staticMeshes) {
    m.computeWorldMatrix(true);
    if (m.material === glass) { m.freezeWorldMatrix(); continue; }
    // Do not merge checkout equipment with distant shelving: each needs its own
    // light selection inside the existing four-light mobile budget.
    const key = `${m.material!.uniqueId}:${Boolean(m.metadata?.castsStoreShadow)}:${counterMeshes.has(m)}`;
    batches.set(key, [...(batches.get(key) ?? []), m]);
  }
  shadows.getShadowMap()!.renderList = [];
  const counterBatches: Mesh[] = [];
  for (const meshes of batches.values()) {
    const castsShadow = Boolean(meshes[0].metadata?.castsStoreShadow);
    const isCounter = counterMeshes.has(meshes[0]);
    const merged = Mesh.MergeMeshes(meshes, true, true);
    if (merged) {
      merged.receiveShadows = true; merged.isPickable = false; merged.freezeWorldMatrix();
      if (castsShadow) shadows.addShadowCaster(merged);
      if (isCounter) {
        counterBatches.push(merged);
        ceilingLamps.forEach(lamp => lamp.excludedMeshes.push(merged));
        taskLight.includedOnlyMeshes.push(merged); terminalLight.includedOnlyMeshes.push(merged);
      }
    }
  }
  canvas.dataset.checkoutLighting = counterBatches.every(mesh => {
    const activeLights = mesh.lightSources.slice(0, 4);
    return activeLights.includes(taskLight) && activeLights.includes(terminalLight)
      && !activeLights.some(lamp => ceilingLamps.includes(lamp));
  }) ? "dedicated-four-light" : "incorrect-light-selection";

  options.onStatus(staffUrl ? "Loading staff" : "Store ready · production staff asset pending");
  if (staffUrl) void LoadAssetContainerAsync(staffUrl, scene).then(container => {
    if (disposed) { container.dispose(); return; }
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
    root.position.set(3.83, -bounds.min.y * factor, .56);
    root.rotation.y = Math.PI;
    root.position.subtractInPlace(new Vector3(3.45, 0, -.3)); root.parent = checkoutRoot;
    for (const mesh of container.meshes) { mesh.isPickable = false; mesh.receiveShadows = true; if (mesh.getTotalVertices()) shadows.addShadowCaster(mesh); }
    taskLight.includedOnlyMeshes.push(...container.meshes);
    terminalLight.includedOnlyMeshes.push(...container.meshes);
    for (const mat of container.materials) {
      if (!(mat instanceof PBRMaterial)) continue;
      // Preserve the authored texture/folds. A cloth response should not shine
      // like skin, and skin should not share the garment's dry roughness.
      if (mat.name.endsWith(".male_casualsuit01")) {
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
    let blinkTargetCount = 0;
    const eyelidUpdates = container.meshes.flatMap(mesh => {
      const manager = mesh.morphTargetManager;
      if (!manager) return [];
      const targets = Array.from({ length: manager.numTargets }, (_, i) => manager.getTarget(i))
        .filter(target => /^eyeBlink(Left|Right)$/.test(target.name));
      // Brows remain neutral; the faulty lash cards stay disabled. None of
      // these meshes should retain a GPU morph-texture shader variant.
      mesh.morphTargetManager = null;
      if (/eyebrow|eyelashes/.test(mesh.name) || !targets.length) return [];
      blinkTargetCount += targets.length;
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
      if (mesh.name === "DastakCashierBody") {
        eyelidGeometryReady = new Set(targets.map(target => target.name)).size === 2
          && buffers.some(buffer => buffer.kind === "position" && buffer.changedCoordinates > 0);
      }
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
    confirmClosedDraw = () => blinkPlayback.markClosedRendered(lastStaffTime);
    const cashierBody = container.meshes.find(mesh => mesh.name === "DastakCashierBody");
    if (cashierBody instanceof Mesh) cashierBody.onAfterRenderObservable.add(() => { bodyDrawnThisFrame = true; });
    // A small chest/neck cycle, rather than scaling the whole person, gives
    // an understated breathing idle; the shared relaxed arm pose follows it.
    staffUpdate = time => {
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
      canvas.dataset.staffPose="arms-at-sides";
      canvas.dataset.leftWristHeight=wrists[0].y.toFixed(3);
      canvas.dataset.rightWristHeight=wrists[1].y.toFixed(3);
      // Smooth quick closure, short hold, slower opening. No sharp triangular
      // velocity reversal at full closure; both lids remain synchronized.
      const testTime = (performance.now() - blinkTestStarted) / 1000;
      const automaticBlink = blinkPlayback(time);
      // Explicit local diagnostic: visibly close, hold, then reopen once.
      // It also works with Reduced Motion without enabling continuous idle.
      const blink = eyesClosed ? 1 : testTime < 1 ? Math.max(0, Math.min(1, testTime / .18, (1 - testTime) / .3)) : automaticBlink;
      for (const update of eyelidUpdates) update(blink);
      canvas.dataset.blinkWeight = blink.toFixed(3);
    };
    clock = 0; lastFrameTime = performance.now();
    staffUpdate(0);
    dirty = true;
    canvas.dataset.staff = "ready";
    canvas.dataset.staffRig = "makehuman-game-engine";
    canvas.dataset.staffBlinks = String(blinkTargetCount);
    canvas.dataset.eyelidGeometry = eyelidGeometryReady ? "validated" : "missing";
    reportMotion();
  }).catch(() => { if (!disposed) { canvas.dataset.staff = "unavailable"; options.onStatus("Store ready · staff asset unavailable"); } });

  const targetPosition = new Vector3(); const targetGaze = new Vector3();
  function destinations() {
    if (outside) ensureExterior();
    exterior.setEnabled(outside);
    canvas.dataset.view = outside ? "outside" : atCounter ? "billing" : "entrance";
    const portraitBilling = mobile.matches && atCounter;
    camera.fov = outside ? (mobile.matches ? 2 * Math.atan(Math.tan(1.15 / 2) / .74) : 1.15) : mobile.matches && !atCounter ? 1.2 : .92;
    // Portrait store views occupy the upper portion, leaving the lower
    // area for controls instead of stretching ceiling and floor vertically.
    // Only interior studies reserve space for controls. Outside renders behind
    // the floating panel, with a wider vertical field to retain storefront width.
    const compactInterior = mobile.matches && !outside;
    camera.viewport = new Viewport(0, compactInterior ? .26 : 0, 1, compactInterior ? .74 : 1);
    scene.clearColor = outside ? new Color4(.76, .85, .91, 1) : portraitBilling ? new Color4(.965, .957, .933, 1) : new Color4(.075, .083, .075, 1);
    if (!outside) {
      nightLighting?.update(1, false);
      sun.direction.set(.45, -1, .7); sun.position.set(-5, 9, -5);
      sun.intensity = 1.35; sun.diffuse.set(1, .98, .95); fill.intensity = .22;
      scene.environmentIntensity = .58; scene.fogDensity = .005; scene.fogColor.set(.65, .68, .7);
      outdoor?.reset();
    }
    canvas.dataset.billingViewport = portraitBilling ? "compact-portrait" : "full";
    if (outside) {
      sun.direction.set(.48, -.8, .45); sun.position.set(-7, 10, -16);
      targetPosition.set(-.5, 1.7, mobile.matches ? -19 : -16);
      targetGaze.set(-.5, mobile.matches ? .35 : 2.45, -7);
    } else if (atCounter) {
      // Customer stands on the cashier's centreline, directly across the desk.
      // Resolve both points through the station pivot so turning the counter
      // cannot leave the billing camera looking diagonally from the aisle.
      // Portrait frames the cashier and working countertop, not the whole
      // station and surrounding floor. Keep the same front-on centreline.
      targetPosition.copyFrom(checkoutPoint(3.83, 1.68, mobile.matches ? -2.4 : -2.7));
      targetGaze.copyFrom(checkoutPoint(3.83, 1.52, .61));
    }
    else { targetPosition.set(.2, 1.65, mobile.matches ? -2.3 : -4.8); targetGaze.set(.3, 1.35, 10); }
  }
  destinations(); camera.position.copyFrom(targetPosition); gaze.copyFrom(targetGaze); camera.setTarget(gaze);
  const resize = () => { destinations(); engine.resize(); dirty = true; };
  function reportMotion() {
    if (outside) { options.onStatus(weather ? "Outdoor study · nearby-area weather · local solar cycle" : "Outdoor study · approximate device-time sky"); return; }
    if (canvas.dataset.staff !== "ready") return;
    canvas.dataset.motion = staffPlaying() ? "playing" : "reduced";
    canvas.dataset.renderedBlinks = String(renderedBlinks);
    const playback = staffPlaying() ? `Playing ${Math.floor(clock)}s${motion.matches ? " (preview override)" : ""}` : "Paused: Reduce Motion · press Play staff";
    canvas.dataset.bodyDrawFrames = String(bodyDrawFrames);
    const eyes = !eyelidGeometryReady ? "ERROR: eyelid geometry missing" : eyesClosed ? "EYES HELD CLOSED" : "Eyelid geometry validated";
    options.onStatus(`Cashier blink v7 · ${playback} · ${eyes} · Blink cycles: ${renderedBlinks} · Face frames: ${bodyDrawFrames}`);
  }
  const motionChanged = () => { resize(); reportMotion(); };
  const observer = new ResizeObserver(resize); observer.observe(canvas);
  const visibility = () => {
    lastFrameTime = performance.now();
    if (document.hidden) engine.stopRenderLoop(render); else engine.runRenderLoop(render);
  };
  function render() {
    if (disposed || document.hidden) return;
    const now = performance.now();
    const elapsed = Math.max(0, (now - lastFrameTime) / 1000);
    lastFrameTime = now;
    const testingBlink = now - blinkTestStarted < 1000;
    if (outside && motion.matches && !dirty && outdoorMinute === Math.floor(Date.now() / 60_000) && scene.isReady()) return;
    if (!outside && !staffPlaying() && !testingBlink && !dirty && scene.isReady() && (!contactShading || contactShading.isReady())) return;
    const readyBeforeRender = scene.isReady() && (!contactShading || contactShading.isReady());
    const dt = Math.min(engine.getDeltaTime() / 1000, .05);
    if (outside && outdoor) {
      outdoorMinute = Math.floor(Date.now() / 60_000);
      const sky = outdoor.update(Date.now(), dt, weather, motion.matches);
      canvas.dataset.nightLighting = String(nightLighting?.update(sky.daylight, true) ?? 0);
      sun.intensity = .06 + sky.daylight * (1.29 - sky.cloud * .7);
      sun.diffuse.set(.65 + sky.daylight * .35, .76 + sky.daylight * .22, 1 - sky.daylight * .05);
      fill.intensity = .14 + sky.daylight * .20;
      scene.environmentIntensity = .12 + sky.daylight * .46;
      if (exteriorPavement) exteriorPavement.roughness = sky.wet ? .43 : .91;
      scene.fogDensity = sky.fog ? .045 : sky.wet ? .012 : .004;
      scene.fogColor.set(.08 + sky.daylight*.57, .10 + sky.daylight*.58, .16 + sky.daylight*.55);
      canvas.dataset.daylight = sky.daylight.toFixed(2);
      canvas.dataset.weatherWind = String(sky.wind);
      canvas.dataset.precipitation = sky.precipitation;
      canvas.dataset.weatherParticles = String(sky.particleCount);
    }
    const blend = motion.matches ? 1 : 1 - Math.exp(-dt * 3.6);
    Vector3.LerpToRef(camera.position, targetPosition, blend, camera.position);
    Vector3.LerpToRef(gaze, targetGaze, blend, gaze); camera.setTarget(gaze);
    // Camera damping may cap its step, but an idle cycle must follow actual
    // visible time: a 5-second blink cannot take 30 seconds at low FPS.
    if (staffPlaying()) clock += elapsed;
    staffUpdate?.(staffPlaying() ? clock : 0);
    bodyDrawnThisFrame = false;
    scene.render();
    if (readyBeforeRender && !firstFrameReady) {
      firstFrameReady = true;
      options.onReady?.();
    }
    // Count a rendered closure followed by reopening, not scheduled events.
    // Keep diagnostics to once per second/blink rather than React per frame.
    const weight = Number(canvas.dataset.blinkWeight ?? 0);
    // Global readiness includes unrelated shelves and postprocessing. A
    // cashier blink is acknowledged only by its own body draw, not that gate.
    if (bodyDrawnThisFrame) bodyDrawFrames++;
    if (eyelidGeometryReady && bodyDrawnThisFrame && weight > .95) { sawClosedEyes = true; confirmClosedDraw?.(); }
    const completedBlink = eyelidGeometryReady && bodyDrawnThisFrame && sawClosedEyes && weight < .01;
    if (completedBlink) { renderedBlinks++; sawClosedEyes = false; }
    if (completedBlink || Math.floor(clock) !== reportedSecond) {
      reportedSecond = Math.floor(clock); reportMotion();
    }
    // A frame that starts shader compilation is not a completed still. Draw
    // again after late staff/materials compile before freezing Reduced Motion.
    dirty = !readyBeforeRender || testingBlink;
    canvas.dataset.sceneReady = String(readyBeforeRender && Boolean(canvas.dataset.staff));
    if (++frames % 5 === 0 || motion.matches || frames === 1) {
      canvas.dataset.camera = camera.position.asArray().map(v => v.toFixed(3)).join(",");
      canvas.dataset.cameraGaze = gaze.asArray().map(v => v.toFixed(3)).join(",");
      canvas.dataset.animationTime = clock.toFixed(3);
      canvas.dataset.fps = Math.round(engine.getFps()).toString();
    }
  }
  document.addEventListener("visibilitychange", visibility);
  mobile.addEventListener("change", resize);
  motion.addEventListener("change", motionChanged);
  engine.runRenderLoop(render);
  canvas.dataset.renderer = "babylon-webgl";
  return {
    setWeather(value) { weather = value; dirty = true; reportMotion(); },
    setOutside(value) { outside = value; destinations(); dirty = true; reportMotion(); },
    setCounter(value) { atCounter = value; destinations(); dirty = true; },
    setStaffPlayback(value) { staffPlaybackRequested = import.meta.env.DEV && value; lastFrameTime = performance.now(); dirty = true; reportMotion(); },
    setEyesClosed(value) { eyesClosed = import.meta.env.DEV && value; dirty = true; reportMotion(); },
    testBlink() { if (import.meta.env.DEV) { blinkTestStarted = performance.now(); dirty = true; } },
    dispose() { disposed = true; observer.disconnect(); document.removeEventListener("visibilitychange", visibility); mobile.removeEventListener("change", resize); motion.removeEventListener("change", motionChanged); engine.stopRenderLoop(render); scene.dispose(); engine.dispose(); },
  };
  } catch (error) {
    // Construction can fail before React receives a disposer (unsupported GPU,
    // shader setup, etc.). Never leave a partial engine/listeners behind.
    engine.dispose();
    throw error;
  }
}
