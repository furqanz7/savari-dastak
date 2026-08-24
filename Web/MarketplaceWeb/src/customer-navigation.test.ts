import { describe, expect, it } from "vitest";
import { parseCustomerDestination, serializeCustomerDestination } from "./customerNavigation";

describe("customer navigation", () => {
  it("restores approved customer sections and exact entity details", () => {
    const order = { section: "orders", entityType: "merchantOrder", entityId: "77777777-7777-4777-8777-777777777777" } as const;
    expect(parseCustomerDestination(serializeCustomerDestination(order))).toEqual(order);
    const v1Order = { section: "orders", entityType: "dastakV1Order", entityId: "88888888-8888-4888-8888-888888888888" } as const;
    expect(parseCustomerDestination(serializeCustomerDestination(v1Order))).toEqual(v1Order);
    expect(parseCustomerDestination('{"section":"admin"}')).toEqual({ section: "home" });
  });
});
