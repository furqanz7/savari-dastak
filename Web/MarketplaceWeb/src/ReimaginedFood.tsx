import { useId, useMemo, useRef, useState, type Dispatch, type ReactNode } from "react";
import { ArrowLeft, ArrowRight, MapPin, Minus, Plus, RefreshCw, Trash2, Utensils, WifiOff } from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import { formatV1Price, type V1RestaurantMenu, type V1RestaurantMenuItem } from "./dastakV1";
import { foodAcceptingOrders, foodAvailability, foodCategoryControls, foodCategoryRestaurants, foodDistance, foodRestaurantName, searchFood } from "./reimaginedFoodCatalogue";
import type { ReimaginedAction, ReimaginedState } from "./reimaginedState";
import type { useReimaginedFood } from "./useReimaginedFood";
import { foodSelection, sameFoodOptions } from "./reimaginedFoodSelection";
import { WishlistButton } from "./ReimaginedWishlist";
import type { useReimaginedWishlist } from "./useReimaginedWishlist";
import "./design/reimaginedFood.css";

type Props = { state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; resource: ReturnType<typeof useReimaginedFood>; supabaseUrl: string; online: boolean; legacyUrl: string; canEdit?: boolean; checkoutContent?: ReactNode; availabilityNotice?: ReactNode; wishlist?: ReturnType<typeof useReimaginedWishlist>; headingOwnedByShell?: boolean };

