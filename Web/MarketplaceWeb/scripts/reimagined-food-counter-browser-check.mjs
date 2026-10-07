import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = "http://127.0.0.1:5179";
const browser = await chromium.launch({ headless: true });
const issues = [];
try {
  for (const width of [1440, 390]) {
    const context = await browser.newContext({ viewport: { width, height: width === 390 ? 844 : 1000 } });
    await context.route("**/*", route => {
      if (new URL(route.request().url()).origin !== origin) { issues.push(`Blocked non-local request: ${route.request().url()}`); return route.abort(); }
      return route.continue();
    });
    const page = await context.newPage(); page.on("pageerror", error => issues.push(error.message));
    const button = name => page.getByRole("button", { name, exact: true });
    const cart = async () => JSON.parse(await page.getByTestId("counter-cart").textContent());
    const events = () => page.evaluate(() => JSON.parse(sessionStorage.getItem("fixture:events") ?? "[]"));
    async function open(scenario) {
      await page.goto(origin); await page.evaluate(() => sessionStorage.clear());
      await page.goto(`${origin}/reimagined-food-counter-check.html?scenario=${scenario}`);
      await page.getByRole("heading", { name: "Local Food counter test" }).waitFor();
    }
    for (const scenario of ["disabled", "offline", "read-only"]) {
      await open(scenario); assert.equal(await button(scenario === "disabled" ? "Food checkout integration pending" : "Reserve Food order").isDisabled(), true); assert.deepEqual(await events(), []);
    }
    await open("normal"); const initial = await cart();
    await button("Reserve Food order").click(); await page.getByText("Server order total: ₹370.00", { exact: true }).waitFor();
    assert.equal(await page.getByText(/No order has been created/).count(), 0);
    assert.deepEqual((await events()).map(e => e.operation), ["submit"]); assert.deepEqual(await cart(), initial);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    if (process.env.DASTAK_FOOD_SCREENSHOT_DIR) await page.screenshot({ path: `${process.env.DASTAK_FOOD_SCREENSHOT_DIR}/food-counter-${width}.png`, fullPage: true });
    await page.reload(); await button("Recover Food reservation").click(); await button("Confirm Food order").waitFor();
    await button("Confirm Food order").click(); await button("Recover confirmed Food cart").waitFor();
    assert.deepEqual(await cart(), { retail: initial.retail, food: [] });
    await button("Recover confirmed Food cart").click(); assert.equal((await events()).filter(e => e.operation === "commit").length, 1);
    for (const scenario of ["lost-submit", "lost-commit", "refresh-fail", "ack-fail", "expiry"]) {
      await open(scenario); await button("Reserve Food order").click();
      if (scenario === "lost-submit") {
        await page.getByRole("alert").waitFor(); await page.reload(); await button("Reserve Food order").click(); await button("Confirm Food order").waitFor();
        const submitted = (await events()).filter(e => e.operation === "submit"); assert.equal(submitted.length, 2); assert.equal(submitted[0].key, submitted[1].key);
      } else {
        await button("Confirm Food order").waitFor();
        if (scenario === "lost-commit" || scenario === "ack-fail") {
          await button("Confirm Food order").click(); await page.getByRole("alert").waitFor(); assert.equal((await cart()).food.length, 1);
          if (scenario === "lost-commit") { await page.reload(); await button("Recover Food reservation").click(); }
          else await button("Recover confirmed Food cart").click();
          await page.waitForFunction(() => JSON.parse(document.querySelector('[data-testid="counter-cart"]').textContent).food.length === 0);
          assert.equal((await events()).filter(e => e.operation === "commit").length, 1);
        } else {
          await button("Refresh Food order status").click();
          if (scenario === "refresh-fail") { await page.getByRole("alert").waitFor(); assert.equal(await button("Confirm Food order").count(), 0); }
          else { await button("Recheck closed Food reservation").click(); await button("Reserve Food order").waitFor(); }
          assert.equal((await cart()).food.length, 1); assert.equal((await events()).filter(e => e.operation === "commit").length, 0);
        }
      }
    }
    await context.close();
    console.log(`Food counter browser checks passed at ${width}px: disabled/offline/ownership, reserve/reload/recover/confirm, retry keys, lost commitment, failed status, cart-save retry, expiry; Grocery retained.`);
  }
  assert.deepEqual(issues, []);
} finally { await browser.close(); }
