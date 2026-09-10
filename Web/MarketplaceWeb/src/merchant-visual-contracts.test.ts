import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./design/merchant-experience.css", import.meta.url), "utf8");
describe("Merchant visual scope and responsive contracts", () => {
  it("keeps Merchant styling separate from every other application's layout", () => {
    const shell = readFileSync(new URL("./MerchantOrdersView.tsx", import.meta.url), "utf8");
    expect(shell).toContain('import "./design/customer-experience.css"');
    expect(shell).toContain('import "./design/merchant-experience.css"');
    expect(shell.indexOf('import "./design/customer-experience.css"')).toBeLessThan(shell.indexOf('import "./design/merchant-experience.css"'));
    expect(css).not.toMatch(/\.variant-dastak-(customer|delivery|admin)/);
    expect(css).toContain("var(--customer-shadow)");
    expect(css).toContain("var(--primary-action-foreground)");
    expect(css).toContain("var(--font-dastak-wordmark)");
    expect(css).toContain(".merchant-experience [hidden] { display: none !important;");
  });
  it("keeps mobile controls readable, grids bounded and Store in normal document scrolling", () => {
    expect(css).toContain("@media (max-width: 620px)");
    expect(css).toContain("@media (max-width: 900px)");
    expect(css).toContain("@media (min-width: 1320px)");
    expect(css).toContain("repeat(5, minmax(0, 1fr))");
    expect(css).toContain("repeat(2, minmax(0, 1fr))");
    expect(css).toContain("font: 16px/1.4 var(--font-system)");
    expect(css).toContain("height: auto; overflow: visible;");
    expect(css).toContain(".merchant-experience .merchant-v1-subcategory-rail { display: none;");
    expect(css).toContain("bottom: calc(88px + env(safe-area-inset-bottom))");
  });
  it("preserves native visual order, keyboard focus and reduced-motion/forced-color alternatives", () => {
    expect(css).not.toMatch(/\border:\s*-\d/);
    expect(css).toContain(":focus-visible");
    expect(css).toContain("prefers-reduced-motion: reduce");
    expect(css).toContain("forced-colors: active");
    expect(css).toContain("label:has(input:focus-visible)");
  });
  it("gives long order-item descriptions the flexible column at wide and narrow card widths", () => {
    expect(css).toContain("grid-template-columns: max-content minmax(0, 1fr) max-content");
    expect(css).toContain(".merchant-experience .merchant-order-lines li > span { min-width: 0; display: grid; grid-template-columns: minmax(0, 1fr)");
    expect(css).toContain(".merchant-experience .merchant-order-lines li > span > strong { min-width: 0; white-space: normal; overflow-wrap: break-word; word-break: normal;");
    expect(css).toContain(".merchant-experience .merchant-order-lines li > span > small { grid-column: auto; min-width: 0; overflow-wrap: break-word; word-break: normal;");
    expect(css).not.toMatch(/\.merchant-experience \.merchant-order-lines li > span[^}]*grid-template-columns:\s*24px/);
  });
});
