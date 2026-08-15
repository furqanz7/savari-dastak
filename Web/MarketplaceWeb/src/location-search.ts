export type LocationSearchResult = {
  id: string;
  label: string;
  latitude: number;
  longitude: number;
};

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export async function searchLocations(query: string, fetcher: Fetcher = fetch) {
  const normalized = query.trim().replace(/\s+/g, " ");
  if (normalized.length < 3 || normalized.length > 180) return [];
  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "5");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("q", normalized);
  const response = await fetcher(url, { headers: { accept: "application/json" } });
  if (!response.ok) throw new Error("Location search is unavailable right now.");
  const payload = await response.json();
  if (!Array.isArray(payload)) throw new Error("Location search returned an invalid response.");
  return payload.flatMap((value): LocationSearchResult[] => {
    const source = record(value);
    const latitude = Number(source?.lat);
    const longitude = Number(source?.lon);
    const label = source?.display_name;
    const id = source?.place_id;
    return typeof label === "string" && label.length > 0 && label.length <= 500 &&
      (typeof id === "number" || typeof id === "string") &&
      Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
      Number.isFinite(longitude) && longitude >= -180 && longitude <= 180
      ? [{ id: String(id), label, latitude, longitude }]
      : [];
  });
}

export async function reverseGeocodeLocation(latitude: number, longitude: number, fetcher: Fetcher = fetch) {
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
    !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new Error("Location coordinates are invalid.");
  }
  const url = new URL("https://nominatim.openstreetmap.org/reverse");
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("zoom", "18");
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("lat", String(latitude));
  url.searchParams.set("lon", String(longitude));
  const response = await fetcher(url, { headers: { accept: "application/json" } });
  if (!response.ok) throw new Error("The address for this location is unavailable.");
  const source = record(await response.json());
  const label = source?.display_name;
  if (typeof label !== "string" || label.length === 0 || label.length > 500) {
    throw new Error("The address for this location is unavailable.");
  }
  return label;
}

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}
