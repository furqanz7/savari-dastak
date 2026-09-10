import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { userFacingError } from "./userFacingError";
import {
  AlertTriangle, Camera, Check, Clock3, PackageCheck, RefreshCw, ShieldCheck, Timer, X,
} from "lucide-react";
import {
  addV1FulfilmentReadyEvidence,
  declareV1FulfilmentPackages,
  getV1MerchantOperationFeeds,
  getV1MerchantOpportunities,
  getV1RestaurantRequests,
  markV1FulfilmentReady,
  reportV1FulfilmentProblem,
  reportV1ExactSkuFailure,
  respondV1ExactSkuRecoveryOffer,
  respondV1RestaurantRequest,
  respondToV1MerchantOpportunity,
  uploadV1MerchantReadyEvidence,
  type DastakV1Auth,
  type V1MerchantFulfilment,
  type V1MerchantOpportunity,
  type V1RecoveryOpportunity,
  type V1RestaurantRequest,
} from "./dastakV1";
import {
  initialMerchantFeedStates,
  isMerchantConcurrencyReconciliation,
  merchantDataIssue,
  merchantFallbackCadence,
  merchantFeedFailed,
  merchantFeedFailures,
  merchantFeedStarted,
  merchantFeedSucceeded,
  merchantFeedsLoading,
  merchantFeedsSettledWithoutErrors,
  shouldRunMerchantFallback,
  type MerchantFeedKey,
  type MerchantFeedStates,
} from "./merchantOperationsState";
import { RefreshCoalescer, RefreshQueue, useOrderRealtime } from "./orderRealtime";
import {
  acceptMerchantOrder,
  confirmMerchantCancellationReturn,
  getMerchantOrders,
  markMerchantOrderReady,
  rejectMerchantOrder,
  type MerchantOrderSnapshot,
} from "./orders";
import { MerchantLiveDelivery } from "./MerchantLiveDelivery";
import {
  merchantFulfilmentQueue,
  merchantPaymentPresentation,
  merchantQueueCounts,
  merchantReadyActionState,
  type MerchantOperationalQueue,
} from "./merchantOrderPresentation";

type Props = {
  auth: DastakV1Auth;
  client: SupabaseClient;
  accountId: string;
  onSessionExpired: () => void;
};

const operationFeedKeys: MerchantFeedKey[] = ["fulfilments", "recovery", "returns", "settlements"];

