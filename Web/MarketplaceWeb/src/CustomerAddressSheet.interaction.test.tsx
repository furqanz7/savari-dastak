// @vitest-environment jsdom
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { CustomerAddressSheet } from "./CustomerAddressSheet";
import { searchLocations } from "./location-search";
vi.mock("./location-search", () => ({ searchLocations: vi.fn(), reverseGeocodeLocation: vi.fn() }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const home = { addressId: "home", label: "Home", address: "Old area", building: "1", details: "", displayAddress: "Old area", location: { latitude: 12, longitude: 77 }, isDefault: true, updatedAt: "today" };
let host: HTMLDivElement, root: Root;
const save = vi.fn(async () => {}), dismiss = vi.fn();
beforeEach(() => { vi.clearAllMocks(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); });
function render(busy = false) { act(() => root.render(<CustomerAddressSheet address={home} busy={busy} context="account" onSave={save} onDismiss={dismiss} />)); }
function submit() { act(() => host.querySelector("form")!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))); }
function changePin(value: string) {
  const input = host.querySelector<HTMLInputElement>('[placeholder="Search delivery pin"]')!;
  act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value); input.dispatchEvent(new Event("input", { bubbles: true })); });
}
it("invalidates an old delivery pin when its search text is edited and saves only a newly chosen pin", async () => {
  render(); changePin("New area"); submit();
  expect(save).not.toHaveBeenCalled();
  expect(host.querySelector<HTMLButtonElement>('button[type="submit"]')!.disabled).toBe(true);
  vi.mocked(searchLocations).mockResolvedValueOnce([{ id: "new", label: "New area confirmed", latitude: 13, longitude: 78 }]);
  await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="Search delivery pin"]')!.click());
  act(() => host.querySelector<HTMLButtonElement>('.place-search-results button')!.click());
  submit();
  expect(save).toHaveBeenCalledWith(expect.objectContaining({ place: { address: "New area confirmed", latitude: 13, longitude: 78 } }));
});
it("blocks submit and draft edits while saving", () => {
  render(true); submit(); expect(save).not.toHaveBeenCalled();
  expect([...host.querySelectorAll('input,textarea')].every(input => input.matches(':disabled'))).toBe(true);
});
it("cancelling keeps the original address untouched", () => {
  render(); changePin("New area");
  act(() => host.querySelector<HTMLButtonElement>('[aria-label="Close address editor"]')!.click());
  expect(dismiss).toHaveBeenCalledOnce(); expect(save).not.toHaveBeenCalled(); expect(home.address).toBe("Old area");
});
