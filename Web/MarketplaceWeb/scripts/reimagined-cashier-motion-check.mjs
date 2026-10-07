// Local-only deterministic rig inspection. The pose hook is injected into the
// dev response by this test, never exposed in application or production code.
import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 900, height: 760 }, reducedMotion: "reduce" });
  const errors = [];
  page.on("pageerror", e => errors.push(e.message));
  await page.route("**/src/reimaginedGroceryScene.ts*", async route => {
    const response = await route.fetch();
    const source = await response.text();
    assert.ok(source.includes("const targetPosition ="), "Pose injection boundary exists");
    await route.fulfill({ response, body: source.replace("const targetPosition =", "window.__cashierStudy = { scene, pose: time => staffUpdate?.(time) }; const targetPosition =") });
  });
  await page.goto("http://127.0.0.1:5179/reimagined-environment-study.html");
  await page.waitForFunction(() => document.querySelector("canvas")?.dataset.sceneReady === "true", null, { timeout: 90000 });
  const result = await page.evaluate(() => {
    const { scene, pose } = window.__cashierStudy;
    const names = ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"];
    const nodes = names.map(name => scene.getTransformNodeByName(name));
    const snapshot = () => nodes.map(n => n.rotationQuaternion.asArray());
    const error = (a, b) => Math.max(...a.map((q, i) => 2 * Math.acos(Math.min(1, Math.abs(q.reduce((sum, x, j) => sum + x * b[i][j], 0)) / (Math.hypot(...q) * Math.hypot(...b[i]))))));
    pose(0); const first = snapshot();
    let maxKnuckleTilt = 0;
    let lowestFingerJoint = Infinity;
    for (let i = 0; i < 360; i++) {
      pose(i / 12);
      for (const side of ["l", "r"]) {
        const y = name => scene.getTransformNodeByName(`${name}_${side}`).computeWorldMatrix(true).getTranslation().y;
        maxKnuckleTilt = Math.max(maxKnuckleTilt, Math.abs(y("index_01") - y("pinky_01")));
        lowestFingerJoint = Math.min(lowestFingerJoint, y("middle_03"));
      }
    }
    pose(0); const driftRadians = error(first, snapshot());
    pose(3.1); const coarse = snapshot();
    for (let i = 0; i < 187; i++) pose(i / 60);
    pose(3.1); const cadenceErrorRadians = error(coarse, snapshot());
    pose(0);
    // Inspect the real skinned character, without counter occlusion.
    for (const mesh of scene.meshes) {
      let n = mesh; let staff = false;
      while (n) { if (n.name === "cashier") staff = true; n = n.parent; }
      mesh.setEnabled(staff && !mesh.name.includes("eyelashes01"));
    }
    const head = scene.getTransformNodeByName("head").getAbsolutePosition();
    scene.activeCamera.position.set(head.x - .58, head.y + .015, head.z);
    scene.activeCamera.setTarget(head);
    scene.render();
    const handPoints = ["hand_r", "middle_01_r", "middle_02_r", "middle_03_r", "index_01_r", "pinky_01_r"].map(name => ({ name, position: scene.getTransformNodeByName(name).getAbsolutePosition().asArray() }));
    const browWeights = scene.meshes.filter(m => m.name.includes("eyebrow")).flatMap(m => m.morphTargetManager ? Array.from({ length: m.morphTargetManager.numTargets }, (_, i) => m.morphTargetManager.getTarget(i).influence) : []);
    return { driftRadians, cadenceErrorRadians, maxKnuckleTilt, lowestFingerJoint, browWeights, handPoints };
  });
  await page.locator(".environment-study-tools").evaluateAll(elements => elements.forEach(e => e.style.display = "none"));
  await page.screenshot({ path: "/tmp/dastak-eyes-open.png" });
  await page.evaluate(() => { const { scene, pose } = window.__cashierStudy; pose(4.9); scene.render(); });
  await page.screenshot({ path: "/tmp/dastak-eyes-blink.png" });
  await page.evaluate(() => {
    const { scene, pose } = window.__cashierStudy; pose(0);
    const head = scene.getTransformNodeByName("head").getAbsolutePosition();
    scene.activeCamera.position.set(head.x - 1.2, 1.36, head.z);
    scene.activeCamera.setTarget(head.clone().set(head.x, 1.36, head.z)); scene.render();
  });
  await page.screenshot({ path: "/tmp/dastak-hands-rest.png" });
  console.log(JSON.stringify({ ...result, errors }));
  if (!process.env.DASTAK_MOTION_BASELINE) {
    assert.ok(result.driftRadians < .001, "No cumulative arm/hand drift across idle cycles");
    assert.ok(result.cadenceErrorRadians < .001, "Pose must not depend on frame cadence/history");
    assert.ok(result.maxKnuckleTilt < .008, "Both palms remain level rather than rolling onto their edges");
    assert.ok(result.lowestFingerJoint > 1.10, "Finger joints remain above the keyboard surface");
    assert.ok(result.browWeights.every(weight => weight === 0), "Idle blink must not deform eyebrows");
    assert.deepEqual(errors, []);
  }
} finally { await browser.close(); }
