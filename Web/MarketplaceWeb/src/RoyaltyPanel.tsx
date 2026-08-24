import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Landmark, RefreshCw, WalletCards } from "lucide-react";
import { formatPrice } from "./catalogue";
import {
  getRoyalty,
  registerRoyaltyPayoutDestination,
  requestRoyaltyWithdrawal,
  retryRoyaltyWithdrawal,
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
                  payoutAvailability={snapshot.payoutAvailability}
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
  payoutAvailability,
  showSubject,
  onChanged,
}: {
  auth: Auth;
  subject: RoyaltySubject;
  payoutAvailability: RoyaltySnapshot["payoutAvailability"];
  showSubject: boolean;
  onChanged: () => Promise<void>;
}) {
  const [amount, setAmount] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string>();
  const [error, setError] = useState<string>();
  const [editingDestination, setEditingDestination] = useState(!subject.payoutDestination);
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
      {!payoutAvailability.destinationRegistrationAvailable && !subject.payoutDestination
        ? (
          <div className="royalty-notice royalty-payout-unavailable" role="status">
            <strong>Royalty payout setup is not active yet.</strong>
            <span>
              Your earnings remain safe in Royalty. Bank or UPI setup will open after the
              secure payout service is connected.
            </span>
          </div>
        )
        : editingDestination || !subject.payoutDestination
        ? (
          <PayoutDestinationForm
            auth={auth}
            subject={subject}
            onSaved={async () => {
              setEditingDestination(false);
              setNotice("Payout destination saved securely.");
              await onChanged();
            }}
          />
        )
        : payoutAvailability.destinationRegistrationAvailable
        ? (
          <button
            className="secondary-button royalty-destination-change"
            type="button"
            onClick={() => setEditingDestination(true)}
          >
            <Landmark size={16} /> Change payout destination
          </button>
        )
        : null}
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
              min="1"
              max={(subject.availablePaise / 100).toFixed(2)}
              step="0.01"
              inputMode="decimal"
              value={amount}
              onChange={(event) => setAmount(event.currentTarget.value)}
              disabled={busy || !subject.canWithdraw ||
                !payoutAvailability.withdrawalExecutionAvailable}
              aria-describedby={"withdraw-help-" + subject.subjectId}
            />
          </span>
        </label>
        <button
          className="primary-button"
          type="submit"
          disabled={busy || !subject.canWithdraw ||
            !payoutAvailability.withdrawalExecutionAvailable || !amountPaise ||
            amountPaise > subject.availablePaise}
        >
          {busy ? "Requesting…" : "Withdraw"}
        </button>
      </form>
      <p id={"withdraw-help-" + subject.subjectId} className="royalty-help">
        {!payoutAvailability.withdrawalExecutionAvailable
          ? "Withdrawals will open after Dastak activates the secure payout service. Your Royalty balance remains unchanged."
          : subject.payoutDestination
          ? "Available Royalty is reserved immediately. Paid appears only after provider confirmation."
          : "Complete payout-method onboarding before requesting a withdrawal."}
      </p>
      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <p className="royalty-notice" role="status">{notice}</p>}
      <RoyaltyHistory title="Earnings and adjustments" entries={subject.entries} />
      <WithdrawalHistory
        auth={auth}
        withdrawals={subject.withdrawals}
        onChanged={onChanged}
      />
    </article>
  );
}