export function ReimaginedFood({ state, dispatch, resource, supabaseUrl, online, canEdit = true, checkoutContent, availabilityNotice, wishlist, headingOwnedByShell = false }: Props) {
  const exploration = state.exploration.food;
  const categoryControls = useMemo(() => foodCategoryControls(resource.data ?? []), [resource.data]);
  const restaurants = useMemo(() => {
    const selected = exploration.foodCategoryFilter;
    const current = categoryControls.find(filter => filter.label === selected?.label);
    if (!selected || !current) return foodCategoryRestaurants(resource.data ?? [], selected);
    const knownBranches = new Set(selected.members.map(member => member.branchId));
    // New pages may extend a shared label, but must not replace a selected
    // category with a different identity in an already-known restaurant.
    return foodCategoryRestaurants(resource.data ?? [], { ...selected, members: [...selected.members, ...current.members.filter(member => !knownBranches.has(member.branchId))] });
  }, [resource.data, exploration.foodCategoryFilter, categoryControls]);
  if (exploration.checkout) return <section className="reimagined-food-cart" aria-label="Review Food cart">{!headingOwnedByShell ? <h2>Your saved Food items</h2> : null}
    <p>Your Food cart is separate from Grocery. Final prices and availability are confirmed by the server at checkout.</p>
    {!state.shopping.food.length ? <div className="reimagined-food-empty"><Utensils size={28} aria-hidden="true" /><h2>Your Food cart is empty</h2><p>Choose a restaurant and add something you like.</p><button type="button" onClick={() => dispatch({ type: "continueShopping" })}>Browse Food<ArrowRight size={16} aria-hidden="true" /></button></div> : <ul className="reimagined-food-cart-lines">{state.shopping.food.map(line => {
      const menu = resource.data?.find(value => value.restaurant.branchId === line.branchId);
      const item = menu?.categories.flatMap(category => category.items).find(value => value.id === line.itemId);
      const selection = item ? foodSelection(item, line.optionIds) : undefined;
      return <li className="reimagined-food-cart-line" key={`${line.branchId}:${line.itemId}:${[...line.optionIds].sort().join(",")}`}>
        <FoodImage name={item?.name ?? "Saved dish"} imageKey={item?.imageKey} supabaseUrl={supabaseUrl} />
        <div className="reimagined-food-cart-description"><strong>{item?.name ?? "Saved dish"}</strong><small>{menu ? foodRestaurantName(menu) : "Restaurant unavailable"}</small>
        {selection?.valid ? <><p>{selection.options.map(option => option.name).join(", ") || "No options"}</p><p>{formatV1Price(selection.pricePaise * line.quantity)} estimated</p></> : <p>Saved selection unavailable in the current menu; retained unchanged.</p>}
        </div><div className="reimagined-food-cart-actions"><div className="reimagined-food-quantity" role="group" aria-label={`${item?.name ?? "Saved dish"} cart quantity`}>
        <button type="button" disabled={!canEdit} aria-label={`Decrease ${item?.name ?? "saved dish"} in Food cart`} onClick={() => dispatch({ type: "setFoodQuantity", line: { ...line, quantity: line.quantity - 1 } })}><Minus size={16} aria-hidden="true" /></button><output aria-label={`${item?.name ?? "Saved dish"} quantity`}>{line.quantity}</output>
        <button type="button" disabled={!canEdit || !online || !selection?.valid || !menu?.restaurant.isOpen || !menu.restaurant.acceptingOrders || menu.restaurant.branchStatus !== "ACTIVE" || line.quantity >= 99} aria-label={`Increase ${item?.name ?? "saved dish"} in Food cart`} onClick={() => dispatch({ type: "setFoodQuantity", line: { ...line, quantity: line.quantity + 1 } })}><Plus size={16} aria-hidden="true" /></button></div>
        <button className="reimagined-food-remove" type="button" disabled={!canEdit} aria-label={`Remove ${item?.name ?? "saved dish"}`} onClick={() => dispatch({ type: "setFoodQuantity", line: { ...line, quantity: 0 } })}><Trash2 size={15} aria-hidden="true" />Remove</button></div>
      </li>;
    })}</ul>}
    {state.shopping.food.length ? checkoutContent ?? <button type="button" disabled>Food checkout integration pending</button> : null}</section>;
  if (availabilityNotice) return <>{availabilityNotice}</>;
  if (!resource.data) return <FoodPanelMessage title={!online ? "You’re offline" : resource.status === "unavailable" ? "Menus couldn’t load" : "Opening restaurants and menus…"} detail={!online ? "Reconnect to load Food menus. Your saved carts are unchanged." : resource.status === "unavailable" ? "Couldn’t load Food menus. Your saved carts are unchanged." : "Finding the latest menus and store availability."} loading={online && resource.status !== "unavailable"} offline={!online}>
    {online && resource.status === "unavailable" ? <button type="button" onClick={resource.retry}>Retry Food menus<RefreshCw size={16} aria-hidden="true" /></button> : null}</FoodPanelMessage>;
  const branchId = exploration.view.kind === "restaurant" ? exploration.view.branchId : undefined;
  const menu = resource.data.find(value => value.restaurant.branchId === branchId);
  if (menu && !foodAcceptingOrders(menu)) return <FoodPanelMessage title="Store closed" detail={`${foodRestaurantName(menu)} isn’t accepting orders right now. Your saved Food cart is unchanged.`}><button type="button" onClick={() => dispatch({ type: "navigate", section: "home" })}><ArrowLeft size={16} aria-hidden="true" />Back to restaurants</button></FoodPanelMessage>;
  const item = menu?.categories.flatMap(category => category.items).find(value => value.id === exploration.detailId);
  return <div className="reimagined-food">
    <div className="reimagined-food-toolbar">{exploration.detailId ? <button type="button" className="reimagined-detail-close" onClick={() => dispatch({ type: "closeDetail" })}><ArrowLeft size={16} aria-hidden="true" />Back to menu</button> : menu ? <button type="button" className="reimagined-food-back" onClick={() => dispatch({ type: "navigate", section: "home" })}><ArrowLeft size={16} aria-hidden="true" />Back to restaurants</button> : <p>Restaurants and cafés near you</p>}<button type="button" disabled={!online || resource.status === "loading"} onClick={resource.retry} aria-label="Refresh Food menus"><RefreshCw size={16} aria-hidden="true" /><span>Refresh</span></button></div>
    {resource.status === "loading" ? <p role="status">Searching Dastak’s restaurant catalogue…</p> : null}
    {!online ? <p className="reimagined-food-notice" role="status"><WifiOff size={16} aria-hidden="true" />Offline: showing saved menus. Reconnect to add dishes or refresh availability.</p> : null}
    {resource.error && resource.data ? <p role="alert">More Food results could not load. The menus already loaded are retained.</p> : null}
    {exploration.detailId ? item && menu ? <section className="reimagined-product-detail" aria-label={`${item.name} dish details`}>
      <FoodImage name={item.name} imageKey={item.imageKey} supabaseUrl={supabaseUrl} />
      {!headingOwnedByShell ? <h2>{item.name}</h2> : null}<p className="reimagined-food-detail-restaurant">{foodRestaurantName(menu)}</p>{item.description ? <p>{item.description}</p> : null}<p className="reimagined-food-base-price">Base price: {formatV1Price(item.basePricePaise)}</p><p className="reimagined-food-status" data-open={foodAcceptingOrders(menu)}>{foodAvailability(menu)}</p>
      <WishlistButton wishlist={wishlist} kind="MENU_ITEM" id={item.id} name={item.name} online={online} />
      <FoodChoices key={JSON.stringify([menu.restaurant.branchId, item])} item={item} menu={menu} state={state} dispatch={dispatch} online={online} canEdit={canEdit} />
    </section> : <p role="status">This dish is no longer in the loaded menu. <button type="button" onClick={() => dispatch({ type: "closeDetail" })}>Back to menu</button></p>
      : exploration.view.kind === "restaurant" ? menu ? <><section className="reimagined-food-restaurant-intro" aria-label="Restaurant information"><FoodImage name={foodRestaurantName(menu)} imageKey={menu.restaurant.imageKey} supabaseUrl={supabaseUrl} /><div>{!headingOwnedByShell ? <h2>{foodRestaurantName(menu)}</h2> : null}{menu.restaurant.description ? <p>{menu.restaurant.description}</p> : null}<p className="reimagined-food-status" data-open={foodAcceptingOrders(menu)}>Accepting orders</p>{resource.nearest ? <small><MapPin size={14} aria-hidden="true" />{foodDistance(menu)} · straight-line distance</small> : null}</div></section>
        <RestaurantMenu key={menu.restaurant.branchId} menu={menu} supabaseUrl={supabaseUrl} dispatch={dispatch} wishlist={wishlist} online={online} /></>
        : <p role="status">This restaurant is not in the loaded catalogue. <button type="button" onClick={() => dispatch({ type: "navigate", section: "home" })}>Back to restaurants</button></p>
      : exploration.view.kind === "search" ? resource.status === "loading" ? null : resource.error && !resource.searchData ? <p role="status">The server search did not complete. Refresh Food menus to retry; your saved carts are unchanged.</p> : <><p className="reimagined-commerce-note">{online ? "Search results come from Dastak’s restaurant catalogue. Load more if further matches are available." : "Offline: showing only menus already loaded on this device."}</p><FoodResults menus={resource.searchData ?? resource.data} query={exploration.view.query} dispatch={dispatch} nearest={resource.nearest} canonical={Boolean(resource.searchData)} /></>
      : <><details className="reimagined-food-distance"><summary>{resource.nearest ? online ? "Nearest first" : "Offline: saved distance order" : "Choose a saved delivery location"}</summary><p>{resource.nearest ? "A straight-line distance from your selected address is not a delivery time. Restaurants without a location appear last." : "Choose a saved delivery location for nearest-first restaurants. Showing catalogue order."}</p></details><nav className="reimagined-food-categories" aria-label="Food menu categories">
        <button type="button" aria-pressed={!exploration.foodCategoryFilter} onClick={() => dispatch({ type: "selectFoodCategory" })}>All restaurants</button>
        {categoryControls.map(filter => <button key={filter.label} type="button" aria-label={`Browse Food category ${filter.label}`} aria-pressed={exploration.foodCategoryFilter?.label === filter.label} onClick={() => dispatch({ type: "selectFoodCategory", filter })}>{filter.label}</button>)}
      </nav><section className="reimagined-wooden-shelf" aria-label="Restaurants"><header><h2>{exploration.foodCategoryFilter ? `Restaurants offering ${exploration.foodCategoryFilter.label}` : "Restaurants"}</h2><small>{restaurants.length} {resource.hasMore ? "loaded" : restaurants.length === 1 ? "restaurant" : "restaurants"}</small></header>
        {restaurants.length ? <div className="reimagined-restaurant-grid" aria-label="Restaurant shelf">{restaurants.map(value => <article className="reimagined-restaurant-card" key={value.restaurant.branchId} data-closed={!foodAcceptingOrders(value)}>
          <button type="button" className="reimagined-product-open" disabled={!foodAcceptingOrders(value)} aria-label={`Open ${foodRestaurantName(value)} menu`} onClick={() => dispatch({ type: "openRestaurant", branchId: value.restaurant.branchId })}>
            <FoodImage name={foodRestaurantName(value)} imageKey={value.restaurant.imageKey} supabaseUrl={supabaseUrl} /><span className="reimagined-restaurant-card-body"><strong>{foodRestaurantName(value)}</strong>{value.restaurant.description ? <small>{value.restaurant.description}</small> : null}<span className="reimagined-food-status" data-open={foodAcceptingOrders(value)}>{foodAcceptingOrders(value) ? "Accepting orders" : "Store closed"}</span>{resource.nearest ? <small><MapPin size={14} aria-hidden="true" />{foodDistance(value)}</small> : null}<span className="reimagined-food-card-action">{foodAcceptingOrders(value) ? "View menu" : "Not accepting orders"}<ArrowRight size={16} aria-hidden="true" /></span></span></button>
        </article>)}</div> : <FoodPanelMessage title={exploration.foodCategoryFilter ? "No matches in this category" : "Food delivery isn’t available in your area yet"} detail={exploration.foodCategoryFilter ? "No restaurants in the loaded menus currently match this category. Choose All restaurants or refresh the menus." : "Try another delivery location or check back later. Your saved Food cart is unchanged."}>{exploration.foodCategoryFilter ? <button type="button" onClick={() => dispatch({ type: "selectFoodCategory" })}>Show all restaurants<ArrowRight size={16} aria-hidden="true" /></button> : null}</FoodPanelMessage>}</section></>}
    {!exploration.detailId && exploration.view.kind !== "restaurant" && resource.hasMore && resource.loadMore ? <div className="reimagined-food-pagination"><button type="button" disabled={!online || resource.loadingMore || resource.status === "loading"} onClick={() => void resource.loadMore?.()}>{resource.loadingMore ? "Loading more Food results…" : exploration.view.kind === "search" ? "Load more Food search results" : "Load more restaurants"}<ArrowRight size={16} aria-hidden="true" /></button></div> : null}
  </div>;
}

