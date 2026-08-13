import { useState, type FormEvent } from "react";
import { Check, MapPin, X } from "lucide-react";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import type { CustomerDeliveryAddress } from "./customerAddresses";

export type CustomerAddressDraft = {
  label: string;
  details: string;
  place: SelectedPlace;
};

export function CustomerAddressSheet({ address, initialPlace, busy, error, onDismiss, onSave }: {
  address?: CustomerDeliveryAddress;
  initialPlace?: SelectedPlace;
  busy: boolean;
  error?: string;
  onDismiss: () => void;
  onSave: (draft: CustomerAddressDraft) => Promise<void>;
}) {
  const [label, setLabel] = useState(address?.label ?? "Home");
  const [details, setDetails] = useState(address?.details ?? "");
  const [place, setPlace] = useState<SelectedPlace | undefined>(initialPlace ?? (address ? {
    address: address.address,
    latitude: address.location.latitude,
    longitude: address.location.longitude,
  } : undefined));

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (place && details.trim()) void onSave({ label, details: details.trim(), place });
  };

  return (
    <div className="customer-sheet-backdrop" role="presentation">
      <form className="customer-sheet customer-address-sheet" aria-modal="true" aria-labelledby="address-sheet-title" role="dialog" onSubmit={submit}>
        <header>
          <div><p className="eyebrow">Delivery details</p><h2 id="address-sheet-title">Where should we deliver?</h2></div>
          <button className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close address editor" title="Close"><X size={19} /></button>
        </header>
        <LocationSearchField label="Delivery location" value={place} onChange={setPlace} disabled={busy} />
        <fieldset className="address-type-picker">
          <legend>Address type</legend>
          <div>{["Home", "Work", "Other"].map((option) => (
            <button className={label === option ? "selected" : ""} type="button" key={option} onClick={() => setLabel(option)}>{option}</button>
          ))}</div>
        </fieldset>
        <label className="customer-address-details">
          <span>House, building, street and landmark</span>
          <textarea value={details} maxLength={300} rows={3} onChange={(event) => setDetails(event.target.value)} placeholder="Flat or house number, street, landmark" required />
        </label>
        {place && <div className="address-preview"><MapPin size={18} /><span><strong>{label}</strong><small>{place.address}</small></span></div>}
        {error && <p className="order-error" role="alert">{error}</p>}
        <button className="primary-button customer-sheet-action" type="submit" disabled={busy || !place || !details.trim()}>
          <Check size={18} /> {busy ? "Saving..." : "Save delivery address"}
        </button>
      </form>
    </div>
  );
}
