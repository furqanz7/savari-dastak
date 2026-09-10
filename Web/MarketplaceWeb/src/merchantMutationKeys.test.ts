import { describe, expect, it } from "vitest";
import { MerchantMutationKeys } from "./merchantMutationKeys";

describe("merchant menu mutation identities", () => {
  it("retains one key for retries of the same logical payload until cleared", () => {
    const keys = new MerchantMutationKeys();
    const first = keys.keyFor("item:1", { name: "Tea", price: 20 });
    expect(keys.keyFor("item:1", { name: "Tea", price: 20 })).toBe(first);
    expect(keys.keyFor("item:1", { name: "Tea", price: 25 })).not.toBe(first);
    const current = keys.keyFor("item:1", { name: "Tea", price: 25 });
    keys.clear("item:1");
    expect(keys.keyFor("item:1", { name: "Tea", price: 25 })).not.toBe(current);
  });
});
