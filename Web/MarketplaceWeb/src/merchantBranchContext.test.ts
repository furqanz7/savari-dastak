import { describe, expect, it } from "vitest";
import { DastakV1RequestError } from "./dastakV1";
import {
  classifyMerchantBranch,
  classifyMerchantCommerceProbeFailure,
  mergeMerchantBranches,
  merchantCommerceKind,
  persistMerchantBranch,
  readPersistedMerchantBranch,
} from "./merchantBranchContext";

const auth = { supabaseUrl: "https://example.supabase.co", publishableKey: "key", accessToken: "token" };
const branchId = "88888888-8888-4888-8888-888888888888";

describe("merchant branch context", () => {
  it("classifies session, permission, connectivity, not-applicable, and service failures distinctly", () => {
    expect(classifyMerchantCommerceProbeFailure(new DastakV1RequestError("authentication_required", "expired", 401))).toBe("session");
    expect(classifyMerchantCommerceProbeFailure(new DastakV1RequestError("access_denied", "denied", 403))).toBe("access");
    expect(classifyMerchantCommerceProbeFailure(new DastakV1RequestError("request_timeout", "late", 0))).toBe("connectivity");
    expect(classifyMerchantCommerceProbeFailure(new DastakV1RequestError("not_found", "not restaurant", 404))).toBe("not_applicable");
    expect(classifyMerchantCommerceProbeFailure(new DastakV1RequestError("internal", "failed", 500))).toBe("service");
  });

  it("never guesses a Store experience for unknown merchant metadata", () => {
    expect(merchantCommerceKind({ id: branchId, branchName: "Main", organizationName: "Dastak", merchantType: "RETAIL" })).toBe("retail");
    expect(merchantCommerceKind({ id: branchId, branchName: "Main", organizationName: "Dastak", merchantType: "RESTAURANT_CAFE" })).toBe("restaurant");
    expect(merchantCommerceKind({ id: branchId, branchName: "Main", organizationName: "Dastak", merchantType: "UNKNOWN" })).toBeUndefined();
  });

  it("falls back to retail only after an authoritative not-applicable restaurant response", async () => {
    const bodies: Record<string, unknown>[] = [];
    const branch = await classifyMerchantBranch(auth, { id: branchId, displayName: "Main" }, async (_url, init) => {
      const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
      bodies.push(body);
      if (body.operation === "merchantRestaurantMenu") {
        return Response.json({ error: { code: "not_found", message: "not a restaurant" } }, { status: 404 });
      }
      return Response.json(retailFixture());
    });
    expect(branch).toMatchObject({ id: branchId, branchName: "Main", merchantType: "RETAIL" });
    expect(bodies).toEqual([
      { operation: "merchantRestaurantMenu", branchId },
      { operation: "merchantSnapshot", branchId, limit: 1 },
    ]);
  });

  it("does not misclassify permission failures as retail", async () => {
    let requests = 0;
    await expect(classifyMerchantBranch(auth, { id: branchId, displayName: "Main" }, async () => {
      requests += 1;
      return Response.json({ error: { code: "access_denied", message: "denied" } }, { status: 403 });
    })).rejects.toMatchObject({ code: "access_denied", status: 403 });
    expect(requests).toBe(1);
  });

  it("merges verified branches and persists selection per account", () => {
    const merged = mergeMerchantBranches(
      [{ id: "b", branchName: "South", organizationName: "Zed", merchantType: "RETAIL" }],
      [{ id: "a", branchName: "North", organizationName: "Acme", merchantType: "RESTAURANT_CAFE" }, { id: "b", branchName: "South updated", organizationName: "Zed", merchantType: "RETAIL" }],
    );
    expect(merged.map((item) => item.id)).toEqual(["a", "b"]);
    expect(merged[1].branchName).toBe("South updated");
    const values = new Map<string, string>();
    const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => values.set(key, value) };
    persistMerchantBranch("account-a", "branch-a", storage);
    persistMerchantBranch("account-b", "branch-b", storage);
    expect(readPersistedMerchantBranch("account-a", storage)).toBe("branch-a");
    expect(readPersistedMerchantBranch("account-b", storage)).toBe("branch-b");
  });
});

function retailFixture() {
  return {
    branch: {
      branchId, branchName: "Main", branchStatus: "ACTIVE", branchVersion: 1,
      organizationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", organizationName: "Dastak", merchantType: "RETAIL",
      operationalState: { isOpen: true, acceptingOrders: true, version: 1, updatedAt: null },
      capacity: { limit: 10, held: 0, available: 10 },
    },
    categoryTypes: [], categories: [], subcategories: [], skus: [], truncated: false,
  };
}
