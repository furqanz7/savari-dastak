import { useEffect, useRef, useState, type FormEvent } from "react";
import { Bike, FileCheck2, FileUp, Navigation, ShieldCheck } from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { ApplicationProgress } from "./ApplicationProgress";
import {
  DeliveryRequestError,
  getDeliveryPartnerSnapshot,
  isAcceptedPartnerEvidence,
  submitDeliveryPartnerApplication,
  uploadPartnerEvidence,
  type DeliveryMethod,
} from "./delivery";

type Props = {
  client: SupabaseClient;
  session: Session;
  supabaseUrl: string;
  publishableKey: string;
  onSubmitted: () => void;
  onSessionExpired: () => void;
};

export function DeliveryPartnerApplicationForm({
  client,
  session,
  supabaseUrl,
  publishableKey,
  onSubmitted,
  onSessionExpired,
}: Props) {
  const [deliveryMethod, setDeliveryMethod] = useState<DeliveryMethod>("bike");
  const [evidenceFile, setEvidenceFile] = useState<File>();
  const [uploadedEvidence, setUploadedEvidence] = useState<{ file: File; path: string }>();
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();
  const [reviewReason, setReviewReason] = useState<string>();
  const requestKey = useRef(crypto.randomUUID());
  const valid = !!evidenceFile && isAcceptedPartnerEvidence(evidenceFile) && !loading;

  useEffect(() => {
    let active = true;
    void getDeliveryPartnerSnapshot({
      supabaseUrl,
      publishableKey,
      accessToken: session.access_token,
    }).then((snapshot) => {
      if (!active || snapshot.onboardingState !== "rejected") return;
      if (snapshot.deliveryMethod) setDeliveryMethod(snapshot.deliveryMethod);
      setReviewReason(snapshot.reviewReason ?? undefined);
    }).catch((loadError) => {
      if (!active) return;
      if (loadError instanceof DeliveryRequestError && loadError.status === 401) {
        onSessionExpired();
        return;
      }
      setError(loadError instanceof Error ? loadError.message : "The application could not be loaded.");
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
  }, [onSessionExpired, publishableKey, session.access_token, supabaseUrl]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || !evidenceFile) return;
    setBusy(true);
    setError(undefined);
    try {
      const identityEvidenceObjectPath = uploadedEvidence?.file === evidenceFile
        ? uploadedEvidence.path
        : await uploadPartnerEvidence(client, session.user.id, evidenceFile);
      setUploadedEvidence({ file: evidenceFile, path: identityEvidenceObjectPath });
      await submitDeliveryPartnerApplication({
        supabaseUrl,
        publishableKey,
        accessToken: session.access_token,
        deliveryMethod,
        identityEvidenceObjectPath,
        idempotencyKey: requestKey.current,
      });
      onSubmitted();
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "The application could not be submitted.");
      setBusy(false);
    }
  };

  return (
    <form className="application-onboarding delivery-application-panel" onSubmit={submit}>
      <header className="application-heading">
        <span className="application-heading-icon"><Bike size={24} /></span>
        <div><p className="eyebrow">Delivery Partner</p><h1>Deliver with Dastak</h1><p>Choose how you travel and provide one identity document for owner review.</p></div>
      </header>

      <ApplicationProgress />

      {reviewReason && <aside className="application-review-note" role="status">
        <ShieldCheck size={19} />
        <div><strong>Update requested</strong><p>{reviewReason}</p></div>
      </aside>}

      <section className="application-section" aria-labelledby="partner-method-title">
        <header><Navigation size={20} /><div><h2 id="partner-method-title">Delivery method</h2><p>Choose the method you will actively use.</p></div></header>
        <label>
          Travel method
          <select value={deliveryMethod} onChange={(event) => setDeliveryMethod(event.target.value as DeliveryMethod)}>
            <option value="walking">Walking</option>
            <option value="bicycle">Bicycle</option>
            <option value="bike">Bike</option>
            <option value="auto">Auto</option>
            <option value="car">Car</option>
          </select>
        </label>
      </section>

      <section className="application-section" aria-labelledby="partner-document-title">
        <header><ShieldCheck size={20} /><div><h2 id="partner-document-title">Identity proof</h2><p>Upload one clear document that belongs to you.</p></div></header>
        <label className="application-file-picker">
          <input
            type="file"
            accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
            onChange={(event) => {
              setEvidenceFile(event.target.files?.[0]);
              setUploadedEvidence(undefined);
              requestKey.current = crypto.randomUUID();
            }}
          />
          <span>{evidenceFile ? <FileCheck2 size={23} /> : <FileUp size={23} />}</span>
          <span><strong>{evidenceFile?.name ?? "Choose a document"}</strong><small>PDF, JPG or PNG, up to 10 MB</small></span>
        </label>
      </section>

      {evidenceFile && !isAcceptedPartnerEvidence(evidenceFile) && (
        <p className="error-text" role="alert">Choose a supported file up to 10 MB.</p>
      )}
      {error && <p className="error-text" role="alert">{error}</p>}
      <button className="primary-button application-submit" disabled={!valid || busy} type="submit">
        {loading ? "Loading details..." : busy ? "Submitting..." : reviewReason ? "Resubmit for review" : "Submit for review"}
      </button>
      <p className="application-privacy"><ShieldCheck size={15} /> Your document is private and used only to review this application.</p>
    </form>
  );
}
