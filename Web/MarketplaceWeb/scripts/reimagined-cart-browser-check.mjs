import { createRequire } from "node:module";
import assert from "node:assert/strict";

// Use a supplied existing Playwright installation; never download browsers/dependencies.
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = process.env.DASTAK_LOCAL_CART_CHECK_ORIGIN ?? "http://127.0.0.1:5179";
if (!["localhost", "127.0.0.1", "[::1]"].includes(new URL(origin).hostname)) throw new Error("Local loopback origin required.");
const browser = await chromium.launch({ headless: true, ...(process.env.DASTAK_BROWSER_CHANNEL ? { channel: process.env.DASTAK_BROWSER_CHANNEL } : {}) });
try {
  const context = await browser.newContext(); // Isolated from real customer/browser storage.
  const first = await context.newPage(); const second = await context.newPage();
  const issues = [];
  await context.route("**/*", route => {
    if (new URL(route.request().url()).origin !== new URL(origin).origin) {
      issues.push("Unexpected non-local request"); return route.abort();
    }
    return route.continue();
  });
  for (const page of [first, second]) page.on("pageerror", error => issues.push(error.message));
  const key = "dastak:v1-cart:__reimagined_browser_cart_check__";
  const shopping = page => page.getByTestId("shopping").textContent().then(JSON.parse);
  const waitFor = async (page, predicate) => {
    for (let attempt = 0; attempt < 100; attempt++) {
      if (predicate(await shopping(page))) return;
      await page.waitForTimeout(20);
    }
    throw new Error("Cart synchronization timeout");
  };
  await first.goto(`${origin}/reimagined-cart-check.html`);
  await first.getByTestId("editing").filter({ hasText: "true" }).waitFor();
  await first.getByRole("button", { name: "Take Bucket", exact: true }).click();
  await first.getByRole("button", { name: "Add rice", exact: true }).click();
  await first.getByRole("button", { name: "Add test Food", exact: true }).click();
  await second.goto(`${origin}/reimagined-cart-check.html`);
  await second.getByTestId("editing").filter({ hasText: "false" }).waitFor();
  assert.equal(await second.getByRole("button", { name: "Add rice", exact: true }).isDisabled(), true);
  await first.getByRole("button", { name: "Simulate local acknowledgement", exact: true }).click();
  await waitFor(second, value => !value.retail["browser-test-rice"] && value.food[0]?.quantity === 2);
  await second.getByRole("button", { name: "Navigate Orders", exact: true }).click();
  const raw = await first.evaluate(key => JSON.parse(localStorage.getItem(key)), key);
  assert.deepEqual(raw.reimaginedGroceryAcknowledgements, ["browser-test-confirmation"]);
  await first.getByRole("button", { name: "Add rice", exact: true }).click();
  await waitFor(second, value => value.retail["browser-test-rice"] === 1);
  await first.close();
  await second.getByTestId("editing").filter({ hasText: "true" }).waitFor();
  await second.getByRole("button", { name: "Add rice", exact: true }).click();
  await waitFor(second, value => value.retail["browser-test-rice"] === 2 && value.food[0]?.quantity === 2);
  assert.deepEqual(issues, []);
  console.log("PASS: native Chromium tabs, read-only follower, acknowledgement synchronization, Food preservation, navigation safety and editor handoff. No backend requests.");
} finally { await browser.close(); }
