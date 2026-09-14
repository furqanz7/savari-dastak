import { useCallback, useDeferredValue, useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Camera, CirclePause, ImagePlus, Plus, Search, ShieldCheck, Store } from "lucide-react";
import { catalogueImageUrl } from "./catalogue";
import { CustomerEmptyState, CustomerNotice, CustomerSkeleton } from "./CustomerUI";
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
import { validateDecodableImage } from "./imageValidation";
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
  uploadV1GovernedMedia,
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

  if (probing) return <CustomerSkeleton label="Opening your Store" kind="orders" />;
  if (!commerceKind) return <section className="merchant-v1-control"><CustomerNotice title="Store unavailable">This branch’s Store type is not supported. Contact Dastak to check its setup.</CustomerNotice></section>;
  if (isRestaurant) return restaurant
    ? <MerchantV1RestaurantMenuControl auth={auth} branch={branch} onSessionExpired={onSessionExpired} initial={restaurant} />
    : <section className="merchant-v1-control"><CustomerNotice title="Menu couldn’t load">{error ?? "Restaurant menu unavailable."}</CustomerNotice></section>;
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
  const [menuQuery, setMenuQuery] = useState("");
  const query = useDeferredValue(menuQuery.trim().toLowerCase());
  const visibleCategories = menu.categories.map((category) => ({ ...category, items: category.items.filter((item) => !query || `${category.name} ${item.name} ${item.description ?? ""}`.toLowerCase().includes(query)) })).filter((category) => !query || category.items.length > 0);
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

  const uploadMedia = async (
    entityType: "RESTAURANT_BRANCH_BANNER" | "RESTAURANT_MENU_ITEM",
    entityId: string,
    expectedMediaVersion: number,
    file: File,
  ) => {
    const identity = `media:${entityType}:${entityId}`;
    if (busy) return false;
    if (!await validateDecodableImage(file, 5 * 1024 * 1024) || !["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      setError("Choose a genuine JPG, PNG or WebP image up to 5 MB.");
      return false;
    }
    const keyPayload = { entityType, entityId, expectedMediaVersion, name: file.name, size: file.size, modified: file.lastModified };
    setBusy(identity);
    setError(undefined);
    try {
      await uploadV1GovernedMedia({
        ...auth, entityType, entityId, expectedMediaVersion, file,
        sourceReference: `Merchant-owned image: ${file.name}`,
        reason: entityType === "RESTAURANT_BRANCH_BANNER" ? "Update restaurant banner" : "Update dish image",
        idempotencyKey: mutationKeys.current.keyFor(identity, keyPayload),
      });
      const authoritative = await getV1MerchantRestaurantMenu({ ...auth, branchId: menu.restaurant.branchId });
      setMenu(authoritative);
      mutationKeys.current.clear(identity);
      return true;
    } catch (requestError) {
      if (isSessionError(requestError)) onSessionExpired();
      setError(message(requestError));
      try {
        const authoritative = await getV1MerchantRestaurantMenu({ ...auth, branchId: menu.restaurant.branchId });
        setMenu(authoritative);
        const nextVersion = entityType === "RESTAURANT_BRANCH_BANNER"
          ? authoritative.restaurant.mediaVersion
          : authoritative.categories.flatMap((category) => category.items).find((item) => item.id === entityId)?.mediaVersion;
        if ((nextVersion ?? expectedMediaVersion) > expectedMediaVersion) {
          mutationKeys.current.clear(identity);
          setError(undefined);
          return true;
        }
      } catch {
        // Keep the same logical key until authoritative state resolves the uncertain upload.
      }
      return false;
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
    <header className="merchant-orders-heading"><div><p className="eyebrow">YOUR KITCHEN</p><h1>{menu.restaurant.name}</h1><p>Your menu, made easy to manage.</p></div></header>
    {error ? <CustomerNotice title="Menu update needs attention" onRetry={() => void refresh()}>{error}</CustomerNotice> : null}
    <RestaurantMediaPicker
      className="merchant-restaurant-banner"
      title="Restaurant banner"
      copy="Shown at the top of your Dastak restaurant and menu. Use a clear, landscape photo without text."
      imageKey={menu.restaurant.imageKey}
      supabaseUrl={auth.supabaseUrl}
      busy={Boolean(busy)}
      onChoose={(file) => uploadMedia("RESTAURANT_BRANCH_BANNER", menu.restaurant.branchId, menu.restaurant.mediaVersion ?? 1, file)}
    />
    <div className="merchant-v1-operation-grid">
      <article><Store size={19} /><span><strong>{menu.restaurant.isOpen ? "Restaurant open" : "Restaurant closed"}</strong><small>Existing confirmed orders continue</small></span><button className="secondary-button" type="button" disabled={Boolean(busy)} onClick={() => void setOperation(!menu.restaurant.isOpen, false)}>{menu.restaurant.isOpen ? "Close" : "Open"}</button></article>
      <article><CirclePause size={19} /><span><strong>{menu.restaurant.acceptingOrders ? "Accepting food orders" : "New food orders paused"}</strong><small>Choose when your kitchen takes new requests</small></span><button className="secondary-button" type="button" disabled={Boolean(busy)} onClick={() => void setOperation(true, !menu.restaurant.acceptingOrders)}>{menu.restaurant.acceptingOrders ? "Pause" : "Resume"}</button></article>
      <article><ShieldCheck size={19} /><span><strong>{menu.restaurant.activeOrderCount} active orders</strong><small>Soft threshold {menu.restaurant.softActiveOrderThreshold}; never a hard cutoff</small></span><b>Live</b></article>
    </div>
    <div className="merchant-v1-canonical-note"><ShieldCheck size={18} /><span><strong>Your menu, your craft.</strong><small>Manage dishes, prices and options. Changes apply to future orders; confirmed selections stay protected.</small></span></div>
    <div className="merchant-v1-catalogue-tools"><label><Search size={18} aria-hidden="true" /><input type="search" value={menuQuery} onChange={(event) => setMenuQuery(event.target.value)} aria-label="Search your menu" placeholder="Find a dish or category" /></label></div>
    <details className="merchant-menu-options merchant-menu-create-disclosure"><summary>Add to your menu</summary>
    <div className="merchant-v1-menu-create">
      <form onSubmit={(event) => void createCategory(event)}><strong>New category</strong><label>Category name<input value={categoryName} maxLength={100} onChange={(event) => setCategoryName(event.target.value)} placeholder="Breakfast" /></label><button className="primary-button" disabled={Boolean(busy) || !categoryName.trim()}><Plus size={16} /> Add category</button></form>
      <form onSubmit={(event) => void createItem(event)}><strong>New dish</strong><label>Category<select value={itemCategoryId} onChange={(event) => setItemCategoryId(event.target.value)} required><option value="">Choose category</option>{menu.categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label><label>Item name<input value={itemName} maxLength={160} onChange={(event) => setItemName(event.target.value)} placeholder="What’s cooking?" required /></label><label>Price in rupees<input value={itemPrice} inputMode="decimal" onChange={(event) => setItemPrice(event.target.value)} placeholder="₹ 0.00" required /></label><button className="primary-button" disabled={Boolean(busy)}><Plus size={16} /> Add item</button></form>
    </div>
    </details>
    {visibleCategories.length === 0 ? <CustomerEmptyState title={query ? "No matching dishes" : "Make this menu yours"} copy={query ? "Try another dish or category name." : "Add your first category and dish using “Add to your menu” above."} /> : null}
    <div className="merchant-v1-menu-list">{menu.categories.map((category) => <section key={category.id} hidden={!visibleCategories.some((visible) => visible.id === category.id)}>
      <header><div><strong>{category.name}</strong><small>{category.items.length} items · {category.status.toLowerCase()}</small></div><button className="secondary-button" type="button" disabled={Boolean(busy)} onClick={() => void save(`category:${category.id}`, "CATEGORY", category.id, category.version, { name: category.name, description: category.description ?? "", sortOrder: category.sortOrder, status: category.status === "ACTIVE" ? "INACTIVE" : "ACTIVE" })}>{category.status === "ACTIVE" ? "Hide" : "Activate"}</button></header>
      <div>{category.items.map((item) => <div key={item.id} hidden={!visibleCategories.find((visible) => visible.id === category.id)?.items.some((visible) => visible.id === item.id)}><RestaurantItemEditor item={item} categoryId={category.id} supabaseUrl={auth.supabaseUrl} busy={Boolean(busy)} save={save} uploadMedia={uploadMedia} /></div>)}</div>
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

function RestaurantItemEditor({ item, categoryId, supabaseUrl, busy, save, uploadMedia }: {
  item: V1RestaurantMenuItem; categoryId: string; supabaseUrl: string; busy: boolean; save: Save;
  uploadMedia: (entityType: "RESTAURANT_MENU_ITEM", entityId: string, expectedMediaVersion: number, file: File) => Promise<boolean>;
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
  return <article className={`merchant-v1-menu-item ${draft.stale ? "stale-draft" : ""}`}>
    <RestaurantMediaPicker
      className="merchant-dish-photo"
      title="Dish photo"
      copy="Optional. A clear photo helps customers recognise this dish."
      imageKey={item.imageKey}
      supabaseUrl={supabaseUrl}
      busy={busy || draft.stale}
      onChoose={(file) => uploadMedia("RESTAURANT_MENU_ITEM", item.id, item.mediaVersion ?? 1, file)}
    />
    <div className="merchant-v1-menu-item-fields">
    {draft.stale ? <p className="merchant-v1-draft-warning" role="status"><span>Newer server changes are available. Your draft was not overwritten.</span><button className="secondary-button" type="button" onClick={() => setDraft(useLatestVersionedDraft)}>Use latest</button></p> : null}
    <label>Item name<input value={draft.value.name} maxLength={160} disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, name: event.target.value }))} aria-label="Menu item name" /></label>
    <label><span>Price ₹</span><input value={draft.value.price} inputMode="decimal" disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, price: event.target.value }))} /></label>
    <label className="merchant-menu-description">Description<input value={draft.value.description} maxLength={1000} disabled={draft.stale} onChange={(event) => setDraft((current) => editVersionedDraft(current, { ...current.value, description: event.target.value }))} aria-label="Menu item description" placeholder="A little about this dish" /></label>
    <div><button className="primary-button" type="button" disabled={busy || draft.stale || !draft.dirty} onClick={() => updateItem()}>Save changes</button><button className="secondary-button" type="button" disabled={busy || draft.stale} onClick={() => updateItem(item.status === "ACTIVE" ? "INACTIVE" : "ACTIVE")}>{item.status === "ACTIVE" ? "Mark unavailable" : "Activate"}</button></div></div>
    <details className="merchant-menu-options"><summary><span>Customer choices &amp; extras<small>Sizes, flavours, preparation choices or paid extras</small></span><b>{item.optionGroups.length} {item.optionGroups.length === 1 ? "group" : "groups"}</b></summary>
    {item.optionGroups.map((group) => <RestaurantOptionGroupEditor key={group.id} group={group} itemId={item.id} busy={busy} save={save} />)}
    <form className="merchant-v1-option-create" onSubmit={(event) => void createGroup(event)}><strong>Add a customer choice</strong><p>Example: “Choose a size” with Small, Medium and Large; or “Add extras” with Cheese and Sauce.</p><label>Choice name<input value={groupName} maxLength={100} onChange={(event) => setGroupName(event.target.value)} placeholder="Choose a size" /></label><label>How customers choose<select value={groupType} onChange={(event) => setGroupType(event.target.value as "SINGLE" | "MULTIPLE")}><option value="SINGLE">One option</option><option value="MULTIPLE">One or more options</option></select></label>{groupType === "MULTIPLE" ? <label>Maximum options<input type="number" min={1} max={20} value={groupMax} onChange={(event) => setGroupMax(Number(event.target.value))} /></label> : null}<button className="secondary-button" disabled={busy || !groupName.trim()}><Plus size={15} /> Add choice group</button></form>
    </details>
  </article>;
}

