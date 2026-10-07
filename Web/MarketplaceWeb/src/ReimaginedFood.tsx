import { useMemo, useState, type Dispatch, type ReactNode } from "react";
import { Utensils } from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import { formatV1Price, type V1RestaurantMenu, type V1RestaurantMenuItem } from "./dastakV1";
import { foodAvailability, foodCategoryControls, foodCategoryRestaurants, foodRestaurantName, searchFood } from "./reimaginedFoodCatalogue";
import type { ReimaginedAction, ReimaginedState } from "./reimaginedState";
import type { useReimaginedFood } from "./useReimaginedFood";
import { foodSelection, sameFoodOptions } from "./reimaginedFoodSelection";

type Props = { state: ReimaginedState; dispatch: Dispatch<ReimaginedAction>; resource: ReturnType<typeof useReimaginedFood>; supabaseUrl: string; online: boolean; legacyUrl: string; canEdit?: boolean; checkoutContent?: ReactNode };

export function ReimaginedFood({ state, dispatch, resource, supabaseUrl, online, legacyUrl, canEdit = true, checkoutContent }: Props) {
  const exploration = state.exploration.food;
  const categoryControls = useMemo(() => foodCategoryControls(resource.data ?? []), [resource.data]);
  const restaurants = useMemo(() => foodCategoryRestaurants(resource.data ?? [], exploration.foodCategoryFilter), [resource.data, exploration.foodCategoryFilter]);
  if (exploration.checkout) return <section aria-label="Review Food cart"><h2>Your saved Food items</h2>
    <p>Your Food cart is separate from Grocery. Prices are estimates; checkout remains disabled.</p>
    <ul>{state.shopping.food.map(line => {
      const menu = resource.data?.find(value => value.restaurant.branchId === line.branchId);
      const item = menu?.categories.flatMap(category => category.items).find(value => value.id === line.itemId);
      const selection = item ? foodSelection(item, line.optionIds) : undefined;
      return <li key={`${line.branchId}:${line.itemId}:${[...line.optionIds].sort().join(",")}`}>
        {item?.name ?? "Saved dish"} · {menu ? foodRestaurantName(menu) : "Restaurant unavailable"} · Quantity {line.quantity}
        {selection?.valid ? <><p>{selection.options.map(option => option.name).join(", ") || "No options"}</p><p>{formatV1Price(selection.pricePaise * line.quantity)} estimated</p></> : <p>Saved selection unavailable in the current menu; retained unchanged.</p>}
        <button type="button" disabled={!canEdit} aria-label={`Remove ${item?.name ?? "saved dish"}`} onClick={() => dispatch({ type: "setFoodQuantity", line: { ...line, quantity: 0 } })}>Remove</button>
      </li>;
    })}</ul><a href={legacyUrl}>Open existing Food</a>
    {checkoutContent ?? <button type="button" disabled>Food checkout integration pending</button>}</section>;
  if (!resource.data) return <section role="status"><p>{!online ? "You’re offline. Reconnect to load Food menus." : resource.status === "unavailable" ? "Couldn’t load Food menus. Your saved carts are unchanged." : "Opening restaurants and menus…"}</p>
    {online && resource.status === "unavailable" ? <button type="button" onClick={resource.retry}>Retry Food menus</button> : null}</section>;
  const branchId = exploration.view.kind === "restaurant" ? exploration.view.branchId : undefined;
  const menu = resource.data.find(value => value.restaurant.branchId === branchId);
  const item = menu?.categories.flatMap(category => category.items).find(value => value.id === exploration.detailId);
  return <div className="reimagined-food">
    <p className="reimagined-commerce-note">Food preview · Choose your options explicitly. Prices are estimates; checkout is disabled.</p>
    {resource.data.length === 100 ? <p role="status">Showing the first 100 restaurants returned by Dastak. Search covers these loaded menus only.</p> : null}
    <button type="button" disabled={!online} onClick={resource.retry}>Refresh Food menus</button>
    {exploration.detailId ? item && menu ? <section className="reimagined-product-detail" aria-label={`${item.name} dish details`}>
      <button type="button" className="reimagined-detail-close" onClick={() => dispatch({ type: "closeDetail" })}>Back to menu</button>
      <FoodImage name={item.name} imageKey={item.imageKey} supabaseUrl={supabaseUrl} />
      <h2>{item.name}</h2><p>{foodRestaurantName(menu)}</p><p>{item.description}</p><p>Base price: {formatV1Price(item.basePricePaise)}</p><p>{foodAvailability(menu)}</p>
      <FoodChoices key={JSON.stringify([menu.restaurant.branchId, item])} item={item} menu={menu} state={state} dispatch={dispatch} online={online} canEdit={canEdit} />
    </section> : <p role="status">This dish is no longer in the loaded menu. <button type="button" onClick={() => dispatch({ type: "closeDetail" })}>Back to menu</button></p>
      : exploration.view.kind === "restaurant" ? menu ? <><button type="button" onClick={() => dispatch({ type: "navigate", section: "home" })}>Back to restaurants</button>
        <h2>{foodRestaurantName(menu)}</h2><p>{menu.restaurant.description}</p><p>{foodAvailability(menu)}</p>
        {menu.categories.length ? menu.categories.map(category => <DishShelf key={category.id} name={category.name} items={category.items} supabaseUrl={supabaseUrl} dispatch={dispatch} />) : <p>No dishes in this menu yet.</p>}</>
        : <p role="status">This restaurant is not in the loaded catalogue. <button type="button" onClick={() => dispatch({ type: "navigate", section: "home" })}>Back to restaurants</button></p>
      : exploration.view.kind === "search" ? <FoodResults menus={resource.data} query={exploration.view.query} dispatch={dispatch} />
      : <><nav className="reimagined-food-categories" aria-label="Food menu categories">
        <button type="button" aria-pressed={!exploration.foodCategoryFilter} onClick={() => dispatch({ type: "selectFoodCategory" })}>All restaurants</button>
        {categoryControls.map(filter => <button key={filter.label} type="button" aria-label={`Browse Food category ${filter.label}`} aria-pressed={exploration.foodCategoryFilter?.label === filter.label} onClick={() => dispatch({ type: "selectFoodCategory", filter })}>{filter.label}</button>)}
      </nav><section className="reimagined-wooden-shelf" aria-label="Restaurants"><header><h2>{exploration.foodCategoryFilter ? `Restaurants offering ${exploration.foodCategoryFilter.label}` : "Restaurants"}</h2></header>
        {restaurants.length ? <div className="reimagined-shelf-track" tabIndex={0} aria-label="Restaurant shelf">{restaurants.map(value => <article className="reimagined-shelf-product" key={value.restaurant.branchId}>
          <button type="button" className="reimagined-product-open" aria-label={`Open ${foodRestaurantName(value)} menu`} onClick={() => dispatch({ type: "openRestaurant", branchId: value.restaurant.branchId })}>
            <FoodImage name={foodRestaurantName(value)} imageKey={value.restaurant.imageKey} supabaseUrl={supabaseUrl} /><span className="reimagined-product-name">{foodRestaurantName(value)}</span></button><small>{foodAvailability(value)}</small>
        </article>)}</div> : <p>{exploration.foodCategoryFilter ? "No restaurants in the loaded menus currently match this category. Choose All restaurants or refresh the menus." : "No restaurants returned by Dastak yet."}</p>}</section></>}
  </div>;
}

