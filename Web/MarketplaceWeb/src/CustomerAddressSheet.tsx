import { useEffect, useState, type FormEvent, type MouseEvent } from "react";
import { BriefcaseBusiness, Check, House, MapPin, MapPinned, X } from "lucide-react";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import type { CustomerDeliveryAddress } from "./customerAddresses";

export type CustomerAddressDraft = {
  label: string;
  details: string;
  place: SelectedPlace;
};

type AddressContext = "checkout" | "account";
type AddressKind = "Home" | "Work" | "Other";

export function CustomerAddressSheet({ address, initialPlace, busy, error, context, onDismiss, onSave }: {
  address?: CustomerDeliveryAddress;
  initialPlace?: SelectedPlace;
  busy: boolean;
  error?: string;
  context: AddressContext;
  onDismiss: () => void;
  onSave: (draft: CustomerAddressDraft) => Promise<void>;
}) {
  const initialKind: AddressKind = address?.label === "Home" || address?.label === "Work" ? address.label : address ? "Other" : "Home";
  const [kind, setKind] = useState<AddressKind>(initialKind);
  const [customLabel, setCustomLabel] = useState(initialKind === "Other" ? address?.label ?? "" : "");
  const [details, setDetails] = useState(address?.details ?? "");
  const [place, setPlace] = useState<SelectedPlace | undefined>(initialPlace ?? (address ? {
    address: address.address,
    latitude: address.location.latitude,
    longitude: address.location.longitude,
  } : undefined));

  const resolvedLabel = kind === "Other" ? customLabel.trim() : kind;
  const canSave = Boolean(place && details.trim() && resolvedLabel);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onDismiss();
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [busy, onDismiss]);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (place && details.trim() && resolvedLabel) void onSave({ label: resolvedLabel, details: details.trim(), place });
  };

  const dismissFromBackdrop = (event: MouseEvent<HTMLDivElement>) => {
    if (event.target === event.currentTarget && !busy) onDismiss();
  };

  const addressKinds: Array<{ value: AddressKind; icon: typeof House }> = [
    { value: "Home", icon: House },
    { value: "Work", icon: BriefcaseBusiness },
    { value: "Other", icon: MapPinned },
  ];

  return (
    <div className="customer-sheet-backdrop" role="presentation" onMouseDown={dismissFromBackdrop}>
      <form className="customer-sheet customer-address-sheet" aria-modal="true" aria-labelledby="address-sheet-title" role="dialog" onSubmit={submit}>
        <header>
          <div>
            <p className="eyebrow">{context === "checkout" ? "Checkout" : "Saved address"}</p>
            <h2 id="address-sheet-title">{context === "checkout" ? "Where should we bring it?" : "Your delivery address"}</h2>
            <p>{context === "checkout" ? "Confirm the pin and add details for the right door." : "Keep a precise address ready for faster checkout."}</p>
          </div>
          <button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close address editor" title="Close"><X size={19} /></button>
        </header>
        {context === "checkout" && <div className="address-progress" aria-label="Address completion">
          <span className={place ? "complete" : ""}>{place ? <Check size={14} /> : "1"} Pin location</span>
          <i />
          <span className={details.trim() ? "complete" : ""}>{details.trim() ? <Check size={14} /> : "2"} Doorstep</span>
        </div>}
        <LocationSearchField label="Delivery pin" value={place} onChange={setPlace} disabled={busy} />
        <fieldset className="address-type-picker">
          <legend>Save as</legend>
          <div>{addressKinds.map(({ value, icon: Icon }) => (
            <button className={kind === value ? "selected" : ""} type="button" key={value} onClick={() => setKind(value)} aria-pressed={kind === value}>
              <Icon size={18} /><span>{value}</span>
            </button>
          ))}</div>
        </fieldset>
        {kind === "Other" && <label className="customer-address-label">
          <span>Address label</span>
          <input value={customLabel} maxLength={40} onChange={(event) => setCustomLabel(event.target.value)} placeholder="For example, Parents' home" required />
        </label>}
        <label className="customer-address-details">
          <span>Doorstep details</span>
          <small>House or flat number, floor, building and a nearby landmark.</small>
          <textarea value={details} maxLength={300} rows={3} onChange={(event) => setDetails(event.target.value)} placeholder="For example: Flat 4B, second floor, opposite the post office" required />
        </label>
        {place && <div className="address-preview"><MapPin size={18} /><span><strong>{resolvedLabel || "Delivery address"}</strong><small>{details.trim() || "Add doorstep details"}</small><small>{place.address}</small></span></div>}
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy || !canSave}>
          <Check size={18} /> {busy ? "Saving..." : context === "checkout" ? "Save and review order" : "Save address"}
        </button>
      </form>
    </div>
  );
}
