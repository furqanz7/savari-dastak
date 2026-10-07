import { browseChildren, validateBrowseMap } from "./catalogueBrowse";
import type { V1CatalogueBrowseMap } from "./dastakV1";

export type ReimaginedDirectory = Array<{ key: string; label: string; destinations: Array<{ key: string; label: string }> }>;

// Preserve backend presentation identity, including cross-department sources.
export function reimaginedDirectory(map: V1CatalogueBrowseMap | null | undefined): ReimaginedDirectory {
  if (!map || validateBrowseMap(map).length) return [];
  return browseChildren(map, null).map(section => ({
    key: section.key, label: section.label,
    destinations: browseChildren(map, section.key).filter(node => node.kind === "DESTINATION").map(node => ({ key: node.key, label: node.label })),
  }));
}
