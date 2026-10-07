import { describe, expect, it } from "vitest";
import { existingCustomerUrl, reimaginedHostedOptIn, reimaginedLocalOptIn } from "./reimaginedOptIn";

describe("Reimagined local-only activation", () => {
  it("allows the approved hosted Customer trial only with explicit opt-in", () => {
    for (const hostname of ["dastak-customer.vercel.app", "dastak-liquiflows-projects.vercel.app"]) {
      expect(reimaginedHostedOptIn({ hostname, search: "?reimagined=1" })).toBe(true);
      expect(reimaginedHostedOptIn({ hostname, search: "" })).toBe(false);
    }
    expect(reimaginedHostedOptIn({ hostname: "dastak-admin.vercel.app", search: "?reimagined=1" })).toBe(false);
    expect(reimaginedHostedOptIn({ hostname: "dastak-customer.vercel.app.attacker.test", search: "?reimagined=1" })).toBe(false);
    expect(reimaginedHostedOptIn()).toBe(false);
  });
  it("requires development mode, loopback and an explicit opt-in", () => {
    for (const hostname of ["localhost", "127.0.0.1", "[::1]"]) {
      expect(reimaginedLocalOptIn(true, { hostname, search: "?reimagined=1" })).toBe(true);
      expect(reimaginedLocalOptIn(false, { hostname, search: "?reimagined=1" })).toBe(false);
    }
    expect(reimaginedLocalOptIn(true, { hostname: "dastak-customer.vercel.app", search: "?reimagined=1" })).toBe(false);
    expect(reimaginedLocalOptIn(true, { hostname: "localhost", search: "" })).toBe(false);
    expect(reimaginedLocalOptIn(true, { hostname: "localhost", search: "?reimagined=0" })).toBe(false);
    expect(reimaginedLocalOptIn(true)).toBe(false);
  });
  it("returns to the existing interface without losing other URL parameters", () => {
    expect(existingCustomerUrl("orders", "http://localhost:5179/?reimagined=1&locale=en#home"))
      .toBe("http://localhost:5179/?locale=en#orders");
  });
});
