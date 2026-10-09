import { describe, expect, it, vi } from "vitest";
import { reverseGeocodeLocation, searchLocations } from "./location-search";

describe("location search", () => {
  it("normalizes a valid geocoding response", async () => {
    const fetcher = () => Promise.resolve(new Response(JSON.stringify({ features: [{
      properties: { osm_id: 12, osm_type: "N", name: "Vaniyambadi", state: "Tamil Nadu", country: "India" },
      geometry: { type: "Point", coordinates: [78.6201, 12.6819] },
    }] }), { status: 200 }));
    await expect(searchLocations("  Vaniyambadi  ", fetcher)).resolves.toEqual([{
      id: "N-12",
      label: "Vaniyambadi, Tamil Nadu, India",
      latitude: 12.6819,
      longitude: 78.6201,
    }]);
  });

  it("does not send incomplete searches", async () => {
    let called = false;
    expect(await searchLocations("ab", () => { called = true; return Promise.reject(); })).toEqual([]);
    expect(called).toBe(false);
  });
  it("uses an autocomplete-capable provider, English, India and cancellation", async () => {
    const fetcher = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      expect(input).toBeInstanceOf(URL); expect(init?.signal).toBeDefined();
      return new Response(JSON.stringify({ features: [] }));
    });
    const controller = new AbortController();
    await searchLocations("Mysore", fetcher, controller.signal);
    const url = fetcher.mock.calls[0]?.[0] as unknown as URL;
    expect(url.origin).toBe("https://photon.komoot.io");
    expect(url.searchParams.get("countrycode")).toBe("IN");
    expect(url.searchParams.get("lang")).toBe("en");
    expect(fetcher).toHaveBeenCalledWith(expect.any(URL), expect.objectContaining({ signal: controller.signal }));
  });
  it("drops invalid coordinates and duplicate labels", async () => {
    const valid = { properties: { name: "Mysore", osm_id: 1 }, geometry: { type: "Point", coordinates: [76.65, 12.3] } };
    const fetcher = async () => new Response(JSON.stringify({ features: [valid, { ...valid, properties: { name: "Mysore", osm_id: 2 } }, { ...valid, geometry: { type: "Point", coordinates: [76, 95] } }] }));
    expect(await searchLocations("Mysore", fetcher)).toHaveLength(1);
  });
  it("rejects malformed responses and invalid reverse coordinates", async () => {
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ bad: [] })));
    await expect(searchLocations("Mysore", fetcher)).rejects.toThrow("invalid response");
    fetcher.mockClear();
    await expect(reverseGeocodeLocation(NaN, 76, fetcher)).rejects.toThrow("invalid");
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("turns current coordinates into a human address", async () => {
    const fetcher = () => Promise.resolve(new Response(JSON.stringify({ features: [{
      properties: { name: "CL Road", city: "Vaniyambadi", state: "Tamil Nadu", country: "India" },
      geometry: { type: "Point", coordinates: [78.6201, 12.6819] },
    }] }), { status: 200 }));
    await expect(reverseGeocodeLocation(12.6819, 78.6201, fetcher)).resolves.toBe(
      "CL Road, Vaniyambadi, Tamil Nadu, India",
    );
  });
});
