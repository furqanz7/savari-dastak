import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = "http://127.0.0.1:5179";
const browser = await chromium.launch({ headless: true });
try {
  for (const [width, height, reducedMotion] of [[390, 844, "reduce"], [320, 740, "reduce"], [430, 932, "reduce"], [1440, 900, "no-preference"], [1440, 900, "reduce"]]) {
    const context = await browser.newContext({ viewport: { width, height }, reducedMotion });
    const issues = [];
    await context.route("**/*", route => {
      if (new URL(route.request().url()).origin !== origin) { issues.push("Non-local request"); return route.abort(); }
      return route.continue();
    });
    const page = await context.newPage();
    page.on("pageerror", error => issues.push(error.message));
    page.on("console", message => { if (message.type() === "error") issues.push(message.text().slice(0, 200)); });
    await page.goto(`${origin}/reimagined-environment-study.html`);
    await page.waitForFunction(() => document.querySelector("canvas")?.dataset.staff === "ready", undefined, { timeout: 90000 });
    await page.waitForFunction(() => document.querySelector("canvas")?.dataset.camera, undefined, { timeout: 30000 });
    await page.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", undefined, { timeout: 30000 });
    const canvas = await page.locator("canvas").elementHandle();
    const initial = await canvas.evaluate(e => ({ ...e.dataset }));
    assert.equal(initial.staffRig, "makehuman-game-engine");
    assert.equal(initial.checkoutFacing, "-1.000,0.000,-0.000", "Checkout front must face store-left");
    assert.ok(Number(initial.heroPackCount) > 100, "Near aisle must contain detailed instanced stock");
    assert.equal(initial.checkoutLighting, "dedicated-four-light", "Checkout batches must receive both local lamps inside the four-light budget");
    assert.ok(Number(initial.staffBlinks) >= 2, "Both eyelid shapes must be present");
    assert.equal(initial.staffPose, "arms-at-sides", "Staff must not reach toward the keyboard");
    assert.ok(Number(initial.leftWristHeight) < 1 && Number(initial.rightWristHeight) < 1, "Both wrists must hang below counter height");
    if (process.env.DASTAK_ENVIRONMENT_SCREENSHOT_DIR) await page.screenshot({ path: `${process.env.DASTAK_ENVIRONMENT_SCREENSHOT_DIR}/entrance-${width}.png` });
    await page.getByRole("button", { name: "Billing view", exact: true }).click();
    await page.waitForFunction(x => {
      const value = document.querySelector("canvas")?.dataset.camera?.split(",").map(Number);
      const gaze = document.querySelector("canvas")?.dataset.cameraGaze?.split(",").map(Number);
      return value && gaze && Math.abs(value[0] - x) < .02 && Math.abs(value[2] + .68) < .02
        && Math.abs(gaze[0] - 4.36) < .02 && Math.abs(gaze[2] + .68) < .02;
    }, width < 720 ? -1.75 : 1.05, { timeout: 45000 });
    assert.equal(await canvas.evaluate(e => e === document.querySelector("canvas")), true, "Camera movement must not recreate GPU scene");
    const counter = await canvas.evaluate(e => ({ ...e.dataset }));
    assert.equal(counter.billingViewport, width < 720 ? "compact-portrait" : "full");
    assert.ok(Number(counter.monitorTop) < 1.45, "Low-profile terminal should expose cashier upper body");
    const billingCamera = counter.camera.split(",").map(Number);
    const billingGaze = counter.cameraGaze.split(",").map(Number);
    assert.ok(Math.abs(billingCamera[2] - billingGaze[2]) < .03, "Customer must face straight across the counter, not diagonally");
    assert.ok(Math.abs(billingGaze[2] + .68) < .03 && Math.abs(billingGaze[0] - 4.36) < .03, "Cashier must be horizontally centred in billing view");
    assert.equal(counter.contactShading, width < 720 ? "lightweight" : "ssao-half", "Expected rendering tier in Chromium WebGL2");
    assert.notEqual(initial.camera, counter.camera);
    if (reducedMotion === "reduce") assert.equal(counter.animationTime, "0.000");
    else assert.ok(Number(counter.animationTime) > Number(initial.animationTime), "Breathing clock advances");
    const bounds = await page.locator("canvas").boundingBox();
    assert.equal(Math.round(bounds.width), width); assert.equal(Math.round(bounds.height), height);
    if (process.env.DASTAK_ENVIRONMENT_SCREENSHOT_DIR) await page.screenshot({ path: `${process.env.DASTAK_ENVIRONMENT_SCREENSHOT_DIR}/counter-${width}.png` });
    await page.getByRole("button", { name: "Show interface", exact: true }).click();
    await page.getByRole("heading", { name: "At the billing counter.", exact: true }).waitFor();
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, "Billing overlay must fit the phone width");
    if (process.env.DASTAK_ENVIRONMENT_SCREENSHOT_DIR) await page.screenshot({ path: `${process.env.DASTAK_ENVIRONMENT_SCREENSHOT_DIR}/billing-interface-${width}.png` });
    await page.getByRole("button", { name: "Hide interface", exact: true }).click();
    await page.getByRole("button", { name: "Entrance", exact: true }).click();
    await page.getByRole("button", { name: "Show interface", exact: true }).click();
    assert.match(await page.getByRole("region", { name: "Grocery Bucket summary" }).textContent(), /1 item/);
    assert.equal(await page.locator(".reimagined-environment").evaluate(e => getComputedStyle(e).pointerEvents), "none");
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, "No horizontal overflow");
    assert.deepEqual(await page.evaluate(() => Object.keys(localStorage)), []);
    // Force an unavailable renderer and confirm the real interface still works.
    await page.addInitScript(() => { Object.defineProperty(window, "WebGLRenderingContext", { value: undefined }); });
    await page.reload();
    await page.getByRole("button", { name: "Show interface", exact: true }).click();
    await page.waitForFunction(() => document.querySelector(".grocery-room-3d")?.getAttribute("data-status")?.includes("unavailable"));
    await page.getByRole("button", { name: "Take a Bucket", exact: true }).click();
    assert.deepEqual(issues, []);
    console.log(JSON.stringify({ width, reducedMotion, renderer: counter.renderer, contactShading: counter.contactShading, checkoutLighting: counter.checkoutLighting, staff: counter.staff, staffRig: counter.staffRig, staffBlinks: counter.staffBlinks, staffPose: counter.staffPose, reportedFps: counter.fps, passed: true }));
    await context.close();
  }
} finally { await browser.close(); }
