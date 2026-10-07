// @vitest-environment jsdom
import { act, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it } from "vitest";
import { ReimaginedProductBrowser } from "./ReimaginedProductBrowser";
import { fixtureId, groceryFixture } from "./reimaginedCatalogue.testFixtures";

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
const small = groceryFixture.catalogue.skus[0];
const large = { ...small, id: fixtureId(31), packSize: "5 kg" };
const other = groceryFixture.catalogue.skus[1];
const third = groceryFixture.catalogue.skus[2];
const families = [[small, large], [other], [third]];
let root: Root; let host: HTMLDivElement;
function Harness({ groups = families }: { groups?: typeof families }) {
  const [selected, setSelected] = useState(small.id);
  return <ReimaginedProductBrowser groups={groups} selectedId={selected} onSelect={setSelected} supabaseUrl="">
    {select => <><output data-selected>{selected}</output><p data-swipe-surface>Product description</p><button onClick={() => select(large.id)}>Choose large</button><select aria-label="Unrelated control"><option>Value</option></select></>}
  </ReimaginedProductBrowser>;
}
function mount(groups = families) { host = document.createElement("div"); document.body.append(host); root = createRoot(host); act(() => root.render(<Harness groups={groups} />)); }
function button(label: string) { return Array.from(host.querySelectorAll("button")).find(button => (button.getAttribute("aria-label") ?? button.textContent) === label)!; }
function click(label: string) { act(() => button(label).click()); }
function selected() { return host.querySelector("[data-selected]")?.textContent; }
function pointer(target: Element, type: string, x: number, y = 0) {
  const event = new MouseEvent(type, { bubbles: true, clientX: x, clientY: y, button: 0 });
  Object.defineProperty(event, "pointerId", { value: 1 });
  act(() => target.dispatchEvent(event));
}
afterEach(() => { if (root) act(() => root.unmount()); host?.remove(); });
describe("Reimagined product browser", () => {
  it("pages by genuine products, stops at boundaries and remembers an exact pack when returning", () => {
    mount(); expect(button("Previous product").disabled).toBe(true);
    expect(host.textContent).toContain("Product 1 of 3");
    click("Choose large"); click("Next product");
    expect(selected()).toBe(other.id);
    click("Previous product"); expect(selected()).toBe(large.id);
    expect(button(`Browse ${large.name}, 5 kg`).getAttribute("aria-current")).toBe("true");
    click("Next product"); click("Next product");
    expect(selected()).toBe(third.id); expect(button("Next product").disabled).toBe(true);
  });
  it("lets the circular picker select an exact product without duplicating its sizes", () => {
    mount(); expect(host.querySelectorAll('.reimagined-product-orbit button')).toHaveLength(3);
    click(`Browse ${third.name}, ${third.packSize}`);
    expect(selected()).toBe(third.id);
    expect(host.textContent).toContain("Product 3 of 3");
  });
  it("handles horizontal swipes in both directions without looping at the ends", () => {
    mount(); let surface = host.querySelector('[data-swipe-surface]')!;
    pointer(surface, "pointerdown", 150); pointer(surface, "pointerup", 30);
    expect(selected()).toBe(other.id);
    surface = host.querySelector('[data-swipe-surface]')!;
    pointer(surface, "pointerdown", 30); pointer(surface, "pointerup", 150);
    expect(selected()).toBe(small.id);
    surface = host.querySelector('[data-swipe-surface]')!;
    pointer(surface, "pointerdown", 30); pointer(surface, "pointerup", 150);
    expect(selected()).toBe(small.id);
  });
  it("ignores vertical, short, cancelled and control-origin gestures", () => {
    mount(); const surface = host.querySelector('[data-swipe-surface]')!;
    pointer(surface, "pointerdown", 150); pointer(surface, "pointerup", 130);
    pointer(surface, "pointerdown", 150); pointer(surface, "pointerup", 30, 160);
    pointer(surface, "pointerdown", 150); pointer(surface, "pointercancel", 30); pointer(surface, "pointerup", 30);
    const control = host.querySelector('select')!;
    pointer(control, "pointerdown", 150); pointer(control, "pointerup", 30);
    expect(selected()).toBe(small.id);
  });
  it("supports keyboard arrows but leaves native select keyboard use alone", () => {
    mount(); const browser = host.querySelector('.reimagined-product-browser')!;
    act(() => browser.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })));
    expect(selected()).toBe(other.id);
    act(() => host.querySelector('select')!.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })));
    expect(selected()).toBe(other.id);
  });
  it("suppresses a picker click after dragging, and resets before a normal click", () => {
    mount(); const orbit = host.querySelector('.reimagined-product-orbit')!;
    pointer(orbit, "pointerdown", 150); pointer(orbit, "pointerup", 30);
    click(`Browse ${third.name}, ${third.packSize}`); expect(selected()).toBe(other.id);
    const target = button(`Browse ${third.name}, ${third.packSize}`);
    pointer(target, "pointerdown", 100); pointer(target, "pointerup", 100);
    click(`Browse ${third.name}, ${third.packSize}`); expect(selected()).toBe(third.id);
  });
  it("omits a useless orbit when only one product is available, despite multiple sizes", () => {
    mount([families[0]]); expect(host.querySelector('.reimagined-product-orbit')).toBeNull();
    expect(button("Previous product").disabled).toBe(true); expect(button("Next product").disabled).toBe(true);
  });
});
