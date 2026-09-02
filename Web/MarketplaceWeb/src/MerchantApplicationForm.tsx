import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  FileCheck2,
  FileUp,
  LockKeyhole,
  MapPin,
  ShoppingBasket,
  ShieldCheck,
  Store,
  UtensilsCrossed,
  WifiOff,
  X,
} from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { ApplicationProgress } from "./ApplicationProgress";
import {
  isAcceptedEvidenceFile,
  getMerchantApplicationSnapshot,
  type MerchantApplicationSnapshot,
  type MerchantType,
  MerchantApplicationRequestError,
  submitMerchantApplication,
  uploadMerchantEvidence,
} from "./merchant-application";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import { usePullToRefresh } from "./usePullToRefresh";

type Props = {
  accessState: "denied" | "pending" | "suspended";
  client: SupabaseClient;
  session: Session;
  supabaseUrl: string;
  publishableKey: string;
  onSubmitted: () => void;
  onSessionExpired: () => void;
};

type Presentation = "loading" | "application" | "pending" | "approved" | "suspended" | "failure";

export function MerchantApplicationForm({
  accessState,
  client,
  session,
  supabaseUrl,
  publishableKey,
  onSubmitted,
  onSessionExpired,
}: Props) {
  const [businessName, setBusinessName] = useState("");
  const [legalName, setLegalName] = useState("");
  const [merchantType, setMerchantType] = useState<MerchantType>();
  const [businessAddress, setBusinessAddress] = useState("");
  const [storeLocation, setStoreLocation] = useState<SelectedPlace>();
  const [evidenceFile, setEvidenceFile] = useState<File>();
  const [uploadedEvidence, setUploadedEvidence] = useState<{ file: File; path: string }>();
  const [snapshot, setSnapshot] = useState<MerchantApplicationSnapshot>();
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string>();
  const [submitError, setSubmitError] = useState<string>();
  const submissionKey = useRef<string | undefined>(undefined);

  const valid = !!merchantType
    && legalName.trim().length >= 1 && legalName.trim().length <= 160
    && businessName.trim().length >= 1 && businessName.trim().length <= 120
    && businessAddress.trim().length >= 1 && businessAddress.trim().length <= 300
    && !!storeLocation
    && !!evidenceFile && isAcceptedEvidenceFile(evidenceFile) && !loading;

  const loadSnapshot = useCallback(async () => {
    setLoadError(undefined);
    try {
      const nextSnapshot = await getMerchantApplicationSnapshot({
        supabaseUrl,
        publishableKey,
        accessToken: session.access_token,
      });
      setSnapshot(nextSnapshot);
      if (nextSnapshot.merchantType) setMerchantType(nextSnapshot.merchantType);
      if (nextSnapshot.legalName) setLegalName(nextSnapshot.legalName);
      if (nextSnapshot.businessName) setBusinessName(nextSnapshot.businessName);
      if (nextSnapshot.businessAddress) setBusinessAddress(nextSnapshot.businessAddress);
      if (nextSnapshot.businessAddress && nextSnapshot.latitude !== null && nextSnapshot.longitude !== null) {
        setStoreLocation({
          address: nextSnapshot.businessAddress,
          latitude: nextSnapshot.latitude,
          longitude: nextSnapshot.longitude,
        });
      }
      return true;
    } catch (loadError) {
      if (loadError instanceof MerchantApplicationRequestError && loadError.status === 401) {
        onSessionExpired();
        return false;
      }
      setLoadError(loadError instanceof Error
        ? loadError.message
        : "We could not check your merchant application. Try again.");
      return false;
    } finally {
      setLoading(false);
    }
  }, [onSessionExpired, publishableKey, session.access_token, supabaseUrl]);

  useEffect(() => {
    void loadSnapshot();
  }, [loadSnapshot]);

  const presentation: Presentation = accessState === "suspended"
    ? "suspended"
    : loading
      ? "loading"
      : accessState === "pending" || snapshot?.onboardingState === "pending"
        ? "pending"
        : loadError
          ? "failure"
          : snapshot?.onboardingState === "approved"
            ? "approved"
            : "application";

  const refresh = useCallback(async () => {
    const loaded = await loadSnapshot();
    if (loaded) onSubmitted();
  }, [loadSnapshot, onSubmitted]);
  const pull = usePullToRefresh(refresh, presentation !== "application");

  useEffect(() => {
    if (presentation === "application" || presentation === "loading") return;
    const interval = window.setInterval(() => { void refresh(); }, 20_000);
    const becameVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", becameVisible);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", becameVisible);
    };
  }, [presentation, refresh]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || !evidenceFile || !merchantType || !storeLocation) return;
    setBusy(true);
    setSubmitError(undefined);
    try {
      const evidenceObjectPath = uploadedEvidence?.file === evidenceFile
        ? uploadedEvidence.path
        : await uploadMerchantEvidence(client, session.user.id, evidenceFile);
      setUploadedEvidence({ file: evidenceFile, path: evidenceObjectPath });
      submissionKey.current ??= crypto.randomUUID();
      const result = await submitMerchantApplication({
        supabaseUrl,
        publishableKey,
        accessToken: session.access_token,
        merchantType,
        legalName,
        businessName,
        businessAddress,
        latitude: storeLocation.latitude,
        longitude: storeLocation.longitude,
        evidenceObjectPath,
        idempotencyKey: submissionKey.current,
      });
      setSnapshot({
        onboardingState: "pending",
        applicationId: result.applicationId,
        merchantType,
        legalName: legalName.trim(),
        businessName: businessName.trim(),
        businessAddress: businessAddress.trim(),
        latitude: storeLocation.latitude,
        longitude: storeLocation.longitude,
        serviceZoneId: result.serviceZoneId,
        serviceZoneName: result.serviceZoneName,
        evidenceObjectPath,
        reviewReason: null,
        organizationId: null,
        branchId: null,
      });
      submissionKey.current = undefined;
      onSubmitted();
    } catch (submissionError) {
      setSubmitError(submissionError instanceof Error
        ? submissionError.message
        : "The merchant application could not be submitted.");
      setBusy(false);
    }
  };

  if (presentation === "loading") {
    return (
      <section className="merchant-access-state merchant-access-loading" role="status">
        <span className="merchant-state-spinner" />
        <p>Checking your merchant application</p>
      </section>
    );
  }

  if (presentation !== "application") {
    const state = merchantStatusCopy(presentation, loadError);
    const Icon = state.icon;
    return (
      <section className="merchant-access-state">
        <div className={`application-pull-indicator ${pull.refreshing ? "refreshing" : ""}`} style={{ opacity: pull.distance > 0 || pull.refreshing ? 1 : 0 }} aria-live="polite">
          {pull.refreshing ? "Checking your application…" : pull.progress >= 1 ? "Release to check" : "Pull down to check status"}
        </div>
        <span className="application-heading-icon"><Icon size={25} /></span>
        <div className="merchant-state-copy">
          <p className="eyebrow">{state.eyebrow}</p>
          <h1>{state.title}</h1>
          <p>{state.message}</p>
        </div>
        {(presentation === "pending" || presentation === "approved") && <ApplicationProgress current={3} />}
        {snapshot?.businessName && (
          <div className="merchant-application-summary">
            <small>{snapshot.merchantType === "RESTAURANT_CAFE" ? "Restaurant / Cafe" : "Retail store"}</small>
            <strong>{snapshot.businessName}</strong>
            {snapshot.businessAddress && <span>{snapshot.businessAddress}</span>}
            {snapshot.serviceZoneName && <span className="application-zone"><MapPin size={14} /> {snapshot.serviceZoneName}</span>}
          </div>
        )}
        <p className="application-refresh-hint">Pull down on mobile to check now. This page also checks automatically.</p>
      </section>
    );
  }

  const rejected = snapshot?.onboardingState === "rejected";
  return (
    <form className="application-onboarding merchant-application-panel" onSubmit={submit}>
      <header className="application-heading application-heading-compact">
        <p className="eyebrow">{rejected ? "Application update" : "Merchant registration"}</p>
        <h1>{rejected ? "Update your store application" : "Bring your store to Dastak"}</h1>
        <p>{rejected
          ? "Make the requested changes and send the application back for review."
          : "Add the store customers know, then verify that you own or operate it."}</p>
      </header>

      <ApplicationProgress />

      {snapshot?.reviewReason && (
        <aside className="application-review-note" role="status">
          <AlertTriangle size={19} />
          <div><strong>Changes requested</strong><p>{snapshot.reviewReason}</p></div>
        </aside>
      )}

      <section className="application-section" aria-labelledby="merchant-type-title">
        <header>
          <span className="application-section-icon"><Store size={18} /></span>
          <div><h2 id="merchant-type-title">Business type</h2><p>This selects the correct Dastak catalogue and order tools.</p></div>
        </header>
        <div className="merchant-type-grid" role="radiogroup" aria-label="Business type">
          <button type="button" role="radio" aria-checked={merchantType === "RESTAURANT_CAFE"} className={merchantType === "RESTAURANT_CAFE" ? "selected" : ""} onClick={() => { setMerchantType("RESTAURANT_CAFE"); submissionKey.current = undefined; setSubmitError(undefined); }}>
            <span><UtensilsCrossed size={22} /></span><strong>Restaurant or cafe</strong><small>Build menus, items, options and food availability.</small>
          </button>
          <button type="button" role="radio" aria-checked={merchantType === "RETAIL"} className={merchantType === "RETAIL" ? "selected" : ""} onClick={() => { setMerchantType("RETAIL"); submissionKey.current = undefined; setSubmitError(undefined); }}>
            <span><ShoppingBasket size={22} /></span><strong>Retail store</strong><small>Select exact products from Dastak's canonical catalogue.</small>
          </button>
        </div>
      </section>

      <section className="application-section" aria-labelledby="merchant-store-title">
        <header>
          <span className="application-section-icon"><Store size={18} /></span>
          <div><h2 id="merchant-store-title">Business and branch</h2><p>Tell Admin who operates it and what customers should see.</p></div>
        </header>
        <label>
          <span className="application-field-label">Legal business name <small>{legalName.length}/160</small></span>
          <input autoComplete="organization" maxLength={160} value={legalName} placeholder="Name on registration or identity document" onChange={(event) => { setLegalName(event.target.value); submissionKey.current = undefined; setSubmitError(undefined); }} />
          <small className="application-field-help">Used for verification and never substituted for the public store name.</small>
        </label>
        <label>
          <span className="application-field-label">
            Customer-facing name <small>{businessName.length}/120</small>
          </span>
          <input
            autoComplete="organization"
            maxLength={120}
            value={businessName}
            placeholder="Store name"
            onChange={(event) => {
              setBusinessName(event.target.value);
              submissionKey.current = undefined;
              setSubmitError(undefined);
            }}
          />
        </label>
        <label>
          <span className="application-field-label">
            Business address <small>{businessAddress.length}/300</small>
          </span>
          <span className="application-input-icon"><MapPin size={18} /></span>
          <textarea
            autoComplete="street-address"
            maxLength={300}
            rows={4}
            value={businessAddress}
            placeholder="Shop number, street, area and city"
            onChange={(event) => {
              setBusinessAddress(event.target.value);
              submissionKey.current = undefined;
              setSubmitError(undefined);
            }}
          />
        </label>
      </section>

      <section className="application-section" aria-labelledby="merchant-location-title">
        <header>
          <span className="application-section-icon"><MapPin size={18} /></span>
          <div><h2 id="merchant-location-title">Exact store location</h2><p>Required to connect this branch to the correct Dastak service area.</p></div>
        </header>
        <LocationSearchField label="Store location" value={storeLocation} disabled={busy} onSelectionCleared={() => {
          setStoreLocation(undefined);
          submissionKey.current = undefined;
          setSubmitError(undefined);
        }} onChange={(place) => {
          setStoreLocation(place);
          if (!businessAddress.trim()) setBusinessAddress(place.address.slice(0, 300));
          submissionKey.current = undefined;
          setSubmitError(undefined);
        }} />
        {storeLocation && <div className="application-location-confirmed"><CheckCircle2 size={17} /><span><strong>Store pin selected</strong><small>Admin will verify this location and service area before approval.</small></span></div>}
      </section>

      <section className="application-section" aria-labelledby="merchant-document-title">
        <header>
          <span className="application-section-icon"><ShieldCheck size={18} /></span>
          <div><h2 id="merchant-document-title">Store verification</h2><p>Government identity or business registration document.</p></div>
        </header>
        <label className={`application-file-picker ${evidenceFile ? "selected" : ""}`}>
          <input
            type="file"
            accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
            onChange={(event) => {
              setEvidenceFile(event.target.files?.[0]);
              setUploadedEvidence(undefined);
              submissionKey.current = undefined;
              setSubmitError(undefined);
            }}
          />
          <span>{evidenceFile ? <FileCheck2 size={23} /> : <FileUp size={23} />}</span>
          <span><strong>{evidenceFile?.name ?? "Choose a document"}</strong><small>{evidenceFile ? "Select to replace" : "PDF, JPG or PNG, up to 10 MB"}</small></span>
          <span className="application-file-status">{evidenceFile ? <CheckCircle2 size={19} /> : null}</span>
        </label>
        {evidenceFile && (
          <button
            className="application-remove-file"
            type="button"
            onClick={() => {
              setEvidenceFile(undefined);
              setUploadedEvidence(undefined);
              submissionKey.current = undefined;
              setSubmitError(undefined);
            }}
          >
            <X size={15} /> Remove document
          </button>
        )}
        <p className="application-privacy"><LockKeyhole size={14} /> Private and used only for merchant verification.</p>
      </section>

      {evidenceFile && !isAcceptedEvidenceFile(evidenceFile) && (
        <p className="error-text" role="alert">Choose a supported file up to 10 MB.</p>
      )}
      {submitError && (
        <aside className="application-error" role="alert">
          <AlertTriangle size={18} /><div><strong>Application not sent</strong><p>{submitError}</p></div>
        </aside>
      )}
      <button className="primary-button application-submit" disabled={!valid || busy} type="submit">
        {busy ? "Submitting application" : rejected ? "Resubmit for review" : "Submit for review"}
      </button>
    </form>
  );
}

function merchantStatusCopy(presentation: Exclude<Presentation, "loading" | "application">, error?: string) {
  switch (presentation) {
    case "pending":
      return {
        icon: Clock3,
        eyebrow: "Application received",
        title: "Your store is under review",
        message: "We'll unlock the merchant workspace as soon as the application is approved.",
      };
    case "approved":
      return {
        icon: CheckCircle2,
        eyebrow: "Approved",
        title: "Your merchant access is ready",
        message: "Your store workspace will open automatically.",
      };
    case "suspended":
      return {
        icon: ShieldCheck,
        eyebrow: "Access paused",
        title: "Merchant access is suspended",
        message: "Your store workspace is unavailable while this account is being reviewed.",
      };
    case "failure":
      return {
        icon: WifiOff,
        eyebrow: "Connection issue",
        title: "We couldn't check your application",
        message: error ?? "Try again when your connection is stable.",
      };
  }
}
