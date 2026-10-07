import { groceryCheckoutAcknowledged } from "./customerCartPersistence";
export type CheckoutStorage = Pick<Storage, "getItem" | "setItem">;
export type CheckoutLock = <T>(name: string, operation: () => Promise<T>) => Promise<T>;
export const browserCheckoutLock: CheckoutLock = async (name, operation) => {
  if (typeof navigator === "undefined" || !navigator.locks) throw new Error("This browser cannot safely coordinate checkout tabs. No order request was sent.");
  return navigator.locks.request(name, { mode: "exclusive", ifAvailable: true }, lock => {
    if (!lock) throw new Error("Checkout is running in another tab. Wait, then recover its status.");
    return operation();
  });
};
export type CheckoutJournalRecord = {
  version: 1; fingerprint: string; retail: Record<string, number>;
  submitKey: string; commitKey: string; orderId?: string; orderVersion?: number; commitVersion?: number;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function checkoutJournal(accountId: string, supabaseUrl: string, suppliedStorage?: CheckoutStorage, lock: CheckoutLock = browserCheckoutLock) {
  const key = `dastak:reimagined-checkout:v1:${encodeURIComponent(supabaseUrl.replace(/\/$/, ""))}:${encodeURIComponent(accountId)}`;
  function storage() {
    const value = suppliedStorage ?? (typeof localStorage === "undefined" ? undefined : localStorage);
    if (!value) throw new Error("Checkout recovery storage is unavailable. No new order will be sent.");
    return value;
  }
  return {
    exclusive<T>(operation: () => Promise<T>) { return lock(key, operation); },
    read(): CheckoutJournalRecord | undefined {
      const raw = storage().getItem(key);
      if (!raw || raw === "null") return undefined;
      const value = JSON.parse(raw) as CheckoutJournalRecord;
      if (!value || value.version !== 1 || !/^[0-9a-f]{64}$/.test(value.fingerprint) || !value.retail || Array.isArray(value.retail)
        || !Object.keys(value.retail).length || Object.entries(value.retail).some(([id, quantity]) => !uuid.test(id) || !Number.isInteger(quantity) || quantity < 1 || quantity > 99)
        || ![value.submitKey, value.commitKey].every(key => typeof key === "string" && key.length > 0 && key.length <= 200)
        || (value.orderId !== undefined && (!uuid.test(value.orderId) || !Number.isInteger(value.orderVersion) || value.orderVersion! < 1))
        || (value.commitVersion !== undefined && (!Number.isInteger(value.commitVersion) || value.commitVersion < 1))) throw new Error("Saved checkout recovery data is invalid. Review Orders before starting another checkout.");
      // Copy only approved fields; never restore a serialized token, recipient or address.
      return { version: 1, fingerprint: value.fingerprint, retail: { ...value.retail }, submitKey: value.submitKey, commitKey: value.commitKey, orderId: value.orderId, orderVersion: value.orderVersion, commitVersion: value.commitVersion };
    },
    write(record: CheckoutJournalRecord) { storage().setItem(key, JSON.stringify(record)); },
    acknowledged(orderId: string) { return groceryCheckoutAcknowledged(accountId, orderId, storage()); },
    clear() { storage().setItem(key, "null"); },
  };
}
export type CheckoutJournal = ReturnType<typeof checkoutJournal>;
export async function checkoutFingerprint(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}
