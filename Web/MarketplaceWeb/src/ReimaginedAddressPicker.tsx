import { useId } from "react";
import type { useReimaginedAddresses } from "./useReimaginedAddresses";

export function ReimaginedAddressPicker({ resource, online, accountUrl, compact = false }: {
  resource: ReturnType<typeof useReimaginedAddresses>; online: boolean; accountUrl: string; compact?: boolean;
}) {
  const groupId = useId();
  const selected = online && resource.status === "ready" ? resource.addresses.find(address => address.addressId === resource.selected?.addressId) : undefined;
  const choices = online && resource.status === "ready" && resource.addresses.length > 0 ? <fieldset>
    <legend>Deliver to</legend>
    {resource.addresses.map(address => <label key={address.addressId} className="reimagined-address-option" data-selected={selected?.addressId === address.addressId}>
      <input type="radio" name={`${groupId}-delivery-address`} checked={selected?.addressId === address.addressId} onChange={() => resource.select(address.addressId)} />
      <span><strong>{address.label}</strong><span>{address.displayAddress}</span>{address.deliveryNotes ? <small>{address.deliveryNotes}</small> : null}</span>
    </label>)}
  </fieldset> : null;
  return <section className="reimagined-address-picker" aria-label="Choose a saved delivery address">
    <h3>Delivery address</h3>
    {!online ? <p role="status">You’re offline. Reconnect to confirm saved delivery addresses.</p>
      : resource.status === "loading" ? <p role="status">Loading your saved addresses…</p>
      : resource.status === "unavailable" ? <><p role="alert">Saved addresses are unavailable. No delivery location has been confirmed.</p><button type="button" onClick={resource.retry}>Retry addresses</button></>
      : resource.status === "ready" && resource.addresses.length === 0 ? <p>You have no saved delivery addresses yet.</p> : null}
    {compact && selected ? <><div className="reimagined-selected-address"><strong>{selected.label}</strong><span>{selected.displayAddress}</span>{selected.deliveryNotes ? <small>{selected.deliveryNotes}</small> : null}</div><details><summary>Change delivery address</summary>{choices}</details></> : choices}
    <p className="reimagined-address-guidance">Choosing here does not change your saved default address. Delivery eligibility is still checked at checkout.</p>
    <a href={accountUrl}>Add or edit addresses in your existing account</a>
  </section>;
}
