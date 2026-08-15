import { useEffect, useState, type FormEvent, type MouseEvent } from "react";
import { BriefcaseBusiness, Check, House, MapPin, MapPinned, X } from "lucide-react";
import { LocationSearchField, type SelectedPlace } from "./LocationSearchField";
import type { CustomerDeliveryAddress } from "./customerAddresses";
import { combineDoorstepDetails, splitDoorstepDetails } from "./customerAddressDetails";

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
  const initialDetails = splitDoorstepDetails(address?.details);
  const [building, setBuilding] = useState(initialDetails.building);
  const [landmark, setLandmark] = useState(initialDetails.landmark);
  const [place, setPlace] = useState<SelectedPlace | undefined>(initialPlace ?? (address ? {
    address: address.address,
    latitude: address.location.latitude,
    longitude: address.location.longitude,
  } : undefined));

  const resolvedLabel = kind === "Other" ? customLabel.trim() : kind;
  const canSave = Boolean(place && building.trim() && resolvedLabel);

  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onDismiss();
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [busy, onDismiss]);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (place && building.trim() && resolvedLabel) {
      void onSave({ label: resolvedLabel, details: combineDoorstepDetails(building, landmark), place });
    }
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
        <div className="customer-address-scroll">
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
            <span className={building.trim() ? "complete" : ""}>{building.trim() ? <Check size={14} /> : "2"} Doorstep</span>
          </div>}
          <AddressMapPreview place={place} />
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
          <fieldset className="customer-address-details">
            <legend>Doorstep details</legend>
            <small>Tell us exactly where to stop. Only the first field is required.</small>
            <div>
              <input value={building} maxLength={180} onChange={(event) => setBuilding(event.target.value)} placeholder="House, flat or building" required autoComplete="street-address" />
              <input value={landmark} maxLength={110} onChange={(event) => setLandmark(event.target.value)} placeholder="Landmark or delivery note (optional)" />
            </div>
          </fieldset>
          {place && <div className="address-preview"><MapPin size={18} /><span><strong>{resolvedLabel || "Delivery address"}</strong><small>{combineDoorstepDetails(building, landmark) || "Add doorstep details"}</small><small>{place.address}</small></span></div>}
          {error && <p className="order-error" role="alert">{error}</p>}
        </div>
        <footer className="customer-address-footer">
          <button className="primary-button customer-sheet-action" type="submit" disabled={busy || !canSave}>
            <Check size={18} /> {busy ? "Saving..." : context === "checkout" ? "Save and review order" : "Save address"}
          </button>
        </footer>
      </form>
    </div>
  );
}

function AddressMapPreview({ place }: { place?: SelectedPlace }) {
  if (!place) {
    return (
      <div className="address-map-stage empty" aria-label="No delivery pin selected">
        <MapPinned size={30} />
        <strong>Choose a delivery pin</strong>
        <span>Search below or use your current location.</span>
      </div>
    );
  }

  const padding = 0.006;
  const parameters = new URLSearchParams({
    bbox: [
      place.longitude - padding,
      place.latitude - padding,
      place.longitude + padding,
      place.latitude + padding,
    ].join(","),
    layer: "mapnik",
    marker: `${place.latitude},${place.longitude}`,
  });

  return (
    <div className="address-map-stage selected">
      <iframe
        title="Selected delivery pin"
        loading="lazy"
        src={`https://www.openstreetmap.org/export/embed.html?${parameters.toString()}`}
      />
      <span className="address-map-caption"><MapPin size={16} /> Pin confirmed</span>
    </div>
  );
}
