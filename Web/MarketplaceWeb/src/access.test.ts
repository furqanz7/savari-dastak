import { describe, expect, it } from "vitest";
import { isValidProfile, mapDastakRoute, mapDeliverySnapshot, mapSavariAccess } from "./access";

const passenger = {
  name: "Furqan",
  phone: "+919876543210",
  role: "Passenger",
  has_user_profile: true,
  has_driver_profile: false,
};

describe("Savari role isolation", () => {
  it("allows an active passenger profile", () => {
    expect(mapSavariAccess(passenger, "passenger").state).toBe("active");
  });

  it("does not treat a passenger as an approved rider", () => {
    expect(mapSavariAccess(passenger, "rider", false).state).toBe("denied");
  });

  it("requires verified onboarding for riders", () => {
    const driver = { ...passenger, role: "Driver", has_driver_profile: true };
    expect(mapSavariAccess(driver, "rider", false).state).toBe("denied");
    expect(mapSavariAccess(driver, "rider", true).state).toBe("active");
  });
});

describe("Dastak role isolation", () => {
  it("maps server access routes without client-side promotion", () => {
    expect(mapDastakRoute("active").state).toBe("active");
    expect(mapDastakRoute("pending_approval").state).toBe("pending");
    expect(mapDastakRoute("unknown").state).toBe("denied");
  });

  it("requires approved delivery onboarding", () => {
    expect(mapDeliverySnapshot({ onboardingState: "not_applied" }).state).toBe("denied");
    expect(mapDeliverySnapshot({ onboardingState: "pending" }).state).toBe("pending");
    expect(mapDeliverySnapshot({ onboardingState: "approved" }).state).toBe("active");
  });
});

describe("profile validation", () => {
  it("requires a normalized name and E.164 phone", () => {
    expect(isValidProfile({ displayName: "Furqan", phoneNumber: "+919876543210" })).toBe(true);
    expect(isValidProfile({ displayName: "F", phoneNumber: "9876543210" })).toBe(false);
  });
});
