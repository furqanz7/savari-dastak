import { useCallback, useEffect, useState, type FormEvent } from "react";
import { CirclePause, Plus, RefreshCw, ShieldCheck, Store } from "lucide-react";
import { MerchantV1CatalogueControl } from "./MerchantV1CatalogueControl";
import { userFacingError } from "./userFacingError";
import {
  formatV1Price,
  getV1MerchantRestaurantMenu,
  updateV1MerchantBranchState,
  upsertV1RestaurantMenuEntity,
  type DastakV1Auth,
  type V1RestaurantMenu,
  type V1RestaurantMenuItem,
  type V1RestaurantMenuOption,
  type V1RestaurantMenuOptionGroup,
} from "./dastakV1";

type Props = { auth: DastakV1Auth };

export function MerchantV1CommerceControl({ auth }: Props) {
  const [restaurant, setRestaurant] = useState<V1RestaurantMenu>();
  const [probing, setProbing] = useState(true);

  useEffect(() => {
    void getV1MerchantRestaurantMenu(auth)
      .then(setRestaurant)
      .catch(() => undefined)
      .finally(() => setProbing(false));
  }, [auth]);

  if (probing) return <div className="catalogue-loading" role="status"><span /> Opening V1 merchant controls</div>;
  return restaurant
    ? <MerchantV1RestaurantMenuControl auth={auth} initial={restaurant} />
    : <MerchantV1CatalogueControl auth={auth} />;
}