function RestaurantMediaPicker({ className, title, copy, imageKey, supabaseUrl, busy, onChoose }: {
  className: string; title: string; copy: string; imageKey?: string; supabaseUrl: string; busy: boolean;
  onChoose: (file: File) => Promise<boolean>;
}) {
  const [uploading, setUploading] = useState(false);
  const source = catalogueImageUrl(supabaseUrl, imageKey ?? null);
  return <section className={`merchant-media-picker ${className}`}>
    <div className="merchant-media-preview">{source ? <img src={source} alt="" /> : <Camera size={28} aria-hidden="true" />}</div>
    <span><strong>{title}</strong><small>{copy}</small></span>
    <label className="secondary-button" aria-disabled={busy || uploading}>
      <ImagePlus size={17} aria-hidden="true" /> {uploading ? "Uploading…" : source ? "Replace photo" : "Add photo"}
      <input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy || uploading} onChange={(event) => {
        const file = event.target.files?.[0];
        event.currentTarget.value = "";
        if (!file) return;
        setUploading(true);
        void onChoose(file).finally(() => setUploading(false));
      }} />
    </label>
  </section>;
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
    <form onSubmit={(event) => void create(event)}><label>Option name<input value={name} maxLength={100} onChange={(event) => setName(event.target.value)} placeholder="Option name" /></label><label>Additional price ₹<input value={price} inputMode="decimal" onChange={(event) => setPrice(event.target.value)} /></label><button className="secondary-button" disabled={busy || !name.trim()}><Plus size={15} /> Add option</button></form>
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
