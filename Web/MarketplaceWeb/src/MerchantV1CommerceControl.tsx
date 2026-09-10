import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { CirclePause, Plus, ShieldCheck, Store } from "lucide-react";
import { MerchantV1CatalogueControl } from "./MerchantV1CatalogueControl";
import { merchantCommerceKind, type MerchantBranch } from "./merchantBranchContext";
import { MerchantMutationKeys } from "./merchantMutationKeys";
import {
  createVersionedDraft,
  editVersionedDraft,
  reconcileVersionedDraft,
  useLatestVersionedDraft,
  type VersionedDraft,
} from "./restaurantMenuDraft";
import { userFacingError } from "./userFacingError";
import {
  DastakV1RequestError,
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

type Props = {
  auth: DastakV1Auth;
  branch: MerchantBranch;
  onSessionExpired: () => void;
};

export function MerchantV1CommerceControl({ auth, branch, onSessionExpired }: Props) {
  const [restaurant, setRestaurant] = useState<V1RestaurantMenu>();
  const [probing, setProbing] = useState(true);
  const [error, setError] = useState<string>();
  const commerceKind = merchantCommerceKind(branch);
  const isRestaurant = commerceKind === "restaurant";

  useEffect(() => {
    setProbing(true);
    setRestaurant(undefined);
    setError(undefined);
    if (!isRestaurant) {
      setProbing(false);
      return;
    }
    void getV1MerchantRestaurantMenu({ ...auth, branchId: branch.id })
      .then(setRestaurant)
      .catch((requestError: unknown) => {
        if (isSessionError(requestError)) onSessionExpired();
        setError(message(requestError));
      })
      .finally(() => setProbing(false));
  }, [auth, branch.id, isRestaurant, onSessionExpired]);

  if (probing) return <div className="catalogue-loading" role="status"><span /> Opening V1 merchant controls</div>;
  if (!commerceKind) return <section className="merchant-v1-control"><p className="order-error" role="alert">This branch’s Store type is not supported. Dastak has not guessed a catalogue.</p></section>;
  if (isRestaurant) return restaurant
    ? <MerchantV1RestaurantMenuControl auth={auth} branch={branch} onSessionExpired={onSessionExpired} initial={restaurant} />
    : <section className="merchant-v1-control"><p className="order-error" role="alert">{error ?? "Restaurant menu unavailable."}</p></section>;
  return <MerchantV1CatalogueControl auth={auth} branchId={branch.id} onSessionExpired={onSessionExpired} />;
}

function MerchantV1RestaurantMenuControl({ auth, initial, onSessionExpired }: Props & { initial: V1RestaurantMenu }) {
  const [menu, setMenu] = useState(initial);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [categoryName, setCategoryName] = useState("");
  const [itemCategoryId, setItemCategoryId] = useState(initial.categories[0]?.id ?? "");
  const [itemName, setItemName] = useState("");
  const [itemPrice, setItemPrice] = useState("");
  const mutationKeys = useRef(new MerchantMutationKeys());

  const refresh = useCallback(async () => {
    try {
      setMenu(await getV1MerchantRestaurantMenu({ ...auth, branchId: initial.restaurant.branchId }));
      setError(undefined);
      return true;
    } catch (requestError) {
      if (isSessionError(requestError)) onSessionExpired();
      setError(message(requestError));
      return false;
    }
  }, [auth, initial.restaurant.branchId, onSessionExpired]);

  useEffect(() => {
    const reconcile = () => { if (document.visibilityState === "visible") void refresh(); };
    window.addEventListener("focus", reconcile);
    document.addEventListener("visibilitychange", reconcile);
    return () => {
      window.removeEventListener("focus", reconcile);
      document.removeEventListener("visibilitychange", reconcile);
    };
  }, [refresh]);

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
      const idempotencyKey = mutationKeys.current.keyFor(identity, payload);
      const result = await upsertV1RestaurantMenuEntity({
        ...auth,
        branchId: menu.restaurant.branchId,
        entityType,
        entityId,
        expectedVersion,
        payload,
        idempotencyKey,
      });
      setMenu(result.menu);
      mutationKeys.current.clear(identity);
      return true;
    } catch (requestError) {
      if (isSessionError(requestError)) onSessionExpired();
      setError(message(requestError));
      try {
        const authoritative = await getV1MerchantRestaurantMenu({ ...auth, branchId: menu.restaurant.branchId });
        setMenu(authoritative);
        if (menuProvesMutation(authoritative, entityType, entityId, payload)) {
          mutationKeys.current.clear(identity);
          setError(undefined);
          return true;
        }
      } catch {
        // Preserve the logical mutation key until a later retry receives an authoritative result.
      }
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
      if (isSessionError(requestError)) onSessionExpired();
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
    <header className="merchant-orders-heading"><div><p className="eyebrow">STORE &amp; MENU</p><h1>{menu.restaurant.name}</h1><p>{menu.restaurant.branchName}</p></div></header>
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

type ItemDraftValue = { name: string; description: string; price: string };

function RestaurantItemEditor({ item, categoryId, busy, save }: {
  item: V1RestaurantMenuItem; categoryId: string; busy: boolean; save: Save;
}) {
  const serverValue = useMemo(() => ({
    name: item.name,
    description: item.description ?? "",
    price: String(item.basePricePaise / 100),
  }), [item.basePricePaise, item.description, item.name]);
  const [draft, setDraft] = useState<VersionedDraft<ItemDraftValue>>(() => createVersionedDraft(serverValue, item.version));
  useEffect(() => setDraft((current) => reconcileVersionedDraft(current, serverValue, item.version)), [item.version, serverValue]);
  const [groupName, setGroupName] = useState("");
  const [groupType, setGroupType] = useState<"SINGLE" | "MULTIPLE">("SINGLE");
  const [groupMax, setGroupMax] = useState(1);
  const updateItem = (status = item.status) => {
    if (draft.stale) return;
    const basePricePaise = Math.round(Number(draft.value.price) * 100);
    if (!draft.value.name.trim() || !Number.isSafeInteger(basePricePaise) || basePricePaise < 1) return;
    void save(`item:${item.id}`, "ITEM", item.id, draft.loadedVersion, {
      categoryId, name: draft.value.name.trim(), description: draft.value.description.trim(), imageKey: item.imageKey ?? "",
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
  return <article className={`merchant-v1-menu-item ${draft.stale ? "stale-draft" : ""}`}><div className="merchant-v1-menu-item-fields">
    {draft.stale ? <p className="merchant-v1-draft-warning" role="status"><span>Newer server changes are available. Your draft was not overwritten.</span><button className="secondary-button" type="button" onClick={() => setDraft(useLatestVersionedDraft)}>Use latest</button></p> : null}
    <input value={draft.value.name} maxLength={160} disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, name: event.target.value }))} aria-label="Menu item name" /><input value={draft.value.description} maxLength={1000} disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, description: event.target.value }))} aria-label="Menu item description" placeholder="Description" /><label><span>Price ₹</span><input value={draft.value.price} inputMode="decimal" disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, price: event.target.value }))} /></label><div><button className="primary-button" type="button" disabled={busy || draft.stale || !draft.dirty} onClick={() => updateItem()}>Save</button><button className="secondary-button" type="button" disabled={busy || draft.stale} onClick={() => updateItem(item.status === "ACTIVE" ? "INACTIVE" : "ACTIVE")}>{item.status === "ACTIVE" ? "Mark unavailable" : "Activate"}</button></div></div>
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
  const serverValue = useMemo(() => ({ name: option.name, price: String(option.priceDeltaPaise / 100) }), [option.name, option.priceDeltaPaise]);
  const [draft, setDraft] = useState<VersionedDraft<typeof serverValue>>(() => createVersionedDraft(serverValue, option.version));
  useEffect(() => setDraft((current) => reconcileVersionedDraft(current, serverValue, option.version)), [option.version, serverValue]);
  const update = (status = option.status) => {
    if (draft.stale) return;
    const priceDeltaPaise = Math.round(Number(draft.value.price) * 100);
    if (!draft.value.name.trim() || !Number.isSafeInteger(priceDeltaPaise) || priceDeltaPaise < 0) return;
    void save(`option:${option.id}`, "OPTION", option.id, draft.loadedVersion, {
      optionGroupId: groupId, name: draft.value.name.trim(), priceDeltaPaise,
      sortOrder: option.sortOrder, status,
    });
  };
  return <div className={`merchant-v1-option-row ${draft.stale ? "stale-draft" : ""}`}>{draft.stale ? <p className="merchant-v1-draft-warning" role="status"><span>Newer server version available.</span><button className="secondary-button" type="button" onClick={() => setDraft(useLatestVersionedDraft)}>Use latest</button></p> : null}<input value={draft.value.name} maxLength={100} disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, name: event.target.value }))} aria-label="Option name" /><input value={draft.value.price} inputMode="decimal" disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, price: event.target.value }))} aria-label="Option price in rupees" /><span>{formatV1Price(option.priceDeltaPaise)}</span><button className="secondary-button" type="button" disabled={busy || draft.stale || !draft.dirty} onClick={() => update()}>Save</button><button className="secondary-button" type="button" disabled={busy || draft.stale} onClick={() => update(option.status === "ACTIVE" ? "INACTIVE" : "ACTIVE")}>{option.status === "ACTIVE" ? "Hide" : "Activate"}</button></div>;
}

