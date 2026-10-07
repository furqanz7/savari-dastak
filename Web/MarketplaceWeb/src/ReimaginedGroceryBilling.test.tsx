// @vitest-environment jsdom
import { act, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ReimaginedGroceryBilling } from "./ReimaginedGroceryBilling";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";
import type { CustomerDeliveryAddress } from "./customerAddresses";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const addresses: CustomerDeliveryAddress[] = ["Home", "Office"].map((label, index) => ({ addressId: `test-${index}`, label, address: "Test Street", building: "1", details: "", displayAddress: `Test ${label} address`, location: { latitude: 12, longitude: 77 }, isDefault: index === 0, updatedAt: "today" }));
let host: HTMLDivElement; let root: Root;
function ConfirmationProbe() { const [count, setCount] = useState(0); return <><button onClick={() => setCount(value => value + 1)}>Test counter state</button><output data-testid="counter">{count}</output></>; }
function Harness({ online = true, canEdit = true, unresolved = false, phone = "+919000000000", saved = addresses, status = "ready", retry = () => undefined }: { online?: boolean; canEdit?: boolean; unresolved?: boolean; phone?: string; saved?: CustomerDeliveryAddress[]; status?: "ready" | "loading" | "unavailable"; retry?: () => void }) {
  const [selectedId, select] = useState(saved[0]?.addressId);
  const [quantity, setQuantity] = useState(1);
  return <div className="reimagined-panel-content"><ReimaginedGroceryBilling items={<button onClick={() => setQuantity(value => value + 1)}>Increase test quantity</button>} retail={{ [fixtureId(6)]: quantity }} subtotal={unresolved ? undefined : quantity * 10000} addresses={{ addresses: saved, selected: saved.find(address => address.addressId === selectedId), status, select, retry, error: undefined }} recipient={{ name: "Test customer", phoneNumber: phone }} online={online} canEdit={canEdit} accountUrl="/#account" counter={<ConfirmationProbe />} /></div>;
}
function mount(props: Parameters<typeof Harness>[0] = {}) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness {...props} />)); }
function click(label: string) { const button = [...host.querySelectorAll<HTMLButtonElement>("button")].find(item => item.textContent?.trim() === label); if (!button) throw new Error(label); act(() => button.click()); }
function billing() { return host.querySelector<HTMLElement>('.reimagined-billing-step-content:nth-of-type(3)')!; }
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Grocery delivery and billing review", () => {
  it("separates steps, focuses delivery, and restores item scroll without losing counter state", () => {
    mount(); const content = host.querySelector<HTMLElement>(".reimagined-panel-content")!;
    expect(billing().hidden).toBe(true); expect(billing().hasAttribute("inert")).toBe(true);
    content.scrollTop = 145; click("Review delivery & billing");
    expect(content.scrollTop).toBe(0); expect(document.activeElement).toBe(host.querySelector(".reimagined-billing-heading"));
    const probe = host.querySelector('[data-testid="counter"]'); click("Test counter state");
    click("1Items"); expect(content.scrollTop).toBe(145); expect(billing().hidden).toBe(true);
    click("2Delivery & billing"); expect(host.querySelector('[data-testid="counter"]')).toBe(probe); expect(probe?.textContent).toBe("1");
  });
  it("selects an exact saved address locally, retaining its default and updated item estimate", () => {
    mount(); click("Increase test quantity"); click("Review delivery & billing");
    expect(host.querySelector('[aria-label="Billing estimate"]')?.textContent).toContain("₹200.00");
    expect(host.querySelector(".reimagined-selected-address")?.textContent).toContain("Test Home address");
    const radio = host.querySelectorAll<HTMLInputElement>('input[type="radio"]')[1];
    act(() => radio.click());
    expect(host.querySelector(".reimagined-selected-address")?.textContent).toContain("Test Office address");
    expect(addresses[0].isDefault).toBe(true);
    expect(host.querySelector('[role="status"]')?.textContent).toContain("pass local checks");
    expect(host.querySelector('[aria-label="Billing estimate"]')?.textContent).toContain("Not confirmed");
  });
  it("does not claim delivery readiness or a complete total for unresolved, offline or read-only data", () => {
    mount({ online: false, canEdit: false, unresolved: true, phone: "" }); click("Review delivery & billing");
    const checks = host.querySelector('[aria-label="Grocery checkout checks"]')!;
    expect(checks.textContent).toContain("Reconnect"); expect(checks.textContent).toContain("cannot edit or submit"); expect(checks.textContent).toContain("Resolve every saved product"); expect(checks.textContent).toContain("name and phone number");
    expect(host.querySelectorAll('input[type="radio"]')).toHaveLength(0);
    expect(host.querySelector('[aria-label="Billing estimate"]')?.textContent).toContain("Unavailable");
  });
  it("keeps unavailable and loading addresses honest, with an explicit retry", () => {
    const retry = vi.fn(); mount({ status: "unavailable", retry }); click("Review delivery & billing"); click("Retry addresses"); expect(retry).toHaveBeenCalledOnce();
    expect(host.querySelector('[aria-label="Grocery checkout checks"]')?.textContent).toContain("Choose a saved delivery address");
    act(() => root.render(<Harness status="loading" />)); expect(host.textContent).toContain("Loading your saved addresses"); expect(host.querySelectorAll('input[type="radio"]')).toHaveLength(0);
  });
  it("rejects invalid saved location data and uses Account for missing addresses", () => {
    mount({ saved: [{ ...addresses[0], location: { latitude: NaN, longitude: 77 } }] }); click("Review delivery & billing");
    expect(host.querySelector('[aria-label="Grocery checkout checks"]')?.textContent).toContain("Choose a valid saved delivery address");
    act(() => root.render(<Harness saved={[]} />));
    expect(host.textContent).toContain("no saved delivery addresses"); expect(host.querySelector('a')?.getAttribute("href")).toBe("/#account");
  });
});
