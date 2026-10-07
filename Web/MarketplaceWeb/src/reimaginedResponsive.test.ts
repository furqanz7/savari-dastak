import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./design/reimagined.css", import.meta.url), "utf8");
const phone = css.slice(css.indexOf("/* Phone controls use full-width rows"));

describe("Reimagined responsive layout safeguards", () => {
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
  it("uses four bottom navigation targets and a full-width category row on phones", () => {
    expect(phone).toMatch(/\.reimagined-navigation \{[^}]*top: auto;[^}]*right:[^}]*grid-template-columns: repeat\(4, minmax\(0, 1fr\)\)/);
    expect(phone).toMatch(/\.reimagined-navigation button \{[^}]*min-height: 56px/);
    expect(phone).toMatch(/\.reimagined-directory \{[^}]*overflow-x: auto; overflow-y: hidden/);
    expect(phone).toMatch(/\.reimagined-directory section button \{[^}]*min-height: 48px/);
  });
  it("reserves space for the testing notice, cart and navigation", () => {
    expect(phone).toContain("--panel-preview-space: 56px");
    expect(phone).toMatch(/data-bottom-rows="1"[^}]*--panel-bottom: max\(162px/);
    expect(phone).toMatch(/data-bottom-rows="2"[^}]*--panel-bottom: max\(220px/);
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
