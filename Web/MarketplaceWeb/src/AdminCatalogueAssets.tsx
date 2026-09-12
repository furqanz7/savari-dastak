import { useCallback, useEffect, useMemo, useState } from "react";
import { BadgeCheck, CircleAlert, ImagePlus, LoaderCircle, ShieldCheck, Star, Trash2 } from "lucide-react";
import { AdminPrivilegedActionDialog, type AdminPrivilegedActionIntent } from "./AdminPrivilegedActionDialog";
import { runAdminPrivilegedMutation } from "./adminPrivilegedMutation";
import { catalogueImageUrl } from "./catalogue";
import {
  DastakV1RequestError,
  getV1AdminCatalogueAssets,
  promoteV1AdminCataloguePrimary,
  removeV1AdminCatalogueAsset,
  uploadV1AdminCatalogueAsset,
  type DastakV1Auth,
  type V1AdminCatalogueAsset,
  type V1AdminCatalogueAssets,
  type V1AdminCataloguePageSku,
} from "./dastakV1";
import { validateDecodableImage } from "./imageValidation";
import { userFacingError } from "./userFacingError";

const sourceTypes = [
  ["MANUFACTURER", "Manufacturer"],
  ["BRAND", "Brand owner"],
  ["AUTHORIZED_RETAILER", "Authorized retailer"],
  ["DISTRIBUTOR", "Distributor"],
  ["OWNER_CAPTURE", "Dastak-owned capture"],
  ["COMMODITY_STOCK", "Approved stock image"],
  ["OTHER", "Other reviewed source"],
] as const;

const governanceReasons = [
  "Correct inaccurate product imagery",
  "Improve exact-SKU identification",
  "Replace low-quality imagery",
  "Rights or provenance correction",
  "Catalogue launch readiness",
  "Other",
] as const;

type Intent = {
  dialog: AdminPrivilegedActionIntent;
  identity: string;
  mutate: (key: string, reason: string) => Promise<unknown>;
  success: string;
  clearUpload?: boolean;
};

