// @vitest-environment jsdom
import { act } from "react";
import { createRoot } from "react-dom/client";
import { expect, it, vi } from "vitest";
import { ReimaginedWishlist } from "./ReimaginedWishlist";
import { groceryFixture, fixtureId } from "./reimaginedCatalogue.testFixtures";
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
it("keeps unresolved saved identities visible and opens the exact available SKU without cart writes", () => {
  const host = document.createElement("div"); const root = createRoot(host); const onOpen = vi.fn(); const toggle = vi.fn();
  const wishlist = { items: [{ kind: "RETAIL_SKU" as const, itemId: fixtureId(6), createdAt: "today" }, { kind: "MENU_ITEM" as const, itemId: fixtureId(99), createdAt: "today" }], ready: true, busy: false, error: undefined, retry: vi.fn(), saved: () => true, toggle };
  try {
    act(() => root.render(<ReimaginedWishlist wishlist={wishlist} data={groceryFixture} menus={[]} online supabaseUrl="https://test.supabase.co" onOpen={onOpen} onClose={vi.fn()} />));
    expect(host.textContent).toContain("Retained in your Wishlist"); expect(toggle).not.toHaveBeenCalled();
    const buttons = [...host.querySelectorAll("button")].filter(button => button.textContent === "View saved item");
    expect(buttons[1].disabled).toBe(true); act(() => buttons[0].click()); expect(onOpen).toHaveBeenCalledWith(fixtureId(6), undefined, undefined);
    act(() => host.querySelector<HTMLButtonElement>(`button[aria-label="Remove Test Plain Rice from Wishlist"]`)!.click());
    expect(toggle).toHaveBeenCalledWith("RETAIL_SKU", fixtureId(6));
  } finally { act(() => root.unmount()); }
});
