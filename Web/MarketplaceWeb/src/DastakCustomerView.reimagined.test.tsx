// @vitest-environment jsdom
import { act, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DastakCustomerView, ExistingDastakCustomerView } from "./DastakCustomerView";
import { DastakV1CustomerExperience } from "./DastakV1CustomerExperience";
import { ReimaginedCustomerRoot } from "./ReimaginedCustomerRoot";
import { CatalogueView } from "./CatalogueView";
vi.mock("./CatalogueView", () => ({ CatalogueView: vi.fn(() => <p>Operational account controller</p>) }));
vi.mock("./DastakV1CustomerExperience", () => ({ DastakV1CustomerExperience: vi.fn(() => <p>Existing catalogue</p>) }));
vi.mock("./ReimaginedCustomerRoot", () => ({ ReimaginedCustomerRoot: vi.fn(() => <p>Authenticated Reimagined root</p>) }));
vi.mock("./orderRealtime", () => ({ useOrderRealtime: () => "subscribed" }));
vi.mock("./useDastakWebPush", () => ({ useDastakWebPush: () => ({ shouldPrompt: false }) }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let root: Root; let host: HTMLDivElement;
const props: ComponentProps<typeof DastakCustomerView> = {
  accountId: "account", accessToken: "session-token", client: {} as ComponentProps<typeof DastakCustomerView>["client"],
  supabaseUrl: "https://example.supabase.co", publishableKey: "publishable", onSignOut: vi.fn(),
  legalLinks: { privacy: "/privacy", terms: "/terms", support: "/support" }, webPushPublicKey: "", deliveryPartnerUrl: "/delivery", merchantUrl: "/merchant",
};
async function mount(url: string) {
  window.history.replaceState(null, "", url);
  vi.stubGlobal("scrollTo", vi.fn());
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  await act(async () => { root.render(<DastakCustomerView {...props} />); });
}
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); vi.clearAllMocks(); vi.unstubAllGlobals(); });
describe("customer entry ownership", () => {
  it("returns embedded Payments to the owning Profile instead of showing legacy Account under Orders", async () => {
    vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const onOpenProfile = vi.fn();
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="payments" onOpenProfile={onOpenProfile} />));
    act(() => vi.mocked(DastakV1CustomerExperience).mock.calls.at(-1)![0].onNavigate("account"));
    expect(onOpenProfile).toHaveBeenCalledOnce(); expect(CatalogueView).not.toHaveBeenCalled();
  });
  it("hands the Profile Payments shortcut to the outer navigation owner", async () => {
    vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const onOpenPayments = vi.fn();
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="account" accountPane="profile" onOpenPayments={onOpenPayments} />));
    act(() => vi.mocked(CatalogueView).mock.calls.at(-1)![0].onNavigate("payments"));
    expect(onOpenPayments).toHaveBeenCalledOnce(); expect(DastakV1CustomerExperience).not.toHaveBeenCalled();
  });
  it.each([true, false])("opens an older record with its own controller (embedded=%s)", async embedded => {
    const id = "11111111-1111-4111-8111-111111111111", onOrderRecordClosed = vi.fn();
    window.history.replaceState(null, "", `/#/orders/${id}`); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded={embedded} initialSection="orders" initialMerchantOrderId={id} onOrderRecordClosed={onOrderRecordClosed} />));
    expect(DastakV1CustomerExperience).not.toHaveBeenCalled();
    const controller = vi.mocked(CatalogueView).mock.calls.at(-1)![0];
    expect(controller.section).toBe("orders"); expect(controller.selectedOrderId).toBe(id);
    act(() => controller.onCloseOrder());
    expect(onOrderRecordClosed).toHaveBeenCalledOnce();
    expect(DastakV1CustomerExperience).toHaveBeenCalledWith(expect.objectContaining({ section: "orders", initialOrderId: undefined }), undefined);
    expect(window.location.hash).toBe(embedded ? `#/orders/${id}` : "#/orders");
  });
  it("hands older account-record selections to the owning navigation", async () => {
    window.history.replaceState(null, "", "/?reimagined=1#/account"); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const onOpenMerchantOrder = vi.fn(), onOpenOrders = vi.fn(), id = "11111111-1111-4111-8111-111111111111";
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="account" onOpenMerchantOrder={onOpenMerchantOrder} onOpenOrders={onOpenOrders} />));
    act(() => vi.mocked(CatalogueView).mock.calls.at(-1)![0].onOpenOrder(id));
    expect(onOpenMerchantOrder).toHaveBeenCalledWith(id); expect(onOpenOrders).not.toHaveBeenCalled();
    expect(window.location.hash).toBe("#/account");
  });
  it("mounts only Reimagined when explicitly opted in locally", async () => {
    await mount("/?reimagined=1");
    expect(host.textContent).toContain("Authenticated Reimagined root");
    expect(DastakV1CustomerExperience).not.toHaveBeenCalled();
    expect(ReimaginedCustomerRoot).toHaveBeenCalledWith(expect.objectContaining({ accountId: "account", accessToken: "session-token" }), undefined);
  });
  it("retains the current customer experience without opt-in", async () => {
    await mount("/#home");
    expect(host.textContent).toContain("Existing catalogue");
    expect(ReimaginedCustomerRoot).not.toHaveBeenCalled();
  });
  it("embeds real Orders without another shopping owner or duplicate navigation", async () => {
    window.history.replaceState(null, "", "/?reimagined=1"); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const orderId = "11111111-1111-4111-8111-111111111111";
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="orders" initialOrderId={orderId} />));
    expect(DastakV1CustomerExperience).toHaveBeenCalledWith(expect.objectContaining({ section: "orders", initialOrderId: orderId, onOrderAgainInExisting: expect.any(Function), presentation: "reimagined" }), undefined);
    expect(host.querySelector('[aria-label="Dastak"]')).toBeNull();
    expect(window.location.hash).toBe("");
  });
  it("routes account shortcuts through global Reimagined Orders while retaining the selected pane", async () => {
    window.history.replaceState(null, "", "/?reimagined=1"); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const onOpenOrders = vi.fn(); const onViewChange = vi.fn();
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="account" accountPane="settings" onOpenOrders={onOpenOrders} onViewChange={onViewChange} />));
    const account = vi.mocked(CatalogueView).mock.calls.at(-1)![0];
    expect(account.accountPane).toBe("settings"); expect(onViewChange).toHaveBeenCalledWith("account");
    act(() => account.onNavigate("orders")); expect(onOpenOrders).toHaveBeenCalledOnce();
    expect(window.location.hash).toBe("");
  });
  it("hands a payment-history selection to the global Orders record without changing URL state", async () => {
    window.history.replaceState(null, "", "/?reimagined=1"); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const onOpenOrders = vi.fn();
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="payments" onOpenOrders={onOpenOrders} />));
    const experience = vi.mocked(DastakV1CustomerExperience).mock.calls.at(-1)![0];
    act(() => experience.onOpenOrder("11111111-1111-4111-8111-111111111111"));
    expect(onOpenOrders).toHaveBeenCalledWith("11111111-1111-4111-8111-111111111111"); expect(window.location.hash).toBe("");
  });
  it("hands embedded Orders selections to the owning Reimagined navigation", async () => {
    window.history.replaceState(null, "", "/?reimagined=1#/orders"); vi.stubGlobal("scrollTo", vi.fn());
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
    const onOpenOrders = vi.fn(), orderId = "11111111-1111-4111-8111-111111111111";
    await act(async () => root.render(<ExistingDastakCustomerView {...props} embedded initialSection="orders" onOpenOrders={onOpenOrders} />));
    act(() => vi.mocked(DastakV1CustomerExperience).mock.calls.at(-1)![0].onOpenOrder(orderId));
    expect(onOpenOrders).toHaveBeenCalledWith(orderId); expect(window.location.hash).toBe("#/orders");
  });
});
