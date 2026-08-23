import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { RefreshCw, WalletCards } from "lucide-react";
import { formatPrice } from "./catalogue";
import {
  getRoyalty,
  requestRoyaltyWithdrawal,
  type RoyaltySnapshot,
  type RoyaltySubject,
  type RoyaltyWithdrawal,
} from "./earnings";

type Auth = { accessToken: string; supabaseUrl: string; publishableKey: string };

export function RoyaltyPanel({
  auth,
  kind,
}: {
  auth: Auth;
  kind: "MERCHANT" | "RIDER";
}) {
  const [snapshot, setSnapshot] = useState<RoyaltySnapshot>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      setSnapshot(
        await getRoyalty(
          auth,
          kind === "MERCHANT" ? "merchantRoyaltySnapshot" : "deliveryRoyaltySnapshot",
        ),
      );
      setError(undefined);
    } catch (loadError) {
      setError(message(loadError));
    } finally {
      setLoading(false);
    }
  }, [auth, kind]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return (
    <section className="royalty-shell" aria-labelledby="royalty-title">
      <header className="royalty-heading">
        <div>
          <p className="eyebrow">Earnings balance</p>
          <h1 id="royalty-title">Royalty</h1>
          <p>Credits, adjustments, and payout requests from the append-only ledger.</p>
        </div>
        <button
          className="icon-button"
          type="button"
          onClick={() => void refresh()}
          disabled={loading}
          aria-label="Refresh Royalty"
        >
          <RefreshCw size={19} />
        </button>
      </header>
      {error && <p className="order-error" role="alert">{error}</p>}
      {loading && !snapshot
        ? (
          <div className="catalogue-loading" role="status">
            <span /> Loading Royalty
          </div>
        )
        : snapshot
        ? (
          <>
            <div className="royalty-summary" aria-label="Royalty summary">
              <RoyaltyMetric label="Available" value={formatPrice(snapshot.availablePaise)} />
              <RoyaltyMetric
                label="Lifetime earned"
                value={formatPrice(snapshot.lifetimeEarnedPaise)}
              />
              <RoyaltyMetric
                label="Amount owed"
                value={formatPrice(snapshot.negativeBalancePaise)}
                warning={snapshot.negativeBalancePaise > 0}
              />
            </div>
            <div className="royalty-subjects">
              {snapshot.subjects.map((subject) => (
                <RoyaltySubjectCard
                  key={subject.subjectType + ":" + subject.subjectId}
                  auth={auth}
                  subject={subject}
                  showSubject={snapshot.subjects.length > 1}
                  onChanged={refresh}
                />
              ))}
            </div>
          </>
        )
        : null}
    </section>
  );
}

function RoyaltyMetric({
  label,
  value,
  warning = false,
}: {
  label: string;
  value: string;
  warning?: boolean;
}) {
  return (
    <div className={warning ? "warning" : ""}>
      <small>{label}</small>
      <strong>{value}</strong>
    </div>
  );
}

function RoyaltySubjectCard({
  auth,
  subject,
  showSubject,
  onChanged,
}: {
  auth: Auth;
  subject: RoyaltySubject;
  showSubject: boolean;
  onChanged: () => Promise<void>;
}) {
  const [amount, setAmount] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string>();
  const [error, setError] = useState<string>();
  const requestKeys = useRef(new Map<string, string>());
  const amountPaise = useMemo(() => {
    const value = Number(amount);
    if (!Number.isFinite(value) || value <= 0) return undefined;
    const paise = Math.round(value * 100);
    return Number.isSafeInteger(paise) && paise > 0 ? paise : undefined;
  }, [amount]);

  const withdraw = async () => {
    if (!amountPaise) return;
    const identity = subject.subjectType + ":" + subject.subjectId + ":" + amountPaise;
    const idempotencyKey = requestKeys.current.get(identity) ?? crypto.randomUUID();
    requestKeys.current.set(identity, idempotencyKey);
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    try {
      const result = await requestRoyaltyWithdrawal({
        ...auth,
        subjectType: subject.subjectType,
        subjectId: subject.subjectId,
        amountPaise,
        idempotencyKey,
      });
      requestKeys.current.delete(identity);
      setAmount("");
      setNotice(
        result.status === "REQUESTED"
          ? "Withdrawal requested. It is not paid until the payout provider confirms it."
          : "Withdrawal status: " + withdrawalLabel(result.status) + ".",
      );
      await onChanged();
    } catch (withdrawalError) {
      setError(message(withdrawalError));
    } finally {
      setBusy(false);
    }
  };

  return (
    <article className="royalty-card">
      <header>
        <span className="royalty-icon">
          <WalletCards size={20} />
        </span>
        <div>
          <strong>
            {showSubject ? "Royalty account · " + shortId(subject.subjectId) : "Your Royalty"}
          </strong>
          <small>
            {subject.payoutDestination?.displayLabel ?? "Payout method not registered"}
          </small>
        </div>
      </header>
      <div className="royalty-balance-row">
        <div>
          <small>Available</small>
          <strong>{formatPrice(subject.availablePaise)}</strong>
        </div>
        <div>
          <small>Adjustments</small>
          <strong>{signedTotal(subject.adjustments)}</strong>
        </div>
        <div className={subject.negativeBalancePaise > 0 ? "warning" : ""}>
          <small>Negative balance</small>
          <strong>{formatPrice(subject.negativeBalancePaise)}</strong>
        </div>
      </div>
      <form
        className="royalty-withdraw-form"
        onSubmit={(event) => {
          event.preventDefault();
          void withdraw();
        }}
      >
        <label>
          <span>Withdrawal amount</span>
          <span className="royalty-amount-input">
            <span aria-hidden="true">₹</span>
            <input
              type="number"
              min="0.01"
              max={(subject.availablePaise / 100).toFixed(2)}
              step="0.01"
              inputMode="decimal"
              value={amount}
              onChange={(event) => setAmount(event.currentTarget.value)}
              disabled={busy || !subject.canWithdraw}
              aria-describedby={"withdraw-help-" + subject.subjectId}
            />
          </span>
        </label>
        <button
          className="primary-button"
          type="submit"
          disabled={busy || !subject.canWithdraw || !amountPaise ||
            amountPaise > subject.availablePaise}
        >
          {busy ? "Requesting…" : "Withdraw"}
        </button>
      </form>
      <p id={"withdraw-help-" + subject.subjectId} className="royalty-help">
        {subject.payoutDestination
          ? "Available Royalty is reserved immediately. Paid appears only after provider confirmation."
          : "Complete payout-method onboarding before requesting a withdrawal."}
      </p>
      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="royalty-notice" role="status">{notice}</p>}
      <RoyaltyHistory title="Earnings and adjustments" entries={subject.entries} />
      <WithdrawalHistory withdrawals={subject.withdrawals} />
    </article>
  );
}

