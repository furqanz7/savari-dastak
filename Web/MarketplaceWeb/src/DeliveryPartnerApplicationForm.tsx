import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import {
  Bike,
  Car,
  FileCheck2,
  FileUp,
  Footprints,
  Gauge,
  ShieldCheck,
  Truck,
  type LucideIcon,
} from "lucide-react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import { ApplicationProgress } from "./ApplicationProgress";
import { userFacingError } from "./userFacingError";
import {
  DeliveryRequestError,
  getDeliveryPartnerSnapshot,
  isAcceptedPartnerEvidence,
  isValidVehicleRegistration,
  normalizeVehicleRegistration,
  requiresVehicleVerification,
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

type UploadedEvidence = { file: File; path: string };

const methods: Array<{
  value: DeliveryMethod;
  label: string;
  detail: string;
  icon: LucideIcon;
}> = [
  { value: "walking", label: "Walk", detail: "Identity only", icon: Footprints },
  { value: "bicycle", label: "Bicycle", detail: "Identity only", icon: Bike },
  { value: "motorbike", label: "Motorbike", detail: "Vehicle check", icon: Gauge },
  { value: "scooter", label: "Scooter", detail: "Vehicle check", icon: Bike },
  { value: "auto", label: "Auto", detail: "Vehicle check", icon: Truck },
  { value: "car", label: "Car", detail: "Vehicle check", icon: Car },
];

export function DeliveryPartnerApplicationForm({
  client,
  session,
  supabaseUrl,
  publishableKey,
  onSubmitted,
  onSessionExpired,
}: Props) {
  const [deliveryMethod, setDeliveryMethod] = useState<DeliveryMethod>("motorbike");
  const [identityFile, setIdentityFile] = useState<File>();
  const [vehicleFile, setVehicleFile] = useState<File>();
  const [uploadedIdentity, setUploadedIdentity] = useState<UploadedEvidence>();
  const [uploadedVehicle, setUploadedVehicle] = useState<UploadedEvidence>();
  const [registration, setRegistration] = useState("");
  const [makeModel, setMakeModel] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();
  const [reviewReason, setReviewReason] = useState<string>();
  const requestKey = useRef(crypto.randomUUID());
  const needsVehicle = requiresVehicleVerification(deliveryMethod);
  const identityValid = !!identityFile && isAcceptedPartnerEvidence(identityFile);
  const vehicleValid = !!vehicleFile && isAcceptedPartnerEvidence(vehicleFile);
  const normalizedMakeModel = makeModel.trim().replace(/\s+/g, " ");
  const valid = identityValid && !loading && (!needsVehicle || (
    vehicleValid && isValidVehicleRegistration(registration) &&
    normalizedMakeModel.length >= 2 && normalizedMakeModel.length <= 80
  ));

  useEffect(() => {
    let active = true;
    void getDeliveryPartnerSnapshot({
      supabaseUrl,
      publishableKey,
      accessToken: session.access_token,
    }).then((snapshot) => {
      if (!active || snapshot.onboardingState !== "rejected") return;
      if (snapshot.deliveryMethod) {
        setDeliveryMethod(snapshot.deliveryMethod === "bike" ? "motorbike" : snapshot.deliveryMethod);
      }
      setRegistration(snapshot.vehicleRegistrationNumber ?? "");
      setMakeModel(snapshot.vehicleMakeModel ?? "");
      setReviewReason(snapshot.reviewReason ?? undefined);
    }).catch((loadError) => {
      if (!active) return;
      if (loadError instanceof DeliveryRequestError && loadError.status === 401) {
        onSessionExpired();
        return;
      }
      setError(userFacingError(loadError, "The application could not be loaded."));
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => { active = false; };
  }, [onSessionExpired, publishableKey, session.access_token, supabaseUrl]);

  const resetRequest = () => {
    requestKey.current = crypto.randomUUID();
    setError(undefined);
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!valid || !identityFile) return;
    setBusy(true);
    setError(undefined);
    try {
      const identityEvidenceObjectPath = uploadedIdentity?.file === identityFile
        ? uploadedIdentity.path
        : await uploadPartnerEvidence(client, session.user.id, identityFile, "identity");
      setUploadedIdentity({ file: identityFile, path: identityEvidenceObjectPath });

      let vehicleEvidenceObjectPath: string | null = null;
      if (needsVehicle && vehicleFile) {
        vehicleEvidenceObjectPath = uploadedVehicle?.file === vehicleFile
          ? uploadedVehicle.path
          : await uploadPartnerEvidence(client, session.user.id, vehicleFile, "vehicle");
        setUploadedVehicle({ file: vehicleFile, path: vehicleEvidenceObjectPath });
      }

      await submitDeliveryPartnerApplication({
        supabaseUrl,
        publishableKey,
        accessToken: session.access_token,
        deliveryMethod,
        identityEvidenceObjectPath,
        vehicleRegistrationNumber: needsVehicle ? normalizeVehicleRegistration(registration) : null,
        vehicleMakeModel: needsVehicle ? normalizedMakeModel : null,
        vehicleEvidenceObjectPath,
        idempotencyKey: requestKey.current,
      });
      onSubmitted();
    } catch (submitError) {
      setError(userFacingError(submitError, "The application could not be submitted."));
      setBusy(false);
    }
  };

  const chooseFile = (kind: "identity" | "vehicle", file: File | undefined) => {
    if (kind === "identity") {
      setIdentityFile(file);
      setUploadedIdentity(undefined);
    } else {
      setVehicleFile(file);
      setUploadedVehicle(undefined);
    }
    resetRequest();
  };

  return (
    <form className="application-onboarding delivery-application-panel" onSubmit={submit}>
      <header className="application-heading application-heading-compact">
        <p className="eyebrow">Delivery Partner</p>
        <h1>{reviewReason ? "Update your application" : "Deliver with Dastak"}</h1>
        <p>{reviewReason
          ? "Review the requested changes and send your documents again."
          : "Choose how you deliver. Motor vehicles require identity and vehicle verification."}</p>
      </header>

      <ApplicationProgress />

      {reviewReason && <aside className="application-review-note" role="status">
        <ShieldCheck size={19} />
        <div><strong>Update requested</strong><p>{reviewReason}</p></div>
      </aside>}

      <ApplicationSection number="1" title="How will you deliver?" detail="Choose the method you will actively use.">
        <div className="delivery-method-grid" role="radiogroup" aria-label="Delivery method">
          {methods.map(({ value, label, detail, icon: Icon }) => {
            const selected = deliveryMethod === value;
            return <button
              type="button"
              key={value}
              className={`delivery-method-option${selected ? " selected" : ""}`}
              role="radio"
              aria-checked={selected}
              onClick={() => { setDeliveryMethod(value); resetRequest(); }}
            >
              <Icon size={23} />
              <strong>{label}</strong>
              <small>{detail}</small>
            </button>;
          })}
        </div>
      </ApplicationSection>

      <ApplicationSection number="2" title="Verify your identity" detail="Use one clear government-issued identity document.">
        <EvidencePicker
          file={identityFile}
          title="Choose identity proof"
          detail="Aadhaar, driving licence, voter ID or passport"
          onChange={(file) => chooseFile("identity", file)}
        />
        {identityFile && !identityValid && <p className="field-error" role="alert">Choose a PDF, JPG or PNG up to 10 MB.</p>}
      </ApplicationSection>

      {needsVehicle && <ApplicationSection
        number="3"
        title="Verify your vehicle"
        detail="Motorbike, Scooter, Auto, and Car partners must verify the vehicle used for deliveries."
      >
        <div className="vehicle-details-grid">
          <label>
            Registration number
            <input
              value={registration}
              maxLength={20}
              autoCapitalize="characters"
              autoCorrect="off"
              placeholder="TN 23 AB 1234"
              onChange={(event) => { setRegistration(event.target.value.toUpperCase()); resetRequest(); }}
            />
          </label>
          <label>
            Make and model
            <input
              value={makeModel}
              maxLength={80}
              placeholder="Bajaj Pulsar 150"
              onChange={(event) => { setMakeModel(event.target.value); resetRequest(); }}
            />
          </label>
        </div>
        <EvidencePicker
          file={vehicleFile}
          title="Choose registration certificate"
          detail="Upload the vehicle RC"
          onChange={(file) => chooseFile("vehicle", file)}
        />
        {vehicleFile && !vehicleValid && <p className="field-error" role="alert">Choose a PDF, JPG or PNG up to 10 MB.</p>}
      </ApplicationSection>}

      {error && <p className="error-text" role="alert">{error}</p>}
      <div className="application-submit-panel">
        <button className="primary-button application-submit" disabled={!valid || busy} type="submit">
          {loading ? "Loading details..." : busy ? "Submitting..." : reviewReason ? "Resubmit for review" : "Submit for review"}
        </button>
        <p className="application-privacy"><ShieldCheck size={15} />
          {needsVehicle
            ? "Your identity and vehicle documents stay private and are used only for verification."
            : "Your identity document stays private and is used only for verification."}
        </p>
      </div>
    </form>
  );
}

function ApplicationSection({
  number,
  title,
  detail,
  children,
}: {
  number: string;
  title: string;
  detail: string;
  children: ReactNode;
}) {
  return <section className="application-section application-step-section">
    <header>
      <span className="application-step-number">{number}</span>
      <div><h2>{title}</h2><p>{detail}</p></div>
    </header>
    {children}
  </section>;
}

function EvidencePicker({
  file,
  title,
  detail,
  onChange,
}: {
  file: File | undefined;
  title: string;
  detail: string;
  onChange: (file: File | undefined) => void;
}) {
  return <label className={`application-file-picker${file ? " selected" : ""}`}>
    <input
      type="file"
      accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
      onChange={(event) => onChange(event.target.files?.[0])}
    />
    <span>{file ? <FileCheck2 size={23} /> : <FileUp size={23} />}</span>
    <span><strong>{file?.name ?? title}</strong><small>{file ? "Ready to upload" : `${detail} · PDF, JPG or PNG`}</small></span>
    {file && <FileCheck2 className="application-file-status" size={20} aria-hidden="true" />}
  </label>;
}
