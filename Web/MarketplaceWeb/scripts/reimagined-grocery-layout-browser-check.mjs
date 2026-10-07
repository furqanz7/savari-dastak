import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = "http://127.0.0.1:5179";
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const issues = [];
  await context.route("**/*", route => {
    if (new URL(route.request().url()).origin !== origin) { issues.push("Non-local request"); return route.abort(); }
    return route.continue();
  });
  const page = await context.newPage(); page.on("pageerror", error => issues.push(error.message));
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`${origin}/reimagined-grocery-check.html`);
    const track = page.locator(".reimagined-shelf-track");
    assert.equal(await track.locator("article").count(), 3);
    const dimensions = await track.evaluate(element => ({ width: element.clientWidth, card: element.querySelector("article").getBoundingClientRect().width, scroll: element.scrollWidth }));
    if (width === 390) {
      assert.ok(dimensions.width / (dimensions.card + 12) >= 2);
      assert.ok(dimensions.width / (dimensions.card + 12) <= 2.5);
      assert.ok(dimensions.scroll > dimensions.width);
    }
    await page.getByRole("button", { name: "Add Test Plain Rice, 1 kg", exact: true }).click();
    assert.equal(await page.getByRole("region", { name: "Grocery Bucket summary" }).count(), 0);
    await page.getByRole("button", { name: "Take a Bucket", exact: true }).click();
    await page.getByRole("button", { name: "Add Test Plain Rice, 1 kg", exact: true }).click();
    const shopping = await page.getByTestId("grocery-check-shopping").textContent();
    if (process.env.DASTAK_GROCERY_SCREENSHOT_DIR) await page.screenshot({ path: `${process.env.DASTAK_GROCERY_SCREENSHOT_DIR}/shelf-${width}.png`, fullPage: true });
    await page.getByRole("button", { name: "View Test Plain Rice, 1 kg details", exact: true }).click();
    assert.equal(await page.getByRole("region", { name: "Test Plain Rice details", exact: true }).count(), 1);
    await page.getByRole("button", { name: "Close product details", exact: true }).click();
    await page.getByRole("button", { name: "Take to Cart", exact: true }).click();
    assert.equal(await page.getByRole("button", { name: "Grocery checkout integration pending", exact: true }).isDisabled(), true);
    await page.getByRole("button", { name: "Continue Shopping", exact: true }).click();
    assert.equal(await page.getByTestId("grocery-check-shopping").textContent(), shopping);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  }
  assert.deepEqual(issues, []);
  console.log("PASS: 320/390/768/1440 Grocery layout, 2–2.5 mobile card capacity, Bucket gate, exact details, disabled checkout and retained cart. Synthetic fixture only.");
} finally { await browser.close(); }
