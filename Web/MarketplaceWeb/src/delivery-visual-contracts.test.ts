import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./design/delivery-experience.css", import.meta.url), "utf8");
const profileSheet = readFileSync(new URL("./AccountProfileSheet.tsx", import.meta.url), "utf8");
describe("Delivery presentation scope and responsive contracts", () => {
  it("reuses the shared palette without styling another application's layout", () => {
    expect(css).not.toMatch(/\.variant-dastak-(customer|merchant|admin)/);
    expect(css).toContain("var(--customer-shadow)");
    expect(css).toContain("var(--primary-action-foreground)");
    expect(css).toContain("var(--font-dastak-wordmark)");
    expect(css).toContain("var(--destructive)");
    expect(css).toContain("var(--warning)");
    expect(css).not.toMatch(/#[\da-f]{3,8}\b|rgba?\(/i);
  });
  it("bounds the mission/map split, mobile columns, long content and form controls", () => {
    expect(css).toContain("minmax(0, 1.45fr) minmax(300px, 1fr)");
    expect(css).toContain("@media (max-width: 1100px)");
    expect(css).toContain("@media (max-width: 760px)");
    expect(css).toContain("@media (max-width: 380px)");
    expect(css).toContain(".rider-desk { grid-template-columns: minmax(0, 1fr)");
    expect(css).toContain("font: 16px/1.5 var(--font-system)");
    expect(css).toContain("min-width: 0; overflow-wrap: anywhere");
    expect(css).toContain("repeat(5, minmax(0, 1fr))");
    expect(css).toContain("calc(110px + env(safe-area-inset-bottom))");
  });
  it("preserves keyboard/visual order and reduced-motion and forced-color alternatives", () => {
    expect(css).not.toMatch(/\border:\s*-?\d|grid-row:\s*1/);
    expect(css).toContain(":focus-visible");
    expect(css).toContain("prefers-reduced-motion: reduce");
    expect(css).toContain("forced-colors: active");
    expect(css).toContain(".availability-switch input { appearance: auto");
  });
  it("reserves Safari contact AutoFill space without disabling the full-name contract", () => {
    expect(profileSheet).toContain('id="customer-profile-name"');
    expect(profileSheet).toContain('autoComplete="name"');
    expect(css).toMatch(/\.delivery-experience \.rider-profile-presentation \.customer-profile-name-control input\s*\{[^}]*padding-inline-start:\s*48px;[^}]*padding-inline-end:\s*52px;[^}]*-webkit-appearance:\s*auto;[^}]*appearance:\s*auto;/s);
    expect(css).toMatch(/\.delivery-experience \.rider-profile-presentation \.customer-profile-name-control > svg\s*\{[^}]*top:\s*50%;[^}]*inset-inline-start:\s*16px;[^}]*translateY\(-50%\)/s);
    expect(css).not.toMatch(/contacts-auto-fill-button[^}]*display:\s*none|contacts-auto-fill-button[^}]*visibility:\s*hidden/s);
  });
});
