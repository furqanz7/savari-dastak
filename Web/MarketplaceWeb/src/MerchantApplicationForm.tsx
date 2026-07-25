import { useState, type FormEvent } from "react";
import { Store } from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import {
  isAcceptedEvidenceFile,
  submitMerchantApplication,
  uploadMerchantEvidence,
} from "./merchant-application";

type Props = {
  client: SupabaseClient;
  session: Session;
  supabaseUrl: string;
  publishableKey: string;
  onSubmitted: () => void;
};

export function MerchantApplicationForm({
  client,
  session,
  supabaseUrl,
  publishableKey,
  onSubmitted,
}: Props) {
  const [businessName, setBusinessName] = useState("");
  const [businessAddress, setBusinessAddress] = useState("");
  const [evidenceFile, setEvidenceFile] = useState<File>();
  const [uploadedEvidence, setUploadedEvidence] = useState<{ file: File; path: string }>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const valid = businessName.trim().length >= 1 && businessName.trim().length <= 120 &&
    businessAddress.trim().length >= 1 && businessAddress.trim().length <= 300 &&
    !!evidenceFile && isAcceptedEvidenceFile(evidenceFile);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || !evidenceFile) return;
    setBusy(true);
    setError(undefined);
    try {
      const evidenceObjectPath = uploadedEvidence?.file === evidenceFile
        ? uploadedEvidence.path
        : await uploadMerchantEvidence(client, session.user.id, evidenceFile);
      setUploadedEvidence({ file: evidenceFile, path: evidenceObjectPath });
      await submitMerchantApplication({
        supabaseUrl,
        publishableKey,
        accessToken: session.access_token,
        businessName,
        businessAddress,
        evidenceObjectPath,
        idempotencyKey: crypto.randomUUID(),
      });
      onSubmitted();
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "The merchant application could not be submitted.");
      setBusy(false);
    }
  };

  return (
    <form className="form-panel merchant-application-panel" onSubmit={submit}>
      <div className="section-icon"><Store size={22} /></div>
      <p className="eyebrow">Merchant registration</p>
      <h1>Apply to sell</h1>
      <label>
        Business name
        <input
          autoComplete="organization"
          maxLength={120}
          value={businessName}
          onChange={(event) => setBusinessName(event.target.value)}
        />
      </label>
      <label>
        Business address
        <textarea
          autoComplete="street-address"
          maxLength={300}
          rows={4}
          value={businessAddress}
          onChange={(event) => setBusinessAddress(event.target.value)}
        />
      </label>
      <label>
        Business registration or identity proof
        <input
          className="file-input"
          type="file"
          accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
          onChange={(event) => {
            setEvidenceFile(event.target.files?.[0]);
            setUploadedEvidence(undefined);
          }}
        />
      </label>
      <small>PDF, JPG or PNG, up to 10 MB.</small>
      {evidenceFile && !isAcceptedEvidenceFile(evidenceFile) && (
        <p className="error-text" role="alert">Choose a supported file up to 10 MB.</p>
      )}
      {error && <p className="error-text" role="alert">{error}</p>}
      <button className="primary-button" disabled={!valid || busy} type="submit">
        {busy ? "Submitting..." : "Submit for review"}
      </button>
    </form>
  );
}
