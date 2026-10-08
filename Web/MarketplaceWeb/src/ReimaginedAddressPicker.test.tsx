// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { ReimaginedAddressPicker } from "./ReimaginedAddressPicker";
import { setDefaultCustomerAddress } from "./customerAddresses";
vi.mock("./customerAddresses", () => ({ setDefaultCustomerAddress: vi.fn(), saveCustomerAddress: vi.fn(), deleteCustomerAddress: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let host: HTMLDivElement; let root: Root;
const home = { addressId: "home", label: "Home", address: "Test street", building: "1", details: "", displayAddress: "Test street", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" };
const resource = { addresses: [home], selected: home, error: undefined, status: "ready" as const, select: vi.fn(), retry: vi.fn() };
const auth = { accessToken: "test", supabaseUrl: "https://test.supabase.co", publishableKey: "public" };
beforeEach(() => { vi.clearAllMocks(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); });
function button(text: string) { return [...host.querySelectorAll("button")].find(value => value.textContent?.includes(text))!; }
it("opens native address management and reuses an ambiguous request key", async () => {
  act(() => root.render(<ReimaginedAddressPicker resource={resource} auth={auth} online accountUrl="/#account" />));
  expect(setDefaultCustomerAddress).not.toHaveBeenCalled(); act(() => button("Add or manage delivery addresses").click());
  expect(host.querySelector('[role="dialog"]')).toBeNull();
  expect(document.querySelector('.reimagined-address-modal [role="dialog"]')?.textContent).toContain("Saved addresses");
  vi.mocked(setDefaultCustomerAddress).mockRejectedValueOnce(new Error("Lost response")).mockResolvedValueOnce({ addresses: [home] });
  await act(async () => document.querySelector<HTMLButtonElement>('.customer-address-book-select')!.click());
  expect(resource.retry).not.toHaveBeenCalled(); expect(document.querySelector('.reimagined-address-modal')?.textContent).toContain("Lost response");
  await act(async () => document.querySelector<HTMLButtonElement>('.customer-address-book-select')!.click());
  expect(resource.retry).toHaveBeenCalledOnce();
  const calls = vi.mocked(setDefaultCustomerAddress).mock.calls;
  expect(calls[0][0].idempotencyKey).toBe(calls[1][0].idempotencyKey);
});
it("closes the portalled book and returns focus without changing addresses", () => {
  act(() => root.render(<ReimaginedAddressPicker resource={resource} auth={auth} online accountUrl="/#account" />));
  const opener = button("Add or manage delivery addresses"); opener.focus();
  act(() => opener.click());
  expect(document.activeElement?.getAttribute("aria-label")).toBe("Close saved addresses");
  expect(host.inert).toBe(true);
  act(() => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(document.querySelector('.reimagined-address-modal')).toBeNull();
  expect(document.activeElement).toBe(opener);
  expect(Boolean(host.inert)).toBe(false);
  expect(setDefaultCustomerAddress).not.toHaveBeenCalled();
});
it("keeps the editor outside the panel with modal keyboard focus", () => {
  act(() => root.render(<ReimaginedAddressPicker resource={{ ...resource, addresses: [], selected: undefined }} auth={auth} online accountUrl="/#account" />));
  const opener = button("Add or manage delivery addresses"); opener.focus();
  act(() => opener.click());
  expect(host.querySelector('[role="dialog"]')).toBeNull();
  expect(document.activeElement?.getAttribute("aria-label")).toBe("Close address editor");
  expect(host.inert).toBe(true);
  act(() => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
  expect(document.querySelector('.reimagined-address-modal')).toBeNull();
  expect(document.activeElement).toBe(opener);
});
it("blocks address writes while offline", () => {
  act(() => root.render(<ReimaginedAddressPicker resource={resource} auth={auth} online={false} accountUrl="/#account" />));
  expect(button("Add or manage delivery addresses").disabled).toBe(true); expect(setDefaultCustomerAddress).not.toHaveBeenCalled();
});
