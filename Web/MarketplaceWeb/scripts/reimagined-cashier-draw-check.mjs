import { createRequire } from "node:module";
import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
const { webkit } = createRequire(import.meta.url)(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const browser = await webkit.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, reducedMotion: "no-preference" });
  const errors = [];
  page.on("pageerror", e => errors.push(e.message));
  await page.route("**/src/reimaginedGroceryScene.ts*", async route => {
    const response = await route.fetch();
    const source = (await response.text())
      .replace("const targetPosition =", "window.__drawScene = scene; const targetPosition =")
      .replace("const readyBeforeRender = scene.isReady()", "const readyBeforeRender = !window.__otherSceneNotReady && scene.isReady()");
    await route.fulfill({ response, body: source });
  });
  await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
  await page.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", null, { timeout: 90000 });
  await page.getByRole("button", { name: "Billing view", exact: true }).click();
  await page.evaluate(() => {
    const scene = window.__drawScene;
    window.__otherSceneNotReady = true;
    window.__body = scene.getMeshByName("DastakCashierBody");
    window.__body.setEnabled(false);
    window.__initialCount = Number(document.querySelector("canvas").dataset.renderedBlinks);
    scene.onAfterRenderObservable.add(() => {
      const canvas = document.querySelector("canvas");
      if (window.__body.isEnabled() && Number(canvas.dataset.blinkWeight) > .95 && !window.__closedFrame) window.__closedFrame = canvas.toDataURL();
    });
  });
  await page.waitForFunction(() => Number(document.querySelector("canvas").dataset.blinkWeight) > .95, null, { timeout: 10000 });
  await page.waitForTimeout(1000);
  assert.equal(await page.locator("canvas").getAttribute("data-blink-weight"), "1.000", "Closure must remain pending until a body draw");
  assert.equal(await page.locator("canvas").evaluate(c => Number(c.dataset.renderedBlinks)), await page.evaluate(() => window.__initialCount), "No blink may be counted while the body isn't drawing");
  await page.evaluate(() => window.__body.setEnabled(true));
  await page.waitForFunction(() => Number(document.querySelector("canvas").dataset.renderedBlinks) > window.__initialCount, null, { timeout: 5000 });
  await page.waitForFunction(() => document.querySelector(".grocery-room-status").textContent.includes(`Blink cycles: ${document.querySelector("canvas").dataset.renderedBlinks}`));
  const result = await page.evaluate(() => ({ status: document.querySelector(".grocery-room-status").textContent, sceneReady: document.querySelector("canvas").dataset.sceneReady, image: window.__closedFrame }));
  assert.equal(result.sceneReady, "false", "Simulated unrelated scene readiness must remain false");
  assert.ok(result.image, "Closed body frame must reach the framebuffer before reopening");
  assert.deepEqual(errors, []);
  await writeFile("/tmp/dastak-blink-v5-delayed-draw.png", Buffer.from(result.image.split(",")[1], "base64"));
  console.log(JSON.stringify({ status: result.status, sceneReady: result.sceneReady, delayedDrawRecovered: true, errors }));
} finally { await browser.close(); }
