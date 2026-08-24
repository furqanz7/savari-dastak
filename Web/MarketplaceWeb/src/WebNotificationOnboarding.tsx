import { useEffect, useRef } from "react";
import { BellRing, LockKeyhole } from "lucide-react";

export function WebNotificationOnboarding({ busy, onEnable, onDismiss }: {
  busy: boolean;
  onEnable: () => void;
  onDismiss: () => void;
}) {
  const dialogRef = useRef<HTMLElement>(null);

  useEffect(() => {
    const previouslyFocused = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : undefined;
    return () => previouslyFocused?.focus();
  }, []);

  return <div className="web-notification-backdrop" role="presentation">
    <section
      ref={dialogRef}
      className="web-notification-onboarding"
      role="dialog"
      aria-modal="true"
      aria-labelledby="web-notification-title"
      aria-describedby="web-notification-description"
      aria-busy={busy || undefined}
      onKeyDown={(event) => {
        if (event.key === "Escape" && !busy) onDismiss();
        if (event.key !== "Tab") return;
        const controls = Array.from(
          dialogRef.current?.querySelectorAll<HTMLElement>("button:not([disabled]), a[href]") ?? [],
        );
        if (controls.length === 0) return;
        const first = controls[0];
        const last = controls[controls.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }}
    >
      <span className="web-notification-icon" aria-hidden="true"><BellRing size={28} /></span>
      <div>
        <p className="eyebrow">Order alerts</p>
        <h2 id="web-notification-title">Stay updated</h2>
        <p id="web-notification-description">Get payment, preparation and delivery updates even when this tab is not open.</p>
      </div>
      <p className="web-notification-privacy"><LockKeyhole size={17} /> Alerts never contain payment credentials, verification codes or private evidence.</p>
      <button autoFocus className="primary-button" type="button" disabled={busy} onClick={onEnable}>
        {busy ? "Enabling alerts…" : "Enable order alerts"}
      </button>
      <button className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>Not now</button>
    </section>
  </div>;
}
