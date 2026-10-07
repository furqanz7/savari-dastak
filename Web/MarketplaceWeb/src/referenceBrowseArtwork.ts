import type { V1CatalogueBrowseNode } from "./dastakV1";

// The reference destinations often combine multiple canonical categories. Their
// first source is not a reliable image (and may have no category slug at all).
// Use an intentional, shipped asset for each destination instead.
const destinationArtwork: Record<string, string> = {
  "fresh-vegetables": "fresh-produce/fresh-vegetables.avif",
  "fresh-fruits": "fresh-produce/fresh-fruits.avif",
  "dairy-bread-eggs": "canonical/taxonomy/dairy-bread-eggs.png",
  "meat-seafood": "fresh-produce/meat-seafood.avif",
  "atta-flour-dal": "canonical/taxonomy/atta-rice-dal.png",
  masalas: "canonical/taxonomy/masala-oil.png",
  "oils-ghee": "",
  "cereals-breakfast": "canonical/taxonomy/breakfast-instant.png",
  "cold-drinks-juices": "beverages/soft-drinks.avif",
  "ice-creams": "instant-ready-frozen-food/ice-cream-frozen-desserts.avif",
  "chips-namkeens": "snacks-munchies/chips.avif",
  chocolates: "chocolates-sweets/chocolates.avif",
  "biscuits-cakes": "biscuits-bakery/biscuits.avif",
  "tea-coffee-milk-drinks": "tea-coffee-drink-mixes/tea.avif",
  "sauces-spreads": "canonical/taxonomy/sauces-spreads.png",
  "sweet-corner": "chocolates-sweets/indian-sweets.avif",
  "noodles-pasta-vermicelli": "instant-ready-frozen-food/noodles.avif",
  "frozen-food": "instant-ready-frozen-food/frozen-snacks.avif",
  "dry-fruits-seeds-mix": "snacks-munchies/nuts-trail-mixes.avif",
  "paan-corner": "canonical/taxonomy/paan-corner.png",
  "bath-body": "personal-care/bath-body.avif",
  "hair-care": "personal-care/hair-care.avif",
  skincare: "personal-care/skin-care.avif",
  makeup: "beauty-grooming/makeup.avif",
  "feminine-hygiene": "health-hygiene/feminine-care.avif",
  "sexual-wellness": "",
  "health-pharma": "pharmacy/medicines.avif",
  "baby-care": "canonical/taxonomy/baby-care.png",
  "home-kitchen": "kitchen-dining/cookware.avif",
  "pooja-store": "canonical/taxonomy/puja-festive.png",
  "cleaners-repellents": "home-cleaning/surface-cleaning.avif",
  "toys-stationery": "canonical/taxonomy/toys-games-kids.png",
  "electronics-appliances": "canonical/taxonomy/electronics-accessories.png",
  fashion: "",
  "pet-supplies": "canonical/taxonomy/pet-care.png",
  "sports-fitness": "",
};

export function referenceBrowseArtworkKey(node: V1CatalogueBrowseNode): string | null {
  if (node.kind !== "DESTINATION") return null;
  const path = destinationArtwork[node.key];
  return path ? path.startsWith("canonical/") ? path : `local/${path}` : null;
}

export function missingReferenceDestinationArtwork(map: { nodes: V1CatalogueBrowseNode[] }): string[] {
  return map.nodes.filter((node) => node.kind === "DESTINATION" && !(node.key in destinationArtwork)).map((node) => node.key);
}
