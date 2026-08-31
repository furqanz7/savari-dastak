import { describe, expect, it } from "vitest";
import {
  isValidProfile,
  mapDastakRoute,
  mapDeliverySnapshot,
  mapSavariAccess,
  mustSignOutDeniedAdmin,
  ProfileSubmissionAttempt,
} from "./access";

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

  it("removes denied Admin sessions while preserving an assigned profile setup", () => {
    expect(mustSignOutDeniedAdmin({ state: "denied" }, "admin")).toBe(true);
    expect(mustSignOutDeniedAdmin({ state: "pending" }, "admin")).toBe(true);
    expect(mustSignOutDeniedAdmin({ state: "needs_profile" }, "admin")).toBe(false);
    expect(mustSignOutDeniedAdmin({ state: "active" }, "admin")).toBe(false);
    expect(mustSignOutDeniedAdmin({ state: "denied" }, "merchant")).toBe(false);
  });

  it("recognizes a revoked server session", async () => {
    const access = await import("./access");
    const isAuthenticationRequiredResponse = (
      access as typeof access & {
        isAuthenticationRequiredResponse?: (status: number) => boolean;
      }
    ).isAuthenticationRequiredResponse;

    expect(isAuthenticationRequiredResponse?.(401)).toBe(true);
    expect(isAuthenticationRequiredResponse?.(500)).toBe(false);
  });
});

describe("profile validation", () => {
  it("requires a normalized name and E.164 phone", () => {
    expect(isValidProfile({ displayName: "Furqan", phoneNumber: "+919876543210" })).toBe(true);
    expect(isValidProfile({ displayName: "F", phoneNumber: "+919876543210" })).toBe(true);
    expect(isValidProfile({ displayName: "F", phoneNumber: "9876543210" })).toBe(false);
    expect(isValidProfile({ displayName: "F", phoneNumber: "+910000000000" })).toBe(false);
    expect(isValidProfile({ displayName: "F".repeat(81), phoneNumber: "+919876543210" })).toBe(false);
  });

  it("reuses one idempotency key for retries of the same normalized profile", () => {
    const attempt = new ProfileSubmissionAttempt();
    const first = attempt.keyFor({ displayName: " Furqan  Ahmed ", phoneNumber: "+919876543210" });
    expect(attempt.keyFor({ displayName: "Furqan Ahmed", phoneNumber: "+919876543210" })).toBe(first);
    expect(attempt.keyFor({ displayName: "Furqan Ahmed", phoneNumber: "+919876543211" })).not.toBe(first);
  });
});
