import { useState, type FormEvent } from "react";
import { FileCheck2, FileUp, MapPin, ShieldCheck, Store } from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { ApplicationProgress } from "./ApplicationProgress";
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
    <form className="application-onboarding merchant-application-panel" onSubmit={submit}>
      <header className="application-heading">
        <span className="application-heading-icon"><Store size={24} /></span>
        <div><p className="eyebrow">Merchant registration</p><h1>Bring your store to Dastak</h1><p>Tell us where you trade and provide one document for owner review.</p></div>
      </header>

      <ApplicationProgress />

      <section className="application-section" aria-labelledby="merchant-store-title">
        <header><Store size={20} /><div><h2 id="merchant-store-title">Store details</h2><p>Use the name customers recognise.</p></div></header>
        <label>
          Business name
          <input
            autoComplete="organization"
            maxLength={120}
            value={businessName}
            placeholder="Your store name"
            onChange={(event) => setBusinessName(event.target.value)}
          />
        </label>
        <label>
          Business address
          <span className="application-input-icon"><MapPin size={18} /></span>
          <textarea
            autoComplete="street-address"
            maxLength={300}
            rows={4}
            value={businessAddress}
            placeholder="Shop number, street, area and city"
            onChange={(event) => setBusinessAddress(event.target.value)}
          />
        </label>
      </section>

      <section className="application-section" aria-labelledby="merchant-document-title">
        <header><ShieldCheck size={20} /><div><h2 id="merchant-document-title">Verification document</h2><p>Business registration or the owner's identity proof.</p></div></header>
        <label className="application-file-picker">
          <input
            type="file"
            accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
            onChange={(event) => {
              setEvidenceFile(event.target.files?.[0]);
              setUploadedEvidence(undefined);
            }}
          />
          <span>{evidenceFile ? <FileCheck2 size={23} /> : <FileUp size={23} />}</span>
          <span><strong>{evidenceFile?.name ?? "Choose a document"}</strong><small>PDF, JPG or PNG, up to 10 MB</small></span>
        </label>
      </section>

      {evidenceFile && !isAcceptedEvidenceFile(evidenceFile) && (
        <p className="error-text" role="alert">Choose a supported file up to 10 MB.</p>
      )}
      {error && <p className="error-text" role="alert">{error}</p>}
      <button className="primary-button application-submit" disabled={!valid || busy} type="submit">
        {busy ? "Submitting..." : "Submit for review"}
      </button>
      <p className="application-privacy"><ShieldCheck size={15} /> Your document is private and used only to review this application.</p>
    </form>
  );
}
