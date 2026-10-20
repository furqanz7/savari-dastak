import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("keeps the support safety notice readable on the dark Admin workspace", () => {
  const css = readFileSync(new URL("./design/merchant-support.css", import.meta.url), "utf8");
  const safety = css.match(/\.merchant-support-safety \{([^}]+)\}/)?.[1];
  expect(safety).toContain("color:#24362f;");
  expect(safety).toContain("background:#e9eee5;");
});
