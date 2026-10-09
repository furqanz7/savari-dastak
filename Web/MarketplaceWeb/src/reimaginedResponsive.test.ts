import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./design/reimagined.css", import.meta.url), "utf8");
const foodCss = readFileSync(new URL("./design/reimaginedFood.css", import.meta.url), "utf8");
const phone = css.slice(css.indexOf("/* Preserve the brief's spatial model on phones"));

describe("Reimagined responsive layout safeguards", () => {
  it("applies the compact tablet wordmark after the restored desktop brand size", () => {
    const brand = css.indexOf("/* Existing Dastak brand");
    const tablet = css.indexOf("@media (min-width: 721px) and (max-width: 1100px)", brand);
    expect(tablet).toBeGreaterThan(brand);
    expect(css.slice(tablet)).toMatch(/\.reimagined-wordmark \{ font-size: 28px; \}/);
  });
  it("lets long Food group and option names shrink within the phone panel", () => {
    expect(foodCss).toMatch(/\.reimagined-food-choices fieldset \{[^}]*min-inline-size: 0;[^}]*max-width: 100%/);
    expect(foodCss).toMatch(/\.reimagined-food-choices legend \{[^}]*max-width: 100%;[^}]*overflow-wrap: anywhere/);
    expect(foodCss).toMatch(/\.reimagined-food-choices label > span \{[^}]*min-width: 0;[^}]*overflow-wrap: anywhere/);
  });
  it("replaces the legacy two-column account grid with a panel-sized single column", () => {
    expect(css).toMatch(/\.reimagined \.customer-account\[data-account-pane\] \{[^}]*grid-template-columns: minmax\(0, 1fr\);[^}]*container: reimagined-account \/ inline-size/);
    expect(css).toContain("@container reimagined-account (max-width: 360px)");
    expect(css).toMatch(/\.customer-account-row:has\(\.customer-identity-actions\) \{ grid-template-columns: 42px minmax\(0, 1fr\); \}/);
  });
  it("keeps authenticated shell layout independent of legacy account-screen mounting", () => {
    expect(css).toMatch(/\.app\.variant-dastak-customer:has\(\.reimagined\[data-authenticated="true"\]\) \{ padding: 0; background: transparent; \}/);
    expect(css).toMatch(/\.content\.workspace-content:has\(\.reimagined\[data-authenticated="true"\]\) \{[^}]*max-width: none;[^}]*padding: 0; margin: 0/);
  });
  it("keeps legacy workspaces and body-portalled dialogs readable on light glass in system dark mode", () => {
    expect(css).toMatch(/\.reimagined \.customer-workspace, \.reimagined-address-modal\.customer-experience \{[^}]*color-scheme: light;[^}]*--text-primary: #28231d;[^}]*--text-secondary: #71695e;/);
    expect(css).toMatch(/\.reimagined \.customer-workspace, \.reimagined-address-modal\.customer-experience \{[^}]*--surface: #fdfcf9;[^}]*--surface-raised: #ffffff;/);
  });
  it("anchors search below the actual heading without moving shopping content", () => {
    expect(css).toMatch(/\.reimagined-search-anchor \{[^}]*position: relative;[^}]*flex-shrink: 0/);
    expect(css).toMatch(/\.reimagined-search-anchor \.reimagined-search \{ top: 8px; left: 0; right: 0; \}/);
  });
  it("keeps long saved-address lists in a bounded scrollable location panel", () => {
    expect(css).toMatch(/\.reimagined-location-panel \{[^}]*max-height: min\(70dvh, 640px\);[^}]*overflow-y: auto/);
    expect(css).toMatch(/\.reimagined-location-panel > \.reimagined-panel-heading \{[^}]*position: sticky/);
  });
  it("releases old signed-out onboarding width and overflow constraints", () => {
    expect(css).toMatch(/\.app\.customer-onboarding-active:has\(\.reimagined\[data-authenticated="false"\]\) \{[^}]*height: auto;[^}]*overflow: visible;[^}]*padding: 0/);
    expect(css).toMatch(/\.content\.dastak-customer-auth-content:has\(> \.reimagined\[data-authenticated="false"\]\) \{[^}]*max-width: none;[^}]*height: auto;[^}]*padding: 0;[^}]*overflow: visible/);
  });
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
    expect(short).toContain(".reimagined-navigation, .reimagined-right, .reimagined-location { position: absolute; }");
  });
  it("does not inherit the scenery study's tiny desktop directory cap", () => {
    expect(css).toMatch(/data-authenticated="true"\]\[data-scene\^="grocery"\] \.reimagined-right \{ max-height: calc\(100dvh - 180px\)/);
  });
});
