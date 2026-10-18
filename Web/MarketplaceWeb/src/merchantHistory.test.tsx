// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { getV1MerchantFulfilmentHistory } from "./dastakV1";
import { MerchantFulfilmentHistory } from "./MerchantFulfilmentHistory";
const branch = "96000000-0000-4000-8000-000000000001";
const id = (value: number) => `96000000-0000-4000-8000-${String(value + 100).padStart(12, "0")}`;
const auth = { accessToken: "fixture-token", publishableKey: "fixture-public", supabaseUrl: "https://fixture.invalid" };
const cursorTime = "2026-10-01T00:00:00.123456+00:00";
function page(start = 1, count = 1, more = false) {
  return { branchId: branch, fulfilments: Array.from({ length: count }, (_, i) => ({
    id: id(start + i), orderId: id(900), displayOrderNumber: `DSK-${start + i}`, orderStatus: "PREPARING",
    status: "COMPLETED", version: 3, branch: { id: branch, displayName: "Store A" },
    promisedPrepMinutes: 15, secondsRemaining: 0, runningLate: false, lateSeconds: 0,
    packages: [], evidence: [], problemReports: [], lines: [{ orderLineId: id(800), skuId: id(801), packSize: "100 g", name: "Tea", quantity: 1 }],
    riderMatchEligibility: { eligible: false, evaluatedAt: "2026-10-01T00:00:00Z", thresholdSeconds: 300, requiredFulfilmentCount: 1, satisfiedFulfilmentCount: 1 },
    canDeclarePackages: false, canAddEvidence: false, canMarkReady: false, readyIsIrreversible: true,
  })), nextCursor: more ? { id: id(start + count - 1), committedAt: cursorTime } : null };
}
describe("Merchant history transport", () => {
  it("binds branch and preserves the cursor timestamp without an actor override", async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json(page(2)));
    await getV1MerchantFulfilmentHistory({ ...auth, branchId: branch, before: { id: id(1), committedAt: cursorTime } }, fetcher);
    const [, options] = fetcher.mock.calls[0];
    expect(JSON.parse(options.body)).toEqual({ operation: "merchantFulfilmentHistory", branchId: branch, limit: 50,
      beforeAt: cursorTime, beforeId: id(1) });
    expect(options.headers.authorization).toBe("Bearer fixture-token");
  });
  it("accepts COMPLETED even if the parent order has not reached a terminal status", async () => {
    const result = await getV1MerchantFulfilmentHistory({ ...auth, branchId: branch }, vi.fn().mockResolvedValue(Response.json(page())));
    expect(result.fulfilments[0].status).toBe("COMPLETED"); expect(result.nextCursor).toBeUndefined();
  });
  it.each(["branch", "active", "duplicate", "missing", "cursor"])("rejects malformed %s pages", async (patch) => {
    const data: Record<string, unknown> = page();
    if (patch === "branch") data.branchId = id(99);
    if (patch === "active") (data.fulfilments as Array<Record<string, unknown>>)[0].status = "PREPARING";
    if (patch === "duplicate") data.fulfilments = [...page().fulfilments, ...page().fulfilments];
    if (patch === "missing") delete data.nextCursor;
    if (patch === "cursor") data.nextCursor = { id: id(99), committedAt: cursorTime };
    await expect(getV1MerchantFulfilmentHistory({ ...auth, branchId: branch }, vi.fn().mockResolvedValue(Response.json(data)))).rejects.toThrow();
  });
});
let root: Root, host: HTMLDivElement;
const onDetails = vi.fn(), onSessionExpired = vi.fn();
beforeEach(() => {
  (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  onDetails.mockReset(); onSessionExpired.mockReset();
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.unstubAllGlobals(); });
async function show(branchId = branch) {
  await act(async () => root.render(<MerchantFulfilmentHistory key={branchId} auth={auth} branchId={branchId} onDetails={onDetails} onSessionExpired={onSessionExpired} />));
}
async function click(text: string) {
  const button = [...host.querySelectorAll("button")].find((value) => value.textContent === text);
  expect(button).toBeDefined(); await act(async () => button!.click());
}
describe("Merchant history paging UI", () => {
  it("loads older pages, deduplicates and resets on explicit refresh", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(Response.json(page(1, 50, true)))
      .mockResolvedValueOnce(Response.json(page(50, 2))).mockResolvedValueOnce(Response.json(page(70))));
    await show(); expect(host.querySelectorAll("article")).toHaveLength(50);
    await click("Load older orders"); expect(host.querySelectorAll("article")).toHaveLength(51);
    expect(host.textContent).toContain("All currently available");
    await click("Refresh history"); expect(host.querySelectorAll("article")).toHaveLength(1);
    expect(host.textContent).toContain("DSK-70");
  });
  it("opens a branch-scoped full order with no mutation controls", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json(page())));
    await show(); await click("View full order");
    expect(onDetails).toHaveBeenCalledWith({ kind: "FULFILMENT", id: id(1), branchId: branch });
    expect(host.textContent).not.toContain("Mark Ready");
  });
  it("retains read-only rows after a timeout then clears them on revoked permission", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(Response.json(page()))
      .mockRejectedValueOnce(new TypeError("offline")).mockResolvedValueOnce(Response.json({ error: { code: "forbidden", message: "Denied" } }, { status: 403 })));
    await show(); await click("Refresh history");
    expect(host.querySelectorAll("article")).toHaveLength(1); expect(host.querySelector('[role="alert"]')).not.toBeNull();
    expect(host.textContent).not.toContain("No past fulfilments");
    await click("Refresh history"); expect(host.querySelectorAll("article")).toHaveLength(0);
  });
  it("does not publish a previous location's delayed response after switching", async () => {
    let resolve!: (response: Response) => void;
    vi.stubGlobal("fetch", vi.fn().mockImplementationOnce(() => new Promise<Response>((reply) => { resolve = reply; }))
      .mockResolvedValueOnce(Response.json({ branchId: id(90), fulfilments: [], nextCursor: null })));
    await show(); await show(id(90));
    await act(async () => resolve(Response.json(page())));
    expect(host.querySelectorAll("article")).toHaveLength(0); expect(host.textContent).toContain("No past fulfilments");
  });
});
