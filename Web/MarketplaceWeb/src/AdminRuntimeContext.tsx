/* eslint-disable react-refresh/only-export-components */
import { createContext, useCallback, useContext, useMemo, type ReactNode } from "react";
import type { OrderRealtimeHealth } from "./orderRealtime";
import { isAdminSessionExpired } from "./adminRuntime";

type AdminRuntimeValue = {
  realtimeHealth: OrderRealtimeHealth;
  reportRequestError: (error: unknown) => boolean;
};

const AdminRuntimeContext = createContext<AdminRuntimeValue>({
  realtimeHealth: "connecting",
  reportRequestError: () => false,
});

export function AdminRuntimeProvider({
  realtimeHealth,
  onSessionExpired,
  children,
}: {
  realtimeHealth: OrderRealtimeHealth;
  onSessionExpired: () => void;
  children: ReactNode;
}) {
  const reportRequestError = useCallback((error: unknown) => {
    if (!isAdminSessionExpired(error)) return false;
    onSessionExpired();
    return true;
  }, [onSessionExpired]);
  const value = useMemo(() => ({ realtimeHealth, reportRequestError }), [realtimeHealth, reportRequestError]);
  return <AdminRuntimeContext.Provider value={value}>
    {children}
  </AdminRuntimeContext.Provider>;
}

export function useAdminRuntime() {
  return useContext(AdminRuntimeContext);
}