export function AdminCatalogueAssets({
  auth,
  sku,
  onCatalogueChanged,
}: {
  auth: DastakV1Auth;
  sku: V1AdminCataloguePageSku;
  onCatalogueChanged: () => Promise<void>;
}) {
  const [snapshot, setSnapshot] = useState<V1AdminCatalogueAssets>();
  const [loading, setLoading] = useState(true);
  const [accessDenied, setAccessDenied] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [intent, setIntent] = useState<Intent>();
  const [reconciliationBlocked, setReconciliationBlocked] = useState(false);
  const [file, setFile] = useState<File>();
  const [sourceType, setSourceType] = useState("MANUFACTURER");
  const [sourceReference, setSourceReference] = useState("");

  const load = useCallback(async (signal?: AbortSignal) => {
    const next = await getV1AdminCatalogueAssets({ ...auth, skuId: sku.id, signal });
    setSnapshot(next);
    setAccessDenied(false);
    return next;
  }, [auth, sku.id]);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    void load(controller.signal).catch((cause) => {
      if (controller.signal.aborted) return;
      if (cause instanceof DastakV1RequestError && cause.code === "access_denied") {
        setAccessDenied(true);
      } else {
        setError(userFacingError(cause, "Catalogue assets could not be loaded."));
      }
    }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [load]);

  const reconcile = useCallback(async () => {
    await Promise.all([load(), onCatalogueChanged()]);
  }, [load, onCatalogueChanged]);

  const primary = useMemo(() => snapshot?.assets.find((asset) => asset.role === "PRIMARY"), [snapshot]);

  const chooseUpload = async (selected?: File) => {
    setError(undefined);
    if (!selected) { setFile(undefined); return; }
    if (!await validateDecodableImage(selected, 5 * 1024 * 1024) || !["image/jpeg", "image/png", "image/webp"].includes(selected.type)) {
      setFile(undefined);
      setError("Choose a genuine JPG, PNG or WebP image up to 5 MB.");
      return;
    }
    setFile(selected);
  };

  const prepareUpload = () => {
    if (!snapshot || !file || sourceReference.trim().length < 3) {
      setError("Choose an image and record its reviewed source or rights reference.");
      return;
    }
    setIntent({
      identity: `catalogue-asset:add:${sku.id}:${snapshot.sku.assetVersion}:${file.name}:${file.size}:${file.lastModified}`,
      success: "The verified image was added to this exact SKU as a gallery asset.",
      clearUpload: true,
      dialog: {
        eyebrow: "Catalogue asset governance",
        title: "Add this image to the exact SKU?",
        entityLabel: "Canonical SKU",
        entityValue: `${sku.name} · ${sku.packSize} · ${sku.id}`,
        currentState: `${snapshot.assets.length} governed asset${snapshot.assets.length === 1 ? "" : "s"}`,
        resultingState: "Verified gallery asset added",
        consequence: "Dastak will verify the image bytes, bind a server-generated object path to this exact SKU, and record source provenance. Product identity, pricing, pack and taxonomy will not change.",
        confirmLabel: "Verify and add image",
        reasonOptions: governanceReasons,
      },
      mutate: (idempotencyKey, reason) => uploadV1AdminCatalogueAsset({
        ...auth,
        skuId: sku.id,
        expectedAssetVersion: snapshot.sku.assetVersion,
        file,
        sourceType,
        sourceReference,
        reason,
        idempotencyKey,
      }),
    });
  };

  const preparePromotion = (asset: V1AdminCatalogueAsset) => {
    if (!snapshot) return;
    setIntent({
      identity: `catalogue-asset:primary:${sku.id}:${snapshot.sku.assetVersion}:${asset.id}:${primary?.id ?? "none"}`,
      success: "The primary image was replaced atomically and authoritative catalogue state was refreshed.",
      dialog: {
        eyebrow: "Primary image governance",
        title: "Make this the primary image?",
        entityLabel: "Canonical SKU",
        entityValue: `${sku.name} · ${sku.packSize} · ${sku.id}`,
        currentState: primary ? `Primary asset ${primary.id}` : "No primary image",
        resultingState: `Primary asset ${asset.id}`,
        consequence: "The current primary image will remain safely associated as a gallery asset. The verified replacement becomes primary in one serialized database transaction; the SKU cannot be left without one valid primary image.",
        confirmLabel: "Replace primary image",
        reasonOptions: governanceReasons,
      },
      mutate: (idempotencyKey, reason) => promoteV1AdminCataloguePrimary({
        ...auth,
        skuId: sku.id,
        assetId: asset.id,
        expectedPrimaryAssetId: primary?.id,
        expectedAssetVersion: snapshot.sku.assetVersion,
        reason,
        idempotencyKey,
      }),
    });
  };

  const prepareRemoval = (asset: V1AdminCatalogueAsset) => {
    if (!snapshot || asset.role === "PRIMARY" || !asset.canRemove) return;
    setIntent({
      identity: `catalogue-asset:remove:${sku.id}:${snapshot.sku.assetVersion}:${asset.id}`,
      success: "The unused asset association and governed storage object were removed.",
      dialog: {
        eyebrow: "Catalogue asset governance",
        title: "Remove this unused image?",
        entityLabel: "Canonical SKU",
        entityValue: `${sku.name} · ${sku.packSize} · ${sku.id}`,
        currentState: `Gallery asset ${asset.id}`,
        resultingState: "Asset removed",
        consequence: "This removes only the reviewed non-primary asset and its exact governed storage object. The current primary image and all product facts remain unchanged.",
        confirmLabel: "Remove unused image",
        tone: "danger",
        reasonOptions: governanceReasons,
      },
      mutate: (idempotencyKey, reason) => removeV1AdminCatalogueAsset({
        ...auth,
        skuId: sku.id,
        assetId: asset.id,
        expectedAssetVersion: snapshot.sku.assetVersion,
        reason,
        idempotencyKey,
      }),
    });
  };

  const confirm = async (reason: string) => {
    if (!intent || busy) return;
    setBusy(true); setError(undefined); setNotice(undefined); setReconciliationBlocked(false);
    const currentIntent = intent;
    const result = await runAdminPrivilegedMutation({
      operationIdentity: intent.identity,
      mutate: (key) => intent.mutate(key, reason),
      reconcile,
    });
    setBusy(false);
    if (result.kind === "completed") {
      setNotice(currentIntent.success);
      if (currentIntent.clearUpload) { setFile(undefined); setSourceReference(""); }
      setIntent(undefined);
    } else if (result.kind === "reconciled" || result.kind === "uncertain_reconciled") {
      setNotice(result.message);
      if (result.kind === "reconciled") setIntent(undefined);
    } else if (result.kind === "uncertain_blocked") {
      setReconciliationBlocked(true); setError(result.message);
    } else {
      setError(userFacingError(result.error, "The catalogue asset action could not be completed."));
    }
  };

  if (accessDenied) return null;
  return <section className="admin-catalogue-assets" aria-labelledby={`assets-${sku.id}`}>
    <header>
      <span><ShieldCheck size={19} /></span>
      <div><strong id={`assets-${sku.id}`}>Governed imagery</strong><small>Verified media bound to this exact canonical SKU</small></div>
      {snapshot ? <b>Asset version {snapshot.sku.assetVersion}</b> : null}
    </header>
    {loading ? <p className="admin-asset-loading" role="status"><LoaderCircle size={17} /> Loading governed assets…</p> : null}
    {error ? <p className="order-error" role="alert"><CircleAlert size={16} /> {error}</p> : null}
    {notice ? <p className="v1-admin-notice" role="status"><BadgeCheck size={16} /> {notice}</p> : null}
    {snapshot ? <>
      <div className="admin-asset-grid">
        {snapshot.assets.map((asset) => <article key={`${asset.id}:${asset.version}`} className={asset.role === "PRIMARY" ? "primary" : ""}>
          <div className="admin-asset-image"><img src={catalogueImageUrl(auth.supabaseUrl, asset.imageKey) ?? undefined} alt={`${sku.name} ${asset.role === "PRIMARY" ? "primary" : "gallery"} asset`} /></div>
          <div className="admin-asset-copy">
            <div><strong>{asset.role === "PRIMARY" ? <><Star size={14} /> Primary image</> : "Gallery image"}</strong><span className={`v1-admin-status ${asset.status === "VERIFIED" ? "active" : "inactive"}`}>{asset.status.toLowerCase()}</span></div>
            <small>{asset.widthPixels && asset.heightPixels ? `${asset.widthPixels} × ${asset.heightPixels}` : "Awaiting byte verification"} · {asset.sourceType.replaceAll("_", " ").toLowerCase()}</small>
            <code>{asset.id}</code>
            <nav aria-label={`Actions for asset ${asset.id}`}>
              {asset.role !== "PRIMARY" && asset.status === "VERIFIED" && asset.rightsStatus === "CLEARED" ? <button type="button" className="secondary-button" disabled={busy} onClick={() => preparePromotion(asset)}><Star size={15} /> Make primary</button> : null}
              {asset.canRemove ? <button type="button" className="secondary-button destructive" disabled={busy} onClick={() => prepareRemoval(asset)}><Trash2 size={15} /> Remove</button> : null}
            </nav>
          </div>
        </article>)}
        {snapshot.assets.length === 0 ? <div className="admin-asset-empty"><ImagePlus size={22} /><strong>No governed imagery</strong><span>Add a verified gallery image, then promote it safely.</span></div> : null}
      </div>
      <div className="admin-asset-upload">
        <div><ImagePlus size={18} /><span><strong>Add exact-SKU image</strong><small>JPG, PNG or WebP · maximum 5 MB</small></span></div>
        <label><span>Image file</span><input type="file" accept="image/jpeg,image/png,image/webp" disabled={busy} onChange={(event) => void chooseUpload(event.target.files?.[0])} /></label>
        <label><span>Reviewed source type</span><select value={sourceType} disabled={busy} onChange={(event) => setSourceType(event.target.value)}>{sourceTypes.map(([value, title]) => <option key={value} value={value}>{title}</option>)}</select></label>
        <label className="wide"><span>Source / rights reference</span><input value={sourceReference} maxLength={500} disabled={busy} onChange={(event) => setSourceReference(event.target.value)} placeholder="Manufacturer page, licence, capture record or reviewed provenance" /></label>
        <button type="button" className="primary-button" disabled={busy || !file || sourceReference.trim().length < 3} onClick={prepareUpload}>Verify and add image</button>
      </div>
    </> : null}
    {intent ? <AdminPrivilegedActionDialog
      intent={intent.dialog}
      busy={busy}
      error={error}
      notice={notice}
      reconciliationBlocked={reconciliationBlocked}
      onConfirm={confirm}
      onDismiss={() => { if (!busy) { setIntent(undefined); setError(undefined); } }}
      onReconcile={async () => {
        setBusy(true);
        try { await reconcile(); setReconciliationBlocked(false); setNotice("Authoritative asset state was refreshed."); }
        catch (cause) { setError(userFacingError(cause, "Asset state could not be reconciled.")); }
        finally { setBusy(false); }
      }}
    /> : null}
  </section>;
}
