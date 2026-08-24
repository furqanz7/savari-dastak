import { useEffect, useRef } from "react";
import { BadgeCheck, BellRing, LockKeyhole, MapPin } from "lucide-react";

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
      <header className="web-notification-brand">
        <p><span>Dastak</span> <span lang="ur">دستک</span></p>
        <small>Finish setup</small>
      </header>
      <div className="web-notification-heading">
        <span className="web-notification-icon" aria-hidden="true"><BellRing size={27} /></span>
        <p className="eyebrow">Order alerts</p>
        <h2 id="web-notification-title">Know the moment your order moves.</h2>
        <p id="web-notification-description">Turn on useful updates, from secured to delivered—even when Dastak is closed.</p>
      </div>
      <div className="web-notification-previews" aria-label="Example order alerts">
        <div>
          <span aria-hidden="true"><BadgeCheck size={18} /></span>
          <p><strong>Your order is secured</strong><small>Everything is ready for payment.</small></p>
          <time>now</time>
        </div>
        <div>
          <span aria-hidden="true"><MapPin size={18} /></span>
          <p><strong>Your order is on the way</strong><small>Your delivery partner has every package.</small></p>
          <time>now</time>
        </div>
      </div>
      <p className="web-notification-privacy"><LockKeyhole size={17} /> Alerts never contain payment credentials, verification codes or private evidence.</p>
      <div className="web-notification-actions">
        <button autoFocus className="primary-button" type="button" disabled={busy} onClick={onEnable}>
          {busy ? <><span className="auth-inline-spinner" aria-hidden="true" />Opening notification settings…</> : "Enable order alerts"}
        </button>
        <button className="secondary-button" type="button" disabled={busy} onClick={onDismiss}>Not now</button>
      </div>
    </section>
  </div>;
}