function RoyaltyHistory({
  title,
  entries,
}: {
  title: string;
  entries: RoyaltySubject["entries"];
}) {
  return (
    <section className="royalty-history" aria-label={title}>
      <h2>{title}</h2>
      {entries.length === 0 ? <p>No Royalty entries yet.</p> : (
        <ul>
          {entries.map((entry) => (
            <li key={entry.id}>
              <div>
                <strong>{entryLabel(entry.type)}</strong>
                <small>
                  {entry.orderId ? "Order " + shortId(entry.orderId) + " · " : ""}
                  {new Date(entry.createdAt).toLocaleString()}
                </small>
              </div>
              <strong className={entry.amountPaise < 0 ? "negative" : "positive"}>
                {entry.amountPaise > 0 ? "+" : ""}
                {formatPrice(entry.amountPaise)}
              </strong>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function WithdrawalHistory({ withdrawals }: { withdrawals: RoyaltyWithdrawal[] }) {
  return (
    <section className="royalty-history" aria-label="Withdrawals">
      <h2>Withdrawals</h2>
      {withdrawals.length === 0 ? <p>No withdrawal requests yet.</p> : (
        <ul>
          {withdrawals.map((withdrawal) => (
            <li key={withdrawal.id}>
              <div>
                <strong>{withdrawalLabel(withdrawal.status)}</strong>
                <small>
                  {withdrawal.destination?.displayLabel ?? "Snapshotted payout destination"}
                  {" · "}
                  {new Date(withdrawal.requestedAt).toLocaleString()}
                </small>
                {withdrawal.status === "FAILED_RETRYABLE" && (
                  <small>Funds are available again; Operations can safely retry.</small>
                )}
              </div>
              <strong>{formatPrice(withdrawal.amountPaise)}</strong>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function signedTotal(entries: RoyaltySubject["adjustments"]) {
  const total = entries.reduce((sum, entry) => sum + entry.amountPaise, 0);
  return (total > 0 ? "+" : "") + formatPrice(total);
}

function withdrawalLabel(status: RoyaltyWithdrawal["status"]) {
  if (status === "REQUESTED") return "Requested";
  if (status === "PROCESSING") return "Processing";
  if (status === "PAID") return "Paid";
  return "Failed · retryable";
}

function entryLabel(type: string) {
  if (type === "MERCHANT_ROYALTY_EARNING" || type === "RIDER_ROYALTY_EARNING") {
    return "Earning credit";
  }
  if (type === "ROYALTY_FAULT_ADJUSTMENT") return "Fault adjustment";
  if (type === "ROYALTY_CREDIT_ADJUSTMENT") return "Credit adjustment";
  if (type === "WITHDRAWAL_RESERVATION") return "Withdrawal reserved";
  if (type === "WITHDRAWAL_RELEASE") return "Withdrawal released";
  return type.replaceAll("_", " ").toLowerCase();
}

function shortId(value: string) {
  return value.slice(0, 8).toUpperCase();
}

function message(error: unknown) {
  return error instanceof Error ? error.message : "Royalty is unavailable.";
}