function FoodPanelMessage({ title, detail, loading = false, offline = false, children }: { title: string; detail: string; loading?: boolean; offline?: boolean; children?: ReactNode }) {
  return <section className="reimagined-food-state" role="status" aria-busy={loading}>
    <span className="reimagined-food-state-icon" aria-hidden="true">{loading ? <RefreshCw className="reimagined-food-spinner" size={25} /> : offline ? <WifiOff size={25} /> : <Utensils size={25} />}</span>
    <h2>{title}</h2><p>{detail}</p>{children}
  </section>;
}

export function ReimaginedFoodSuggestions({ menus, query, dispatch, canonical = false, onSelect, more = false }: { menus?: V1RestaurantMenu[]; query: string; dispatch: Dispatch<ReimaginedAction>; canonical?: boolean; onSelect?: (menu: V1RestaurantMenu) => boolean; more?: boolean }) {
  if (!query.trim()) return <p>Search restaurants or dishes near your delivery location.</p>;
  if (!menus) return null;
  return <><FoodResults menus={menus} query={query} dispatch={dispatch} suggestions canonical={canonical} onSelect={onSelect} /><p>Showing suggestions near your delivery location. {more ? "More restaurants may match. " : ""}Submit Search to browse full results.</p></>;
}

function FoodResults({ menus, query, dispatch, suggestions = false, nearest = false, canonical = false, onSelect }: { menus: V1RestaurantMenu[]; query: string; dispatch: Dispatch<ReimaginedAction>; suggestions?: boolean; nearest?: boolean; canonical?: boolean; onSelect?: (menu: V1RestaurantMenu) => boolean }) {
  const results = searchFood(menus, query, canonical);
  const open = (menu: V1RestaurantMenu, itemId?: string) => {
    if (!foodAcceptingOrders(menu)) return;
    if (onSelect && !onSelect(menu)) return;
    dispatch({ type: "closeSearch" }); dispatch({ type: "openRestaurant", branchId: menu.restaurant.branchId });
    if (itemId) dispatch({ type: "openDetail", id: itemId });
  };
  return <div className="reimagined-grocery-suggestions" aria-label={suggestions ? "Food suggestions" : "Food search results"}>
    {!results.length ? <p>{canonical ? "No matching restaurants or dishes in your area." : "No matches in the loaded Food menus."}</p> : (suggestions ? results.slice(0, 8) : results).map(({ menu, dishes }) => <section key={menu.restaurant.branchId}>
      <button type="button" disabled={!foodAcceptingOrders(menu)} onClick={() => open(menu)}>{foodRestaurantName(menu)}<small>{!foodAcceptingOrders(menu) ? "Store closed" : nearest ? `${foodDistance(menu)} · View menu` : "View menu"}</small></button>
      {(suggestions ? dishes.slice(0, 3) : dishes).map(({ item }) => <button type="button" key={item.id} disabled={!foodAcceptingOrders(menu)} onClick={() => open(menu, item.id)}>{item.name}<small>{!foodAcceptingOrders(menu) ? "Store closed" : `${formatV1Price(item.basePricePaise)} base`}</small></button>)}
    </section>)}
  </div>;
}

