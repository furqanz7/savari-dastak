import { describe, expect, it } from "vitest";
import {
  formatDistance,
  formatDuration,
  parseDestinationResults,
  parseRideQuote,
  parseRideSnapshot,
} from "./rides";

describe("Savari passenger ride data", () => {
  it("parses destination results without trusting malformed coordinates", () => {
    expect(parseDestinationResults({ results: [destination] })).toEqual([destination]);
    expect(() => parseDestinationResults({ results: [{ ...destination, latitude: 100 }] })).toThrow("invalid ride response");
  });

  it("parses server fares and rejects negative values", () => {
    const quote = parseRideQuote(quotePayload);
    expect(quote.fares.auto.paise).toBe(8_000);
    expect(() => parseRideQuote({
      ...quotePayload,
      fares: { ...quotePayload.fares, bike: { paise: -1 } },
    })).toThrow("invalid ride response");
  });

  it("parses passenger-safe ride snapshots", () => {
    expect(parseRideSnapshot({ ride: ridePayload })?.status).toBe("assigned");
    expect(parseRideSnapshot({ ride: null })).toBeNull();
    expect(() => parseRideSnapshot({ ride: { ...ridePayload, passengerId: "leaked" } })).toThrow("invalid ride response");
  });

  it("formats route distance and duration", () => {
    expect(formatDistance(5_000)).toBe("5 km");
    expect(formatDistance(2_450)).toBe("2.5 km");
    expect(formatDuration(900)).toBe("15 min");
  });
});

const destination = {
  label: "Vaniyambadi Railway Station",
  address: "Railway Station Road, Vaniyambadi",
  latitude: 12.676,
  longitude: 78.616,
};
const quotePayload = {
  quoteToken: "signed-quote",
  expiresAt: "2033-05-18T03:38:20.000Z",
  pickup: { label: "Current location", latitude: 12.6819, longitude: 78.6201 },
  destination,
  distanceMeters: 5_000,
  durationSeconds: 900,
  fares: { auto: { paise: 8_000 }, bike: { paise: 5_000 } },
};
const ridePayload = {
  rideId: "33333333-3333-4333-8333-333333333333",
  status: "assigned",
  vehicleType: "Auto",
  pickup: quotePayload.pickup,
  destination,
  distanceMeters: 5_000,
  durationSeconds: 900,
  fare: { paise: 8_000 },
  boardingCode: "1234",
  driver: { displayName: "Driver", phoneNumber: "+919876543210" },
  createdAt: "2033-05-18T03:33:20.000Z",
};
