import { useEffect, useState } from "react";
import type { DastakV1Auth } from "./dastakV1";
import { loadReimaginedCatalogue, type ReimaginedCatalogue } from "./reimaginedCatalogue";

type Session = DastakV1Auth & { accountId: string };
type Resource = { owner: Session; revision: number; data?: ReimaginedCatalogue; error?: unknown };
function sameSession(left: Session, right: Session) {
  return left.accountId === right.accountId && left.accessToken === right.accessToken && left.supabaseUrl === right.supabaseUrl && left.publishableKey === right.publishableKey;
}

// Account/token changes hide old data synchronously; cleanup rejects stale results.
export function useReimaginedCatalogue(session?: Session, loader = loadReimaginedCatalogue) {
  const [revision, setRevision] = useState(0);
  const [resource, setResource] = useState<Resource>();
  const accountId = session?.accountId;
  const accessToken = session?.accessToken;
  const supabaseUrl = session?.supabaseUrl;
  const publishableKey = session?.publishableKey;
  useEffect(() => {
    if (!accountId || !accessToken || !supabaseUrl || !publishableKey) return;
    const owner = { accountId, accessToken, supabaseUrl, publishableKey };
    const controller = new AbortController();
    loader(owner, controller.signal).then(data => {
      if (!controller.signal.aborted) setResource({ owner, revision, data });
    }).catch((error: unknown) => {
      if (!controller.signal.aborted) setResource(previous => ({ owner, revision, error,
        data: previous && sameSession(previous.owner, owner) ? previous.data : undefined }));
    });
    return () => controller.abort();
  }, [accountId, accessToken, supabaseUrl, publishableKey, revision, loader]);
  const current = session && resource && sameSession(resource.owner, session) ? resource : undefined;
  return {
    data: current?.data,
    error: current?.data || current?.revision === revision ? current?.error : undefined,
    refreshing: Boolean(current?.data && current.revision !== revision),
    status: !session ? "unavailable" as const : !current ? "loading" as const : current.data ? "ready" as const : current.revision !== revision ? "loading" as const : "unavailable" as const,
    retry: () => setRevision(value => value + 1),
  };
}
