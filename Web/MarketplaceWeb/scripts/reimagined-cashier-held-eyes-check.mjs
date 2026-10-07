import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";
const { webkit } = createRequire(import.meta.url)(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const glb = await readFile(new URL("../src/assets/reimagined/staff-makehuman.glb", import.meta.url));
const revision = createHash("sha256").update(glb).digest("hex").slice(0, 16);
// Simulate a stale/incompatible asset without touching the file on disk.
const jsonLength = glb.readUInt32LE(12);
const json = JSON.parse(glb.subarray(20, 20 + jsonLength).toString());
for (const mesh of json.meshes) if (mesh.extras?.targetNames) mesh.extras.targetNames = mesh.extras.targetNames.map(name => `unavailable-${name}`);
const encoded = Buffer.from(JSON.stringify(json));
const padded = Buffer.alloc(Math.ceil(encoded.length / 4) * 4, 32); encoded.copy(padded);
const broken = Buffer.concat([glb.subarray(0, 20), padded, glb.subarray(20 + jsonLength)]);
broken.writeUInt32LE(broken.length, 8); broken.writeUInt32LE(padded.length, 12);
const browser = await webkit.launch();
try {
  for (const missing of [false, true]) {
    const page = await browser.newPage({ viewport: { width: 1100, height: 800 }, reducedMotion: "reduce" });
    const errors = [], shaderRequests = []; let requestedRevision;
    page.on("pageerror", e => errors.push(e.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    page.on("request", request => { if (/\.(?:fragment|vertex)\.fx(?:\?|$)/.test(request.url())) shaderRequests.push(request.url()); });
    await page.route("**/staff-makehuman.glb*", async route => {
      requestedRevision = new URL(route.request().url()).searchParams.get("rev");
      if (missing) await route.fulfill({ contentType: "model/gltf-binary", body: broken });
      else await route.continue();
    });
    await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
    await page.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", null, { timeout: 90000 });
    assert.equal(requestedRevision, revision, "Asset revision must match the current GLB");
    await page.getByRole("button", { name: "Billing view", exact: true }).click();
    await page.waitForFunction(() => Math.abs(Number(document.querySelector("canvas").dataset.camera?.split(",")[0]) - 1.05) < .02);
    await page.evaluate(() => { window.__heldCanvas = document.querySelector("canvas"); });
    if (!missing) await page.screenshot({ path: "/tmp/dastak-eyelids-v6-open.png" });
    await page.getByRole("button", { name: "Hold eyes closed", exact: true }).click();
    await page.waitForFunction(() => document.querySelector("canvas").dataset.blinkWeight === "1.000");
    await page.waitForTimeout(2000);
    assert.equal(await page.locator("canvas").getAttribute("data-blink-weight"), "1.000");
    if (!missing) await page.screenshot({ path: "/tmp/dastak-eyelids-v6-held.png" });
    await page.getByRole("button", { name: "Release eyelids", exact: true }).click();
    await page.waitForFunction(() => document.querySelector("canvas").dataset.blinkWeight === "0.000");
    await page.waitForTimeout(100);
    const result = await page.locator("canvas").evaluate(c => ({ sameCanvas: c === window.__heldCanvas, geometry: c.dataset.eyelidGeometry, cycles: Number(c.dataset.renderedBlinks) }));
    assert.ok(result.sameCanvas);
    assert.equal(result.geometry, missing ? "missing" : "validated");
    assert.equal(result.cycles, missing ? 0 : 1, "Missing eyelid geometry must not produce false blink counts");
    if (missing) assert.match(await page.locator(".grocery-room-status").innerText(), /ERROR: eyelid geometry missing/);
    assert.deepEqual(errors, []);
    assert.deepEqual(shaderRequests, [], "Shaders must be registered locally, never fetched as missing .fx files");
    console.log(JSON.stringify({ missing, ...result, errors, shaderRequests }));
    await page.close();
  }
} finally { await browser.close(); }
