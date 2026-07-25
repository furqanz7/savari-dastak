import { useRef, useState, type FormEvent } from "react";
import { Bike } from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import {
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
};

export function DeliveryPartnerApplicationForm({
  client,
  session,
  supabaseUrl,
  publishableKey,
  onSubmitted,
}: Props) {
  const [deliveryMethod, setDeliveryMethod] = useState<DeliveryMethod>("bike");
  const [evidenceFile, setEvidenceFile] = useState<File>();
  const [uploadedEvidence, setUploadedEvidence] = useState<{ file: File; path: string }>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const requestKey = useRef(crypto.randomUUID());
  const valid = !!evidenceFile && isAcceptedPartnerEvidence(evidenceFile);

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
    <form className="form-panel" onSubmit={submit}>
      <div className="section-icon"><Bike size={22} /></div>
      <p className="eyebrow">Delivery Partner</p>
      <h1>Apply to deliver</h1>
      <label>
        Delivery method
        <select value={deliveryMethod} onChange={(event) => setDeliveryMethod(event.target.value as DeliveryMethod)}>
          <option value="walking">Walking</option>
          <option value="bicycle">Bicycle</option>
          <option value="bike">Bike</option>
          <option value="auto">Auto</option>
          <option value="car">Car</option>
        </select>
      </label>
      <label>
        Identity proof
        <input
          className="file-input"
          type="file"
          accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
          onChange={(event) => {
            setEvidenceFile(event.target.files?.[0]);
            setUploadedEvidence(undefined);
            requestKey.current = crypto.randomUUID();
          }}
        />
      </label>
      <small>PDF, JPG or PNG, up to 10 MB.</small>
      {evidenceFile && !isAcceptedPartnerEvidence(evidenceFile) && (
        <p className="error-text" role="alert">Choose a supported file up to 10 MB.</p>
      )}
      {error && <p className="error-text" role="alert">{error}</p>}
      <button className="primary-button" disabled={!valid || busy} type="submit">
        {busy ? "Submitting..." : "Submit for review"}
      </button>
    </form>
  );
}
