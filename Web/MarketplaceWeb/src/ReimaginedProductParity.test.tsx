// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { ReimaginedGrocery } from "./ReimaginedGrocery";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
import { initialReimaginedState, reimaginedReducer } from "./reimaginedState";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
it("restores exact photo galleries, product facts and genuine pack variants", () => {
  const original = groceryFixture.catalogue.skus[0];
  const first = { ...original, name: "Test Rice 1 kg", brand: { id: fixtureId(100), slug: "test", name: "Test brand" }, imageKey: "test/front.jpg", galleryImageKeys: ["test/back.jpg"], manufacturerName: "Test manufacturer", barcode: "123456", quantityValue: 1, quantityUnit: "kg" };
  const second = { ...first, id: fixtureId(101), name: "Test Rice 500 g", packSize: "500 g", quantityValue: 500, quantityUnit: "g" };
  const data = { ...groceryFixture, catalogue: { ...groceryFixture.catalogue, skus: [first, second] } };
  const signed = reimaginedReducer(initialReimaginedState(), { type: "signedIn", accountId: "test" });
  const state = reimaginedReducer(signed, { type: "openDetail", id: first.id });
  const host = document.createElement("div"); const root = createRoot(host); const dispatch = vi.fn();
  try {
    act(() => root.render(<ReimaginedGrocery state={state} dispatch={dispatch} data={data} status="ready" supabaseUrl="https://test.supabase.co" onRetry={vi.fn()} eligibility={() => ({ canAdd: true, maximumQuantity: 99 })} checkoutContent={null} />));
    expect(host.textContent).toContain("Test manufacturer"); expect(host.textContent).toContain("123456");
    expect(host.querySelector('img')?.getAttribute('src')).toContain("front.jpg");
    act(() => host.querySelector<HTMLButtonElement>('[aria-label="Next product photo"]')!.click());
    expect(host.querySelector('img')?.getAttribute('src')).toContain("back.jpg");
    const picker = host.querySelector('[aria-label="Related pack sizes and variants"]')!;
    expect(picker.querySelectorAll('button')).toHaveLength(2);
    act(() => picker.querySelectorAll('button')[1].click());
    expect(dispatch).toHaveBeenCalledWith({ type: "openDetail", id: second.id });
    expect(host.textContent).toContain("Share product");
  } finally { act(() => root.unmount()); }
});
