export type LocationSearchResult = {
  id: string;
  label: string;
  latitude: number;
  longitude: number;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
const endpoint = "https://photon.komoot.io";
const cache = new Map<string, { expires: number; results: LocationSearchResult[] }>();

export async function searchLocations(query: string, fetcher: Fetcher = fetch, signal?: AbortSignal) {
  const normalized = query.trim().replace(/\s+/g, " ");
  if (normalized.length < 3 || normalized.length > 180) return [];
  const key = normalized.toLowerCase();
  const entry = cache.get(key);
  if (fetcher === fetch && entry && entry.expires > Date.now()) return entry.results;
  const url = new URL(`${endpoint}/api/`);
  url.searchParams.set("limit", "5");
  url.searchParams.set("lang", "en");
  url.searchParams.set("countrycode", "IN");
  url.searchParams.set("q", normalized);
  const response = await fetcher(url, { headers: { accept: "application/json" }, signal });
  if (!response.ok) throw new Error("Address suggestions are unavailable. You can still choose a pin on the map.");
  const results = parsePlaces(await response.json());
  if (fetcher === fetch && !signal?.aborted) {
    if (cache.size >= 30) cache.delete(cache.keys().next().value!);
    cache.set(key, { expires: Date.now() + 5 * 60_000, results });
  }
  return results;
}

export async function reverseGeocodeLocation(latitude: number, longitude: number, fetcher: Fetcher = fetch, signal?: AbortSignal) {
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new Error("Location coordinates are invalid.");
  }
  const url = new URL(`${endpoint}/reverse`);
  url.searchParams.set("limit", "1");
  url.searchParams.set("lang", "en");
  url.searchParams.set("lat", String(latitude));
  url.searchParams.set("lon", String(longitude));
  const response = await fetcher(url, { headers: { accept: "application/json" }, signal });
  if (!response.ok) throw new Error("The address for this location is unavailable.");
  const place = parsePlaces(await response.json())[0];
  if (!place) {
    throw new Error("The address for this location is unavailable.");
  }
  return place.label;
}
function parsePlaces(payload: unknown): LocationSearchResult[] {
  const features = record(payload)?.features;
  if (!Array.isArray(features)) throw new Error("Location search returned an invalid response.");
  const seen = new Set<string>();
  return features.flatMap((value): LocationSearchResult[] => {
    const feature = record(value), source = record(feature?.properties), geometry = record(feature?.geometry);
    const coordinates = geometry?.coordinates;
    if (geometry?.type !== "Point" || !Array.isArray(coordinates)) return [];
    const [longitude, latitude] = coordinates;
    if (typeof latitude !== "number" || !Number.isFinite(latitude) || Math.abs(latitude) > 90 || typeof longitude !== "number" || !Number.isFinite(longitude) || Math.abs(longitude) > 180) return [];
    const street = [source?.housenumber, source?.street].filter(v => typeof v === "string" && v.trim()).join(" ");
    const parts = [source?.name, street, source?.district, source?.city, source?.county, source?.state, source?.postcode, source?.country]
      .filter((v): v is string => typeof v === "string" && Boolean(v.trim()));
    const label = [...new Set(parts)].join(", ");
    if (!label || label.length > 500) return [];
    const id = `${source?.osm_type ?? "place"}-${source?.osm_id ?? `${latitude}-${longitude}`}`;
    if (seen.has(id) || seen.has(label.toLowerCase())) return [];
    seen.add(id); seen.add(label.toLowerCase());
    return [{ id, label, latitude, longitude }];
  }).slice(0, 5);
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
