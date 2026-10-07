// Cross-engine checks of rendered skinning, not only the IK joint coordinates.
// The scene hook exists only in the intercepted local development response.
import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const playwright = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const engineName = process.env.DASTAK_TEST_ENGINE ?? "webkit";
const width = Number(process.env.DASTAK_TEST_WIDTH ?? 1100);
const browser = await playwright[engineName].launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width, height: 800 }, reducedMotion: "no-preference" });
  const errors = [];
  page.on("pageerror", e => errors.push(e.message));
  page.on("console", msg => { if (msg.type() === "error") errors.push(msg.text().slice(0, 350)); });
  await page.route("**/src/reimaginedGroceryScene.ts*", async route => {
    const response = await route.fetch();
    const source = await response.text();
    assert.ok(source.includes("const targetPosition ="));
    await route.fulfill({ response, body: source.replace("const targetPosition =", "window.__cashierRender = { scene, pose: time => staffUpdate?.(time) }; const targetPosition =") });
  });
  await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
  await page.waitForFunction(() => document.querySelector("canvas")?.dataset.staff === "ready", null, { timeout: 90000 });
  await page.getByRole("button", { name: "Billing view", exact: true }).click();
  await page.waitForFunction(x => {
    const camera = document.querySelector("canvas")?.dataset.camera?.split(",").map(Number);
    return camera && Math.abs(camera[0] - x) < .02 && document.querySelector("canvas")?.dataset.sceneReady === "true";
  }, width < 720 ? -1.75 : 1.05, { timeout: 60000 });
  await page.screenshot({ path: `/tmp/dastak-${engineName}-staff-live.png` });
  const samples = [];
  // Freeze the render clock, then explicitly render every sampled blink phase.
  await page.evaluate(() => window.__cashierRender.scene.getEngine().stopRenderLoop());
  for (const time of [0, 4.85, 4.9, 5.05, 5.3, 13.4]) {
    await page.evaluate(time => {
      const { scene, pose } = window.__cashierRender;
      pose(time); scene.render();
    }, time);
    await page.waitForTimeout(250);
    const sample = await page.evaluate(time => {
      const { scene } = window.__cashierRender;
      scene.render();
      return { time, meshes: scene.meshes.filter(m => m.skeleton && m.isEnabled()).map(m => ({
        name: m.name, gpuSkinning: m.computeBonesUsingShaders,
        morphTexture: m.morphTargetManager?.isUsingTextureForTargets ?? false,
        compiled: m.isReady(true),
      })) };
    }, time);
    samples.push(sample);
    await page.screenshot({ path: `/tmp/dastak-${engineName}-${width}-staff-${time}.png` });
  }
  console.log(JSON.stringify({ engineName, width, errors, samples }));
  if (!process.env.DASTAK_RENDER_BASELINE) {
    assert.deepEqual(errors, [], "No shader/page errors");
    for (const sample of samples) {
      assert.ok(sample.meshes.length >= 4);
      assert.ok(sample.meshes.every(mesh => mesh.gpuSkinning && mesh.compiled), "All visible body parts retain compiled GPU skinning throughout blink");
      assert.ok(sample.meshes.every(mesh => !mesh.morphTexture), "No body part may return to texture-based morph deformation");
    }
  }
} finally { await browser.close(); }
