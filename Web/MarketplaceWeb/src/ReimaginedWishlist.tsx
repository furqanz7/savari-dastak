import { Bookmark } from "lucide-react";
import type { useReimaginedWishlist } from "./useReimaginedWishlist";
import type { ReimaginedCatalogue } from "./reimaginedCatalogue";
import type { V1RestaurantMenu } from "./dastakV1";
import { formatV1Price } from "./dastakV1";
import { GroceryImage } from "./ReimaginedGrocery";
import { foodAcceptingOrders, foodRestaurantName } from "./reimaginedFoodCatalogue";

export function WishlistButton({ wishlist, kind, id, name, online }: { wishlist?: ReturnType<typeof useReimaginedWishlist>; kind: "RETAIL_SKU" | "MENU_ITEM"; id: string; name: string; online: boolean }) {
  if (!wishlist) return null;
  const saved = wishlist.saved(kind, id);
  return <button className="reimagined-save" type="button" aria-label={`${saved ? "Remove" : "Save"} ${name} ${saved ? "from" : "to"} Wishlist`} aria-pressed={saved} disabled={!online || !wishlist.ready || wishlist.busy} onClick={() => void wishlist.toggle(kind, id)}><Bookmark size={18} fill={saved ? "currentColor" : "none"} /><span>{saved ? "Saved" : "Save"}</span></button>;
}

export function ReimaginedWishlist({ wishlist, data, menus, online, supabaseUrl, onOpen, onClose, headingOwnedByShell = false }: {
  wishlist: ReturnType<typeof useReimaginedWishlist>; data?: ReimaginedCatalogue; menus?: V1RestaurantMenu[]; online: boolean; supabaseUrl: string;
  onOpen: (skuId?: string, branchId?: string, itemId?: string) => void; onClose: () => void;
  headingOwnedByShell?: boolean;
}) {
  return <section aria-label="Your Wishlist">{!headingOwnedByShell ? <h2>Your Wishlist</h2> : null}<button type="button" onClick={onClose}>Back to shopping</button>
    {wishlist.error ? <p role="alert">Wishlist could not update. Your saved items were not discarded.</p> : null}
    <button type="button" disabled={!online || wishlist.busy} onClick={wishlist.retry}>Refresh Wishlist</button>
    {!wishlist.ready ? <p role="status">{online ? "Loading your saved products and dishes…" : "Reconnect to load your Wishlist."}</p> : !wishlist.items.length ? <p>No saved products or dishes yet. Use Save on a shelf or in details.</p> : <ul className="reimagined-saved-list">{wishlist.items.map(saved => {
      const sku = saved.kind === "RETAIL_SKU" ? data?.catalogue.skus.find(value => value.id === saved.itemId) : undefined;
      const menu = saved.kind === "MENU_ITEM" ? menus?.find(value => value.categories.some(category => category.items.some(item => item.id === saved.itemId))) : undefined;
      const item = menu?.categories.flatMap(category => category.items).find(value => value.id === saved.itemId);
      const name = sku?.name ?? item?.name ?? "Saved item unavailable in the loaded catalogue";
      return <li key={`${saved.kind}:${saved.itemId}`}>
        {sku ? <GroceryImage sku={sku} supabaseUrl={supabaseUrl} /> : null}<strong>{name}</strong>
        {sku ? <p>{sku.packSize} · {formatV1Price(sku.sellingPricePaise)}</p> : item && menu ? <p>{foodRestaurantName(menu)} · {formatV1Price(item.basePricePaise)} base</p> : <p>Retained in your Wishlist; it was not silently removed.</p>}
        {menu && !foodAcceptingOrders(menu) ? <p>Store closed</p> : null}
        <button type="button" disabled={(!sku && !item) || Boolean(menu && !foodAcceptingOrders(menu))} onClick={() => onOpen(sku?.id, menu?.restaurant.branchId, item?.id)}>View saved item</button>
        <WishlistButton wishlist={wishlist} kind={saved.kind} id={saved.itemId} name={name} online={online} />
      </li>;
    })}</ul>}
  </section>;
}
