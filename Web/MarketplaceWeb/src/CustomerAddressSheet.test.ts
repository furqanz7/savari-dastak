import { describe, expect, it } from "vitest";
import { combineDoorstepDetails, splitDoorstepDetails } from "./customerAddressDetails";

describe("customer address details", () => {
  it("round-trips structured doorstep details through the existing API field", () => {
    const details = combineDoorstepDetails("  Flat 4B  ", " Opposite the post office ");
    expect(details).toBe("Flat 4B • Opposite the post office");
    expect(splitDoorstepDetails(details)).toEqual({
      building: "Flat 4B",
      landmark: "Opposite the post office",
    });
  });

  it("keeps legacy single-field addresses editable", () => {
    expect(splitDoorstepDetails("128 Mandi Street")).toEqual({
      building: "128 Mandi Street",
      landmark: "",
    });
  });
});