function MerchantV1RestaurantMenuControl({ auth, initial }: Props & { initial: V1RestaurantMenu }) {
  const [menu, setMenu] = useState(initial);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [categoryName, setCategoryName] = useState("");
  const [itemCategoryId, setItemCategoryId] = useState(initial.categories[0]?.id ?? "");
  const [itemName, setItemName] = useState("");
  const [itemPrice, setItemPrice] = useState("");

  const refresh = useCallback(async () => {
    try {
      setMenu(await getV1MerchantRestaurantMenu(auth));
      setError(undefined);
    } catch (requestError) {
      setError(message(requestError));
    }
  }, [auth]);

  const save = async (
    identity: string,
    entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION",
    entityId: string | undefined,
    expectedVersion: number,
    payload: Record<string, unknown>,
  ) => {
    if (busy) return false;
    setBusy(identity);
    setError(undefined);
    try {
      const result = await upsertV1RestaurantMenuEntity({
        ...auth,
        branchId: menu.restaurant.branchId,
        entityType,
        entityId,
        expectedVersion,
        payload,
        idempotencyKey: crypto.randomUUID(),
      });
      setMenu(result.menu);
      return true;
    } catch (requestError) {
      setError(message(requestError));
      await refresh();
      return false;
    } finally {
      setBusy(undefined);
    }
  };

  const setOperation = async (isOpen: boolean, acceptingOrders: boolean) => {
    if (busy) return;
    setBusy("branch");
    setError(undefined);
    try {
      await updateV1MerchantBranchState({
        ...auth,
        branchId: menu.restaurant.branchId,
        isOpen,
        acceptingOrders,
        expectedVersion: menu.restaurant.operationalVersion,
        idempotencyKey: crypto.randomUUID(),
      });
      await refresh();
    } catch (requestError) {
      setError(message(requestError));
      await refresh();
    } finally {
      setBusy(undefined);
    }
  };

  const createCategory = async (event: FormEvent) => {
    event.preventDefault();
    const name = categoryName.trim();
    if (!name) return;
    if (await save("new-category", "CATEGORY", undefined, 0, {
      name, description: "", sortOrder: menu.categories.length, status: "ACTIVE",
    })) setCategoryName("");
  };

  const createItem = async (event: FormEvent) => {
    event.preventDefault();
    const price = Math.round(Number(itemPrice) * 100);
    if (!itemCategoryId || !itemName.trim() || !Number.isSafeInteger(price) || price < 1) return;
    if (await save("new-item", "ITEM", undefined, 0, {
      categoryId: itemCategoryId,
      name: itemName.trim(), description: "", imageKey: "", basePricePaise: price,
      taxRateBps: 0, logisticsAttributes: {}, status: "ACTIVE",
    })) {
      setItemName("");
      setItemPrice("");
    }
  };

  return <section className="merchant-v1-control merchant-v1-menu-control">
    <header className="merchant-orders-heading"><div><p className="eyebrow">V1 Restaurant / Cafe</p><h1>{menu.restaurant.name}</h1><p>{menu.restaurant.branchName}</p></div><button className="icon-button" type="button" disabled={Boolean(busy)} onClick={() => void refresh()} aria-label="Refresh menu"><RefreshCw size={18} /></button></header>
    {error ? <p className="order-error" role="alert">{error}</p> : null}
    <div className="merchant-v1-operation-grid">
      <article><Store size={19} /><span><strong>{menu.restaurant.isOpen ? "Restaurant open" : "Restaurant closed"}</strong><small>Existing paid commitments continue</small></span><button className="secondary-button" type="button" disabled={Boolean(busy)} onClick={() => void setOperation(!menu.restaurant.isOpen, false)}>{menu.restaurant.isOpen ? "Close" : "Open"}</button></article>
      <article><CirclePause size={19} /><span><strong>{menu.restaurant.acceptingOrders ? "Accepting new food orders" : "New food orders paused"}</strong><small>Confirmation remains direct—no rerouting</small></span><button className="secondary-button" type="button" disabled={Boolean(busy)} onClick={() => void setOperation(true, !menu.restaurant.acceptingOrders)}>{menu.restaurant.acceptingOrders ? "Pause" : "Accept"}</button></article>
      <article><ShieldCheck size={19} /><span><strong>{menu.restaurant.activeOrderCount} active orders</strong><small>Soft threshold {menu.restaurant.softActiveOrderThreshold}; never a hard cutoff</small></span><b>Live</b></article>
    </div>
    <div className="merchant-v1-canonical-note"><ShieldCheck size={18} /><span><strong>Restaurant-owned menu</strong><small>Manage exact food, prices, availability and options. Confirmed customer selections are immutable snapshots.</small></span></div>
    <div className="merchant-v1-menu-create">
      <form onSubmit={(event) => void createCategory(event)}><strong>New menu category</strong><input value={categoryName} maxLength={100} onChange={(event) => setCategoryName(event.target.value)} placeholder="Breakfast" /><button className="primary-button" disabled={Boolean(busy) || !categoryName.trim()}><Plus size={16} /> Add category</button></form>
      <form onSubmit={(event) => void createItem(event)}><strong>New menu item</strong><select value={itemCategoryId} onChange={(event) => setItemCategoryId(event.target.value)} required><option value="">Choose category</option>{menu.categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select><input value={itemName} maxLength={160} onChange={(event) => setItemName(event.target.value)} placeholder="Item name" required /><input value={itemPrice} inputMode="decimal" onChange={(event) => setItemPrice(event.target.value)} placeholder="Price ₹" required /><button className="primary-button" disabled={Boolean(busy)}><Plus size={16} /> Add item</button></form>
    </div>
    <div className="merchant-v1-menu-list">{menu.categories.map((category) => <section key={category.id}>
      <header><div><strong>{category.name}</strong><small>{category.items.length} items · {category.status.toLowerCase()}</small></div><button className="secondary-button" type="button" disabled={Boolean(busy)} onClick={() => void save(`category:${category.id}`, "CATEGORY", category.id, category.version, { name: category.name, description: category.description ?? "", sortOrder: category.sortOrder, status: category.status === "ACTIVE" ? "INACTIVE" : "ACTIVE" })}>{category.status === "ACTIVE" ? "Hide" : "Activate"}</button></header>
      <div>{category.items.map((item) => <RestaurantItemEditor key={item.id} item={item} categoryId={category.id} busy={Boolean(busy)} save={save} />)}</div>
    </section>)}</div>
  </section>;
}

type Save = (
  identity: string,
  entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION",
  entityId: string | undefined,
  expectedVersion: number,
  payload: Record<string, unknown>,
) => Promise<boolean>;

function RestaurantItemEditor({ item, categoryId, busy, save }: {
  item: V1RestaurantMenuItem; categoryId: string; busy: boolean; save: Save;
}) {
  const [name, setName] = useState(item.name);
  const [description, setDescription] = useState(item.description ?? "");
  const [price, setPrice] = useState(String(item.basePricePaise / 100));
  const [groupName, setGroupName] = useState("");
  const [groupType, setGroupType] = useState<"SINGLE" | "MULTIPLE">("SINGLE");
  const [groupMax, setGroupMax] = useState(1);
  const updateItem = (status = item.status) => {
    const basePricePaise = Math.round(Number(price) * 100);
    if (!name.trim() || !Number.isSafeInteger(basePricePaise) || basePricePaise < 1) return;
    void save(`item:${item.id}`, "ITEM", item.id, item.version, {
      categoryId, name: name.trim(), description: description.trim(), imageKey: item.imageKey ?? "",
      basePricePaise, taxRateBps: item.taxRateBps,
      logisticsAttributes: item.logisticsAttributes, status,
    });
  };
  const createGroup = async (event: FormEvent) => {
    event.preventDefault();
    if (!groupName.trim()) return;
    if (await save(`group:new:${item.id}`, "OPTION_GROUP", undefined, 0, {
      menuItemId: item.id, name: groupName.trim(), selectionType: groupType,
      minimumSelections: 0, maximumSelections: groupType === "SINGLE" ? 1 : groupMax,
      sortOrder: item.optionGroups.length, status: "ACTIVE",
    })) setGroupName("");
  };
  return <article className="merchant-v1-menu-item"><div className="merchant-v1-menu-item-fields"><input value={name} maxLength={160} onChange={(event) => setName(event.target.value)} aria-label="Menu item name" /><input value={description} maxLength={1000} onChange={(event) => setDescription(event.target.value)} aria-label="Menu item description" placeholder="Description" /><label><span>Price ₹</span><input value={price} inputMode="decimal" onChange={(event) => setPrice(event.target.value)} /></label><div><button className="primary-button" type="button" disabled={busy} onClick={() => updateItem()}>Save</button><button className="secondary-button" type="button" disabled={busy} onClick={() => updateItem(item.status === "ACTIVE" ? "INACTIVE" : "ACTIVE")}>{item.status === "ACTIVE" ? "Mark unavailable" : "Activate"}</button></div></div>
    {item.optionGroups.map((group) => <RestaurantOptionGroupEditor key={group.id} group={group} itemId={item.id} busy={busy} save={save} />)}
    <form className="merchant-v1-option-create" onSubmit={(event) => void createGroup(event)}><strong>Add variant / add-on group</strong><input value={groupName} maxLength={100} onChange={(event) => setGroupName(event.target.value)} placeholder="Size or extras" /><select value={groupType} onChange={(event) => setGroupType(event.target.value as "SINGLE" | "MULTIPLE")}><option value="SINGLE">Choose one</option><option value="MULTIPLE">Choose multiple</option></select>{groupType === "MULTIPLE" ? <input type="number" min={1} max={20} value={groupMax} onChange={(event) => setGroupMax(Number(event.target.value))} aria-label="Maximum selections" /> : null}<button className="secondary-button" disabled={busy || !groupName.trim()}><Plus size={15} /> Add group</button></form>
  </article>;
}

function RestaurantOptionGroupEditor({ group, itemId, busy, save }: {
  group: V1RestaurantMenuOptionGroup; itemId: string; busy: boolean; save: Save;
}) {
  const [name, setName] = useState("");
  const [price, setPrice] = useState("0");
  const create = async (event: FormEvent) => {
    event.preventDefault();
    const priceDeltaPaise = Math.round(Number(price) * 100);
    if (!name.trim() || !Number.isSafeInteger(priceDeltaPaise) || priceDeltaPaise < 0) return;
    if (await save(`option:new:${group.id}`, "OPTION", undefined, 0, {
      optionGroupId: group.id, name: name.trim(), priceDeltaPaise,
      sortOrder: group.options.length, status: "ACTIVE",
    })) { setName(""); setPrice("0"); }
  };
  return <div className="merchant-v1-option-group"><header><span><strong>{group.name}</strong><small>{group.selectionType.toLowerCase()} · {group.minimumSelections}–{group.maximumSelections}</small></span><button className="secondary-button" type="button" disabled={busy} onClick={() => void save(`group:${group.id}`, "OPTION_GROUP", group.id, group.version, { menuItemId: itemId, name: group.name, selectionType: group.selectionType, minimumSelections: group.minimumSelections, maximumSelections: group.maximumSelections, sortOrder: group.sortOrder, status: group.status === "ACTIVE" ? "INACTIVE" : "ACTIVE" })}>{group.status === "ACTIVE" ? "Hide group" : "Activate"}</button></header>
    {group.options.map((option) => <RestaurantOptionEditor key={option.id} option={option} groupId={group.id} busy={busy} save={save} />)}
    <form onSubmit={(event) => void create(event)}><input value={name} maxLength={100} onChange={(event) => setName(event.target.value)} placeholder="Option name" /><input value={price} inputMode="decimal" onChange={(event) => setPrice(event.target.value)} aria-label="Option price in rupees" /><button className="secondary-button" disabled={busy || !name.trim()}><Plus size={15} /> Add option</button></form>
  </div>;
}

function RestaurantOptionEditor({ option, groupId, busy, save }: {
  option: V1RestaurantMenuOption; groupId: string; busy: boolean; save: Save;
}) {
  const [name, setName] = useState(option.name);
  const [price, setPrice] = useState(String(option.priceDeltaPaise / 100));
  const update = (status = option.status) => {
    const priceDeltaPaise = Math.round(Number(price) * 100);
    if (!name.trim() || !Number.isSafeInteger(priceDeltaPaise) || priceDeltaPaise < 0) return;
    void save(`option:${option.id}`, "OPTION", option.id, option.version, {
      optionGroupId: groupId, name: name.trim(), priceDeltaPaise,
      sortOrder: option.sortOrder, status,
    });
  };
  return <div className="merchant-v1-option-row"><input value={name} maxLength={100} onChange={(event) => setName(event.target.value)} aria-label="Option name" /><input value={price} inputMode="decimal" onChange={(event) => setPrice(event.target.value)} aria-label="Option price in rupees" /><span>{formatV1Price(option.priceDeltaPaise)}</span><button className="secondary-button" type="button" disabled={busy} onClick={() => update()}>Save</button><button className="secondary-button" type="button" disabled={busy} onClick={() => update(option.status === "ACTIVE" ? "INACTIVE" : "ACTIVE")}>{option.status === "ACTIVE" ? "Hide" : "Activate"}</button></div>;
}

function message(error: unknown) {
  return userFacingError(error, "Restaurant menu control is unavailable.");
}
