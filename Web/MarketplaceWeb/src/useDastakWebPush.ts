import { useCallback, useEffect, useMemo, useState } from "react";
import {
  applicationServerKey,
  registerWebPushSubscription,
  webPushOnboardingStorageKey,
  webPushSupported,
  type DastakWebPushStatus,
  type WebPushAuthentication,
} from "./webPush";

export type DastakWebPushController = {
  status: DastakWebPushStatus;
  message?: string;
  shouldPrompt: boolean;
  enable: () => Promise<void>;
  dismiss: () => void;
  refresh: () => Promise<void>;
};

export function useDastakWebPush(authentication: WebPushAuthentication): DastakWebPushController {
  const storageKey = useMemo(
    () => webPushOnboardingStorageKey(authentication.accountId),
    [authentication.accountId],
  );
  const [status, setStatus] = useState<DastakWebPushStatus>("checking");
  const [message, setMessage] = useState<string>();

  const registerCurrentSubscription = useCallback(async (create: boolean) => {
    const registration = await navigator.serviceWorker.register("/dastak-sw.js", { scope: "/" });
    let subscription = await registration.pushManager.getSubscription();
    if (!subscription && create) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: applicationServerKey(authentication.publicKey),
      });
    }
    if (!subscription) return false;
    await registerWebPushSubscription(authentication, subscription);
    return true;
  }, [authentication]);

  const refresh = useCallback(async () => {
    if (!webPushSupported()) {
      setStatus("unsupported");
      return;
    }
    setMessage(undefined);
    if (Notification.permission === "denied") {
      setStatus("blocked");
      return;
    }
    if (Notification.permission === "granted") {
      try {
        const registered = await registerCurrentSubscription(true);
        setStatus(registered ? "enabled" : "error");
      } catch {
        setMessage("Browser alerts could not be restored. In-app order updates still work.");
        setStatus("error");
      }
      return;
    }
    let dismissed = false;
    try {
      dismissed = localStorage.getItem(storageKey) === "dismissed";
    } catch {
      // Private browsing can keep the prompt session-only.
    }
    setStatus(dismissed ? "dismissed" : "prompt");
  }, [registerCurrentSubscription, storageKey]);

  useEffect(() => { void refresh(); }, [refresh]);

  const enable = useCallback(async () => {
    if (!webPushSupported()) {
      setStatus("unsupported");
      return;
    }
    if (Notification.permission === "denied") {
      setStatus("blocked");
      setMessage("Allow notifications in your browser settings, then try again.");
      return;
    }
    setStatus("enabling");
    setMessage(undefined);
    try {
      const permission = Notification.permission === "granted"
        ? "granted"
        : await Notification.requestPermission();
      if (permission !== "granted") {
        setStatus(permission === "denied" ? "blocked" : "dismissed");
        return;
      }
      await registerCurrentSubscription(true);
      try { localStorage.removeItem(storageKey); } catch { /* optional preference */ }
      setStatus("enabled");
    } catch {
      setStatus("error");
      setMessage("Browser alerts could not be enabled. In-app order updates still work.");
    }
  }, [registerCurrentSubscription, storageKey]);

  const dismiss = useCallback(() => {
    try { localStorage.setItem(storageKey, "dismissed"); } catch { /* session-only */ }
    setStatus("dismissed");
  }, [storageKey]);

  return {
    status,
    message,
    shouldPrompt: status === "prompt",
    enable,
    dismiss,
    refresh,
  };
}
