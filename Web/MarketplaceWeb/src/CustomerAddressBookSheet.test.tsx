// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CustomerAddressBookSheet } from "./CustomerAddressBookSheet";
import type { CustomerDeliveryAddress } from "./customerAddresses";

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const home: CustomerDeliveryAddress = { addressId: "synthetic-home", label: "Home", address: "Test street", building: "1", details: "1", displayAddress: "Test street", location: { latitude: 0, longitude: 0 }, isDefault: true, updatedAt: "2026-10-09T00:00:00Z" };
let host: HTMLDivElement, root: Root;
beforeEach(() => { host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); vi.restoreAllMocks(); });
function mount(onDelete = vi.fn(async () => true), onDismiss = vi.fn()) {
  act(() => root.render(<CustomerAddressBookSheet addresses={[home]} busy={false} context="account" onDismiss={onDismiss} onAdd={vi.fn()} onEdit={vi.fn()} onSelect={async () => {}} onDelete={onDelete} />));
  const opener = host.querySelector<HTMLButtonElement>('[aria-label="Delete Home"]')!;
  opener.focus(); act(() => opener.click());
  return { opener, onDelete, onDismiss };
}
function confirmationButton(label: string) {
  return [...host.querySelectorAll<HTMLButtonElement>('[role="alertdialog"] button')].find(x => x.textContent === label)!;
}

describe("saved-address deletion confirmation", () => {
  it("focuses the safe action and contains keyboard focus above the address book", () => {
    mount();
    const keep = confirmationButton("Keep address"), remove = confirmationButton("Delete");
    expect(document.activeElement).toBe(keep);
    expect(host.querySelector('.customer-address-book-list')?.getAttribute('aria-hidden')).toBe("true");
    remove.focus(); act(() => remove.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true })));
    expect(document.activeElement).toBe(keep);
    act(() => keep.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", shiftKey: true, bubbles: true, cancelable: true })));
    expect(document.activeElement).toBe(remove);
  });
  it("Escape cancels only the confirmation, preserves the book and restores its opener", () => {
    const { opener, onDelete, onDismiss } = mount();
    act(() => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })));
    expect(host.querySelector('[role="alertdialog"]')).toBeNull();
    expect(host.querySelector('[role="dialog"]')).not.toBeNull();
    expect(document.activeElement).toBe(opener);
    expect(document.body.style.overflow).toBe("hidden");
    expect(onDelete).not.toHaveBeenCalled(); expect(onDismiss).not.toHaveBeenCalled();
  });
  it("retains confirmation after a reported failure and closes only after successful retry", async () => {
    const onDelete = vi.fn(async () => true).mockResolvedValueOnce(false);
    mount(onDelete);
    await act(async () => confirmationButton("Delete").click());
    expect(host.querySelector('[role="alertdialog"]')).not.toBeNull();
    await act(async () => confirmationButton("Delete").click());
    expect(host.querySelector('[role="alertdialog"]')).toBeNull();
    expect(onDelete).toHaveBeenCalledTimes(2);
  });
  it("contains an unexpected rejected callback and offers retry without closing", async () => {
    const onDelete = vi.fn(async () => true).mockRejectedValueOnce(new Error("Synthetic exception"));
    mount(onDelete); await act(async () => confirmationButton("Delete").click());
    expect(host.querySelector('[role="alertdialog"]')).not.toBeNull();
    expect(host.querySelector('[role="alertdialog"] [role="alert"]')?.textContent).toContain("Try again");
  });
});
