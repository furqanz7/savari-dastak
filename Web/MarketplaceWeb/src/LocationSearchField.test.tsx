// @vitest-environment jsdom
import { act, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import { searchLocations, reverseGeocodeLocation } from "./location-search";
vi.mock("./location-search", () => ({ searchLocations: vi.fn(), reverseGeocodeLocation: vi.fn() }));
vi.mock("./DastakMap", () => ({ DastakMap: ({ onPinChange, disabled }: { onPinChange: (point: { latitude: number; longitude: number }) => void; disabled: boolean }) => <button type="button" disabled={disabled} onClick={() => onPinChange({ latitude: 12.31, longitude: 76.65 })}>Move pin</button> }));
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
let host: HTMLDivElement, root: Root;
const changed = vi.fn();
beforeEach(() => { vi.useFakeTimers(); vi.clearAllMocks(); host = document.createElement("div"); document.body.append(host); root = createRoot(host); });
afterEach(() => { act(() => root.unmount()); host.remove(); vi.useRealTimers(); });
function Harness({ disabled = false }: { disabled?: boolean }) {
  const [place, setPlace] = useState<SelectedPlace>();
  return <LocationSearchField label="Delivery pin" value={place} onChange={v => { changed(v); setPlace(v); }} onSelectionCleared={() => setPlace(undefined)} disabled={disabled} />;
}
function render(disabled = false) { act(() => root.render(<Harness disabled={disabled} />)); }
function type(value: string) { const input = host.querySelector("input")!; act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value); input.dispatchEvent(new Event("input", { bubbles: true })); }); }
const place = { id: "mysore", label: "Mysore, Karnataka, India", latitude: 12.3, longitude: 76.6 };
it("automatically suggests below the field after typing, without disabling typing", async () => {
  vi.mocked(searchLocations).mockResolvedValue([place]); render(); type("My");
  await act(async () => vi.advanceTimersByTimeAsync(1000)); expect(searchLocations).not.toHaveBeenCalled();
  type("Mysore"); await act(async () => vi.advanceTimersByTimeAsync(650));
  expect(searchLocations).toHaveBeenCalledOnce(); expect(host.querySelector('input')!.disabled).toBe(false);
  expect(host.querySelector('[role="listbox"]')!.textContent).toContain("Mysore");
  const input = host.querySelector("input")!;
  act(() => input.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
  act(() => input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })));
  expect(changed).toHaveBeenCalledWith({ address: place.label, latitude: place.latitude, longitude: place.longitude });
  expect(host.querySelector('[role="listbox"]')).toBeNull();
});
it("ignores suggestions returned for an older query", async () => {
  let finish!: (value: typeof place[]) => void;
  vi.mocked(searchLocations).mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
  render(); type("Mysore"); await act(async () => vi.advanceTimersByTimeAsync(650));
  type("Delhi"); await act(async () => finish([place])); expect(host.textContent).not.toContain(place.label);
});
it("saves exact dragged coordinates even when reverse lookup is unavailable", async () => {
  vi.mocked(reverseGeocodeLocation).mockRejectedValue(new Error("Offline")); render();
  await act(async () => [...host.querySelectorAll('button')].find(b => b.textContent === "Move pin")!.click());
  expect(changed).toHaveBeenCalledWith({ address: "Selected map location", latitude: 12.31, longitude: 76.65 });
  await act(async () => vi.advanceTimersByTimeAsync(400));
  expect(host.textContent).toContain("Pin selected");
});
it("does not request suggestions or change pins while saving", async () => {
  render(true); expect(host.querySelector('input')!.disabled).toBe(true);
  expect([...host.querySelectorAll('button')].every(b => b.disabled)).toBe(true);
  await act(async () => vi.advanceTimersByTimeAsync(1000)); expect(searchLocations).not.toHaveBeenCalled();
});