export function MerchantV1Opportunities({ auth, client, accountId, onSessionExpired }: Props) {
  const [opportunities, setOpportunities] = useState<V1MerchantOpportunity[]>([]);
  const [restaurantRequests, setRestaurantRequests] = useState<V1RestaurantRequest[]>([]);
  const [fulfilments, setFulfilments] = useState<V1MerchantFulfilment[]>([]);
  const [recoveryOpportunities, setRecoveryOpportunities] = useState<V1RecoveryOpportunity[]>([]);
  const [returnReceipts, setReturnReceipts] = useState<Record<string, unknown>[]>([]);
  const [settlements, setSettlements] = useState<Record<string, unknown>[]>([]);
  const [legacyOrders, setLegacyOrders] = useState<MerchantOrderSnapshot[]>([]);
  const [queue, setQueue] = useState<MerchantOperationalQueue>("all");
  const [feedStates, setFeedStates] = useState<MerchantFeedStates>(initialMerchantFeedStates);
  const [refreshing, setRefreshing] = useState(false);
  const [busyId, setBusyId] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [confirmed, setConfirmed] = useState<Set<string>>(() => new Set());
  const [readyConfirmed, setReadyConfirmed] = useState<Set<string>>(() => new Set());
  const [prepMinutes, setPrepMinutes] = useState<Record<string, number>>({});
  const [restaurantPrepMinutes, setRestaurantPrepMinutes] = useState<Record<string, number>>({});
  const [packageCounts, setPackageCounts] = useState<Record<string, number>>({});
  const [evidenceFiles, setEvidenceFiles] = useState<Record<string, File | undefined>>({});
  const [problemId, setProblemId] = useState<string>();
  const [problemReason, setProblemReason] = useState("");
  const [recoveryLineId, setRecoveryLineId] = useState<string>();
  const [recoveryPrepMinutes, setRecoveryPrepMinutes] = useState<Record<string, number>>({});
  const [legacyRejectingId, setLegacyRejectingId] = useState<string>();
  const [legacyRejectReason, setLegacyRejectReason] = useState("");
  const keys = useRef(new Map<string, string>());
  const uploadedEvidence = useRef(new Map<string, string>());
  const sessionRecoveryStarted = useRef(false);
  const retailRefreshQueue = useRef(new RefreshQueue());
  const restaurantRefreshQueue = useRef(new RefreshQueue());
  const operationsRefreshQueue = useRef(new RefreshQueue());
  const legacyRefreshQueue = useRef(new RefreshQueue());

  const recoverSession = useCallback((requestError: unknown) => {
    const issue = merchantDataIssue(requestError);
    if (issue.action !== "sign_in") return false;
    if (!sessionRecoveryStarted.current) {
      sessionRecoveryStarted.current = true;
      onSessionExpired();
    }
    return true;
  }, [onSessionExpired]);

  const recordFeedFailure = useCallback((key: MerchantFeedKey, requestError: unknown) => {
    setFeedStates((current) => merchantFeedFailed(current, key, requestError));
    recoverSession(requestError);
  }, [recoverSession]);

  const refreshRetail = useCallback(async () => {
    await retailRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => merchantFeedStarted(current, ["retail"]));
      try {
        const result = await getV1MerchantOpportunities({ ...auth, limit: 50 });
        setOpportunities(result);
        setPrepMinutes((current) => {
          const next = { ...current };
          result.forEach((opportunity) => {
            next[opportunity.id] ??= opportunity.promisedPrepMinutes ?? opportunity.prepTimeOptionsMinutes[0] ?? 10;
          });
          return next;
        });
        setFeedStates((current) => merchantFeedSucceeded(current, "retail"));
      } catch (requestError) {
        recordFeedFailure("retail", requestError);
      }
    });
  }, [auth, recordFeedFailure]);

  const refreshRestaurants = useCallback(async () => {
    await restaurantRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => merchantFeedStarted(current, ["restaurant"]));
      try {
        const result = await getV1RestaurantRequests({ ...auth, limit: 50 });
        setRestaurantRequests(result);
        setRestaurantPrepMinutes((current) => {
          const next = { ...current };
          result.forEach((request) => { next[request.id] ??= request.promisedPrepMinutes ?? 15; });
          return next;
        });
        setFeedStates((current) => merchantFeedSucceeded(current, "restaurant"));
      } catch (requestError) {
        recordFeedFailure("restaurant", requestError);
      }
    });
  }, [auth, recordFeedFailure]);

  const refreshOperations = useCallback(async () => {
    await operationsRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => merchantFeedStarted(current, operationFeedKeys));
      try {
        const result = await getV1MerchantOperationFeeds({ ...auth, limit: 50 });
        if (result.fulfilments.ok) {
          const values = result.fulfilments.value;
          setFulfilments(values);
          setPackageCounts((current) => {
            const next = { ...current };
            values.forEach((fulfilment) => {
              next[fulfilment.id] ??= fulfilment.packageCount ?? 1;
            });
            return next;
          });
          setFeedStates((current) => merchantFeedSucceeded(current, "fulfilments"));
        } else recordFeedFailure("fulfilments", result.fulfilments.error);

        if (result.recoveryOpportunities.ok) {
          const values = result.recoveryOpportunities.value;
          setRecoveryOpportunities(values);
          setRecoveryPrepMinutes((current) => {
            const next = { ...current };
            values.forEach((opportunity) => {
              next[opportunity.id] ??= opportunity.promisedPrepMinutes ?? 10;
            });
            return next;
          });
          setFeedStates((current) => merchantFeedSucceeded(current, "recovery"));
        } else recordFeedFailure("recovery", result.recoveryOpportunities.error);

        if (result.returnReceipts.ok) {
          setReturnReceipts(result.returnReceipts.value);
          setFeedStates((current) => merchantFeedSucceeded(current, "returns"));
        } else recordFeedFailure("returns", result.returnReceipts.error);

        if (result.settlements.ok) {
          setSettlements(result.settlements.value);
          setFeedStates((current) => merchantFeedSucceeded(current, "settlements"));
        } else recordFeedFailure("settlements", result.settlements.error);
      } catch (requestError) {
        operationFeedKeys.forEach((key) => recordFeedFailure(key, requestError));
      }
    });
  }, [auth, recordFeedFailure]);

  const refreshLegacy = useCallback(async () => {
    await legacyRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => merchantFeedStarted(current, ["legacy"]));
      try {
        setLegacyOrders(await getMerchantOrders(auth));
        setFeedStates((current) => merchantFeedSucceeded(current, "legacy"));
      } catch (requestError) {
        recordFeedFailure("legacy", requestError);
      }
    });
  }, [auth, recordFeedFailure]);

  const refresh = useCallback(async (showProgress = false) => {
    if (showProgress) setRefreshing(true);
    try {
      await Promise.allSettled([refreshRetail(), refreshRestaurants(), refreshOperations(), refreshLegacy()]);
    } finally {
      if (showProgress) setRefreshing(false);
    }
  }, [refreshLegacy, refreshOperations, refreshRestaurants, refreshRetail]);

  const refreshRef = useRef(refresh);
  refreshRef.current = refresh;
  const reconcileCoalescer = useRef<RefreshCoalescer<void> | undefined>(undefined);
  if (!reconcileCoalescer.current) {
    reconcileCoalescer.current = new RefreshCoalescer(() => void refreshRef.current(false));
  }
  const requestReconciliation = useCallback(() => reconcileCoalescer.current?.request(), []);
  const realtimeHealth = useOrderRealtime({
    client,
    accountId,
    accessToken: auth.accessToken,
    onChange: requestReconciliation,
  });

  useEffect(() => {
    void refresh();
    return () => reconcileCoalescer.current?.cancel();
  }, [refresh]);

  useEffect(() => {
    let fallback: number | undefined;
    const stop = () => {
      if (fallback !== undefined) window.clearInterval(fallback);
      fallback = undefined;
    };
    const start = () => {
      stop();
      if (!shouldRunMerchantFallback(document.visibilityState, navigator.onLine !== false)) return;
      fallback = window.setInterval(requestReconciliation, merchantFallbackCadence(realtimeHealth));
    };
    start();
    document.addEventListener("visibilitychange", start);
    window.addEventListener("online", start);
    window.addEventListener("offline", stop);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", start);
      window.removeEventListener("online", start);
      window.removeEventListener("offline", stop);
    };
  }, [realtimeHealth, requestReconciliation]);

  const keyFor = (identity: string) => {
    const key = keys.current.get(identity) ?? crypto.randomUUID();
    keys.current.set(identity, key);
    return key;
  };

  const handleActionFailure = useCallback(async (actionFailure: unknown) => {
    if (isMerchantConcurrencyReconciliation(actionFailure)) {
      setNotice("This order changed elsewhere. Dastak has reconciled the latest status.");
    } else if (!recoverSession(actionFailure)) {
      setActionError(message(actionFailure));
    }
    await refresh();
  }, [recoverSession, refresh]);

  const respond = async (opportunity: V1MerchantOpportunity, action: "accept" | "unavailable") => {
    if (busyId || (action === "accept" && !confirmed.has(opportunity.id))) return;
    const identity = `${action}:${opportunity.id}:${opportunity.version}`;
    setBusyId(opportunity.id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      await respondToV1MerchantOpportunity({
        ...auth,
        opportunityId: opportunity.id,
        requestScope: opportunity.requestScope,
        expectedVersion: opportunity.version,
        action,
        promisedPrepMinutes: action === "accept" ? prepMinutes[opportunity.id] : undefined,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      await refresh();
    } catch (responseError) {
      await handleActionFailure(responseError);
    } finally {
      setBusyId(undefined);
    }
  };

  const respondRestaurant = async (request: V1RestaurantRequest, response: "CONFIRM" | "DECLINE") => {
    if (busyId) return;
    const identity = `restaurant:${response}:${request.id}:${request.version}`;
    setBusyId(request.id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      await respondV1RestaurantRequest({
        ...auth,
        requestId: request.id,
        response,
        promisedPrepMinutes: response === "CONFIRM" ? restaurantPrepMinutes[request.id] ?? 15 : undefined,
        reason: response === "DECLINE" ? "Restaurant cannot fulfil this exact request" : undefined,
        expectedVersion: request.version,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      await refresh();
    } catch (responseError) {
      await handleActionFailure(responseError);
    } finally {
      setBusyId(undefined);
    }
  };

  const captureEvidence = async (fulfilment: V1MerchantFulfilment) => {
    if (!fulfilment.canAddEvidence) throw new Error("This order is not ready for a preparation photo yet.");
    const file = evidenceFiles[fulfilment.id];
    if (!file) throw new Error("Capture or choose a prepared-order photo first.");
    let objectPath = uploadedEvidence.current.get(fulfilment.id);
    if (!objectPath) {
      objectPath = await uploadV1MerchantReadyEvidence(client, accountId, file);
      uploadedEvidence.current.set(fulfilment.id, objectPath);
    }
    const identity = `evidence:${fulfilment.id}:${fulfilment.version}:${objectPath}`;
    const updated = await addV1FulfilmentReadyEvidence({
      ...auth,
      fulfilmentId: fulfilment.id,
      packageId: fulfilment.packages[0]?.id,
      objectPath,
      expectedVersion: fulfilment.version,
      idempotencyKey: keyFor(identity),
    });
    keys.current.delete(identity);
    uploadedEvidence.current.delete(fulfilment.id);
    setEvidenceFiles((current) => ({ ...current, [fulfilment.id]: undefined }));
    setFulfilments((current) => current.map((item) => item.id === updated.id ? updated : item));
    return updated;
  };

  const declarePackages = async (fulfilment: V1MerchantFulfilment) => {
    if (busyId || !fulfilment.canDeclarePackages) return;
    const packageCount = packageCounts[fulfilment.id];
    if (!Number.isSafeInteger(packageCount) || packageCount < 1 || packageCount > 1000) {
      setActionError("Enter a package count from 1 to 1000.");
      return;
    }
    const identity = `packages:${fulfilment.id}:${fulfilment.version}:${packageCount}`;
    setBusyId(fulfilment.id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      const updated = await declareV1FulfilmentPackages({
        ...auth,
        fulfilmentId: fulfilment.id,
        packageCount,
        expectedVersion: fulfilment.version,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      setFulfilments((values) => values.map((item) => item.id === updated.id ? updated : item));
    } catch (packageError) {
      await handleActionFailure(packageError);
    } finally {
      setBusyId(undefined);
    }
  };

  const markReady = async (fulfilment: V1MerchantFulfilment) => {
    if (busyId || !fulfilment.canMarkReady ||
      (fulfilment.readyIsIrreversible && !readyConfirmed.has(fulfilment.id))) return;
    setBusyId(fulfilment.id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      const identity = `ready:${fulfilment.id}:${fulfilment.version}`;
      const ready = await markV1FulfilmentReady({
        ...auth,
        fulfilmentId: fulfilment.id,
        expectedVersion: fulfilment.version,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      setFulfilments((values) => values.map((item) => item.id === ready.id ? ready : item));
      setReadyConfirmed((values) => without(values, ready.id));
    } catch (readyError) {
      await handleActionFailure(readyError);
    } finally {
      setBusyId(undefined);
    }
  };

  const addPhoto = async (fulfilment: V1MerchantFulfilment) => {
    if (busyId || !fulfilment.canAddEvidence) return;
    setBusyId(fulfilment.id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      await captureEvidence(fulfilment);
    } catch (evidenceError) {
      await handleActionFailure(evidenceError);
    } finally {
      setBusyId(undefined);
    }
  };

  const reportProblem = async (fulfilment: V1MerchantFulfilment) => {
    const reason = problemReason.trim();
    if (busyId || reason.length < 3) return;
    const identity = `problem:${fulfilment.id}:${fulfilment.version}:${reason}`;
    setBusyId(fulfilment.id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      if (fulfilment.canReportExactSkuFailure) {
        const orderLineId = recoveryLineId ?? fulfilment.lines[0]?.orderLineId;
        if (!orderLineId) throw new Error("Choose the exact unavailable item.");
        await reportV1ExactSkuFailure({
          ...auth, fulfilmentId: fulfilment.id, orderLineId, reason,
          expectedVersion: fulfilment.version, idempotencyKey: keyFor(identity),
        });
      } else {
        const updated = await reportV1FulfilmentProblem({
          ...auth, fulfilmentId: fulfilment.id, reason,
          expectedVersion: fulfilment.version, idempotencyKey: keyFor(identity),
        });
        setFulfilments((values) =>
          values.map((item) => item.id === updated.id ? updated : item));
      }
      keys.current.delete(identity);
      setProblemId(undefined);
      setProblemReason("");
      setRecoveryLineId(undefined);
      await refresh();
    } catch (problemError) {
      await handleActionFailure(problemError);
    } finally {
      setBusyId(undefined);
    }
  };

  const respondRecovery = async (
    opportunity: V1RecoveryOpportunity,
    response: "ACCEPT" | "UNAVAILABLE",
  ) => {
    if (busyId || (response === "ACCEPT" && !confirmed.has(opportunity.id))) return;
    setBusyId(opportunity.id);
    setActionError(undefined);
    setNotice(undefined);
    const identity = `recovery:${response}:${opportunity.id}:${opportunity.version}`;
    try {
      await respondV1ExactSkuRecoveryOffer({
        ...auth, recoveryOpportunityId: opportunity.id, response,
        promisedPrepMinutes: response === "ACCEPT"
          ? recoveryPrepMinutes[opportunity.id] ?? 10 : undefined,
        expectedVersion: opportunity.version,
        idempotencyKey: keyFor(identity),
      });
      keys.current.delete(identity);
      await refresh();
    } catch (responseError) {
      await handleActionFailure(responseError);
    } finally {
      setBusyId(undefined);
    }
  };

  const performLegacyAction = async (
    order: MerchantOrderSnapshot,
    action: "accept" | "reject" | "ready" | "confirmReturn",
  ) => {
    if (busyId) return;
    const reason = legacyRejectReason.trim();
    if (action === "reject" && reason.length < 3) return;
    const identity = `legacy:${action}:${order.orderId}:${order.stateVersion}`;
    setBusyId(order.orderId);
    setActionError(undefined);
    setNotice(undefined);
    try {
      if (action === "accept") await acceptMerchantOrder({ ...auth, orderId: order.orderId, idempotencyKey: keyFor(identity) });
      if (action === "ready") await markMerchantOrderReady({ ...auth, orderId: order.orderId, idempotencyKey: keyFor(identity) });
      if (action === "reject") await rejectMerchantOrder({ ...auth, orderId: order.orderId, reason, idempotencyKey: keyFor(identity) });
      if (action === "confirmReturn") await confirmMerchantCancellationReturn({ ...auth, orderId: order.orderId, reason: "All returned items received", idempotencyKey: keyFor(identity) });
      keys.current.delete(identity);
      setLegacyRejectingId(undefined);
      setLegacyRejectReason("");
      await refreshLegacy();
    } catch (legacyError) {
      await handleActionFailure(legacyError);
    } finally {
      setBusyId(undefined);
    }
  };

  const visibleOpportunities = useMemo(
    () => opportunities.filter((opportunity) =>
      opportunity.status === "OFFERED" ||
      opportunity.reservationState === "ITEMS_HELD_WHILE_ORDER_COMPLETES"
    ),
    [opportunities],
  );
  const queueFulfilments = useMemo(
    () => fulfilments.filter((fulfilment) => queue === "all"
      ? merchantFulfilmentQueue(fulfilment) !== "history" && ["PREPARING", "READY", "PICKED_UP"].includes(fulfilment.status)
      : merchantFulfilmentQueue(fulfilment) === queue),
    [fulfilments, queue],
  );
  const offeredRestaurants = restaurantRequests.filter((request) => request.status === "OFFERED");
  const offeredRecovery = recoveryOpportunities.filter((item) => item.status === "OFFERED");
  const counts = merchantQueueCounts({ opportunities, restaurantRequests, fulfilments });
  const showIncoming = queue === "all" || queue === "new";
  const showHistory = queue === "history";
  const activeLegacyOrders = legacyOrders.filter((order) => !isLegacyHistory(order));
  const historicalLegacyOrders = legacyOrders.filter(isLegacyHistory);
  const visibleLegacyOrders = showHistory ? historicalLegacyOrders : queue === "all" ? activeLegacyOrders : [];
  const displayCounts = {
    ...counts,
    all: counts.all + offeredRecovery.length
      + visibleOpportunities.filter((item) => item.status !== "OFFERED").length + activeLegacyOrders.length,
    new: counts.new + offeredRecovery.length,
    history: counts.history + historicalLegacyOrders.length + returnReceipts.length,
  };
  const hasContent = queueFulfilments.length > 0 ||
    (showIncoming && (offeredRestaurants.length > 0 || offeredRecovery.length > 0 || visibleOpportunities.length > 0)) ||
    (showHistory && (returnReceipts.length > 0 || settlements.length > 0)) || visibleLegacyOrders.length > 0;

  return <section className="v1-merchant-panel" aria-labelledby="v1-merchant-title">
    <header>
      <div><p className="eyebrow">LIVE OPERATIONS</p><h2 id="v1-merchant-title">Current fulfilments</h2><span>Confirm exact items, then prepare every declared package as soon as the customer confirms the order.</span></div>
      <button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={refreshing} aria-label="Refresh fulfilments"><RefreshCw size={18} /></button>
    </header>
    {realtimeHealth !== "subscribed" ? <p className="v1-reservation-state" role="status">Live updates are reconnecting. Dastak will reconcile this order desk automatically.</p> : null}
    {notice ? <p className="v1-reservation-state" role="status">{notice}</p> : null}
    {actionError ? <p className="order-error" role="alert">{actionError}</p> : null}
    <nav className="v1-merchant-queues" aria-label="Order queues">
      {(["all", "new", "preparing", "ready", "history"] as const).map((value) => <button
        key={value}
        type="button"
        className={queue === value ? "selected" : ""}
        aria-current={queue === value ? "page" : undefined}
        onClick={() => setQueue(value)}
      ><span>{value[0].toUpperCase() + value.slice(1)}</span><b>{displayCounts[value]}</b></button>)}
    </nav>
    <MerchantOperationsStatus states={feedStates} hasContent={hasContent} />
    {showIncoming && offeredRestaurants.length > 0 ? <div className="v1-opportunity-list">
        {offeredRestaurants.map((request) => <article className="v1-opportunity-card" key={request.id}>
          <header><span className="v1-opportunity-icon"><PackageCheck size={20} /></span><span><strong>{request.displayOrderNumber}</strong><small>Exact Restaurant/Cafe request · {request.branch.displayName}</small></span><b>CONFIRM FOOD</b></header>
          <ul>{request.lines.map((line) => <li key={line.orderLineId}><span><strong>{line.quantity}× {line.name}</strong><small>{selectionSummary(line.selection)}</small></span><b>{formatPaise(line.unitPricePaise * line.quantity)}</b></li>)}</ul>
          {request.softThresholdWarning ? <p className="v1-reservation-state">{request.activeOrderCount} active orders exceeds the default soft threshold of {request.softActiveOrderThreshold}. You may still accept if the kitchen can handle it.</p> : null}
          <label className="v1-prep-choice"><span>Preparation promise</span><input type="number" min={1} max={240} value={restaurantPrepMinutes[request.id] ?? 15} onChange={(event) => setRestaurantPrepMinutes((current) => ({ ...current, [request.id]: Number(event.target.value) }))} /></label>
          <p className="v1-reservation-state">Confirmation binds these exact menu selections. Preparation starts after the customer confirms; the rider collects payment at delivery.</p>
          <div className="v1-opportunity-actions"><button className="secondary-button" type="button" disabled={busyId === request.id} onClick={() => void respondRestaurant(request, "DECLINE")}><X size={17} /> Decline</button><button className="primary-button" type="button" disabled={busyId === request.id || (restaurantPrepMinutes[request.id] ?? 15) < 1} onClick={() => void respondRestaurant(request, "CONFIRM")}><Check size={17} /> {busyId === request.id ? "Confirming…" : "Confirm exact food"}</button></div>
        </article>)}
      </div> : null}
      {queueFulfilments.length > 0 ? <div className="v1-preparation-list">
        {queueFulfilments.map((fulfilment) => <FulfilmentCard
          key={fulfilment.id}
          fulfilment={fulfilment}
          trackingDelayed={realtimeHealth !== "subscribed"}
          busy={busyId === fulfilment.id}
          packageCount={packageCounts[fulfilment.id] ?? 1}
          evidenceFile={evidenceFiles[fulfilment.id]}
          irreversibleConfirmed={readyConfirmed.has(fulfilment.id)}
          reportingProblem={problemId === fulfilment.id}
          problemReason={problemId === fulfilment.id ? problemReason : ""}
          recoveryLineId={problemId === fulfilment.id ? recoveryLineId : undefined}
          onPackageCount={(value) => setPackageCounts((current) => ({ ...current, [fulfilment.id]: value }))}
          onEvidenceFile={(file) => {
            uploadedEvidence.current.delete(fulfilment.id);
            setEvidenceFiles((current) => ({ ...current, [fulfilment.id]: file }));
          }}
          onIrreversibleConfirm={(checked) => setReadyConfirmed((current) => checked ? withValue(current, fulfilment.id) : without(current, fulfilment.id))}
          onDeclarePackages={() => void declarePackages(fulfilment)}
          onAddPhoto={() => void addPhoto(fulfilment)}
          onMarkReady={() => void markReady(fulfilment)}
          onStartProblem={() => {
            setProblemId(fulfilment.id);
            setProblemReason("");
            setRecoveryLineId(fulfilment.lines[0]?.orderLineId);
          }}
          onCancelProblem={() => {
            setProblemId(undefined);
            setProblemReason("");
            setRecoveryLineId(undefined);
          }}
          onProblemReason={setProblemReason}
          onRecoveryLine={setRecoveryLineId}
          onReportProblem={() => void reportProblem(fulfilment)}
        />)}
      </div> : null}
      {visibleLegacyOrders.length > 0 ? <div className="v1-preparation-list" aria-label="Earlier orders">
        {visibleLegacyOrders.map((order) => <LegacyMerchantOrderCard
          key={order.orderId}
          order={order}
          busy={busyId === order.orderId}
          rejecting={legacyRejectingId === order.orderId}
          rejectReason={legacyRejectingId === order.orderId ? legacyRejectReason : ""}
          onRejectReason={setLegacyRejectReason}
          onStartReject={() => { setLegacyRejectingId(order.orderId); setLegacyRejectReason(""); }}
          onCancelReject={() => { setLegacyRejectingId(undefined); setLegacyRejectReason(""); }}
          onAccept={() => void performLegacyAction(order, "accept")}
          onReject={() => void performLegacyAction(order, "reject")}
          onReady={() => void performLegacyAction(order, "ready")}
          onConfirmReturn={() => void performLegacyAction(order, "confirmReturn")}
        />)}
      </div> : null}
      {showIncoming && offeredRecovery.length > 0 ? <div className="v1-opportunity-list">
        {offeredRecovery.map((opportunity) => <RecoveryOpportunityCard
          key={opportunity.id}
          opportunity={opportunity}
          busy={busyId === opportunity.id}
          confirmed={confirmed.has(opportunity.id)}
          prepMinutes={recoveryPrepMinutes[opportunity.id] ?? 10}
          onConfirmed={(checked) => setConfirmed((current) => checked ? withValue(current, opportunity.id) : without(current, opportunity.id))}
          onPrepMinutes={(value) => setRecoveryPrepMinutes((current) => ({ ...current, [opportunity.id]: value }))}
          onUnavailable={() => void respondRecovery(opportunity, "UNAVAILABLE")}
          onAccept={() => void respondRecovery(opportunity, "ACCEPT")}
        />)}
      </div> : null}
      {showIncoming && visibleOpportunities.length > 0 ? <div className="v1-opportunity-list">
        {visibleOpportunities.map((opportunity) => <MerchantOpportunityCard
          key={opportunity.id}
          opportunity={opportunity}
          busy={busyId === opportunity.id}
          confirmed={confirmed.has(opportunity.id)}
          prepMinutes={prepMinutes[opportunity.id] ?? opportunity.prepTimeOptionsMinutes[0] ?? 10}
          onConfirmed={(checked) => setConfirmed((current) => checked ? withValue(current, opportunity.id) : without(current, opportunity.id))}
          onPrepMinutes={(value) => setPrepMinutes((current) => ({ ...current, [opportunity.id]: value }))}
          onUnavailable={() => void respond(opportunity, "unavailable")}
          onAccept={() => void respond(opportunity, "accept")}
        />)}
      </div> : null}
      {showHistory && returnReceipts.length > 0 ? <div className="v1-preparation-list">
        {returnReceipts.map((receipt, index) => <article className="v1-preparation-card" key={recordText(receipt, "returnStopId") ?? index}>
          <header><span className="v1-opportunity-icon"><PackageCheck size={20} /></span><span><strong>Return receipt</strong><small>{recordText(recordObject(receipt, "branch"), "displayName") ?? "Merchant branch"}</small></span><b>{(recordText(receipt, "status") ?? "PENDING").replaceAll("_", " ")}</b></header>
          <p>{recordNumber(receipt, "packageCount") ?? 0} package(s) must transfer together from the assigned rider.</p>
          {recordText(receipt, "receiptCode") ? <div className="v1-merchant-pickup-code"><small>Give this in-app code only after every returned package is present</small><strong>{recordText(receipt, "receiptCode")}</strong></div> : <p className="v1-reservation-state">Receipt verification {recordText(receipt, "verificationStatus")?.toLowerCase() ?? "pending"}.</p>}
        </article>)}
      </div> : null}
      {showHistory && settlements.length > 0 ? <div className="v1-preparation-times" aria-label="Settlement status">
        <span><small>Settlement entries</small><strong>{settlements.length}</strong></span>
        <span><small>Eligible</small><strong>{settlements.filter((item) => recordText(item, "status") === "ELIGIBLE").length}</strong></span>
        <span><small>Settled</small><strong>{settlements.filter((item) => recordText(item, "status") === "SETTLED").length}</strong></span>
      </div> : null}
  </section>;
}

export function MerchantOperationsStatus({ states, hasContent }: {
  states: MerchantFeedStates;
  hasContent: boolean;
}) {
  const failures = merchantFeedFailures(states);
  if (failures.length > 0) {
    const labels = failures.map((failure) => failure.label).join(", ");
    const sessionExpired = failures.some((failure) => failure.issue.action === "sign_in");
    return <p className="order-error" role={hasContent ? "status" : "alert"}>
      {sessionExpired
        ? "Your session expired. Dastak is returning you to sign in."
        : `${labels} could not update. ${hasContent ? "Previously loaded information remains visible." : "Dastak will retry automatically."}`}
    </p>;
  }
  if (!hasContent && merchantFeedsLoading(states)) {
    return <div className="catalogue-loading" role="status"><span /> Loading fulfilments</div>;
  }
  if (!hasContent && merchantFeedsSettledWithoutErrors(states)) {
    return <p className="v1-merchant-empty">You’re online. New exact-item requests will appear here.</p>;
  }
  return null;
}

type OpportunityCardProps = {
  opportunity: V1MerchantOpportunity;
  busy: boolean;
  confirmed: boolean;
  prepMinutes: number;
  onConfirmed: (checked: boolean) => void;
  onPrepMinutes: (minutes: number) => void;
  onUnavailable: () => void;
  onAccept: () => void;
};

function MerchantOpportunityCard({
  opportunity, busy, confirmed, prepMinutes,
  onConfirmed, onPrepMinutes, onUnavailable, onAccept,
}: OpportunityCardProps) {
  const now = useTickingNow();
  const seconds = Math.max(0, Math.ceil((Date.parse(opportunity.expiresAt) - now) / 1_000));
  const offered = opportunity.status === "OFFERED" && seconds > 0;
  return <article className="v1-opportunity-card">
    <header>
      <span className="v1-opportunity-icon"><PackageCheck size={20} /></span>
      <span><strong>{opportunity.displayOrderNumber}</strong><small>{opportunity.requestScope === "FULL_BASKET" ? "Complete basket request" : "Exact subset request"} · {opportunity.branch.displayName}</small></span>
      {offered ? <b><Clock3 size={14} /> {formatDuration(seconds)}</b> : <b>{reservationLabel(opportunity)}</b>}
    </header>
    <LineList lines={opportunity.lines} />
    {offered ? <>
      <label className="v1-physical-check"><input type="checkbox" checked={confirmed} onChange={(event) => onConfirmed(event.target.checked)} /><span>I physically confirmed every exact SKU and quantity above.</span></label>
      <label className="v1-prep-choice"><span>Preparation promise</span><select value={prepMinutes} onChange={(event) => onPrepMinutes(Number(event.target.value))}>{opportunity.prepTimeOptionsMinutes.map((minutes) => <option key={minutes} value={minutes}>{minutes} minutes</option>)}</select></label>
      <div className="v1-opportunity-actions"><button className="secondary-button" type="button" disabled={busy} onClick={onUnavailable}><X size={17} /> Unavailable</button><button className="primary-button" type="button" disabled={busy || !confirmed} onClick={onAccept}><Check size={17} /> {busy ? "Confirming…" : "Accept and hold items"}</button></div>
    </> : <p className={`v1-reservation-state ${opportunity.reservationState.toLowerCase()}`}>{reservationCopy(opportunity)}</p>}
  </article>;
}

type RecoveryOpportunityCardProps = {
  opportunity: V1RecoveryOpportunity;
  busy: boolean;
  confirmed: boolean;
  prepMinutes: number;
  onConfirmed: (checked: boolean) => void;
  onPrepMinutes: (minutes: number) => void;
  onUnavailable: () => void;
  onAccept: () => void;
};

function RecoveryOpportunityCard({
  opportunity, busy, confirmed, prepMinutes,
  onConfirmed, onPrepMinutes, onUnavailable, onAccept,
}: RecoveryOpportunityCardProps) {
  const now = useTickingNow();
  const seconds = Math.max(0, Math.ceil((Date.parse(opportunity.expiresAt) - now) / 1_000));
  return <article className="v1-opportunity-card running-late">
    <header>
      <span className="v1-opportunity-icon"><AlertTriangle size={20} /></span>
      <span><strong>Exact-item recovery</strong><small>{opportunity.branch.displayName}</small></span>
      <b><Clock3 size={14} /> {formatDuration(seconds)}</b>
    </header>
    <ul><li><span><strong>{opportunity.requestedQuantity}× {opportunity.sku.name}</strong><small>{[opportunity.sku.variantName, opportunity.sku.packSize].filter(Boolean).join(" · ")}</small></span></li></ul>
    <label className="v1-physical-check"><input type="checkbox" checked={confirmed} onChange={(event) => onConfirmed(event.target.checked)} /><span>I physically hold this exact SKU and full quantity. No substitution.</span></label>
    <label className="v1-prep-choice"><span>Preparation promise</span><input type="number" min={1} max={180} value={prepMinutes} onChange={(event) => onPrepMinutes(Number(event.target.value))} /></label>
    <div className="v1-opportunity-actions"><button className="secondary-button" type="button" disabled={busy} onClick={onUnavailable}><X size={17} /> Unavailable</button><button className="primary-button" type="button" disabled={busy || !confirmed || seconds === 0} onClick={onAccept}><Check size={17} /> Accept exact item</button></div>
  </article>;
}

type FulfilmentCardProps = {
  fulfilment: V1MerchantFulfilment;
  trackingDelayed: boolean;
  busy: boolean;
  packageCount: number;
  evidenceFile?: File;
  irreversibleConfirmed: boolean;
  reportingProblem: boolean;
  problemReason: string;
  recoveryLineId?: string;
  onPackageCount: (value: number) => void;
  onEvidenceFile: (file?: File) => void;
  onIrreversibleConfirm: (checked: boolean) => void;
  onDeclarePackages: () => void;
  onAddPhoto: () => void;
  onMarkReady: () => void;
  onStartProblem: () => void;
  onCancelProblem: () => void;
  onProblemReason: (reason: string) => void;
  onRecoveryLine: (lineId: string) => void;
  onReportProblem: () => void;
};

function FulfilmentCard(props: FulfilmentCardProps) {
  const { fulfilment } = props;
  const now = useTickingNow();
  const preparing = fulfilment.status === "PREPARING";
  const remaining = fulfilment.estimatedReadyAt
    ? Math.ceil((Date.parse(fulfilment.estimatedReadyAt) - now) / 1_000)
    : 0;
  const runningLate = preparing && remaining < 0;
  const hasRequiredEvidence = fulfilment.evidence.some((item) => item.type === "MERCHANT_READY_PHOTO");
  const capabilities = merchantReadyActionState(fulfilment, props.irreversibleConfirmed);
  const readyActionEnabled = capabilities.canMarkReady;
  const payment = merchantPaymentPresentation();
  const history = merchantFulfilmentQueue(fulfilment) === "history";

  return <article className={`v1-preparation-card ${runningLate ? "running-late" : ""}`}>
    <header>
      <span className="v1-opportunity-icon">{runningLate ? <AlertTriangle size={20} /> : <Timer size={20} />}</span>
      <span><strong>{fulfilment.displayOrderNumber}</strong><small>{fulfilment.branch.displayName} · {fulfilment.promisedPrepMinutes}-minute promise</small></span>
      <b>{fulfilment.status === "PICKED_UP" ? "PICKED UP" : fulfilment.status === "READY" ? "READY FOR PICKUP" : runningLate ? `RUNNING LATE · +${formatDuration(Math.abs(remaining))}` : formatDuration(Math.max(0, remaining))}</b>
    </header>
    <LineList lines={fulfilment.lines} />
    <div className="v1-preparation-times">
      <span><small>Preparation started</small><strong>{formatOptionalTime(fulfilment.prepStartedAt)}</strong></span>
      <span><small>Promised Ready</small><strong>{formatOptionalTime(fulfilment.estimatedReadyAt)}</strong></span>
      <span><small>Actual Ready</small><strong>{formatOptionalTime(fulfilment.actualReadyAt)}</strong></span>
    </div>
    <p className="v1-reservation-state"><ShieldCheck size={16} /> <strong>{payment.state}.</strong> {payment.detail}</p>
    {fulfilment.delivery ? <div className="v1-merchant-pickup-state">
      <span><small>Delivery partner</small><strong>{fulfilment.delivery.riderAssigned ? fulfilment.delivery.rider?.displayName ?? "Assigned" : "Finding rider"}</strong></span>
      <span><small>Pickup status</small><strong>{merchantPickupLabel(fulfilment.delivery.stopStatus, fulfilment.delivery.riderArrivedAt)}</strong></span>
      <span><small>Waiting</small><strong>{fulfilment.delivery.riderArrivedAt ? formatDuration(fulfilment.delivery.waitingSeconds) : "—"}</strong></span>
      {fulfilment.delivery.pickupCode ? <div className="v1-merchant-pickup-code"><small>Give this in-app code to the assigned rider after every package is present</small><strong>{fulfilment.delivery.pickupCode}</strong></div> : null}
      {fulfilment.delivery.verificationStatus === "CONSUMED" ? <p><Check size={17} /> Pickup verified. Package custody transferred to the rider.</p> : null}
    </div> : null}
    <MerchantLiveDelivery fulfilment={fulfilment} delayed={props.trackingDelayed} />
    {preparing ? <div className="v1-ready-workflow">
      <label><span>Physical package count</span><input type="number" inputMode="numeric" min={1} max={1000} value={fulfilment.packageCount ?? props.packageCount} disabled={!capabilities.canDeclarePackages || props.busy} onChange={(event) => props.onPackageCount(Number(event.target.value))} />{capabilities.canDeclarePackages ? <small>Count every sealed package before declaring it.</small> : <small>{fulfilment.packageCount ? "Declared and locked for pickup" : "Package declaration is not available in the current state."}</small>}</label>
      {capabilities.canDeclarePackages ? <button className="secondary-button v1-add-photo" type="button" disabled={props.busy || props.packageCount < 1} onClick={props.onDeclarePackages}><PackageCheck size={17} /> {props.busy ? "Declaring…" : "Declare package count"}</button> : null}
      <label className="v1-photo-field"><span>Prepared items / package photo</span><input type="file" accept="image/jpeg,image/png,image/heic" capture="environment" disabled={!capabilities.canAddEvidence || props.busy} onChange={(event) => props.onEvidenceFile(event.target.files?.[0])} /><small>{props.evidenceFile?.name ?? (hasRequiredEvidence ? `${fulfilment.evidence.length} immutable photo(s) recorded` : capabilities.canAddEvidence ? "Required before Ready · JPG, PNG or HEIC up to 10 MB" : "Photo evidence unlocks after the server accepts the package declaration.")}</small></label>
      {capabilities.canAddEvidence && props.evidenceFile ? <button className="secondary-button v1-add-photo" type="button" disabled={props.busy} onClick={props.onAddPhoto}><Camera size={17} /> {props.busy ? "Recording…" : hasRequiredEvidence ? "Add another photo" : "Record preparation photo"}</button> : null}
      {fulfilment.readyIsIrreversible ? <label className="v1-physical-check"><input type="checkbox" checked={props.irreversibleConfirmed} disabled={!fulfilment.canMarkReady || props.busy} onChange={(event) => props.onIrreversibleConfirm(event.target.checked)} /><span>I confirm every declared package is complete. Ready is irreversible.</span></label> : null}
      <button className="primary-button v1-mark-ready" type="button" disabled={props.busy || !readyActionEnabled} onClick={props.onMarkReady}><PackageCheck size={18} /> {props.busy ? "Finalising Ready…" : "Mark Ready"}</button>
    </div> : <p className="v1-ready-complete"><PackageCheck size={18} /> {history ? "This order is in History." : `${fulfilment.packageCount ?? 0} package(s) ${fulfilment.status === "PICKED_UP" ? "picked up together" : "Ready"}. Original evidence and Ready time are locked.`}</p>}
    {fulfilment.evidence.length > 0 ? <p className="v1-evidence-count"><Camera size={15} /> {fulfilment.evidence.length} immutable evidence photo(s)</p> : null}
    {!history && fulfilment.status !== "PICKED_UP" ? (props.reportingProblem ? <div className="v1-problem-form">
      {fulfilment.canReportExactSkuFailure ? <label><span>Exact unavailable item</span><select value={props.recoveryLineId ?? ""} onChange={(event) => props.onRecoveryLine(event.target.value)}>{fulfilment.lines.map((line) => <option key={line.orderLineId} value={line.orderLineId}>{line.quantity}× {line.name} · {line.packSize}</option>)}</select><small>Dastak will recover only this exact SKU and full quantity.</small></label> : null}
      <label><span>Problem details</span><textarea value={props.problemReason} maxLength={500} rows={3} autoFocus onChange={(event) => props.onProblemReason(event.target.value)} /></label><div><button className="secondary-button" type="button" disabled={props.busy} onClick={props.onCancelProblem}>Back</button><button className="primary-button" type="button" disabled={props.busy || props.problemReason.trim().length < 3} onClick={props.onReportProblem}>{props.busy ? "Reporting…" : fulfilment.canReportExactSkuFailure ? "Start exact-item recovery" : "Report problem"}</button></div></div> : <button className="v1-report-problem" type="button" disabled={props.busy} onClick={props.onStartProblem}><AlertTriangle size={16} /> Report problem</button>) : null}
    {fulfilment.problemReports.length > 0 ? <small className="v1-problem-history">{fulfilment.problemReports.length} problem report(s) preserved for operator review.</small> : null}
  </article>;
}

function merchantPickupLabel(status: "PENDING" | "ARRIVED" | "COMPLETED", arrivedAt?: string) {
  if (status === "COMPLETED") return "Picked Up";
  if (status === "ARRIVED" || arrivedAt) return "Rider arrived";
  return "Rider assigned";
}

function LegacyMerchantOrderCard(props: {
  order: MerchantOrderSnapshot;
  busy: boolean;
  rejecting: boolean;
  rejectReason: string;
  onRejectReason: (value: string) => void;
  onStartReject: () => void;
  onCancelReject: () => void;
  onAccept: () => void;
  onReject: () => void;
  onReady: () => void;
  onConfirmReturn: () => void;
}) {
  const { order } = props;
  return <article className="v1-preparation-card legacy-order">
    <header>
      <span className="v1-opportunity-icon"><PackageCheck size={20} /></span>
      <span><strong>{order.orderId.slice(0, 8).toUpperCase()}</strong><small>Earlier Dastak order · {order.lines.length} item line(s)</small></span>
      <b>{order.status.replaceAll("_", " ")}</b>
    </header>
    <ul>{order.lines.map((line) => <li key={line.productId}><span><strong>{line.quantity}× {line.name}</strong><small>{line.unitLabel}</small></span><b>{formatPaise(line.lineSubtotal.paise)}</b></li>)}</ul>
    <p className="v1-reservation-state"><ShieldCheck size={16} /> <strong>Pay at delivery.</strong> The customer pays the delivery partner; this status does not mean the merchant has received payment.</p>
    <div className="v1-preparation-times">
      <span><small>Order total</small><strong>{formatPaise(order.total.paise)}</strong></span>
      <span><small>Order state</small><strong>{order.status.replaceAll("_", " ")}</strong></span>
      <span><small>Payment collection</small><strong>{legacyCollectionLabel(order)}</strong></span>
    </div>
    {props.rejecting ? <div className="v1-problem-form">
      <label><span>Why can’t this order be fulfilled?</span><textarea value={props.rejectReason} maxLength={500} rows={3} autoFocus onChange={(event) => props.onRejectReason(event.target.value)} /></label>
      <div><button className="secondary-button" type="button" disabled={props.busy} onClick={props.onCancelReject}>Back</button><button className="primary-button" type="button" disabled={props.busy || props.rejectReason.trim().length < 3} onClick={props.onReject}>{props.busy ? "Updating…" : "Reject order"}</button></div>
    </div> : <div className="v1-opportunity-actions">
      {order.status === "paid" || order.status === "merchant_accepted" || order.status === "ready" ? <button className="secondary-button" type="button" disabled={props.busy} onClick={props.onStartReject}>Reject</button> : null}
      {order.status === "paid" ? <button className="primary-button" type="button" disabled={props.busy} onClick={props.onAccept}>{props.busy ? "Accepting…" : "Accept"}</button> : null}
      {order.status === "merchant_accepted" ? <button className="primary-button" type="button" disabled={props.busy} onClick={props.onReady}>{props.busy ? "Updating…" : "Mark ready"}</button> : null}
      {order.status === "returning_to_merchant" ? <button className="primary-button" type="button" disabled={props.busy} onClick={props.onConfirmReturn}>{props.busy ? "Confirming…" : "Confirm items returned"}</button> : null}
    </div>}
  </article>;
}

function isLegacyHistory(order: MerchantOrderSnapshot) {
  return order.status === "delivered" || order.status === "cancelled";
}

function legacyCollectionLabel(order: MerchantOrderSnapshot) {
  if (order.paymentState === "refunded") return "Refunded";
  if (order.paymentState === "refund_pending") return "Refund pending";
  return order.status === "delivered" ? "Completed at doorstep" : "Due at doorstep";
}

function LineList({ lines }: { lines: V1MerchantOpportunity["lines"] }) {
  return <ul>{lines.map((line) => <li key={line.orderLineId}><span><strong>{line.quantity}× {line.name}</strong><small>{line.selection ? selectionSummary(line.selection) : [line.variant, line.packSize].filter(Boolean).join(" · ")}</small></span></li>)}</ul>;
}

function reservationLabel(opportunity: V1MerchantOpportunity) {
  switch (opportunity.reservationState) {
    case "ITEMS_HELD_WHILE_ORDER_COMPLETES": return "Held provisionally";
    case "WAITING_FOR_CUSTOMER_PAYMENT": return "Awaiting order confirmation";
    case "PAYMENT_CONFIRMED": return "Order confirmed";
    case "RESERVATION_RELEASED": return "Released";
    default: return opportunity.status.replaceAll("_", " ").toLowerCase();
  }
}

function reservationCopy(opportunity: V1MerchantOpportunity) {
  switch (opportunity.reservationState) {
    case "ITEMS_HELD_WHILE_ORDER_COMPLETES": return "Items held while Dastak completes the order. No preparation capacity is consumed yet.";
    case "WAITING_FOR_CUSTOMER_PAYMENT": return "Selected for the final plan. Keep items reserved; preparation has not started.";
    case "PAYMENT_CONFIRMED": return "The order is confirmed for pay at delivery. Continue in the preparation card above; no merchant payment action is required.";
    case "RESERVATION_RELEASED": return "Reservation released. Return these items to normal availability.";
    default: return "This request is no longer awaiting a response.";
  }
}

function withValue(values: Set<string>, value: string) {
  const next = new Set(values);
  next.add(value);
  return next;
}
function without(values: Set<string>, value: string) {
  const next = new Set(values);
  next.delete(value);
  return next;
}
function useTickingNow() {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const clock = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(clock);
  }, []);
  return now;
}
function formatDuration(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
function formatOptionalTime(value?: string) {
  return value ? new Intl.DateTimeFormat("en-IN", { hour: "numeric", minute: "2-digit" }).format(new Date(value)) : "—";
}
function message(error: unknown) {
  return userFacingError(error, "V1 fulfilments are unavailable right now.");
}

function recordText(value: Record<string, unknown> | undefined, key: string) {
  const result = value?.[key];
  return typeof result === "string" ? result : undefined;
}
function recordNumber(value: Record<string, unknown>, key: string) {
  const result = value[key];
  return typeof result === "number" ? result : undefined;
}
function recordObject(value: Record<string, unknown>, key: string) {
  const result = value[key];
  return result !== null && typeof result === "object" && !Array.isArray(result)
    ? result as Record<string, unknown>
    : undefined;
}

function selectionSummary(selection: Record<string, unknown>) {
  const groups = selection.groups;
  if (!Array.isArray(groups)) return "Exact menu selection";
  const names = groups.flatMap((group) => {
    if (!group || typeof group !== "object" || Array.isArray(group)) return [];
    const options = (group as Record<string, unknown>).options;
    return Array.isArray(options) ? options.flatMap((option) => {
      if (!option || typeof option !== "object" || Array.isArray(option)) return [];
      const name = (option as Record<string, unknown>).name;
      return typeof name === "string" ? [name] : [];
    }) : [];
  });
  return names.join(" · ") || "Exact menu selection";
}

function formatPaise(value: number) {
  return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(value / 100);
}
