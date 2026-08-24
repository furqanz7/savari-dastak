import { describe, expect, it } from "vitest";
import { publicInformationKindForPath, publicInformationPages } from "./publicInformation";

describe("public Dastak information pages", () => {
  it("resolves only the three first-party public routes", () => {
    expect(publicInformationKindForPath("/privacy")).toBe("privacy");
    expect(publicInformationKindForPath("/terms/")).toBe("terms");
    expect(publicInformationKindForPath(" /support/ ")).toBe("support");
    expect(publicInformationKindForPath("/")).toBeUndefined();
    expect(publicInformationKindForPath("/account")).toBeUndefined();
  });

  it("publishes complete privacy, terms and support content", () => {
    expect(Object.keys(publicInformationPages)).toEqual(["privacy", "terms", "support"]);
    expect(publicInformationPages.privacy.sections.length).toBeGreaterThanOrEqual(7);
    expect(publicInformationPages.terms.sections.length).toBeGreaterThanOrEqual(8);
    expect(publicInformationPages.support.actions?.map((action) => action.href)).toEqual([
      "/#/orders",
      "/#/account",
      "/privacy",
    ]);
    expect(JSON.stringify(publicInformationPages.support)).not.toMatch(/mailto:/i);
  });
});