function menuProvesMutation(menu: V1RestaurantMenu, entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION", entityId: string | undefined, payload: Record<string, unknown>) {
  const categories = menu.categories;
  const items = categories.flatMap((category) => category.items);
  const groups = items.flatMap((item) => item.optionGroups);
  const options = groups.flatMap((group) => group.options);
  const candidates = entityType === "CATEGORY" ? categories : entityType === "ITEM" ? items : entityType === "OPTION_GROUP" ? groups : options;
  return candidates.some((candidate) => {
    if (entityId && candidate.id !== entityId) return false;
    return menuEntityMatchesPayload(candidate as unknown as Record<string, unknown>, entityType, payload);
  });
}

function menuEntityMatchesPayload(candidate: Record<string, unknown>, entityType: "CATEGORY" | "ITEM" | "OPTION_GROUP" | "OPTION", payload: Record<string, unknown>) {
  const comparableKeys = entityType === "CATEGORY"
    ? ["name", "description", "sortOrder", "status"]
    : entityType === "ITEM"
      ? ["name", "description", "imageKey", "basePricePaise", "taxRateBps", "logisticsAttributes", "status"]
      : entityType === "OPTION_GROUP"
        ? ["name", "selectionType", "minimumSelections", "maximumSelections", "sortOrder", "status"]
        : ["name", "priceDeltaPaise", "sortOrder", "status"];
  return comparableKeys.every((key) => payload[key] === undefined || JSON.stringify(candidate[key]) === JSON.stringify(payload[key]));
}

function isSessionError(error: unknown) {
  return error instanceof DastakV1RequestError && (error.status === 401 || error.code === "authentication_required");
}

function message(error: unknown) {
  return userFacingError(error, "Restaurant menu control is unavailable.");
}
