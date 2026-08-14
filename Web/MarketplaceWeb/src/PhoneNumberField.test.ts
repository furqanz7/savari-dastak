import { describe, expect, it } from "vitest";
import { canonicalPhoneNumber, splitPhoneNumber } from "./phoneNumber";

describe("Dastak phone numbers", () => {
  it("splits an Indian E.164 number", () => {
    expect(splitPhoneNumber("+919876543210")).toEqual({
      country: "IN",
      nationalNumber: "9876543210",
    });
  });

  it("keeps the country code outside the editable number", () => {
    expect(canonicalPhoneNumber("GB", "07700 900123")).toBe("+447700900123");
  });

  it("caps E.164 numbers at fifteen digits", () => {
    expect(canonicalPhoneNumber("IN", "12345678901234567890")).toBe("+911234567890123");
  });
});
