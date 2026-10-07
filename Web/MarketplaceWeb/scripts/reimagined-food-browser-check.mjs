import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = process.env.DASTAK_LOCAL_FOOD_CHECK_ORIGIN ?? "http://127.0.0.1:5179";
if (!["localhost", "127.0.0.1", "[::1]"].includes(new URL(origin).hostname)) throw new Error("Loopback origin required.");
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext(); const issues = [];
  await context.route("**/*", route => {
    if (new URL(route.request().url()).origin !== new URL(origin).origin) { issues.push("Non-local request"); return route.abort(); }
    return route.continue();
  });
  const page = await context.newPage(); page.on("pageerror", error => issues.push(error.message));
  for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(viewport); await page.goto(`${origin}/reimagined-food-check.html`);
    const initialShopping = JSON.parse(await page.getByTestId("food-check-shopping").textContent());
    await page.getByRole("button", { name: "Open Test Café menu", exact: true }).click();
    await page.getByRole("button", { name: "View Test Paneer Rice details", exact: true }).click();
    assert.equal(await page.getByRole("button", { name: "Add to Food cart", exact: true }).isDisabled(), true);
    await page.getByRole("radio", { name: "Large" }).check();
    await page.getByRole("button", { name: "Add to Food cart", exact: true }).click();
    await page.getByRole("button", { name: "Add to Food cart", exact: true }).click();
    const shopping = await page.getByTestId("food-check-shopping").textContent();
    const saved = JSON.parse(shopping);
    assert.deepEqual(saved.retail, initialShopping.retail);
    assert.equal(saved.food[0].quantity, 2);
    assert.equal(saved.food[0].optionIds.length, 1);
    if (process.env.DASTAK_FOOD_SCREENSHOT_DIR) {
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({ path: `${process.env.DASTAK_FOOD_SCREENSHOT_DIR}/food-${viewport.width}.png`, fullPage: true });
    }
    await page.getByRole("button", { name: "Back to menu", exact: true }).click();
    await page.getByRole("button", { name: "Back to restaurants", exact: true }).click();
    await page.getByRole("button", { name: "Open search", exact: true }).click();
    const search = page.getByRole("searchbox", { name: "Search Food" }); await search.fill("paneer");
    assert.equal(await page.getByRole("button", { name: "Open Test Café menu", exact: true }).count(), 1);
    await search.press("Enter");
    await page.getByRole("button", { name: "Test Paneer Rice ₹150.00 base", exact: true }).click();
    await page.getByRole("button", { name: "Review Food cart", exact: true }).click();
    assert.equal(await page.getByRole("region", { name: "Food cart summary", exact: true }).count(), 0);
    assert.equal(await page.getByText("Your Food selections, recipient and saved address pass local checks. Reservation and confirmation are separate steps.", { exact: true }).count(), 1);
    assert.equal(await page.getByText("Estimated Food item subtotal: ₹360.00", { exact: true }).count(), 1);
    assert.equal(await page.getByRole("button", { name: "Food checkout integration pending", exact: true }).isDisabled(), true);
    if (process.env.DASTAK_FOOD_SCREENSHOT_DIR) await page.screenshot({ path: `${process.env.DASTAK_FOOD_SCREENSHOT_DIR}/food-review-${viewport.width}.png`, fullPage: true });
    await page.getByRole("button", { name: "Continue Shopping", exact: true }).click();
    assert.equal(await page.getByTestId("food-check-shopping").textContent(), shopping);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  }
  assert.deepEqual(issues, []);
  console.log("PASS: desktop/mobile Food menus, dish details, typing/Enter search, cart preservation, disabled checkout and no page overflow. Synthetic fixture; no backend requests.");
} finally { await browser.close(); }
