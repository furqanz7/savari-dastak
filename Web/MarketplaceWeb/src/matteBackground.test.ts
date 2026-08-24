import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const styles = readFileSync(new URL("./styles.css", import.meta.url), "utf8");

describe("Dastak matte backgrounds", () => {
  it("applies the shared grain to every Dastak application shell", () => {
    expect(styles).toContain(".app.product-dastak::before");
    expect(styles).toContain("background-image: var(--dastak-matte-noise)");
    expect(styles).toMatch(/\.app\.product-dastak\s*\{[^}]*radial-gradient/s);
  });

  it("keeps public privacy, terms and support pages in the same visual system", () => {
    expect(styles).toContain(".public-information-page::before");
    expect(styles).toMatch(/\.public-information-page\s*\{[^}]*isolation: isolate/s);
  });
});