export function ReimaginedFoodSuggestions({ menus, query, dispatch }: { menus?: V1RestaurantMenu[]; query: string; dispatch: Dispatch<ReimaginedAction> }) {
  if (!query.trim()) return <p>Search restaurants or dishes in the loaded Food menus.</p>;
  if (!menus) return <p role="status">Load Food menus to see suggestions.</p>;
  return <FoodResults menus={menus} query={query} dispatch={dispatch} suggestions />;
}

function FoodResults({ menus, query, dispatch, suggestions = false }: { menus: V1RestaurantMenu[]; query: string; dispatch: Dispatch<ReimaginedAction>; suggestions?: boolean }) {
  const results = searchFood(menus, query);
  const open = (menu: V1RestaurantMenu, itemId?: string) => {
    dispatch({ type: "closeSearch" }); dispatch({ type: "openRestaurant", branchId: menu.restaurant.branchId });
    if (itemId) dispatch({ type: "openDetail", id: itemId });
  };
  return <div className="reimagined-grocery-suggestions" aria-label={suggestions ? "Food suggestions" : "Food search results"}>
    {!results.length ? <p>No matches in the loaded Food menus.</p> : (suggestions ? results.slice(0, 8) : results).map(({ menu, dishes }) => <section key={menu.restaurant.branchId}>
      <button type="button" onClick={() => open(menu)}>{foodRestaurantName(menu)}<small>View menu</small></button>
      {(suggestions ? dishes.slice(0, 3) : dishes).map(({ item }) => <button type="button" key={item.id} onClick={() => open(menu, item.id)}>{item.name}<small>{formatV1Price(item.basePricePaise)} base</small></button>)}
    </section>)}
  </div>;
}

function DishShelf({ name, items, dispatch, supabaseUrl }: { name: string; items: V1RestaurantMenuItem[]; dispatch: Dispatch<ReimaginedAction>; supabaseUrl: string }) {
  return <section className="reimagined-wooden-shelf" aria-label={name}><header><h3>{name}</h3></header>{items.length ? <div className="reimagined-shelf-track" tabIndex={0} aria-label={`${name} dish shelf`}>{items.map(item => <article className="reimagined-shelf-product" key={item.id}>
    <button type="button" className="reimagined-product-open" aria-label={`View ${item.name} details`} onClick={() => dispatch({ type: "openDetail", id: item.id })}><FoodImage name={item.name} imageKey={item.imageKey} supabaseUrl={supabaseUrl} /><span className="reimagined-product-name">{item.name}</span></button>
    <p>{formatV1Price(item.basePricePaise)} base</p><small>{item.optionGroups.length ? "Options available in details" : "No customisation options"}</small>
    <button type="button" onClick={() => dispatch({ type: "openDetail", id: item.id })}>Choose dish</button>
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
      {group.options.map(option => <label key={option.id} style={{ display: "block" }}><input type={group.selectionType === "SINGLE" ? "radio" : "checkbox"} name={group.id} checked={optionIds.includes(option.id)} onChange={event => {
        const checked = event.currentTarget.checked;
        setOptionIds(previous => {
          const remaining = previous.filter(id => id !== option.id && (group.selectionType !== "SINGLE" || !group.options.some(value => value.id === id)));
          return checked ? [...remaining, option.id] : remaining;
        });
      }} /> {option.name} · +{formatV1Price(option.priceDeltaPaise)}</label>)}
      {group.selectionType === "SINGLE" && group.minimumSelections === 0 ? <button type="button" onClick={() => setOptionIds(previous => previous.filter(id => !group.options.some(option => option.id === id)))}>Clear {group.name}</button> : null}
    </fieldset>)}
    <p>{formatV1Price(selection.pricePaise)} estimated per dish · In cart: {line?.quantity ?? 0}</p>
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
