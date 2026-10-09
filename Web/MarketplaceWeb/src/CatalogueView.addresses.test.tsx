// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { CatalogueView } from "./CatalogueView";
import { snapshotAccountProfile, snapshotCustomerIdentities } from "./accountProfile";
import { CustomerAddressRequestError, deleteCustomerAddress, getCustomerAddresses, saveCustomerAddress, setDefaultCustomerAddress } from "./customerAddresses";
vi.mock("./accountProfile", async original => ({ ...await original<typeof import("./accountProfile")>(), snapshotAccountProfile: vi.fn(), snapshotCustomerIdentities: vi.fn() }));
vi.mock("./customerAddresses", async original => ({ ...await original<typeof import("./customerAddresses")>(), getCustomerAddresses: vi.fn(), saveCustomerAddress: vi.fn(), setDefaultCustomerAddress: vi.fn(), deleteCustomerAddress: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const home = { addressId: "home", label: "Home", address: "Synthetic area", building: "1", details: "", displayAddress: "Synthetic area", location: { latitude: 0, longitude: 0 }, isDefault: true, updatedAt: "today" };
const work = { ...home, addressId: "work", label: "Work", isDefault: false };
const snapshot = { addresses: [home, work] };
let host: HTMLDivElement, root: Root;
const changed = vi.fn(), signOut = vi.fn(), noop = () => {};
function render(token = "synthetic") {
  root.render(<CatalogueView accountId="synthetic" accessToken={token} client={{} as SupabaseClient} supabaseUrl="https://example.invalid" publishableKey="synthetic" orderRefreshToken={0} section="account" accountPane="profile" overlayPresentation="reimagined" onNavigate={noop} onOpenOrder={noop} onCloseOrder={noop} onOpenParcel={noop} onSignOut={signOut} onAddressesChanged={changed} deliveryPartnerUrl="#delivery" merchantUrl="#merchant" />);
}
beforeEach(async () => {
  vi.clearAllMocks(); vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("Synthetic unavailable resource")));
  vi.mocked(snapshotAccountProfile).mockResolvedValue({ displayName: "Synthetic", phoneNumber: "+919876543210" });
  vi.mocked(snapshotCustomerIdentities).mockResolvedValue([]); vi.mocked(getCustomerAddresses).mockResolvedValue(snapshot);
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  await act(async () => render());
  act(() => host.querySelector<HTMLButtonElement>('.customer-saved-place')!.click());
});
afterEach(() => { act(() => root.unmount()); host.remove(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
function edit() { act(() => document.querySelector<HTMLButtonElement>('[aria-label="Edit Work"]')!.click()); }
function submit() { document.querySelector('form.customer-address-sheet')!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })); }
it("refreshes shopping after editing a saved address, preserving its non-default status", async () => {
  edit(); vi.mocked(saveCustomerAddress).mockResolvedValueOnce(snapshot);
  await act(async () => submit());
  expect(saveCustomerAddress).toHaveBeenCalledWith(expect.objectContaining({ addressId: "work", makeDefault: false }));
  expect(changed).toHaveBeenCalledOnce();
});
it("refreshes shopping after changing the saved default", async () => {
  vi.mocked(setDefaultCustomerAddress).mockResolvedValueOnce({ addresses: [{ ...home, isDefault: false }, { ...work, isDefault: true }] });
  await act(async () => [...document.querySelectorAll<HTMLButtonElement>('.customer-address-book-select')].find(button => button.textContent?.includes("Work"))!.click());
  expect(changed).toHaveBeenCalledOnce();
});
it("refreshes shopping after confirmed deletion, not merely opening confirmation", async () => {
  act(() => document.querySelector<HTMLButtonElement>('[aria-label="Delete Work"]')!.click());
  expect(changed).not.toHaveBeenCalled(); vi.mocked(deleteCustomerAddress).mockResolvedValueOnce({ addresses: [home] });
  await act(async () => [...document.querySelectorAll<HTMLButtonElement>('[role="alertdialog"] button')].find(button => button.textContent === "Delete")!.click());
  expect(changed).toHaveBeenCalledOnce();
});
it("deduplicates submit events and keeps retry keys only for the same draft", async () => {
  edit(); let reject!: (error: Error) => void;
  vi.mocked(saveCustomerAddress).mockReturnValueOnce(new Promise((_, fail) => { reject = fail; })).mockRejectedValue(new Error("Synthetic retry"));
  act(() => { submit(); submit(); }); expect(saveCustomerAddress).toHaveBeenCalledOnce();
  await act(async () => reject(new Error("Synthetic lost response")));
  await act(async () => submit());
  const input = document.querySelector<HTMLInputElement>('[autocomplete="street-address"]')!;
  act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, "2"); input.dispatchEvent(new Event("input", { bubbles: true })); });
  await act(async () => submit());
  const calls = vi.mocked(saveCustomerAddress).mock.calls;
  expect(calls[1][0].idempotencyKey).toBe(calls[0][0].idempotencyKey);
  expect(calls[2][0].idempotencyKey).not.toBe(calls[0][0].idempotencyKey);
  expect(changed).not.toHaveBeenCalled();
});
it.each(["rotate token", "unmount"])("ignores an old unauthorized save after %s", async action => {
  edit(); let reject!: (error: Error) => void;
  vi.mocked(saveCustomerAddress).mockReturnValueOnce(new Promise((_, fail) => { reject = fail; }));
  act(() => submit()); await act(async () => action === "unmount" ? root.render(null) : render("rotated"));
  await act(async () => reject(new CustomerAddressRequestError("AUTH_REQUIRED", "Synthetic expired save", 401)));
  expect(signOut).not.toHaveBeenCalled(); expect(changed).not.toHaveBeenCalled();
});
it.each(["rotate token", "unmount"])("ignores an old successful save after %s", async action => {
  edit(); let resolve!: (value: typeof snapshot) => void;
  vi.mocked(saveCustomerAddress).mockReturnValueOnce(new Promise(done => { resolve = done; }));
  act(() => submit()); await act(async () => action === "unmount" ? root.render(null) : render("rotated"));
  await act(async () => resolve(snapshot)); expect(changed).not.toHaveBeenCalled();
});
