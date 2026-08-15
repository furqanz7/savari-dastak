import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  Clock3,
  FileCheck2,
  FileUp,
  LockKeyhole,
  MapPin,
  RefreshCw,
  ShieldCheck,
  Store,
  WifiOff,
  X,
} from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { ApplicationProgress } from "./ApplicationProgress";
import {
  isAcceptedEvidenceFile,
  getMerchantApplicationSnapshot,
  type MerchantApplicationSnapshot,
  MerchantApplicationRequestError,
  submitMerchantApplication,
  uploadMerchantEvidence,
} from "./merchant-application";

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
  const [businessAddress, setBusinessAddress] = useState("");
  const [evidenceFile, setEvidenceFile] = useState<File>();
  const [uploadedEvidence, setUploadedEvidence] = useState<{ file: File; path: string }>();
  const [snapshot, setSnapshot] = useState<MerchantApplicationSnapshot>();
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState<string>();
  const [submitError, setSubmitError] = useState<string>();
  const submissionKey = useRef<string | undefined>(undefined);

  const valid = businessName.trim().length >= 1 && businessName.trim().length <= 120
    && businessAddress.trim().length >= 1 && businessAddress.trim().length <= 300
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
      if (nextSnapshot.businessName) setBusinessName(nextSnapshot.businessName);
      if (nextSnapshot.businessAddress) setBusinessAddress(nextSnapshot.businessAddress);
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

  const refresh = async () => {
    setRefreshing(true);
    const loaded = await loadSnapshot();
    if (loaded) onSubmitted();
    setRefreshing(false);
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || !evidenceFile) return;
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
        businessName,
        businessAddress,
        evidenceObjectPath,
        idempotencyKey: submissionKey.current,
      });
      setSnapshot({
        onboardingState: "pending",
        applicationId: result.applicationId,
        businessName: businessName.trim(),
        businessAddress: businessAddress.trim(),
        evidenceObjectPath,
        reviewReason: null,
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
        <span className="application-heading-icon"><Icon size={25} /></span>
        <div className="merchant-state-copy">
          <p className="eyebrow">{state.eyebrow}</p>
          <h1>{state.title}</h1>
          <p>{state.message}</p>
        </div>
        {(presentation === "pending" || presentation === "approved") && <ApplicationProgress current={3} />}
        {snapshot?.businessName && (
          <div className="merchant-application-summary">
            <small>Store</small>
            <strong>{snapshot.businessName}</strong>
            {snapshot.businessAddress && <span>{snapshot.businessAddress}</span>}
          </div>
        )}
        <button className="primary-button application-submit" type="button" disabled={refreshing} onClick={refresh}>
          <RefreshCw size={17} className={refreshing ? "spin" : undefined} />
          {refreshing ? "Checking status" : state.action}
        </button>
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

      <section className="application-section" aria-labelledby="merchant-store-title">
        <header>
          <span className="application-section-icon"><Store size={18} /></span>
          <div><h2 id="merchant-store-title">Store details</h2><p>Use the public name and complete trading address.</p></div>
        </header>
        <label>
          <span className="application-field-label">
            Business name <small>{businessName.length}/120</small>
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
        action: "Check status",
      };
    case "approved":
      return {
        icon: CheckCircle2,
        eyebrow: "Approved",
        title: "Your merchant access is ready",
        message: "Refresh access to open your store workspace.",
        action: "Open merchant workspace",
      };
    case "suspended":
      return {
        icon: ShieldCheck,
        eyebrow: "Access paused",
        title: "Merchant access is suspended",
        message: "Your store workspace is unavailable while this account is being reviewed.",
        action: "Check access",
      };
    case "failure":
      return {
        icon: WifiOff,
        eyebrow: "Connection issue",
        title: "We couldn't check your application",
        message: error ?? "Try again when your connection is stable.",
        action: "Try again",
      };
  }
}
