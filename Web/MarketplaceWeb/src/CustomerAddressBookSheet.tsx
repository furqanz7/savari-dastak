import { useRef, useState, type MouseEvent } from "react";
import { BriefcaseBusiness, Check, House, MapPin, MapPinned, Pencil, Plus, Trash2, X } from "lucide-react";
import type { CustomerDeliveryAddress } from "./customerAddresses";
import { useModalDialog } from "./useModalDialog";

type AddressContext = "checkout" | "account";

export function CustomerAddressBookSheet({
  addresses, selectedAddressId, busy, error, context, onDismiss, onAdd, onEdit, onSelect, onDelete,
}: {
  addresses: CustomerDeliveryAddress[];
  selectedAddressId?: string;
  busy: boolean;
  error?: string;
  context: AddressContext;
  onDismiss: () => void;
  onAdd: () => void;
  onEdit: (address: CustomerDeliveryAddress) => void;
  onSelect: (address: CustomerDeliveryAddress) => Promise<void>;
  onDelete: (address: CustomerDeliveryAddress) => Promise<void>;
}) {
  const [deleting, setDeleting] = useState<CustomerDeliveryAddress>();
  const closeButton = useRef<HTMLButtonElement>(null);
  const dialog = useModalDialog<HTMLElement>({
    busy,
    initialFocus: closeButton,
    onDismiss: () => deleting ? setDeleting(undefined) : onDismiss(),
  });

  const dismissFromBackdrop = (event: MouseEvent<HTMLDivElement>) => {
    if (event.target !== event.currentTarget || busy) return;
    if (deleting) setDeleting(undefined);
    else onDismiss();
  };

  return <div className="customer-sheet-backdrop" role="presentation" onMouseDown={dismissFromBackdrop}>
    <section ref={dialog} className="customer-sheet customer-address-book" role="dialog" aria-modal="true" aria-labelledby="address-book-title" tabIndex={-1}>
      <header className="account-sheet-heading">
        <span className="account-dialog-mark" aria-hidden="true"><MapPinned size={21} /></span>
        <div>
          <p className="eyebrow">{context === "checkout" ? "Checkout" : "Account"}</p>
          <h2 id="address-book-title">Saved addresses</h2>
          <p>{context === "checkout" ? "Choose where this order should arrive." : "Keep up to ten delivery addresses ready."}</p>
        </div>
        <button ref={closeButton} className="icon-button" type="button" onClick={onDismiss} disabled={busy} aria-label="Close saved addresses" title="Close"><X size={19} /></button>
      </header>

      <div className="customer-address-book-list">
        {addresses.length === 0 ? <div className="customer-address-book-empty">
          <MapPinned size={28} /><strong>No saved addresses</strong><span>Add a precise pin and doorstep instructions.</span>
        </div> : addresses.map((address) => {
          const selected = address.addressId === selectedAddressId || address.isDefault;
          const Icon = address.label === "Home" ? House : address.label === "Work" ? BriefcaseBusiness : MapPin;
          return <article className={`customer-address-book-row ${selected ? "selected" : ""}`} key={address.addressId}>
            <button type="button" className="customer-address-book-select" disabled={busy} onClick={() => void onSelect(address)}>
              <span className="customer-account-icon"><Icon size={19} /></span>
              <span><strong>{address.label}</strong><small>{address.displayAddress}</small>{address.deliveryNotes && <small className="instructions">“{address.deliveryNotes}”</small>}</span>
              <span className="customer-address-selected">{selected ? <><Check size={15} /> Default</> : context === "checkout" ? "Use" : "Set default"}</span>
            </button>
            <div className="customer-address-book-actions">
              <button type="button" onClick={() => onEdit(address)} disabled={busy} aria-label={`Edit ${address.label}`} title="Edit"><Pencil size={17} /></button>
              <button type="button" onClick={() => setDeleting(address)} disabled={busy} aria-label={`Delete ${address.label}`} title="Delete"><Trash2 size={17} /></button>
            </div>
          </article>;
        })}
      </div>
      {error && <p className="order-error" role="alert">{error}</p>}
      <button className="primary-button customer-address-add" type="button" onClick={onAdd} disabled={busy || addresses.length >= 10}><Plus size={18} /> Add address</button>

      {deleting && <div className="customer-address-confirm" role="alertdialog" aria-modal="true" aria-labelledby="delete-address-title">
        <section><div><h3 id="delete-address-title">Delete {deleting.label}?</h3><p>Orders already placed keep their original delivery details.</p></div>
        <div className="customer-address-confirm-actions"><button type="button" onClick={() => setDeleting(undefined)} disabled={busy}>Keep address</button><button className="destructive" type="button" disabled={busy} onClick={() => void onDelete(deleting).then(() => setDeleting(undefined))}>{busy ? "Deleting..." : "Delete"}</button></div></section>
      </div>}
    </section>
  </div>;
}
