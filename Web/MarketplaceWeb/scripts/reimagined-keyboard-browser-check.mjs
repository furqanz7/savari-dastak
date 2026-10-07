import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.DASTAK_PLAYWRIGHT_PATH ?? "playwright");
const origin = "http://127.0.0.1:5179";
const browser = await chromium.launch({ headless: true });
try {
  const context = await browser.newContext(); const issues = [];
  await context.route("**/*", route => {
    if (new URL(route.request().url()).origin !== origin) { issues.push("Non-local request"); return route.abort(); }
    return route.continue();
  });
  const page = await context.newPage(); page.on("pageerror", error => issues.push(error.message));
  const activate = async locator => { await locator.focus(); await page.keyboard.press("Enter"); };
  const focused = async locator => assert.equal(await locator.evaluate(element => element === document.activeElement), true);
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    for (const service of ["grocery", "food"]) {
      await page.goto(`${origin}/reimagined-${service}-check.html`);
      const shopping = page.getByTestId(`${service}-check-shopping`);
      const original = await shopping.textContent();
      await activate(page.getByRole("link", { name: "Skip to main content" }));
      await focused(page.locator("main"));
      const searchButton = page.getByRole("button", { name: "Open search", exact: true });
      await activate(searchButton);
      await focused(page.getByRole("searchbox"));
      await page.keyboard.press("Tab");
      await focused(page.getByRole("button", { name: "Submit search", exact: true }));
      await page.keyboard.press("Tab");
      await focused(page.getByRole("button", { name: "Close search", exact: true }));
      await page.keyboard.press("Escape"); await focused(searchButton);
      assert.equal(await page.getByRole("searchbox").count(), 0);
      const location = page.getByRole("button", { name: /DELIVERING TO\s*Test location/ });
      await activate(location);
      await focused(page.getByRole("button", { name: "Close location", exact: true }));
      await page.keyboard.press("Escape"); await focused(location);
      assert.equal(await page.getByRole("region", { name: "Delivery location", exact: true }).count(), 0);
      if (service === "food") await activate(page.getByRole("button", { name: "Open Test Café menu", exact: true }));
      const openDetail = page.getByRole("button", { name: service === "grocery" ? "View Test Plain Rice, 1 kg details" : "View Test Paneer Rice details", exact: true });
      await activate(openDetail);
      const closeDetail = page.getByRole("button", { name: service === "grocery" ? "Close product details" : "Back to menu", exact: true });
      await focused(closeDetail);
      await page.keyboard.press("Escape"); await focused(openDetail);
      if (service === "food") {
        await activate(searchButton);
        await page.getByRole("searchbox").fill("paneer");
        await activate(page.getByRole("button", { name: "Test Paneer Rice ₹150.00 base", exact: true }));
        await focused(closeDetail);
        await page.keyboard.press("Escape");
        await focused(page.locator("main"));
      }
      await activate(page.getByRole("button", { name: "Orders", exact: true }));
      await focused(page.locator("main"));
      await activate(page.getByRole("button", { name: "Home", exact: true }));
      await focused(page.locator("main"));
      await activate(page.getByRole("button", { name: service === "food" ? "Grocery" : "Food", exact: true }));
      await focused(page.locator("main"));
      await activate(page.getByRole("button", { name: service === "food" ? "Food" : "Grocery", exact: true }));
      await focused(page.locator("main"));
      assert.equal(await shopping.textContent(), original);
    }
  }
  assert.deepEqual(issues, []);
  console.log("PASS: desktop/mobile Food/Grocery keyboard-only skip link, search Tab/Escape, location Escape, detail entry/return, Food suggestion fallback, navigation/service focus, unchanged carts. Synthetic fixtures only.");
} finally { await browser.close(); }
