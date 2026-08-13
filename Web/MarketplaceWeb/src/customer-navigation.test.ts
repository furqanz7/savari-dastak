import { describe, expect, it } from "vitest";
import { parseCustomerDestination, serializeCustomerDestination } from "./customerNavigation";

describe("customer navigation", () => {
  it("restores approved customer sections and exact entity details", () => {
    const order = { section: "orders", entityType: "merchantOrder", entityId: "77777777-7777-4777-8777-777777777777" } as const;
    expect(parseCustomerDestination(serializeCustomerDestination(order))).toEqual(order);
    expect(parseCustomerDestination('{"section":"admin"}')).toEqual({ section: "home" });
  });
});
