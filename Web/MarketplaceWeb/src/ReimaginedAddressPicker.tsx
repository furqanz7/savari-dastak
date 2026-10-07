import { useEffect, useId, useRef, useState } from "react";
import type { useReimaginedAddresses } from "./useReimaginedAddresses";
import { CustomerAddressBookSheet } from "./CustomerAddressBookSheet";
import { CustomerAddressSheet, type CustomerAddressDraft } from "./CustomerAddressSheet";
import { deleteCustomerAddress, saveCustomerAddress, setDefaultCustomerAddress, type CustomerDeliveryAddress } from "./customerAddresses";
import type { DastakV1Auth } from "./dastakV1";
import { customerDataIssue } from "./customerDataState";

export function ReimaginedAddressPicker({ resource, online, accountUrl, compact = false, auth, onSessionExpired }: {
  resource: ReturnType<typeof useReimaginedAddresses>; online: boolean; accountUrl: string; compact?: boolean; auth?: DastakV1Auth; onSessionExpired?: () => void;
}) {
  const groupId = useId();
  const [book, setBook] = useState(false);
  const [editor, setEditor] = useState<{ address?: CustomerDeliveryAddress }>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const attempt = useRef<{ fingerprint: string; key: string } | undefined>(undefined);
  const writing = useRef(false);
  const session = useRef(0);
  useEffect(() => () => { session.current++; }, []);
  async function change(fingerprint: string, operation: (key: string) => Promise<unknown>) {
    if (!auth || !online || writing.current) return;
    const intent = attempt.current?.fingerprint === fingerprint ? attempt.current : { fingerprint, key: crypto.randomUUID() };
    const epoch = session.current;
    attempt.current = intent; writing.current = true; setBusy(true); setError(undefined);
    try { await operation(intent.key); if (epoch === session.current) { attempt.current = undefined; resource.retry(); setEditor(undefined); setBook(false); } }
    catch (issue) { if (epoch === session.current) { if (customerDataIssue(issue).action === "sign_in") onSessionExpired?.(); else setError(issue instanceof Error ? issue.message : "Addresses could not update."); } }
    finally { if (epoch === session.current) { writing.current = false; setBusy(false); } }
  }
  async function save(draft: CustomerAddressDraft) {
    await change(JSON.stringify(["save", draft]), key => saveCustomerAddress({ ...auth!, ...draft, address: draft.place.address, location: { latitude: draft.place.latitude, longitude: draft.place.longitude }, makeDefault: true, idempotencyKey: key }));
  }
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
    <button type="button" disabled={!online || busy} onClick={resource.retry}>Refresh saved addresses</button>
    {auth ? <button type="button" disabled={!online || busy || resource.status !== "ready"} onClick={() => { setError(undefined); if (resource.addresses.length) setBook(true); else setEditor({}); }}>Add or manage delivery addresses</button> : <a href={accountUrl}>Add or edit addresses in your existing account</a>}
    {book && auth ? <CustomerAddressBookSheet addresses={resource.addresses} selectedAddressId={selected?.addressId} busy={busy} error={error} context="account" onDismiss={() => setBook(false)} onAdd={() => { setBook(false); setEditor({}); }} onEdit={address => { setBook(false); setEditor({ address }); }} onSelect={address => change(`default:${address.addressId}`, key => setDefaultCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: key }))} onDelete={address => change(`delete:${address.addressId}`, key => deleteCustomerAddress({ ...auth, addressId: address.addressId, idempotencyKey: key }))} /> : null}
    {editor && auth ? <CustomerAddressSheet address={editor.address} busy={busy} error={error} context="checkout" onDismiss={() => { if (!busy) setEditor(undefined); }} onSave={save} /> : null}
  </section>;
}
