import { useEffect, useState } from "react";
import { CheckCircle2, Clock3, LockKeyhole, ShieldCheck, Trash2, UserCog } from "lucide-react";
import {
  getV1AdminAccess,
  setV1ExecutiveAdmin,
  type DastakV1Auth,
  type V1AdminAccess,
  type V1AdminSlot,
} from "./dastakV1";

type Props = {
  auth: DastakV1Auth;
  access: V1AdminAccess;
  onChange: (access: V1AdminAccess) => void;
};

export function AdminAccessPanel({ auth, access, onChange }: Props) {
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [busySlot, setBusySlot] = useState<number>();
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();

  useEffect(() => {
    setDrafts(Object.fromEntries(access.slots.map((slot) => [slot.slot, slot.email ?? ""])));
  }, [access]);

  if (!access.canManageAdmins) return null;
  const superadmin = access.slots.find((slot) => slot.role === "SUPERADMIN");
  const executives = access.slots.filter(
    (slot): slot is V1AdminSlot & { slot: 1 | 2 } => slot.role === "EXECUTIVE_ADMIN",
  );

  const update = async (slot: V1AdminSlot & { slot: 1 | 2 }, email?: string) => {
    if (busySlot !== undefined) return;
    setBusySlot(slot.slot);
    setError(undefined);
    setNotice(undefined);
    try {
      await setV1ExecutiveAdmin({
        ...auth,
        slot: slot.slot,
        email,
        expectedVersion: slot.version,
        reason: email
          ? "Updated from protected Dastak Admin access settings."
          : "Cleared from protected Dastak Admin access settings.",
      });
      const refreshed = await getV1AdminAccess(auth);
      onChange(refreshed);
      setNotice(email
        ? "Executive Admin access has been saved."
        : "Executive Admin access has been removed.");
    } catch (updateError) {
      setError(updateError instanceof Error
        ? updateError.message
        : "Admin access could not be updated. Refresh and try again.");
    } finally {
      setBusySlot(undefined);
    }
  };

  return (
    <section className="admin-access" aria-labelledby="admin-access-title">
      <header className="admin-access-heading">
        <div className="admin-access-icon" aria-hidden="true"><ShieldCheck size={22} /></div>
        <div>
          <p className="eyebrow">Superadmin control</p>
          <h2 id="admin-access-title">Admin access</h2>
          <p>One permanent Superadmin and two replaceable Executive Admin seats.</p>
        </div>
      </header>

      {superadmin && (
        <article className="admin-access-seat superadmin-seat">
          <div className="admin-access-seat-icon" aria-hidden="true"><LockKeyhole size={20} /></div>
          <div>
            <strong>Superadmin</strong>
            <span>{superadmin.email}</span>
            <small>Permanent · cannot be changed or removed</small>
          </div>
          <b><CheckCircle2 size={15} /> Active</b>
        </article>
      )}

      <div className="admin-access-executives">
        {executives.map((slot) => {
          const draft = drafts[slot.slot] ?? "";
          const normalizedDraft = draft.trim().toLowerCase();
          const unchanged = normalizedDraft === (slot.email ?? "");
          const busy = busySlot === slot.slot;
          return (
            <form
              className="admin-access-seat executive-seat"
              key={slot.slot}
              onSubmit={(event) => {
                event.preventDefault();
                if (normalizedDraft) void update(slot, normalizedDraft);
              }}
            >
              <div className="admin-access-seat-title">
                <span className="admin-access-seat-icon" aria-hidden="true"><UserCog size={20} /></span>
                <span>
                  <strong>Executive Admin {slot.slot}</strong>
                  <small>{slot.email
                    ? slot.linked ? "Active account" : "Reserved · activates after this email signs in"
                    : "Empty seat"}</small>
                </span>
                {slot.email && <b className={slot.linked ? "linked" : "pending"}>
                  {slot.linked ? <CheckCircle2 size={14} /> : <Clock3 size={14} />}
                  {slot.linked ? "Active" : "Pending"}
                </b>}
              </div>
              <label htmlFor={`executive-email-${slot.slot}`}>Assigned email</label>
              <div className="admin-access-field">
                <input
                  id={`executive-email-${slot.slot}`}
                  type="email"
                  autoComplete="off"
                  placeholder="name@example.com"
                  value={draft}
                  disabled={busySlot !== undefined}
                  required
                  maxLength={320}
                  onChange={(event) => setDrafts((current) => ({
                    ...current,
                    [slot.slot]: event.target.value,
                  }))}
                />
                <button type="submit" disabled={!normalizedDraft || unchanged || busySlot !== undefined}>
                  {busy ? "Saving…" : slot.email ? "Save change" : "Assign"}
                </button>
              </div>
              {slot.email && (
                <button
                  className="admin-access-clear"
                  type="button"
                  disabled={busySlot !== undefined}
                  onClick={() => {
                    if (window.confirm("Remove this Executive Admin's access immediately?")) {
                      void update(slot);
                    }
                  }}
                >
                  <Trash2 size={15} /> Remove Executive Admin
                </button>
              )}
            </form>
          );
        })}
      </div>

      {error && <p className="admin-access-message error" role="alert">{error}</p>}
      {notice && <p className="admin-access-message success" role="status">{notice}</p>}
      <p className="admin-access-note">
        Executive Admins can use every current operations feature. Only the permanent Superadmin can change Admin access.
      </p>
    </section>
  );
}
