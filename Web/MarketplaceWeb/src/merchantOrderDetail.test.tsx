// @vitest-environment jsdom
import { act, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { parseMerchantOrderDetail, type MerchantDetailTarget } from "./merchantOrderDetail";
import { getV1MerchantOrderDetail } from "./dastakV1";
import { MerchantOrderDetailDialog } from "./MerchantOrderDetailDialog";

const id = "97000000-0000-4000-8000-000000000001", branch = "97000000-0000-4000-8000-000000000002";
const orderId = "97000000-0000-4000-8000-000000000003";
const target: MerchantDetailTarget = { kind: "FULFILMENT", id, branchId: branch };
const auth = { accessToken: "fixture-token", publishableKey: "fixture-public", supabaseUrl: "https://fixture.invalid" };
function fixture() {
  return { target, branch: { id: branch, displayName: "Store A" }, order: { id: orderId, displayOrderNumber: "DSK-OLD-001", status: "DELIVERED", orderType: "RETAIL_ONLY", createdAt: "2026-10-18T00:00:00Z" },
    records: [{ id, kind: "FULFILMENT", status: "COMPLETED", version: 3, productSubtotalPaise: 1000,
      lines: [{ orderLineId: id, name: "Tea", quantity: 2, selection: { options: [{ groupName: "Sugar", name: "Less sugar" }] } }], evidence: [], problems: [], recovery: [], delivery: {} }], recoveryOffers: [], returns: [], settlements: [] };
}
describe("Merchant detail display contract", () => {
  it("preserves exact items/options/product values without keeping private extras", () => {
    const detail = parseMerchantOrderDetail({ ...fixture(), customerAddress: "PRIVATE_SECRET", pickupCode: "PRIVATE_SECRET" }, target);
    expect(detail.records[0].lines[0].options).toEqual(["Sugar: Less sugar"]);
    expect(detail.records[0].productValue).toBe(1000);
    expect(JSON.stringify(detail)).not.toContain("PRIVATE_SECRET");
  });
  it("rejects wrong branch, target, missing record and invalid money", () => {
    expect(() => parseMerchantOrderDetail({ ...fixture(), branch: { id, displayName: "Foreign" } }, target)).toThrow();
    expect(() => parseMerchantOrderDetail({ ...fixture(), target: { ...target, id: branch } }, target)).toThrow();
    expect(() => parseMerchantOrderDetail({ ...fixture(), records: [] }, target)).toThrow();
    const bad = fixture(); bad.records[0].productSubtotalPaise = -1;
    expect(() => parseMerchantOrderDetail(bad, target)).toThrow();
  });
  it("uses a dedicated authenticated Merchant read without actor overrides", async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify(fixture())));
    await getV1MerchantOrderDetail({ ...auth, branchId: branch, targetKind: target.kind, targetId: id }, fetcher);
    const call = fetcher.mock.calls[0]; const body = JSON.parse(call[1].body);
    expect(call[0]).toContain("dastak-v1-orders");
    expect(body).toEqual({ operation: "merchantOrderDetail", branchId: branch, targetKind: "FULFILMENT", targetId: id });
    expect(call[1].headers.authorization).toBe("Bearer fixture-token");
  });
  it("accepts omitted or blank optional pack/variant snapshots", () => {
    const data = fixture();
    Object.assign(data.records[0].lines[0], { variant: "", packSize: "  " });
    expect(parseMerchantOrderDetail(data, target).records[0].lines[0].variant).toBeUndefined();
  });
  it("requires the exact return stop or recovery offer and their location", () => {
    const data = { ...fixture(), target: { ...target, kind: "RETURN" as const }, returns: [{ returnStopId: id, orderId, branch: { id: branch }, status: "COMPLETED", packageCount: 1 }] };
    expect(parseMerchantOrderDetail(data, data.target).returns).toHaveLength(1);
    expect(() => parseMerchantOrderDetail({ ...data, returns: [{ ...data.returns[0], branch: { id: orderId } }] }, data.target)).toThrow();
    const recovery = { ...fixture(), target: { ...target, kind: "RECOVERY" as const }, recoveryOffers: [{ id, orderId, branch: { id: branch }, requestedQuantity: 1, status: "ACCEPTED", startedAt: "2026-10-18T00:00:00Z", sku: { name: "Tea", packSize: "200 g" } }] };
    expect(parseMerchantOrderDetail(recovery, recovery.target).recoveryOffers).toHaveLength(1);
    expect(() => parseMerchantOrderDetail({ ...recovery, recoveryOffers: [{ ...recovery.recoveryOffers[0], orderId: branch }] }, recovery.target)).toThrow();
  });
});

let root: Root, host: HTMLDivElement;
beforeEach(() => {
  (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  Object.defineProperty(HTMLDialogElement.prototype, "showModal", { configurable: true, writable: true, value: vi.fn(function(this: HTMLDialogElement) { this.open = true; }) });
  Object.defineProperty(HTMLDialogElement.prototype, "close", { configurable: true, writable: true, value: vi.fn(function(this: HTMLDialogElement) { this.open = false; }) });
});
afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
async function show() { await act(async () => root.render(<MerchantOrderDetailDialog auth={auth} target={target} onClose={() => undefined} />)); }
describe("Merchant detail dialog", () => {
  it("loads read-only details and restores document scrolling on close", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify(fixture()))));
    function Harness() { const [open, setOpen] = useState(true); return open ? <MerchantOrderDetailDialog auth={auth} target={target} onClose={() => setOpen(false)} /> : null; }
    await act(async () => root.render(<Harness />));
    expect(host.textContent).toContain("DSK-OLD-001"); expect(host.textContent).toContain("Less sugar");
    expect(document.body.style.overflow).toBe("hidden");
    expect(host.querySelector("button[aria-label='Close full order']")).not.toBeNull();
    await act(async () => host.querySelector<HTMLButtonElement>("button[aria-label='Close full order']")!.click());
    expect(host.querySelector("dialog")).toBeNull(); expect(document.body.style.overflow).not.toBe("hidden");
  });
  it("retains safe stale details on network failure but clears them on denial", async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify(fixture())))
      .mockRejectedValueOnce(new TypeError("offline"))
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: { code: "access_denied", message: "Denied" } }), { status: 403 }));
    vi.stubGlobal("fetch", fetcher); await show();
    const refresh = () => host.querySelector<HTMLButtonElement>(".merchant-detail-refresh")!;
    await act(async () => refresh().click());
    expect(host.textContent).toContain("DSK-OLD-001"); expect(host.querySelector("[role='alert']")).not.toBeNull();
    await act(async () => refresh().click());
    expect(host.textContent).not.toContain("DSK-OLD-001"); expect(host.textContent).toContain("Order details unavailable");
  });
  it("does not publish an old response after a different target is opened", async () => {
    let release!: (value: Response) => void;
    vi.stubGlobal("fetch", vi.fn().mockImplementationOnce(() => new Promise<Response>((resolve) => { release = resolve; }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: { code: "not_found", message: "Missing" } }), { status: 404 })));
    await show();
    await act(async () => root.render(<MerchantOrderDetailDialog key="other" auth={auth} target={{ ...target, id: orderId }} onClose={() => undefined} />));
    await act(async () => release(new Response(JSON.stringify(fixture()))));
    expect(host.textContent).not.toContain("DSK-OLD-001");
  });
});