function RestaurantMenu({ menu, ...props }: { menu: V1RestaurantMenu; dispatch: Dispatch<ReimaginedAction>; supabaseUrl: string; wishlist?: ReturnType<typeof useReimaginedWishlist>; online: boolean }) {
  const prefix = useId();
  const sections = useRef(new Map<string, HTMLDivElement>());
  const jump = (id: string) => {
    const target = sections.current.get(id);
    if (!target) return;
    target.focus({ preventScroll: true });
    target.scrollIntoView({ block: "start", behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
  };
  if (!menu.categories.length) return <p>No dishes in this menu yet.</p>;
  return <><nav className="reimagined-menu-shortcuts" aria-label="Jump to menu category">{menu.categories.map(category => <button key={category.id} type="button" aria-controls={`${prefix}-${category.id}`} onClick={() => jump(category.id)}>{category.name}</button>)}</nav>
    {menu.categories.map(category => <div key={category.id} id={`${prefix}-${category.id}`} className="reimagined-menu-target" tabIndex={-1} aria-label={`${category.name} menu category`} ref={element => { if (element) sections.current.set(category.id, element); else sections.current.delete(category.id); }}><DishShelf name={category.name} items={category.items} {...props} /></div>)}</>;
}

function DishShelf({ name, items, dispatch, supabaseUrl, wishlist, online }: { name: string; items: V1RestaurantMenuItem[]; dispatch: Dispatch<ReimaginedAction>; supabaseUrl: string; wishlist?: ReturnType<typeof useReimaginedWishlist>; online: boolean }) {
  return <section className="reimagined-food-menu-section" aria-label={name}><header><h3>{name}</h3><small>{items.length} {items.length === 1 ? "dish" : "dishes"}</small></header>{items.length ? <div className="reimagined-dish-grid" aria-label={`${name} dish shelf`}>{items.map(item => <article className="reimagined-dish-card" key={item.id}>
    <button type="button" className="reimagined-product-open" aria-label={`View ${item.name} details`} onClick={() => dispatch({ type: "openDetail", id: item.id })}><FoodImage name={item.name} imageKey={item.imageKey} supabaseUrl={supabaseUrl} /><span className="reimagined-product-name">{item.name}</span></button>
    <p className="reimagined-food-dish-price"><strong>{formatV1Price(item.basePricePaise)}</strong><small>{item.optionGroups.length ? "Choose options" : "Per dish"}</small></p>
    <WishlistButton wishlist={wishlist} kind="MENU_ITEM" id={item.id} name={item.name} online={online} />
    <button className="reimagined-food-choose" type="button" onClick={() => dispatch({ type: "openDetail", id: item.id })}>Choose dish<Plus size={16} aria-hidden="true" /></button>
  </article>)}</div> : <p>No dishes in this category yet.</p>}</section>;
}

function FoodChoices({ item, menu, state, dispatch, online, canEdit }: { item: V1RestaurantMenuItem; menu: V1RestaurantMenu; state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; online: boolean; canEdit: boolean }) {
  const [optionIds, setOptionIds] = useState<string[]>([]);
  const selection = foodSelection(item, optionIds);
  const branchId = menu.restaurant.branchId;
  const line = state.shopping.food.find(value => value.branchId === branchId && value.itemId === item.id && sameFoodOptions(value.optionIds, optionIds));
  const otherRestaurant = state.shopping.food.some(value => value.branchId !== branchId);
  const available = menu.restaurant.branchStatus === "ACTIVE" && menu.restaurant.isOpen && menu.restaurant.acceptingOrders;
  const canAdd = canEdit && online && available && selection.valid && !otherRestaurant && (line?.quantity ?? 0) < 99;
  return <div className="reimagined-food-choices">
    {item.optionGroups.map(group => <fieldset key={group.id}><legend>{group.name}</legend><p>{group.minimumSelections}–{group.maximumSelections} choices · {group.selectionType === "SINGLE" ? "Single choice" : "Multiple choices"}</p>
      {group.options.map(option => <label key={option.id}><input type={group.selectionType === "SINGLE" ? "radio" : "checkbox"} name={group.id} checked={optionIds.includes(option.id)} onChange={event => {
        const checked = event.currentTarget.checked;
        setOptionIds(previous => {
          const remaining = previous.filter(id => id !== option.id && (group.selectionType !== "SINGLE" || !group.options.some(value => value.id === id)));
          return checked ? [...remaining, option.id] : remaining;
        });
      }} /><span>{option.name}</span><small>+{formatV1Price(option.priceDeltaPaise)}</small></label>)}
      {group.selectionType === "SINGLE" && group.minimumSelections === 0 ? <button type="button" onClick={() => setOptionIds(previous => previous.filter(id => !group.options.some(option => option.id === id)))}>Clear {group.name}</button> : null}
    </fieldset>)}
    <p className="reimagined-food-selection-price"><strong>{formatV1Price(selection.pricePaise)}</strong> estimated per dish · In cart: {line?.quantity ?? 0}</p>
    {!selection.valid ? <p role="status">Choose the required options within each group’s limits.</p> : null}
    {otherRestaurant ? <p role="status">Your Food cart belongs to another restaurant. Remove those items first; nothing will be replaced.</p> : null}
    {!online ? <p role="status">Reconnect before adding Food items.</p> : null}
    {!canEdit ? <p role="status">Cart editing is unavailable in this tab.</p> : null}
    <button type="button" disabled={!canAdd} onClick={() => dispatch({ type: "setFoodQuantity", line: { branchId, itemId: item.id, optionIds: [...optionIds].sort(), quantity: (line?.quantity ?? 0) + 1 } })}>Add to Food cart</button>
    {line ? <button type="button" disabled={!canEdit} onClick={() => dispatch({ type: "setFoodQuantity", line: { ...line, quantity: line.quantity - 1 } })}>Remove one selected dish</button> : null}
  </div>;
}

function FoodImage({ name, imageKey, supabaseUrl }: { name: string; imageKey?: string; supabaseUrl: string }) {
  const url = catalogueImageUrl(supabaseUrl, imageKey ?? null);
  return <div className="reimagined-sku-image" key={url ?? name}>{url ? <img src={url} alt={name} loading="lazy" onError={event => { event.currentTarget.hidden = true; event.currentTarget.parentElement?.setAttribute("data-image-unavailable", "true"); }} /> : null}
    <span className="reimagined-sku-image-fallback" data-fallback={!url}><Utensils size={30} aria-hidden="true" /><small>Image unavailable</small></span></div>;
}
