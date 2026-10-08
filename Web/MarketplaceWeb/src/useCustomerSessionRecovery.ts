import { useCallback, useRef } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { recoverCustomerSession } from "./customerSessionRecovery";

export function useCustomerSessionRecovery(client: SupabaseClient, accessToken: string): () => void {
  const pending = useRef<Promise<void> | undefined>(undefined);
  return useCallback(() => {
    if (pending.current) return;
    const request = recoverCustomerSession(client, accessToken);
    pending.current = request;
    void request.finally(() => { if (pending.current === request) pending.current = undefined; });
  }, [client, accessToken]);
}
