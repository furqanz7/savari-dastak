import { useEffect, useState } from "react";
import { getCustomerAddresses, type CustomerDeliveryAddressCollection } from "./customerAddresses";
import type { DastakV1Auth } from "./dastakV1";

type Session = DastakV1Auth & { accountId: string };
type Resource = { owner: string; revision: number; data?: CustomerDeliveryAddressCollection; error?: unknown };
type Loader = (input: DastakV1Auth & { signal?: AbortSignal }) => Promise<CustomerDeliveryAddressCollection>;

// Fetch only when Location/counter is opened. Selection is local, not a default-address write.
export function useReimaginedAddresses(session: Session, enabled: boolean, loader: Loader = getCustomerAddresses) {
  const { accountId, accessToken, supabaseUrl, publishableKey } = session;
  const owner = JSON.stringify([accountId, accessToken, supabaseUrl, publishableKey]);
  const [revision, setRevision] = useState(0);
  const [resource, setResource] = useState<Resource>();
  const [selection, setSelection] = useState<{ owner: string; id: string }>();
  useEffect(() => {
    if (!enabled) return;
    const controller = new AbortController();
    loader({ accessToken, supabaseUrl, publishableKey, signal: controller.signal }).then(data => {
      if (!controller.signal.aborted) setResource({ owner, revision, data });
    }).catch((error: unknown) => {
      if (!controller.signal.aborted) setResource({ owner, revision, error });
    });
    return () => controller.abort();
  }, [enabled, accessToken, supabaseUrl, publishableKey, owner, revision, loader]);
  const current = resource?.owner === owner && resource.revision === revision ? resource : undefined;
  const addresses = current?.data?.addresses ?? [];
  const selected = addresses.find(address => selection?.owner === owner && address.addressId === selection.id)
    ?? addresses.find(address => address.isDefault);
  return {
    addresses, selected, error: current?.error,
    status: current?.data ? "ready" as const : current?.error ? "unavailable" as const : enabled ? "loading" as const : "idle" as const,
    select: (id: string) => { if (addresses.some(address => address.addressId === id)) setSelection({ owner, id }); },
    retry: () => setRevision(value => value + 1),
  };
}
