import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { V1CatalogueBrowseNode } from "./dastakV1";
import { missingReferenceDestinationArtwork, referenceBrowseArtworkKey } from "./referenceBrowseArtwork";

const destinationKeys = [
  "fresh-vegetables", "fresh-fruits", "dairy-bread-eggs", "meat-seafood",
  "atta-flour-dal", "masalas", "oils-ghee", "cereals-breakfast",
  "cold-drinks-juices", "ice-creams", "chips-namkeens", "chocolates",
  "biscuits-cakes", "tea-coffee-milk-drinks", "sauces-spreads", "sweet-corner",
  "noodles-pasta-vermicelli", "frozen-food", "dry-fruits-seeds-mix", "paan-corner",
  "bath-body", "hair-care", "skincare", "makeup", "feminine-hygiene",
  "sexual-wellness", "health-pharma", "baby-care", "home-kitchen", "pooja-store",
  "cleaners-repellents", "toys-stationery", "electronics-appliances", "fashion",
  "pet-supplies", "sports-fitness",
];

const node = (key: string): V1CatalogueBrowseNode => ({
  key, kind: "DESTINATION", label: key, parentKey: "section", sortOrder: 0, sources: [],
});

describe("reference destination artwork", () => {
  it("covers every reference destination and only points at shipped images", () => {
    expect(missingReferenceDestinationArtwork({ nodes: destinationKeys.map(node) })).toEqual([]);
    for (const key of destinationKeys) {
      const imageKey = referenceBrowseArtworkKey(node(key));
      if (!imageKey) continue;
      if (!imageKey.startsWith("local/")) {
        expect(imageKey).toMatch(/^canonical\/taxonomy\/[-a-z0-9]+\.png$/);
        continue;
      }
      const asset = fileURLToPath(new URL(`../public/catalogue/${imageKey.slice("local/".length)}`, import.meta.url));
      expect(existsSync(asset), `${key} points to a missing image`).toBe(true);
    }
  });
  it("does not borrow the first canonical source image for intentionally empty destinations", () => {
    expect(referenceBrowseArtworkKey(node("masalas"))).toBe("canonical/taxonomy/masala-oil.png");
    expect(referenceBrowseArtworkKey(node("fashion"))).toBeNull();
  });
});
