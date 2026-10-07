// Observe actual rendered eyelids during ordinary playback and a UI-requested
// blink. The close-up camera/scene hook exists only in intercepted test code.
import { createRequire } from "node:module";
import { writeFile } from "node:fs/promises";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { webkit } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const browser = await webkit.launch({ headless: true });
try {
  for (const [reducedMotion, forceCpu] of [["no-preference", false], ["reduce", false], ["reduce", true]]) {
    const page = await browser.newPage({ viewport: { width: reducedMotion === "reduce" ? 390 : 1100, height: 800 }, reducedMotion });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    await page.route("**/src/reimaginedGroceryScene.ts*", async route => {
      const response = await route.fetch();
      await route.fulfill({ response, body: (await response.text()).replace("const targetPosition =", "window.__blinkScene = scene; const targetPosition =") });
    });
    await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
    await page.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", null, { timeout: 90000 });
    await page.evaluate(forceCpu => {
      const scene = window.__blinkScene;
      if (forceCpu) scene.getMeshByName("DastakCashierBody").computeBonesUsingShaders = false;
      const canvas = document.querySelector("canvas");
      window.__blinkCanvas = canvas;
      window.__blinkFrames = { open: null, closed: null, reopened: false };
      scene.onBeforeRenderObservable.add(() => {
        const head = scene.getTransformNodeByName("head").getAbsolutePosition();
        scene.activeCamera.position.set(head.x - .58, head.y + .015, head.z);
        scene.activeCamera.setTarget(head);
      });
      scene.onAfterRenderObservable.add(() => {
        const frames = window.__blinkFrames;
        const weight = Number(canvas.dataset.blinkWeight);
        if (weight < .01 && !frames.open) frames.open = canvas.toDataURL();
        if (weight > .95 && !frames.closed) frames.closed = canvas.toDataURL();
        if (frames.closed && weight < .01) frames.reopened = true;
      });
      scene.render();
    }, forceCpu);
    if (reducedMotion === "reduce") {
      await page.waitForTimeout(1000);
      assert.equal(await page.evaluate(() => window.__blinkFrames.closed), null, "Reduced Motion should not autoplay");
      await page.getByRole("button", { name: "Test blink", exact: true }).click();
    }
    await page.waitForFunction(() => window.__blinkFrames.reopened, null, { timeout: 15000 });
    const result = await page.evaluate(() => ({
      ...window.__blinkFrames,
      sameCanvas: document.querySelector("canvas") === window.__blinkCanvas,
      status: document.querySelector(".grocery-room-status").textContent,
    }));
    assert.ok(result.sameCanvas, "Blink must not remount the renderer");
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "Study controls must fit the phone viewport");
    assert.notEqual(result.open, result.closed, "Rendered open/closed images must differ");
    assert.deepEqual(errors, []);
    for (const phase of ["open", "closed"]) {
      await writeFile(`/tmp/dastak-visible-blink-${reducedMotion}-${forceCpu ? "cpu" : "gpu"}-${phase}.png`, Buffer.from(result[phase].split(",")[1], "base64"));
    }
    console.log(JSON.stringify({ reducedMotion, forceCpu, status: result.status, sameCanvas: result.sameCanvas, reopened: result.reopened, errors }));
    await page.close();
  }
} finally { await browser.close(); }
