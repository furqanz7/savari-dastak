import { createRequire } from "node:module";
import { writeFile } from "node:fs/promises";
import assert from "node:assert/strict";
const { webkit } = createRequire(import.meta.url)(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const browser = await webkit.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, reducedMotion: "no-preference" });
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.route("**/src/reimaginedGroceryScene.ts*", async route => {
    const response = await route.fetch();
    await route.fulfill({ response, body: (await response.text()).replace("const targetPosition =", "window.__billingScene = scene; const targetPosition =") });
  });
  await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
  await page.waitForFunction(() => document.querySelector("canvas")?.dataset.staff === "ready", null, { timeout: 90000 });
  await page.getByRole("button", { name: "Billing view", exact: true }).click();
  await page.waitForFunction(() => Math.abs(Number(document.querySelector("canvas").dataset.camera?.split(",")[0]) - 1.05) < .02);
  await page.evaluate(() => {
    window.__billingResult = { started: performance.now(), closedTimes: [], lastClosed: false, openImage: null, closedImage: null };
    window.__billingScene.onAfterRenderObservable.add(() => {
      const result = window.__billingResult;
      const canvas = document.querySelector("canvas");
      const closed = Number(canvas.dataset.blinkWeight) > .95;
      if (closed && !result.lastClosed) result.closedTimes.push((performance.now() - result.started) / 1000);
      if (closed && !result.closedImage) result.closedImage = canvas.toDataURL();
      if (Number(canvas.dataset.blinkWeight) < .01 && !result.openImage) result.openImage = canvas.toDataURL();
      result.lastClosed = closed;
    });
  });
  await page.waitForTimeout(30000);
  const result = await page.evaluate(() => ({ ...window.__billingResult, status: document.querySelector(".grocery-room-status").textContent }));
  for (const phase of ["open", "closed"]) if (result[`${phase}Image`]) await writeFile(`/tmp/dastak-billing-live-${phase}.png`, Buffer.from(result[`${phase}Image`].split(",")[1], "base64"));
  console.log(JSON.stringify({ status: result.status, closedTimes: result.closedTimes, errors }));
  assert.ok(result.closedTimes.length >= 4, "Billing must visibly render at least four closures in 30 seconds");
  assert.ok(Number(await page.locator("canvas").getAttribute("data-rendered-blinks")) >= 4, "Visible counter must record automatic blinks");
  assert.deepEqual(errors, []);
  await page.close();
  const phone = await browser.newPage({ viewport: { width: 390, height: 844 }, reducedMotion: "reduce" });
  phone.on("pageerror", error => errors.push(error.message));
  await phone.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
  await phone.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", null, { timeout: 90000 });
  await phone.getByRole("button", { name: "Billing view", exact: true }).click();
  await phone.evaluate(() => { window.__originalCanvas = document.querySelector("canvas"); });
  assert.match(await phone.locator(".grocery-room-status").innerText(), /Paused: Reduce Motion/);
  await phone.getByRole("button", { name: "Play staff", exact: true }).click();
  await phone.waitForFunction(() => Number(document.querySelector("canvas").dataset.renderedBlinks) >= 2, null, { timeout: 20000 });
  assert.ok(await phone.evaluate(() => document.querySelector("canvas") === window.__originalCanvas));
  assert.ok(await phone.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  console.log(JSON.stringify({ phone: true, status: await phone.locator(".grocery-room-status").innerText(), sameCanvas: true }));
  await phone.screenshot({ path: "/tmp/dastak-billing-blink-v4-phone.png" });
  await phone.getByRole("button", { name: "Use motion preference", exact: true }).click();
  await phone.waitForTimeout(500);
  const pausedCount = await phone.locator("canvas").getAttribute("data-rendered-blinks");
  await phone.waitForTimeout(7000);
  assert.equal(await phone.locator("canvas").getAttribute("data-rendered-blinks"), pausedCount);
  assert.match(await phone.locator(".grocery-room-status").innerText(), /Paused: Reduce Motion/);
  assert.deepEqual(errors, []);
  console.log("Reduced Motion restored; automatic blink counter stayed unchanged.");
} finally { await browser.close(); }
