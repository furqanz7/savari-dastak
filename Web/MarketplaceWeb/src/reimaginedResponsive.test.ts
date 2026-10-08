import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./design/reimagined.css", import.meta.url), "utf8");
const phone = css.slice(css.indexOf("/* Preserve the brief's spatial model on phones"));

describe("Reimagined responsive layout safeguards", () => {
  it("does not inherit the old page minimum width when a short phone needs a scrollbar", () => {
    expect(css).toMatch(/body:has\(\.reimagined\) \{ min-width: 0; \}/);
  });
  it("contains home and Food tracks in a shrinkable grid column", () => {
    for (const selector of ["reimagined-grocery-home", "reimagined-food"]) {
      expect(css).toMatch(new RegExp(`\\.${selector} \\{[^}]*grid-template-columns: minmax\\(0, 1fr\\)`));
    }
  });
  it("keeps sideways scrolling inside dedicated tracks, not the shopping panel", () => {
    expect(css).toMatch(/\.reimagined-panel-content \{[^}]*overflow-y: auto; overflow-x: hidden/);
    for (const selector of ["reimagined-quick-track", "reimagined-shelf-track"]) {
      expect(css).toMatch(new RegExp(`\\.${selector} \\{[^}]*overflow-x: auto`));
    }
  });
  it("preserves top-left vertical navigation and a right-hand vertical directory on phones", () => {
    expect(phone).toMatch(/\.reimagined-navigation \{[^}]*bottom: auto;[^}]*grid-template-columns: minmax\(0, 1fr\)/);
    expect(phone).toMatch(/\.reimagined-navigation button \{[^}]*flex-direction: row;[^}]*min-height: 44px/);
    expect(phone).toMatch(/\.reimagined-right \{[^}]*left: max\(116px/);
    expect(phone).toMatch(/\.reimagined-location \{[^}]*left: max\(116px/);
    expect(phone).toMatch(/\.reimagined-directory \{[^}]*overflow-x: hidden; overflow-y: auto/);
    expect(phone).toMatch(/\.reimagined-directory section button \{[^}]*min-height: 44px/);
  });
  it("reserves bottom space only for the testing notice and contextual shopping/order state", () => {
    expect(phone).toContain("--panel-preview-space: 56px");
    expect(phone).toMatch(/data-bottom-rows="1"[^}]*--panel-bottom: max\(88px/);
    expect(phone).toMatch(/data-bottom-rows="2"[^}]*--panel-bottom: max\(146px/);
  });
  it("keeps phone text inputs readable without changing selection controls", () => {
    expect(phone).toMatch(/input:not\(\[type="radio"\]\):not\(\[type="checkbox"\]\)[^}]*font-size: 16px/);
  });
  it("lets very short screens scroll instead of hiding content behind fixed controls", () => {
    const short = css.slice(css.indexOf("@media (max-width: 720px) and (max-height: 600px)"));
    expect(short).toMatch(/data-authenticated="true"[^}]*height: auto/);
    expect(short).toMatch(/\.reimagined-main \{[^}]*position: relative;[^}]*min-height: 320px/);
    expect(short).toMatch(/\.reimagined-panel-content \{[^}]*min-height: 220px/);
  });
  it("does not inherit the scenery study's tiny desktop directory cap", () => {
    expect(css).toMatch(/data-authenticated="true"\]\[data-scene\^="grocery"\] \.reimagined-right \{ max-height: calc\(100dvh - 180px\)/);
  });
});
