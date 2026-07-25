import { describe, expect, it } from "vitest";
import { searchLocations } from "./location-search";

describe("location search", () => {
  it("normalizes a valid geocoding response", async () => {
    const fetcher = () => Promise.resolve(new Response(JSON.stringify([{
      place_id: 12,
      display_name: "Vaniyambadi, Tamil Nadu, India",
      lat: "12.6819",
      lon: "78.6201",
    }]), { status: 200 }));
    await expect(searchLocations("  Vaniyambadi  ", fetcher)).resolves.toEqual([{
      id: "12",
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
});
