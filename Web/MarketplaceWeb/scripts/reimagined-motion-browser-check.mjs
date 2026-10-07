import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = "http://127.0.0.1:5179";
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext();
  const issues = [];
  await context.route("**/*", route => {
    if (new URL(route.request().url()).origin !== origin) {
      issues.push("Non-local request"); return route.abort();
    }
    return route.continue();
  });
  const page = await context.newPage();
  page.on("pageerror", error => issues.push(error.message));
  for (const reducedMotion of ["no-preference", "reduce"]) {
    await page.emulateMedia({ reducedMotion });
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto(`${origin}/reimagined-preview.html`);
      const scene = async expected => assert.equal(await page.locator(".reimagined").getAttribute("data-scene"), expected);
      const capture = async name => {
        if (!process.env.DASTAK_MOTION_SCREENSHOT_DIR || reducedMotion !== "no-preference") return;
        await page.locator(".reimagined-room, .grocery-room-3d").evaluate(async element => {
          await Promise.all(element.getAnimations().map(animation => animation.finished));
        });
        await page.screenshot({ path: `${process.env.DASTAK_MOTION_SCREENSHOT_DIR}/${name}-${width}.png`, fullPage: true });
      };
      const motion = async () => {
        if (await page.locator(".grocery-room-3d").count()) {
          assert.equal(await page.locator(".grocery-room-canvas").getAttribute("data-renderer"), "babylon-webgl");
          return;
        }
        const style = await page.locator(".reimagined-room").evaluate(element => {
          const css = getComputedStyle(element);
          return { name: css.animationName, duration: css.animationDuration, transform: css.transform };
        });
        assert.equal(style.name, reducedMotion === "reduce" ? "room-arrive-reduced" : "room-arrive");
        assert.equal(style.duration, reducedMotion === "reduce" ? "0.12s" : "0.65s");
        if (reducedMotion === "reduce") assert.equal(style.transform, "none");
      };
      await scene("outside"); await motion();
      assert.equal(await page.locator(".room-storefront").evaluate(element => getComputedStyle(element).display), "block");
      await capture("storefront");
      await page.getByRole("button", { name: "Continue with Apple", exact: true }).click();
      await scene("groceryEntrance");
      assert.equal(await page.locator(".grocery-room-3d").count(), 1);
      await page.waitForFunction(() => document.querySelector(".grocery-room-canvas")?.dataset.staff === "ready", undefined, { timeout: 90000 });
      assert.equal(await page.locator(".reimagined-environment").getAttribute("aria-hidden"), "true");
      await capture("grocery-entrance");
      await page.getByRole("button", { name: "Take a Bucket", exact: true }).click();
      await page.getByText("Local test controls — not real products or orders", { exact: true }).click();
      await page.getByRole("button", { name: "Simulate adding an item", exact: true }).click();
      await page.getByRole("button", { name: "Take to Cart", exact: true }).click();
      await scene("groceryCounter"); await motion();
      await capture("grocery-counter");
      await page.getByRole("button", { name: "Continue Shopping", exact: true }).click();
      assert.match(await page.getByRole("region", { name: "Grocery Bucket summary" }).textContent(), /1 item/);
      await page.getByRole("button", { name: "Food", exact: true }).click();
      await scene("foodEntrance");
      assert.equal(await page.locator(".room-table-left").evaluate(element => getComputedStyle(element).display), "block");
      assert.equal(await page.locator(".room-aisle-left").evaluate(element => getComputedStyle(element).display), "none");
      await capture("food-entrance");
      const foodButton = page.getByRole("button", { name: "Food", exact: true });
      await foodButton.hover();
      assert.equal(await foodButton.evaluate(element => getComputedStyle(element).backgroundColor), "rgb(53, 96, 71)");
      await page.getByRole("button", { name: "Simulate adding an item", exact: true }).click();
      await scene("foodApproachingCounter"); await motion();
      await page.getByRole("button", { name: "Review Food cart", exact: true }).click();
      await scene("foodCounter");
      await capture("food-counter");
      await page.getByRole("button", { name: "Continue Shopping", exact: true }).click();
      await scene("foodApproachingCounter");
      await page.getByRole("button", { name: "Grocery", exact: true }).click();
      assert.match(await page.getByRole("region", { name: "Grocery Bucket summary" }).textContent(), /1 item/);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      if (process.env.DASTAK_MOTION_SCREENSHOT_DIR) {
        await page.getByRole("button", { name: "Food", exact: true }).click();
        await page.locator(".reimagined-room").evaluate(async element => {
          await Promise.all(element.getAnimations().map(animation => animation.finished));
        });
        await page.screenshot({ path: `${process.env.DASTAK_MOTION_SCREENSHOT_DIR}/motion-${width}-${reducedMotion}.png`, fullPage: true });
      }
    }
  }
  assert.deepEqual(issues, []);
  console.log("PASS: desktop/mobile six scene states, normal/reduced motion, preserved service carts and no overflow. Local simulated preview only.");
} finally { await browser.close(); }