function PayoutDestinationForm({
  auth,
  subject,
  onSaved,
}: {
  auth: Auth;
  subject: RoyaltySubject;
  onSaved: () => Promise<void>;
}) {
  const [type, setType] = useState<"BANK_ACCOUNT" | "UPI">("BANK_ACCOUNT");
  const [holderName, setHolderName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [confirmAccountNumber, setConfirmAccountNumber] = useState("");
  const [ifsc, setIfsc] = useState("");
  const [vpa, setVpa] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const bankValid = /^[0-9]{6,34}$/.test(accountNumber.replace(/\s+/g, "")) &&
    accountNumber.replace(/\s+/g, "") === confirmAccountNumber.replace(/\s+/g, "") &&
    /^[A-Za-z]{4}0[A-Za-z0-9]{6}$/.test(ifsc.trim());
  const upiValid = /^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9.-]{2,64}$/.test(vpa.trim());
  const normalizedHolderName = holderName.trim().replace(/\s+/g, " ");
  const holderNameValid = normalizedHolderName.length >= 3 &&
    normalizedHolderName.length <= 50 &&
    /^[A-Za-z0-9 ._()/'-]+$/.test(normalizedHolderName) &&
    !/[^A-Za-z0-9.]$/.test(normalizedHolderName);
  const valid = holderNameValid && (type === "BANK_ACCOUNT" ? bankValid : upiValid);

  const save = async () => {
    if (!valid || busy) return;
    setBusy(true);
    setError(undefined);
    try {
      await registerRoyaltyPayoutDestination({
        ...auth,
        subjectType: subject.subjectType,
        subjectId: subject.subjectId,
        holderName,
        destination: type === "BANK_ACCOUNT"
          ? { type, accountNumber, confirmAccountNumber, ifsc }
          : { type, vpa },
      });
      setAccountNumber("");
      setConfirmAccountNumber("");
      setVpa("");
      await onSaved();
    } catch (saveError) {
      setError(message(saveError));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form
      className="royalty-destination-form"
      onSubmit={(event) => {
        event.preventDefault();
        void save();
      }}
    >
      <header>
        <div><strong>Payout destination</strong><small>Bank and UPI details are sent only to the secure payout service.</small></div>
      </header>
      <div className="royalty-destination-types" role="radiogroup" aria-label="Payout destination type">
        <label><input type="radio" name={`destination-${subject.subjectId}`} checked={type === "BANK_ACCOUNT"} onChange={() => setType("BANK_ACCOUNT")} /> Indian bank account</label>
        <label><input type="radio" name={`destination-${subject.subjectId}`} checked={type === "UPI"} onChange={() => setType("UPI")} /> UPI ID</label>
      </div>
      <label>Account holder name<input autoComplete="name" maxLength={50} value={holderName} onChange={(event) => setHolderName(event.currentTarget.value)} /></label>
      {type === "BANK_ACCOUNT"
        ? (
          <div className="royalty-destination-grid">
            <label>Account number<input type="password" inputMode="numeric" autoComplete="off" maxLength={34} value={accountNumber} onChange={(event) => setAccountNumber(event.currentTarget.value)} /></label>
            <label>Confirm account number<input type="password" inputMode="numeric" autoComplete="off" maxLength={34} value={confirmAccountNumber} onChange={(event) => setConfirmAccountNumber(event.currentTarget.value)} /></label>
            <label>IFSC<input autoCapitalize="characters" autoComplete="off" maxLength={11} value={ifsc} onChange={(event) => setIfsc(event.currentTarget.value.toUpperCase())} /></label>
          </div>
        )
        : <label>UPI ID<input inputMode="email" autoCapitalize="none" autoComplete="off" maxLength={120} value={vpa} onChange={(event) => setVpa(event.currentTarget.value)} placeholder="name@bank" /></label>}
      <button className="primary-button" type="submit" disabled={!valid || busy}>
        {busy ? "Saving securely…" : "Save payout destination"}
      </button>
      {error ? <p className="order-error" role="alert">{error}</p> : null}
    </form>
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

function WithdrawalHistory({
  auth,
  withdrawals,
  onChanged,
}: {
  auth: Auth;
  withdrawals: RoyaltyWithdrawal[];
  onChanged: () => Promise<void>;
}) {
  const [busyId, setBusyId] = useState<string>();
  const [error, setError] = useState<string>();
  const retry = async (withdrawal: RoyaltyWithdrawal) => {
    setBusyId(withdrawal.id);
    setError(undefined);
    try {
      await retryRoyaltyWithdrawal({
        ...auth,
        withdrawalId: withdrawal.id,
        expectedVersion: withdrawal.version,
      });
      await onChanged();
    } catch (retryError) {
      setError(message(retryError));
    } finally {
      setBusyId(undefined);
    }
  };
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
                {withdrawal.status === "FAILED_RETRYABLE"
                  ? <small>Funds are available again. Retry uses the same protected payout identity.</small>
                  : withdrawal.status === "FAILED"
                  ? <small>The failed amount is available again for a new withdrawal.</small>
                  : withdrawal.status === "REVERSED"
                  ? <small>The reversed amount has been restored to Available Royalty.</small>
                  : withdrawal.reconciliationState === "REVIEW_REQUIRED"
                  ? <small>Operations reconciliation is required.</small>
                  : null}
              </div>
              <div className="royalty-withdrawal-action">
                <strong>{formatPrice(withdrawal.amountPaise)}</strong>
                {(withdrawal.status === "REQUESTED" ||
                  withdrawal.status === "FAILED_RETRYABLE" ||
                  withdrawal.status === "PROCESSING" &&
                    withdrawal.reconciliationState === "PENDING")
                  ? <button className="secondary-button" type="button" disabled={busyId === withdrawal.id} onClick={() => void retry(withdrawal)}>{busyId === withdrawal.id ? "Checking…" : "Check / retry"}</button>
                  : null}
              </div>
            </li>
          ))}
        </ul>
      )}
      {error ? <p className="order-error" role="alert">{error}</p> : null}
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
  if (status === "FAILED") return "Failed";
  if (status === "REVERSED") return "Reversed";
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
