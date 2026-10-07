import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium, webkit } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const engine = process.env.DASTAK_TEST_ENGINE === "webkit" ? webkit : chromium;
const browser = await engine.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 700 }, reducedMotion: "no-preference" });
  await page.route("**/src/reimaginedGroceryScene.ts*", async route => {
    const response = await route.fetch();
    const source = await response.text();
    await route.fulfill({ response, body: source.replace("const targetPosition =", "window.__playback = { scene, clock: () => clock }; const targetPosition =") });
  });
  await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
  await page.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", null, { timeout: 90000 });
  await page.evaluate(() => {
    const { scene, clock } = window.__playback;
    const mesh = scene.getMeshByName("DastakCashierBody");
    const first = Float32Array.from(mesh.getVerticesData("position"));
    const result = { startTime: performance.now(), startClock: clock(), frames: 0, maxEyelidChange: 0, closedFrames: 0 };
    window.__playback.result = result;
    scene.onAfterRenderObservable.add(() => {
      result.frames++;
      const current = mesh.getVerticesData("position");
      for (let i = 0; i < current.length; i++) result.maxEyelidChange = Math.max(result.maxEyelidChange, Math.abs(current[i] - first[i]));
      if (Number(document.querySelector("canvas").dataset.blinkWeight) > .9) result.closedFrames++;
    });
  });
  await page.waitForTimeout(10000);
  const result = await page.evaluate(() => {
    const { result, clock } = window.__playback;
    return { ...result, elapsed: (performance.now() - result.startTime) / 1000, animationElapsed: clock() - result.startClock };
  });
  console.log(JSON.stringify({ engine: engine.name(), ...result }));
  if (!process.env.DASTAK_PLAYBACK_BASELINE) {
    assert.ok(result.animationElapsed > result.elapsed * .75, "Idle clock must follow real time even on slow renderers");
    assert.ok(result.maxEyelidChange > .002, "Normal playback must physically move eyelid vertices");
    assert.ok(result.closedFrames >= 1, "A rendered closed-eye frame must not be skipped");
  }
} finally { await browser.close(); }
