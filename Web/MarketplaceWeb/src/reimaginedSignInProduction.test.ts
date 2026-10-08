import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const scene = readFileSync(new URL("./reimaginedGroceryScene.ts", import.meta.url), "utf8");
it("ships the requested exterior rather than stripping it in production", () => {
  expect(scene).toContain("let outside = Boolean(options.outside)");
  expect(scene).toContain("if (outside) ensureExterior()");
  expect(scene).toContain("setOutside(value) { outside = value;");
  expect(scene).not.toMatch(/import\.meta\.env\.DEV\s*\?\s*create(?:Outdoor|NightLighting)/);
});
it("bundles all file textures used by the production exterior", () => {
  for (const asset of ["exterior-pavement-color.jpg", "exterior-pavement-normal.jpg", "exterior-pavement-arm.jpg", "wood_floor-color.jpg", "wood_floor-normal.jpg"]) {
    expect(scene).toContain(`${asset}?url`);
  }
  expect(scene).not.toMatch(/new Texture\([^\n]*\/src\/assets/);
});
