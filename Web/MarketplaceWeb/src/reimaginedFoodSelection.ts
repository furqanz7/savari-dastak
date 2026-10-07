import type { V1RestaurantMenuItem } from "./dastakV1";

export function foodSelection(item: V1RestaurantMenuItem, optionIds: string[]) {
  const unique = new Set(optionIds);
  const options = item.optionGroups.flatMap(group => group.options);
  const known = new Set(options.map(option => option.id));
  const valid = unique.size === optionIds.length && optionIds.every(id => known.has(id)) && item.optionGroups.every(group => {
    const count = group.options.filter(option => unique.has(option.id)).length;
    return count >= group.minimumSelections && count <= group.maximumSelections && (group.selectionType !== "SINGLE" || count <= 1);
  });
  return { valid, pricePaise: item.basePricePaise + options.filter(option => unique.has(option.id)).reduce((sum, option) => sum + option.priceDeltaPaise, 0), options: options.filter(option => unique.has(option.id)) };
}

export function sameFoodOptions(left: string[], right: string[]) {
  return left.length === right.length && [...left].sort().every((id, index) => id === [...right].sort()[index]);
}
