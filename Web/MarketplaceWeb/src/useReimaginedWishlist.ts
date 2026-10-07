import { useEffect, useRef, useState } from "react";
import { getCustomerWishlist, setCustomerWishlistItem, type CustomerWishlistItem, type CustomerWishlistItemKind } from "./customerWishlist";
import type { DastakV1Auth } from "./dastakV1";

export function useReimaginedWishlist(auth: DastakV1Auth & { accountId: string }, online: boolean) {
  const owner = JSON.stringify([auth.accountId, auth.supabaseUrl, auth.accessToken, auth.publishableKey]);
  const [resource, setResource] = useState<{ owner: string; items?: CustomerWishlistItem[]; error?: unknown }>();
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const session = useRef(0);
  const writing = useRef(false);
  const intents = useRef(new Map<string, { wished: boolean; key: string }>());
  const { accessToken, publishableKey, supabaseUrl } = auth;
  useEffect(() => {
    const epoch = ++session.current; const controller = new AbortController();
    writing.current = false; setBusy(false); intents.current.clear();
    if (online) void getCustomerWishlist({ accessToken, publishableKey, supabaseUrl, signal: controller.signal }).then(snapshot => {
      if (epoch === session.current && !controller.signal.aborted) setResource({ owner, items: snapshot.items });
    }).catch(error => { if (epoch === session.current && !controller.signal.aborted) setResource({ owner, error }); });
    return () => { session.current = epoch + 1; controller.abort(); };
  }, [owner, accessToken, publishableKey, supabaseUrl, online, revision]);
  const current = resource?.owner === owner ? resource : undefined;
  const items = current?.items ?? [];
  async function toggle(kind: CustomerWishlistItemKind, itemId: string) {
    if (!online || writing.current || !current?.items) return;
    const epoch = session.current; const identity = `${kind}:${itemId}`;
    const intent = intents.current.get(identity) ?? { wished: !items.some(item => item.kind === kind && item.itemId === itemId), key: crypto.randomUUID() };
    intents.current.set(identity, intent); writing.current = true; setBusy(true);
    try {
      const result = await setCustomerWishlistItem({ accessToken, publishableKey, supabaseUrl, itemKind: kind, itemId, wished: intent.wished, idempotencyKey: intent.key });
      if (epoch === session.current) { intents.current.delete(identity); setResource({ owner, items: result.items }); }
    } catch (error) {
      if (epoch === session.current) setResource({ owner, items, error });
    } finally { if (epoch === session.current) { writing.current = false; setBusy(false); } }
  }
  return { items, busy, error: current?.error, ready: Boolean(current?.items), retry: () => setRevision(value => value + 1),
    saved: (kind: CustomerWishlistItemKind, id: string) => items.some(item => item.kind === kind && item.itemId === id), toggle };
}
