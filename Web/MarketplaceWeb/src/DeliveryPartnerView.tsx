/* eslint-disable react-refresh/only-export-components -- tested delivery presentation helpers intentionally live beside their operational components. */
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Banknote, Bell, BellOff, Camera, Check, CircleAlert, History as HistoryIcon, MapPin, Navigation, PackageCheck, Power, RefreshCw, Store, UserRound, WalletCards, X } from "lucide-react";
import {
  acceptV1DeliveryOffer,
  acceptDeliveryOffer,
  advanceV1DeliveryMission,
  advanceV1ReturnMission,
  advanceDeliveryJob,
  canArriveAtDestination,
  declineV1DeliveryOffer,
  declineDeliveryOffer,
  getDeliveryDispatch,
  getDeliveryPartnerWorkHistory,
  getDeliveryPartnerSnapshot,
  getV1DeliveryLaneSnapshots,
  heartbeatV1DeliveryMission,
  publishDeliveryPartnerLocation,
  publishV1MissionLocation,
  recordV1LaunchCollection,
  setDeliveryPartnerAvailability,
  removeV1EvidenceObject,
  v1DeliveryEvidenceObjectPath,
  v1ReturnEvidenceObjectPath,
  uploadV1DeliveryEvidence,
  uploadV1ReturnEvidence,
  DeliveryRequestError,
  type DeliveryAssignment,
  type DeliveryDispatchSnapshot,
  type DeliveryJobOperation,
  type DeliveryPartnerSnapshot,
  type DeliveryWorkHistoryItem,
  type PartnerAvailability,
  type V1DeliveryDispatchSnapshot,
  type V1DeliveryMission,
  type V1DeliveryMissionOperation,
  type V1ArrivalEligibility,
  type V1PickupStop,
  type V1RiderOffer,
  type V1ReturnMission,
  type V1ReturnMissionOperation,
} from "./delivery";
import { formatPrice } from "./catalogue";
import { formatDeliveryDistance, orderStatusLabel } from "./orders";
import {
  getParcelPartnerSnapshot,
  mutateParcelAssignment,
  parcelStatusLabel,
  type ParcelAssignment,
  type ParcelPartnerSnapshot,
} from "./parcels";
import { RoleAccountView } from "./RoleAccountView";
import { RoyaltyPanel } from "./RoyaltyPanel";
import { RefreshCoalescer, RefreshQueue, useOrderRealtime, type OrderRealtimeHealth } from "./orderRealtime";
import {
  deadlineDelay,
  deliveryDataIssue,
  deliveryFallbackCadence,
  deliveryFeedFailed,
  deliveryFeedFailures,
  deliveryFeedStarted,
  deliveryFeedsForRealtimeSignal,
  deliveryFeedsInitiallyLoading,
  deliveryFeedSucceeded,
  deliveryOperationalFeedKeys,
  deliveryOperationalFeedsSettledWithoutErrors,
  initialDeliveryFeedStates,
  isDeliveryConcurrencyReconciliation,
  isOfferExpired,
  isRiderEffectivelyOnline,
  isUncertainDeliveryMutation,
  shouldRunDeliveryFallback,
  type DeliveryFeedKey,
  type DeliveryFeedStates,
} from "./deliveryOperationsState";
import { userFacingError } from "./userFacingError";
import { validateDecodableImage } from "./imageValidation";
import { useDastakWebPush, type DastakWebPushController } from "./useDastakWebPush";
import {
  useDeliveryGeolocationController,
  type DeliveryGeolocationStatus,
  type WakeLockStatus,
} from "./deliveryGeolocation";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  webPushPublicKey: string;
  onSignOut: () => void;
};

type DispatchAction = "accept" | "decline" | DeliveryJobOperation;
type EvidenceAttempt = {
  objectPath: string;
  idempotencyKey: string;
  fileSignature: string;
  contentType: string;
  uploaded: boolean;
};
type ActionFailureOutcome = "session" | "reconciled" | "uncertain" | "definite";
type RecoveryOperation = Extract<
  V1DeliveryMissionOperation,
  "v1CancelBeforePickup" | "v1ReportCustomerUnreachable" | "v1ReportDeliveryProblem"
>;
type RecoveryIntent = { mission: V1DeliveryMission; operation: RecoveryOperation };

export function DeliveryPartnerView({ accessToken, accountId, client, displayName, email, phoneNumber, supabaseUrl, publishableKey, webPushPublicKey, onSignOut }: Props) {
  const auth = useMemo(() => ({ accessToken, supabaseUrl, publishableKey }), [accessToken, publishableKey, supabaseUrl]);
  const [partner, setPartner] = useState<DeliveryPartnerSnapshot>();
  const [dispatch, setDispatch] = useState<DeliveryDispatchSnapshot>({ offer: null, currentJob: null });
  const [v1Dispatch, setV1Dispatch] = useState<V1DeliveryDispatchSnapshot>({
    offer: null,
    currentMission: null,
    completedMission: null,
    returnMission: null,
  });
  const [parcelDispatch, setParcelDispatch] = useState<ParcelPartnerSnapshot>({ offer: null, currentJob: null });
  const [feedStates, setFeedStates] = useState<DeliveryFeedStates>(initialDeliveryFeedStates);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [recoveryIntent, setRecoveryIntent] = useState<RecoveryIntent>();
  const [verificationCode, setVerificationCode] = useState("");
  const [section, setSection] = useState<"deliveries" | "history" | "royalty" | "account">("deliveries");
  const partnerRefreshQueue = useRef(new RefreshQueue());
  const v1RefreshQueue = useRef(new RefreshQueue());
  const legacyRefreshQueue = useRef(new RefreshQueue());
  const parcelRefreshQueue = useRef(new RefreshQueue());
  const feedControllers = useRef<Partial<Record<DeliveryFeedKey, AbortController>>>({});
  const actionKeys = useRef(new Map<string, string>());
  const evidenceAttempts = useRef(new Map<string, EvidenceAttempt>());
  const sessionRecoveryStarted = useRef(false);
  const webPushAuthentication = useMemo(() => ({
    accessToken, accountId, supabaseUrl, publishableKey, publicKey: webPushPublicKey,
  }), [accessToken, accountId, publishableKey, supabaseUrl, webPushPublicKey]);
  const webPush = useDastakWebPush(webPushAuthentication);

  const recoverSession = useCallback((requestError: unknown) => {
    const issue = deliveryDataIssue(requestError);
    if (issue.action !== "sign_in") return false;
    if (!sessionRecoveryStarted.current) {
      sessionRecoveryStarted.current = true;
      void onSignOut();
    }
    return true;
  }, [onSignOut]);

  const recordFeedFailure = useCallback((key: DeliveryFeedKey, requestError: unknown) => {
    setFeedStates((current) => deliveryFeedFailed(current, key, requestError));
    recoverSession(requestError);
  }, [recoverSession]);

  const nextFeedSignal = useCallback((key: DeliveryFeedKey) => {
    feedControllers.current[key]?.abort();
    const controller = new AbortController();
    feedControllers.current[key] = controller;
    return controller.signal;
  }, []);

  const refreshPartner = useCallback(async () => {
    await partnerRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => deliveryFeedStarted(current, ["partner"]));
      const signal = nextFeedSignal("partner");
      try {
        setPartner(await getDeliveryPartnerSnapshot({ ...auth, signal }));
        setFeedStates((current) => deliveryFeedSucceeded(current, "partner"));
      } catch (requestError) {
        if (!signal.aborted) recordFeedFailure("partner", requestError);
      }
    });
  }, [auth, nextFeedSignal, recordFeedFailure]);

  const refreshV1 = useCallback(async () => {
    await v1RefreshQueue.current.request(false, async () => {
      setFeedStates((current) => deliveryFeedStarted(current, ["v1", "returns"]));
      const signal = nextFeedSignal("v1");
      try {
        const result = await getV1DeliveryLaneSnapshots({ ...auth, signal });
        if (result.delivery.ok) {
          const delivery = result.delivery.value;
          setV1Dispatch((current) => ({ ...current, ...delivery }));
          setFeedStates((current) => deliveryFeedSucceeded(current, "v1"));
        } else recordFeedFailure("v1", result.delivery.error);
        if (result.returns.ok) {
          const returns = result.returns.value;
          setV1Dispatch((current) => ({ ...current, ...returns }));
          setFeedStates((current) => deliveryFeedSucceeded(current, "returns"));
        } else recordFeedFailure("returns", result.returns.error);
      } catch (requestError) {
        if (!signal.aborted) {
          recordFeedFailure("v1", requestError);
          recordFeedFailure("returns", requestError);
        }
      }
    });
  }, [auth, nextFeedSignal, recordFeedFailure]);

  const refreshLegacy = useCallback(async () => {
    await legacyRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => deliveryFeedStarted(current, ["legacy"]));
      const signal = nextFeedSignal("legacy");
      try {
        setDispatch(await getDeliveryDispatch({ ...auth, signal }));
        setFeedStates((current) => deliveryFeedSucceeded(current, "legacy"));
      } catch (requestError) {
        if (!signal.aborted) recordFeedFailure("legacy", requestError);
      }
    });
  }, [auth, nextFeedSignal, recordFeedFailure]);

  const refreshParcel = useCallback(async () => {
    await parcelRefreshQueue.current.request(false, async () => {
      setFeedStates((current) => deliveryFeedStarted(current, ["parcel"]));
      const signal = nextFeedSignal("parcel");
      try {
        setParcelDispatch(await getParcelPartnerSnapshot({ ...auth, signal }));
        setFeedStates((current) => deliveryFeedSucceeded(current, "parcel"));
      } catch (requestError) {
        if (!signal.aborted) recordFeedFailure("parcel", requestError);
      }
    });
  }, [auth, nextFeedSignal, recordFeedFailure]);

  const refreshFeeds = useCallback(async (
    keys: DeliveryFeedKey[] = ["partner", ...deliveryOperationalFeedKeys],
    showProgress = false,
  ) => {
    if (showProgress) setBusy("refresh");
    const unique = new Set(keys);
    try {
      await Promise.allSettled([
        ...(unique.has("partner") ? [refreshPartner()] : []),
        ...(unique.has("v1") || unique.has("returns") ? [refreshV1()] : []),
        ...(unique.has("legacy") ? [refreshLegacy()] : []),
        ...(unique.has("parcel") ? [refreshParcel()] : []),
      ]);
    } finally {
      if (showProgress) setBusy(undefined);
    }
  }, [refreshLegacy, refreshParcel, refreshPartner, refreshV1]);

  const refreshRef = useRef(refreshFeeds);
  refreshRef.current = refreshFeeds;
  const pendingRealtimeFeeds = useRef(new Set<DeliveryFeedKey>());
  const reconcileCoalescer = useRef<RefreshCoalescer<void> | undefined>(undefined);
  if (!reconcileCoalescer.current) {
    reconcileCoalescer.current = new RefreshCoalescer(() => {
      const keys = [...pendingRealtimeFeeds.current];
      pendingRealtimeFeeds.current.clear();
      void refreshRef.current(keys);
    });
  }
  const requestReconciliation = useCallback((keys: DeliveryFeedKey[]) => {
    keys.forEach((key) => pendingRealtimeFeeds.current.add(key));
    reconcileCoalescer.current?.request();
  }, []);

  const reconcileAvailabilityExpiry = useCallback(() => {
    requestReconciliation(["partner"]);
  }, [requestReconciliation]);
  const online = useEffectiveRiderOnline(partner?.availability, reconcileAvailabilityExpiry);
  // A recovery return can intentionally coexist with its source delivery. It
  // is the current custody route and owns the one mission GPS stream.
  const trackingMissionId = v1Dispatch.returnMission?.id ?? v1Dispatch.currentMission?.id;

  const publishTrackedMissionLocation = useCallback(async (
    missionId: string,
    fix: { latitude: number; longitude: number; accuracyMeters: number; recordedAt: string },
  ) => {
    const snapshot = await publishV1MissionLocation({ ...auth, missionId, ...fix });
    setV1Dispatch((current) => mergeMissionTrackingSnapshot(current, snapshot, missionId));
    setFeedStates((current) => deliveryFeedSucceeded(
      current,
      snapshot.returnMission?.id === missionId ? "returns" : "v1",
    ));
  }, [auth]);

  const publishAvailabilityLocation = useCallback(async (location: { latitude: number; longitude: number }) => {
    try {
      const availability = await publishDeliveryPartnerLocation({
        ...auth,
        location,
        idempotencyKey: crypto.randomUUID(),
      });
      setPartner((current) => current && availabilityPresentationChanged(current.availability, availability)
        ? { ...current, availability }
        : current);
      setFeedStates((current) => deliveryFeedSucceeded(current, "partner"));
    } catch (locationError) {
      if (locationError instanceof DeliveryRequestError && locationError.code === "partner_offline") {
        requestReconciliation(["partner"]);
      }
      throw locationError;
    }
  }, [auth, requestReconciliation]);

  const geolocationMode = useMemo(() => trackingMissionId
    ? { kind: "mission" as const, missionId: trackingMissionId }
    : online ? { kind: "availability" as const } : { kind: "idle" as const },
  [online, trackingMissionId]);
  const geolocation = useDeliveryGeolocationController({
    mode: geolocationMode,
    publishMission: publishTrackedMissionLocation,
    publishAvailability: publishAvailabilityLocation,
    onForegroundReconcile: () => requestReconciliation([
      "partner",
      ...(trackingMissionId ? [v1Dispatch.returnMission ? "returns" as const : "v1" as const] : []),
    ]),
  });

  const realtimeHealth = useOrderRealtime({
    client,
    accountId,
    accessToken,
    onChange: (signal) => requestReconciliation(deliveryFeedsForRealtimeSignal(signal)),
    onVisibilityChange: geolocation.handleVisibilityChange,
  });

  useEffect(() => {
    const followNotificationRoute = () => {
      const target = deliveryNotificationTarget(window.location.hash);
      if (!target) return;
      setSection("deliveries");
      requestReconciliation(target.kind === "return" ? ["returns"] : target.kind === "mission" ? ["v1", "returns"] : deliveryOperationalFeedKeys);
      window.setTimeout(() => {
        const selector = target.kind === "return"
          ? "[id^='delivery-return-']"
          : target.kind === "mission" ? "[id^='delivery-mission-']" : ".delivery-offer";
        document.querySelector(selector)?.scrollIntoView({ behavior: "smooth", block: "center" });
      }, 250);
    };
    followNotificationRoute();
    window.addEventListener("hashchange", followNotificationRoute);
    return () => window.removeEventListener("hashchange", followNotificationRoute);
  }, [requestReconciliation]);

  useEffect(() => {
    const controllers = feedControllers.current;
    void refreshFeeds();
    return () => {
      reconcileCoalescer.current?.cancel();
      Object.values(controllers).forEach((controller) => controller?.abort());
    };
  }, [refreshFeeds]);

  useEffect(() => {
    let timer: number | undefined;
    const tick = () => {
      timer = undefined;
      if (!shouldRunDeliveryFallback(document.visibilityState, navigator.onLine !== false)) return;
      requestReconciliation(["partner", ...deliveryOperationalFeedKeys]);
      timer = window.setTimeout(tick, deliveryFallbackCadence(realtimeHealth));
    };
    if (shouldRunDeliveryFallback(document.visibilityState, navigator.onLine !== false)) {
      timer = window.setTimeout(tick, deliveryFallbackCadence(realtimeHealth));
    }
    return () => {
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [realtimeHealth, requestReconciliation]);

  // Preserve operational liveness when precise GPS is temporarily unavailable.
  // Successful mission-location updates also refresh the server contact time.
  useEffect(() => {
    const mission = v1Dispatch.currentMission;
    if (!mission || mission.status === "DELIVERY_RECOVERY") return;
    const heartbeat = async () => {
      try {
        const snapshot = await heartbeatV1DeliveryMission({
          ...auth, missionId: mission.id, expectedVersion: mission.version,
        });
        setV1Dispatch((current) => ({
          ...current,
          offer: snapshot.offer,
          currentMission: snapshot.currentMission,
          completedMission: snapshot.completedMission,
        }));
        setFeedStates((current) => deliveryFeedSucceeded(current, "v1"));
      } catch (heartbeatError) {
        if (isDeliveryConcurrencyReconciliation(heartbeatError)) {
          requestReconciliation(["v1"]);
        }
      }
    };
    const timer = window.setInterval(() => { void heartbeat().catch(() => undefined); }, 20_000);
    return () => window.clearInterval(timer);
  }, [auth, requestReconciliation, v1Dispatch.currentMission]);

  const handleActionFailure = useCallback(async (
    actionError: unknown,
    requestIdentity: string,
    lanes: DeliveryFeedKey[],
  ): Promise<ActionFailureOutcome> => {
    if (recoverSession(actionError)) return "session";
    if (isDeliveryConcurrencyReconciliation(actionError)) {
      actionKeys.current.delete(requestIdentity);
      await refreshFeeds(lanes);
      setError(undefined);
      setNotice("This delivery changed elsewhere. The latest details are now shown.");
      return "reconciled";
    }
    if (isUncertainDeliveryMutation(actionError)) {
      await refreshFeeds(lanes);
      setError("Dastak could not confirm that action. The latest delivery state was checked; retrying will safely use the same request.");
      return "uncertain";
    }
    actionKeys.current.delete(requestIdentity);
    setError(message(actionError));
    return "definite";
  }, [recoverSession, refreshFeeds]);

  const changeAvailability = async (online: boolean) => {
    const requestIdentity = `availability:${online}:${partner?.availability?.stateVersion ?? 0}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy("availability");
    setError(undefined);
    try {
      const location = online ? await geolocation.currentLocation() : undefined;
      const availability = await setDeliveryPartnerAvailability({
        ...auth,
        online,
        location,
        idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setPartner((current) => current ? { ...current, availability } : current);
      setFeedStates((current) => deliveryFeedSucceeded(current, "partner"));
      if (online) {
        await refreshFeeds(deliveryOperationalFeedKeys);
      }
    } catch (availabilityError) {
      await handleActionFailure(
        availabilityError,
        requestIdentity,
        ["partner", ...deliveryOperationalFeedKeys],
      );
    } finally {
      setBusy(undefined);
    }
  };

  const runParcelAction = async (
    assignment: ParcelAssignment,
    operation: "acknowledgeAssignment" | "declineAssignment" | "startToPickup" | "confirmPickup" | "startDelivery" | "completeDelivery",
    code?: string,
  ) => {
    const requestIdentity = `parcel:${operation}:${assignment.assignmentId}:${assignment.parcel.status}:${code ?? ""}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = await mutateParcelAssignment({
        ...auth,
        operation,
        assignmentId: assignment.assignmentId,
        reason: operation === "declineAssignment" ? "Partner declined" : undefined,
        verificationCode: code,
        idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setParcelDispatch(snapshot);
      setFeedStates((current) => deliveryFeedSucceeded(current, "parcel"));
      setVerificationCode("");
      if (operation === "confirmPickup") setNotice("Pickup verified. The parcel is now in your care.");
      if (operation === "completeDelivery") setNotice("Parcel delivery verified and completed.");
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["parcel"]);
    } finally {
      setBusy(undefined);
    }
  };

  const runDispatchAction = async (
    assignment: DeliveryAssignment,
    action: DispatchAction,
    code?: string,
  ) => {
    const requestIdentity = `${action}:${assignment.assignmentId}:${assignment.orderStatus}:${code ?? ""}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = action === "accept"
        ? await acceptDeliveryOffer({ ...auth, assignmentId: assignment.assignmentId, idempotencyKey })
        : action === "decline"
          ? await declineDeliveryOffer({ ...auth, assignmentId: assignment.assignmentId, idempotencyKey })
          : await advanceDeliveryJob({
            ...auth,
            assignmentId: assignment.assignmentId,
            operation: action,
            verificationCode: code,
            idempotencyKey,
          });
      actionKeys.current.delete(requestIdentity);
      setDispatch(snapshot);
      setFeedStates((current) => deliveryFeedSucceeded(current, "legacy"));
      setVerificationCode("");
      if (action === "confirmPickup") setNotice("Pickup verified. The order is now in your care.");
      if (action === "completeDelivery") setNotice("Delivery verified and completed.");
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["legacy"]);
    } finally {
      setBusy(undefined);
    }
  };

  const runV1OfferAction = async (offer: V1RiderOffer, action: "accept" | "decline") => {
    const requestIdentity = `v1:${action}:${offer.id}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = action === "accept"
        ? await acceptV1DeliveryOffer({ ...auth, offerId: offer.id, idempotencyKey })
        : await declineV1DeliveryOffer({
          ...auth,
          offerId: offer.id,
          reason: "Partner declined",
          idempotencyKey,
        });
      actionKeys.current.delete(requestIdentity);
      setV1Dispatch(snapshot);
      setFeedStates((current) =>
        deliveryFeedSucceeded(deliveryFeedSucceeded(current, "v1"), "returns"));
      if (action === "accept") setNotice("Mission assigned. Collect every package at each pickup.");
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["v1"]);
    } finally {
      setBusy(undefined);
    }
  };

  const runV1MissionAction = async (
    mission: V1DeliveryMission,
    operation: V1DeliveryMissionOperation,
    options: {
      stopId?: string;
      accountedPackageCount?: number;
      verificationCode?: string;
      objectPath?: string;
      reason?: string;
    } = {},
  ) => {
    const requestIdentity = `v1:${operation}:${mission.id}:${options.stopId ?? ""}:${options.verificationCode ?? ""}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = await advanceV1DeliveryMission({
        ...auth,
        missionId: mission.id,
        operation,
        ...options,
        idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setV1Dispatch(snapshot);
      setFeedStates((current) =>
        deliveryFeedSucceeded(deliveryFeedSucceeded(current, "v1"), "returns"));
      setVerificationCode("");
      if (operation === "v1VerifyPickup") {
        setNotice("Pickup verified. Every declared package is now in your custody.");
      }
      if (operation === "v1VerifyCustomerPIN") {
        setNotice("Customer PIN verified. Capture the delivery/package photo next.");
      }
      if (operation === "v1CompleteDelivery" || operation === "v1VerifyDelivery") {
        setNotice("Delivery verified. Every package is now in the customer’s custody.");
      }
      return true;
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["v1"]);
      return false;
    } finally {
      setBusy(undefined);
    }
  };

  const captureV1DeliveryEvidence = async (mission: V1DeliveryMission, file: File) => {
    if (!await validateDecodableImage(file)) {
      setError("Capture a genuine JPG, PNG or HEIC package photo up to 10 MB.");
      return;
    }
    const attemptKey = `delivery:${mission.id}`;
    const signature = fileSignature(file);
    let attempt = evidenceAttempts.current.get(attemptKey);
    if (attempt && (attempt.fileSignature !== signature || attempt.contentType !== file.type)) {
      setError("Dastak is still reconciling the previous photo. Choose the same photo to retry, or wait for the mission to update.");
      await refreshFeeds(["v1"]);
      return;
    }
    if (!attempt) {
      attempt = {
        objectPath: v1DeliveryEvidenceObjectPath(accountId, file.type, crypto.randomUUID()),
        idempotencyKey: crypto.randomUUID(),
        fileSignature: signature,
        contentType: file.type,
        uploaded: false,
      };
      evidenceAttempts.current.set(attemptKey, attempt);
    }
    const requestIdentity = `v1:evidence:${mission.id}:${attempt.objectPath}`;
    actionKeys.current.set(requestIdentity, attempt.idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      if (!attempt.uploaded) {
        await uploadV1DeliveryEvidence(client, accountId, file, attempt.objectPath);
        attempt.uploaded = true;
      }
      const snapshot = await advanceV1DeliveryMission({
        ...auth,
        missionId: mission.id,
        operation: "v1AddDeliveryEvidence",
        objectPath: attempt.objectPath,
        idempotencyKey: attempt.idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      evidenceAttempts.current.delete(attemptKey);
      setV1Dispatch(snapshot);
      setFeedStates((current) =>
        deliveryFeedSucceeded(deliveryFeedSucceeded(current, "v1"), "returns"));
      setNotice("Package photo secured. Record the pay-at-delivery collection next.");
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["v1"]);
    } finally {
      setBusy(undefined);
    }
  };

  const runV1Collection = async (
    mission: V1DeliveryMission,
    input: {
      outcome: "COLLECTED" | "FAILED";
      method: "CASH" | "UPI";
      collectionReference?: string;
      failureReason?: string;
    },
  ) => {
    const requestIdentity = `v1:collection:${mission.id}:${input.outcome}:${input.method}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = await recordV1LaunchCollection({
        ...auth,
        missionId: mission.id,
        expectedMissionVersion: mission.version,
        idempotencyKey,
        ...input,
      });
      actionKeys.current.delete(requestIdentity);
      setV1Dispatch(snapshot);
      setFeedStates((current) =>
        deliveryFeedSucceeded(deliveryFeedSucceeded(current, "v1"), "returns"));
      setNotice(input.outcome === "COLLECTED"
        ? "Payment collected and recorded. You can now complete the delivery."
        : "Collection attempt recorded. Keep the order secure and retry before delivery.");
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["v1"]);
    } finally {
      setBusy(undefined);
    }
  };

  const runV1ReturnAction = async (
    mission: V1ReturnMission,
    operation: V1ReturnMissionOperation,
    options: { returnStopId?: string; verificationCode?: string; objectPath?: string } = {},
  ) => {
    const requestIdentity = `v1-return:${operation}:${mission.id}:${options.returnStopId ?? ""}:${options.verificationCode ?? ""}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const snapshot = await advanceV1ReturnMission({
        ...auth, returnMissionId: mission.id, operation, ...options, idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setV1Dispatch(snapshot);
      setFeedStates((current) =>
        deliveryFeedSucceeded(deliveryFeedSucceeded(current, "v1"), "returns"));
      if (operation === "v1VerifyReturnPickup") {
        setNotice("Return pickup verified. Every return package is now in your custody.");
      }
      if (operation === "v1VerifyReturnReceipt") {
        setNotice("Merchant receipt verified. Reverse custody was recorded exactly once.");
      }
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["returns"]);
    } finally {
      setBusy(undefined);
    }
  };

  const captureV1ReturnEvidence = async (mission: V1ReturnMission, file: File) => {
    if (!await validateDecodableImage(file)) {
      setError("Capture a genuine JPG, PNG or HEIC return-package photo up to 10 MB.");
      return;
    }
    const attemptKey = `return:${mission.id}`;
    const signature = fileSignature(file);
    let attempt = evidenceAttempts.current.get(attemptKey);
    if (attempt && (attempt.fileSignature !== signature || attempt.contentType !== file.type)) {
      setError("Dastak is still reconciling the previous return photo. Choose the same photo to retry, or wait for the mission to update.");
      await refreshFeeds(["returns"]);
      return;
    }
    if (!attempt) {
      attempt = {
        objectPath: v1ReturnEvidenceObjectPath(accountId, file.type, crypto.randomUUID()),
        idempotencyKey: crypto.randomUUID(),
        fileSignature: signature,
        contentType: file.type,
        uploaded: false,
      };
      evidenceAttempts.current.set(attemptKey, attempt);
    }
    const requestIdentity = `v1-return:evidence:${mission.id}:${attempt.objectPath}`;
    actionKeys.current.set(requestIdentity, attempt.idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      if (!attempt.uploaded) {
        await uploadV1ReturnEvidence(client, accountId, file, attempt.objectPath);
        attempt.uploaded = true;
      }
      const snapshot = await advanceV1ReturnMission({
        ...auth, returnMissionId: mission.id, operation: "v1AddReturnEvidence",
        objectPath: attempt.objectPath, idempotencyKey: attempt.idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      evidenceAttempts.current.delete(attemptKey);
      setV1Dispatch(snapshot);
      setFeedStates((current) =>
        deliveryFeedSucceeded(deliveryFeedSucceeded(current, "v1"), "returns"));
      setNotice("Immutable return-package photo captured.");
    } catch (actionError) {
      await handleActionFailure(actionError, requestIdentity, ["returns"]);
    } finally {
      setBusy(undefined);
    }
  };

  useEffect(() => {
    const deliveryMission = v1Dispatch.currentMission;
    const returnMission = v1Dispatch.returnMission;
    const cleanup: string[] = [];
    if (deliveryMission) {
      const key = `delivery:${deliveryMission.id}`;
      const attempt = evidenceAttempts.current.get(key);
      if (attempt && deliveryMission.deliveryEvidence.some((item) => item.objectPath === attempt.objectPath)) {
        evidenceAttempts.current.delete(key);
      } else if (attempt?.uploaded && !deliveryMission.canCaptureDeliveryEvidence) {
        evidenceAttempts.current.delete(key);
        cleanup.push(attempt.objectPath);
      }
    }
    if (returnMission) {
      const key = `return:${returnMission.id}`;
      const attempt = evidenceAttempts.current.get(key);
      if (attempt && returnMission.evidence.some((item) => item.objectPath === attempt.objectPath)) {
        evidenceAttempts.current.delete(key);
      } else if (attempt?.uploaded && !returnMission.canCaptureEvidence) {
        evidenceAttempts.current.delete(key);
        cleanup.push(attempt.objectPath);
      }
    }
    cleanup.forEach((objectPath) => {
      void removeV1EvidenceObject(client, accountId, objectPath).catch(() => undefined);
    });
  }, [accountId, client, v1Dispatch.currentMission, v1Dispatch.returnMission]);

  const hasJob = Boolean(
    v1Dispatch.currentMission || v1Dispatch.returnMission || dispatch.currentJob || parcelDispatch.currentJob,
  );
  const hasOperationalContent = Boolean(
    v1Dispatch.offer || v1Dispatch.currentMission || v1Dispatch.returnMission ||
    v1Dispatch.completedMission || dispatch.offer || dispatch.currentJob ||
    parcelDispatch.offer || parcelDispatch.currentJob,
  );
  const operationalFeedsHealthy = deliveryOperationalFeedsSettledWithoutErrors(feedStates);

  return (
    <div className="delivery-shell">
      <nav className="workspace-tabs" role="tablist" aria-label="Delivery Partner workspace">
        <button type="button" role="tab" aria-selected={section === "deliveries"} className={section === "deliveries" ? "selected" : ""} onClick={() => setSection("deliveries")}><Navigation size={18} /> Deliveries</button>
        <button type="button" role="tab" aria-selected={section === "history"} className={section === "history" ? "selected" : ""} onClick={() => setSection("history")}><HistoryIcon size={18} /> History</button>
        <button type="button" role="tab" aria-selected={section === "royalty"} className={section === "royalty" ? "selected" : ""} onClick={() => setSection("royalty")}><WalletCards size={18} /> Earnings</button>
        <button type="button" role="tab" aria-selected={section === "account"} className={section === "account" ? "selected" : ""} onClick={() => setSection("account")}><UserRound size={18} /> Account</button>
      </nav>
      {section === "royalty" ? <RoyaltyPanel auth={auth} kind="RIDER" /> : section === "history" ? <DeliveryHistoryPanel
        auth={auth}
        onOpenEarnings={() => setSection("royalty")}
        onSessionExpired={recoverSession}
      /> : section === "account" ? <RoleAccountView
        accessToken={accessToken}
        displayName={displayName}
        email={email}
        phoneNumber={phoneNumber}
        roleName="Delivery Partner"
        persona="DELIVERY"
        deliveryPartner={partner}
        deliveryPartnerLoading={!partner && !feedStates.partner.loaded}
        deliveryPartnerError={partner ? undefined : feedStates.partner.issue?.message}
        supabaseUrl={supabaseUrl}
        publishableKey={publishableKey}
        onRefreshPartner={() => void refreshFeeds(["partner"], true)}
        onOpenWorkspace={() => setSection("deliveries")}
        notificationSurface={<DeliveryNotificationStatus controller={webPush} />}
        onSignOut={onSignOut}
      /> : <>
      <header className="delivery-heading">
        <div>
          <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak Delivery Partner"}</p>
          <h1>Delivery</h1>
          <p>{partner?.deliveryMethod ? deliveryMethodLabel(partner.deliveryMethod) : "Delivery Partner"}</p>
        </div>
        <button className="icon-button" type="button" onClick={() => void refreshFeeds(undefined, true)} disabled={Boolean(busy)} aria-label="Refresh delivery queue" title="Refresh delivery queue">
          <RefreshCw size={19} />
        </button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      <DeliveryNotificationStatus controller={webPush} />
      <DeliveryTrackingStatus
        status={geolocation.status}
        wakeLockStatus={geolocation.wakeLockStatus}
        missionActive={Boolean(trackingMissionId)}
        realtimeHealth={realtimeHealth}
      />
      {notice && <div className="delivery-notice" role="status"><Check size={18} /><span>{notice}</span><button type="button" onClick={() => setNotice(undefined)} aria-label="Dismiss confirmation"><X size={16} /></button></div>}
      <DeliveryOperationsStatus
        states={feedStates}
        hasContent={hasOperationalContent}
        onRetry={() => void refreshFeeds(undefined, true)}
      />
      {partner ? (
          <section className="delivery-availability" aria-label="Availability">
            <span className={`availability-icon ${online ? "online" : ""}`}><Power size={21} /></span>
            <div>
              <strong>{online ? "Online" : "Offline"}</strong>
              <AvailabilityStatusText availability={partner.availability} online={online} />
            </div>
            <label className="availability-switch" title={online && hasJob ? "Complete the active delivery first" : undefined}>
              <input
                type="checkbox"
                checked={online}
                disabled={Boolean(busy) || (online && hasJob)}
                onChange={(event) => void changeAvailability(event.currentTarget.checked)}
                aria-label="Available for deliveries"
              />
              <span aria-hidden="true" />
            </label>
          </section>
      ) : null}
          {v1Dispatch.returnMission && (
            <CurrentV1ReturnMission
              mission={v1Dispatch.returnMission}
              busy={Boolean(busy)}
              onAction={(operation, options) =>
                void runV1ReturnAction(v1Dispatch.returnMission!, operation, options)}
              onCaptureEvidence={(file) =>
                void captureV1ReturnEvidence(v1Dispatch.returnMission!, file)}
            />
          )}

          {v1Dispatch.currentMission && !v1Dispatch.returnMission && (
            <CurrentV1Mission
              mission={v1Dispatch.currentMission}
              busy={Boolean(busy)}
              onAction={(operation, options) =>
                void runV1MissionAction(v1Dispatch.currentMission!, operation, options)}
              onCaptureEvidence={(file) =>
                void captureV1DeliveryEvidence(v1Dispatch.currentMission!, file)}
              onCollection={(input) =>
                void runV1Collection(v1Dispatch.currentMission!, input)}
              onRequestRecovery={(operation) => setRecoveryIntent({
                mission: v1Dispatch.currentMission!,
                operation,
              })}
            />
          )}

          {v1Dispatch.offer && !v1Dispatch.currentMission && !v1Dispatch.returnMission && (
            <V1DeliveryOffer
              key={v1Dispatch.offer.id}
              offer={v1Dispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runV1OfferAction(v1Dispatch.offer!, "accept")}
              onDecline={() => void runV1OfferAction(v1Dispatch.offer!, "decline")}
              onExpire={() => requestReconciliation(["v1"])}
            />
          )}

          {v1Dispatch.completedMission && !v1Dispatch.currentMission && !v1Dispatch.returnMission && (
            <section className="delivery-notice v1-delivered-card" role="status">
              <Check size={20} />
              <div>
                <strong>Delivered</strong>
                <span>{v1Dispatch.completedMission.packageCount} {v1Dispatch.completedMission.packageCount === 1 ? "package" : "packages"} handed over securely.</span>
              </div>
            </section>
          )}

          {!v1Dispatch.currentMission && !v1Dispatch.returnMission && dispatch.currentJob && (
            <CurrentDelivery
              assignment={dispatch.currentJob}
              busy={Boolean(busy)}
              verificationCode={verificationCode}
              onVerificationCode={setVerificationCode}
              onAction={(action, code) => void runDispatchAction(dispatch.currentJob!, action, code)}
            />
          )}

          {!v1Dispatch.currentMission && !v1Dispatch.returnMission && parcelDispatch.currentJob && (
            <CurrentParcel
              assignment={parcelDispatch.currentJob}
              busy={Boolean(busy)}
              verificationCode={verificationCode}
              onVerificationCode={setVerificationCode}
              onAction={(operation, code) => void runParcelAction(parcelDispatch.currentJob!, operation, code)}
            />
          )}

          {!v1Dispatch.offer && !v1Dispatch.currentMission && !v1Dispatch.returnMission && dispatch.offer && (
            <DeliveryOffer
              key={dispatch.offer.assignmentId}
              offer={dispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runDispatchAction(dispatch.offer!, "accept")}
              onDecline={() => void runDispatchAction(dispatch.offer!, "decline")}
              onExpire={() => requestReconciliation(["legacy"])}
            />
          )}

          {!v1Dispatch.offer && !v1Dispatch.currentMission && !v1Dispatch.returnMission && parcelDispatch.offer && (
            <ParcelOffer
              key={parcelDispatch.offer.assignmentId}
              offer={parcelDispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runParcelAction(parcelDispatch.offer!, "acknowledgeAssignment")}
              onDecline={() => void runParcelAction(parcelDispatch.offer!, "declineAssignment")}
              onExpire={() => requestReconciliation(["parcel"])}
            />
          )}

          {!hasOperationalContent && operationalFeedsHealthy && (
            <section className="delivery-empty">
              <Navigation size={25} />
              <div><h2>{online ? "Waiting for assignments" : "Offline"}</h2><p>{online ? "No ready orders nearby." : "Go online when available."}</p></div>
            </section>
          )}
          {recoveryIntent ? <RecoveryConfirmation
            intent={recoveryIntent}
            busy={Boolean(busy)}
            onDismiss={() => setRecoveryIntent(undefined)}
            onConfirm={async (reason) => {
              const succeeded = await runV1MissionAction(
                recoveryIntent.mission,
                recoveryIntent.operation,
                { reason },
              );
              if (succeeded) setRecoveryIntent(undefined);
            }}
          /> : null}
      </>}
    </div>
  );
}

export function DeliveryHistoryPanel({ auth, onOpenEarnings, onSessionExpired }: {
  auth: { accessToken: string; supabaseUrl: string; publishableKey: string };
  onOpenEarnings: () => void;
  onSessionExpired: (error: unknown) => boolean;
}) {
  const [items, setItems] = useState<DeliveryWorkHistoryItem[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>();
  const request = useRef<AbortController | undefined>(undefined);

  const load = useCallback(async () => {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    setLoading(true);
    try {
      const history = await getDeliveryPartnerWorkHistory({ ...auth, limit: 30, signal: controller.signal });
      if (controller.signal.aborted) return;
      setItems(history);
      setLoaded(true);
      setError(undefined);
    } catch (loadError) {
      if (controller.signal.aborted || onSessionExpired(loadError)) return;
      setError(userFacingError(loadError, "Delivery history could not update."));
    } finally {
      if (!controller.signal.aborted) setLoading(false);
    }
  }, [auth, onSessionExpired]);

  useEffect(() => {
    void load();
    return () => request.current?.abort();
  }, [load]);

  return <section className="delivery-history" aria-labelledby="delivery-history-title">
    <header className="delivery-heading">
      <div>
        <p className="eyebrow">Your work</p>
        <h1 id="delivery-history-title">History</h1>
        <p>Completed, returned and cancelled work across Dastak deliveries.</p>
      </div>
      <button className="icon-button" type="button" onClick={() => void load()} disabled={loading} aria-label="Refresh delivery history">
        <RefreshCw size={19} />
      </button>
    </header>
    {error ? <div className={items.length > 0 ? "delivery-notice" : "order-error"} role={items.length > 0 ? "status" : "alert"}>
      <CircleAlert size={18} />
      <span>{error}{items.length > 0 ? " Previously loaded history remains visible." : ""}</span>
      <button type="button" onClick={() => void load()}>Try again</button>
    </div> : null}
    {loading && !loaded ? <div className="catalogue-loading" role="status"><span /> Loading delivery history</div> : null}
    {loaded && items.length === 0 && !error ? <section className="delivery-empty">
      <HistoryIcon size={25} />
      <div><h2>No completed work yet</h2><p>Delivered and returned work will appear here.</p></div>
    </section> : null}
    {items.length > 0 ? <div className="delivery-history-list" aria-label="Past delivery work">
      {items.map((item) => <article className="delivery-history-card" key={`${item.kind}:${item.workId}`}>
        <div className="delivery-history-icon" aria-hidden="true">{item.kind === "RETURN" ? <PackageCheck size={19} /> : item.kind === "PARCEL" ? <Store size={19} /> : <Navigation size={19} />}</div>
        <div>
          <span>{deliveryWorkKindLabel(item.kind)}</span>
          <strong>{item.reference}</strong>
          <small>{item.packageCount === null ? "Package count unavailable" : `${item.packageCount} ${item.packageCount === 1 ? "package" : "packages"}`} · <time dateTime={item.endedAt}>{formatDeliveryHistoryDate(item.endedAt)}</time></small>
        </div>
        <div className={`delivery-history-outcome ${item.outcome.toLowerCase()}`}>
          <strong>{deliveryWorkOutcomeLabel(item.outcome)}</strong>
          <small>{humanizeDeliveryStatus(item.status)}</small>
          {item.payoutPaise !== null ? <span>{formatPrice(item.payoutPaise)}</span> : null}
        </div>
      </article>)}
    </div> : null}
    <button className="delivery-history-earnings" type="button" onClick={onOpenEarnings}><WalletCards size={18} /> Open earnings ledger</button>
  </section>;
}

export function DeliveryOperationsStatus({ states, hasContent, onRetry }: {
  states: DeliveryFeedStates;
  hasContent: boolean;
  onRetry?: () => void;
}) {
  const failures = deliveryFeedFailures(states);
  if (failures.length > 0) {
    const labels = failures.map((failure) => failure.label).join(", ");
    const sessionExpired = failures.some((failure) => failure.issue.action === "sign_in");
    return <div className={hasContent ? "delivery-notice" : "order-error"} role={hasContent ? "status" : "alert"}>
      <CircleAlert size={18} />
      <span>{sessionExpired
        ? "Your session expired. Dastak is returning you to sign in."
        : `${labels} could not update. ${hasContent ? "Previously loaded information remains visible." : "Dastak will retry automatically."}`}</span>
      {!sessionExpired && onRetry ? <button type="button" onClick={onRetry}>Try again</button> : null}
    </div>;
  }
  const waitingForOperationalFeed = deliveryOperationalFeedKeys.some((key) => !states[key].loaded);
  if (!hasContent && (deliveryFeedsInitiallyLoading(states) || waitingForOperationalFeed)) {
    return <div className="catalogue-loading" role="status"><span /> Loading delivery queue</div>;
  }
  return null;
}

export function DeliveryNotificationStatus({ controller }: { controller: DastakWebPushController }) {
  if (controller.status === "dismissed") return null;
  if (controller.status === "checking") {
    return <p className="delivery-notification-status" role="status"><Bell size={17} /> Checking delivery alerts…</p>;
  }
  if (controller.status === "enabled") {
    return <p className="delivery-notification-status enabled" role="status"><Check size={17} /> Delivery alerts on</p>;
  }
  const blocked = controller.status === "blocked";
  const unsupported = controller.status === "unsupported";
  const failed = controller.status === "error";
  return <aside className="delivery-notification-status attention" aria-label="Delivery notifications">
    {blocked ? <BellOff size={18} /> : <Bell size={18} />}
    <span><strong>{blocked ? "Delivery alerts are blocked" : unsupported ? "Browser alerts unavailable" : failed ? "Delivery alerts need attention" : "Get delivery alerts"}</strong><small>{controller.message ?? (blocked ? "Allow notifications in browser settings, then retry." : unsupported ? "Keep Delivery open for live in-app offers and mission updates." : "Enable browser alerts for offers, assignments, merchant readiness and returns.")}</small></span>
    {!unsupported ? <div><button type="button" disabled={controller.status === "enabling"} onClick={() => void (failed ? controller.refresh() : controller.enable())}>{controller.status === "enabling" ? "Enabling…" : failed || blocked ? "Retry" : "Enable alerts"}</button>{controller.status === "prompt" ? <button type="button" className="quiet" onClick={controller.dismiss}>Later</button> : null}</div> : null}
  </aside>;
}

function DeliveryTrackingStatus({ status, wakeLockStatus, missionActive, realtimeHealth }: {
  status: DeliveryGeolocationStatus;
  wakeLockStatus: WakeLockStatus;
  missionActive: boolean;
  realtimeHealth: OrderRealtimeHealth;
}) {
  const messages = deliveryTrackingMessages(status, wakeLockStatus, missionActive, realtimeHealth);
  if (messages.length === 0) return null;
  return <div className={`delivery-tracking-status ${messages.some((item) => item.tone === "warning") ? "warning" : ""}`} role="status">
    <Navigation size={18} />
    <span>{messages.map((item) => <small key={item.text}>{item.text}</small>)}</span>
  </div>;
}

export function deliveryTrackingMessages(
  status: DeliveryGeolocationStatus,
  wakeLockStatus: WakeLockStatus,
  missionActive: boolean,
  realtimeHealth: OrderRealtimeHealth,
) {
  const messages: Array<{ text: string; tone: "normal" | "warning" }> = [];
  const statusText: Partial<Record<DeliveryGeolocationStatus, string>> = {
    starting: "Acquiring a fresh, precise location…",
    tracking: missionActive
      ? "Foreground mission tracking is active."
      : "Location is ready for nearby delivery offers.",
    background_limited: "Web tracking was suspended in the background. Dastak will publish immediately when this tab returns.",
    unavailable: "This browser cannot share location.",
    permission_denied: "Precise location is blocked. Allow it in browser settings to continue.",
    inaccurate: "GPS accuracy is too low. Arrival remains locked until the position improves.",
    stale: "The last GPS position is stale. Arrival remains locked.",
    interrupted: "Location publication is reconnecting. Arrival remains server-locked.",
  };
  const text = statusText[status];
  if (text) messages.push({ text, tone: ["tracking"].includes(status) ? "normal" : "warning" });
  if (missionActive && wakeLockStatus === "unsupported") {
    messages.push({ text: "Screen wake lock is unavailable in this browser; keep the screen and tab open.", tone: "warning" });
  } else if (missionActive && wakeLockStatus === "failed") {
    messages.push({ text: "Dastak could not keep the screen awake. Keep this tab visible during active work.", tone: "warning" });
  }
  if (missionActive) {
    messages.push({ text: "Browsers cannot guarantee background GPS. Use Dastak Delivery on iOS for continuous background tracking.", tone: "normal" });
  }
  if (realtimeHealth !== "subscribed") {
    messages.push({ text: "Live delivery updates are reconnecting; authoritative state will reconcile automatically.", tone: "warning" });
  }
  return messages;
}

function AvailabilityStatusText({ availability, online }: {
  availability: PartnerAvailability | null;
  online: boolean;
}) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!online || !availability?.availableUntil) return;
    const remaining = Date.parse(availability.availableUntil) - Date.now();
    if (remaining <= 0) return;
    const timer = window.setTimeout(() => setNow(Date.now()), Math.min(60_000, remaining));
    return () => window.clearTimeout(timer);
  }, [availability?.availableUntil, now, online]);
  if (!online) return <small>Not receiving assignments</small>;
  const remaining = availability?.availableUntil ? Date.parse(availability.availableUntil) - now : 0;
  if (remaining <= 3 * 60_000) {
    return <small className="availability-expiring">Expiring soon · renew availability to keep receiving offers</small>;
  }
  return <small>{availabilityMessage(availability?.availableUntil)}</small>;
}

function useEffectiveRiderOnline(
  availability: PartnerAvailability | null | undefined,
  onExpire: () => void,
) {
  const [, renderExpiry] = useState(0);
  const expiryCallback = useRef(onExpire);
  expiryCallback.current = onExpire;
  useEffect(() => {
    if (availability?.status !== "online" || !availability.availableUntil) return;
    const delay = deadlineDelay(availability.availableUntil);
    const timer = window.setTimeout(() => {
      renderExpiry((value) => value + 1);
      expiryCallback.current();
    }, delay);
    return () => window.clearTimeout(timer);
  }, [availability?.availableUntil, availability?.status]);
  return isRiderEffectivelyOnline(availability);
}

function useOfferExpiration(respondBy: string, onExpire: () => void) {
  const [expired, setExpired] = useState(() => isOfferExpired(respondBy));
  const expiryCallback = useRef(onExpire);
  const notified = useRef(false);
  expiryCallback.current = onExpire;
  useEffect(() => {
    const delay = deadlineDelay(respondBy);
    const timer = window.setTimeout(() => {
      setExpired(true);
      if (!notified.current) {
        notified.current = true;
        expiryCallback.current();
      }
    }, delay);
    return () => window.clearTimeout(timer);
  }, [respondBy]);
  return expired;
}

function V1DeliveryOffer({ offer, busy, onAccept, onDecline, onExpire }: {
  offer: V1RiderOffer;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
  onExpire: () => void;
}) {
  const expired = useOfferExpiration(offer.respondBy, onExpire);
  return (
    <section id={`delivery-offer-${offer.id}`} className="delivery-offer v1-delivery-card" aria-label="New Dastak order mission">
      <header>
        <div><p className="eyebrow">Dastak order mission</p><h2>{offer.displayOrderNumber}</h2></div>
        <OfferTimer respondBy={offer.respondBy} />
      </header>

      <div className="delivery-route-facts">
        <span><Store size={17} /> {offer.pickupCount} {offer.pickupCount === 1 ? "pickup" : "pickups"}</span>
        <span><Navigation size={17} /> {formatDeliveryDistance(Math.round(offer.distanceMeters))} to pickup</span>
      </div>
      <ol className="v1-pickup-list">
        {offer.pickupStops.map((stop) => (
          <li key={stop.id}>
            <span>{stop.sequence}</span>
            <div><strong>{stop.branch.displayName}</strong><small>{stop.branch.address}</small></div>
            <em>{stop.ready ? "Ready" : "Preparing"}</em>
          </li>
        ))}
      </ol>
      <p className="delivery-return-note">
        One customer order · {transportLabel(offer.transportType)} eligible · No batching
      </p>
      <div className="delivery-offer-actions">
        <button className="danger-button" type="button" disabled={busy || expired} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy || expired} onClick={onAccept}><Check size={18} /> {expired ? "Offer expired" : "Accept mission"}</button>
      </div>
    </section>
  );
}

function CurrentV1ReturnMission({
  mission,
  busy,
  onAction,
  onCaptureEvidence,
}: {
  mission: V1ReturnMission;
  busy: boolean;
  onAction: (
    operation: V1ReturnMissionOperation,
    options?: { returnStopId?: string; verificationCode?: string; objectPath?: string },
  ) => void;
  onCaptureEvidence: (file: File) => void;
}) {
  const [pickupCode, setPickupCode] = useState("");
  const [receiptCodes, setReceiptCodes] = useState<Record<string, string>>({});
  const [packagesAccounted, setPackagesAccounted] = useState(false);
  useEffect(() => {
    setPickupCode("");
    setReceiptCodes({});
    setPackagesAccounted(false);
  }, [mission.id, mission.status]);
  return <section id={`delivery-return-${mission.id}`} className="current-delivery v1-delivery-card" aria-label="Active Dastak return mission">
    <header><span className="section-icon"><PackageCheck size={22} /></span><div><p className="eyebrow">Secure return mission</p><h2>{mission.status === "ASSIGNED" ? "Collect from customer" : mission.status === "AT_CUSTOMER" ? "Verify reverse pickup" : "Return to merchants"}</h2><small>{mission.packageCount} package(s) · no partial custody transfer</small></div></header>
    {mission.status !== "RETURNING_TO_MERCHANTS" ? <>
      <div className="delivery-stop"><span><MapPin size={19} /></span><div><small>Customer destination</small><strong>{mission.customerDestination.address}</strong>{mission.customerDestination.recipientName ? <p>Recipient: {mission.customerDestination.recipientName}</p> : null}</div></div>
      {mission.customerDestination.location ? <MapLink location={mission.customerDestination.location} label="Open return pickup route" /> : null}
      {mission.status === "ASSIGNED" ? <ArrivalAction arrival={mission.customerArrival} permitted={mission.canArriveCustomer} busy={busy} onArrive={() => onAction("v1ReturnArriveAtCustomer")} /> : null}
      {mission.canCaptureEvidence ? <label className="v1-delivery-photo"><Camera size={20} /><span><strong>{mission.evidence.length ? "Add another return photo" : "Capture return packages"}</strong><small>Immutable evidence is required before custody transfer</small></span><input type="file" accept="image/jpeg,image/png,image/heic" capture="environment" disabled={busy} onChange={(event) => { const file = event.currentTarget.files?.[0]; if (file) onCaptureEvidence(file); event.currentTarget.value = ""; }} /></label> : null}
      {mission.evidence.length ? <p className="delivery-notice" role="status"><Check size={18} /> {mission.evidence.length} immutable return photo(s) secured.</p> : null}
      {mission.canVerifyPickup ? <div className="v1-pickup-verification">
        <label className="v1-physical-check"><input type="checkbox" checked={packagesAccounted} onChange={(event) => setPackagesAccounted(event.target.checked)} /><span>I accounted for all {mission.packageCount} return package(s).</span></label>
        <label className="handoff-input">Customer return code<input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={pickupCode} onChange={(event) => setPickupCode(event.target.value.replace(/\D/g, "").slice(0, 6))} placeholder="000000" /></label>
        <button className="primary-button delivery-next-action" type="button" disabled={busy || !mission.evidence.length || !packagesAccounted || pickupCode.length !== 6 || mission.pickupVerification.status === "BLOCKED"} onClick={() => onAction("v1VerifyReturnPickup", { verificationCode: pickupCode })}><PackageCheck size={18} /> Verify complete return pickup</button>
      </div> : null}
      {mission.pickupVerification.status === "BLOCKED" ? <p className="order-error" role="alert">Return pickup verification is blocked. Keep custody unchanged and contact Operations.</p> : null}
    </> : <div className="v1-mission-stops">{mission.stops.map((stop) => {
      const code = receiptCodes[stop.id] ?? "";
      return <article className={`v1-pickup-stop ${stop.status === "COMPLETED" ? "completed" : ""}`} key={stop.id}>
        <header><span>{stop.sequence}</span><div><strong>{stop.branch.displayName}</strong><small>{stop.branch.address}</small></div><em>{stop.status.replaceAll("_", " ")}</em></header>
        {stop.branch.location && stop.status !== "COMPLETED" ? <MapLink location={stop.branch.location} label="Open merchant route" /> : null}
        {stop.status === "PENDING" ? <ArrivalAction arrival={stop.arrival} permitted={stop.canArrive} busy={busy} onArrive={() => onAction("v1ArriveAtReturnStop", { returnStopId: stop.id })} /> : null}
        {stop.status === "ARRIVED" ? <div className="v1-pickup-verification"><p>Transfer all {stop.packageCount} package(s) together.</p><label className="handoff-input">Merchant return receipt code<input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={(event) => setReceiptCodes((current) => ({ ...current, [stop.id]: event.target.value.replace(/\D/g, "").slice(0, 6) }))} placeholder="000000" /></label><button className="primary-button delivery-next-action" type="button" disabled={busy || code.length !== 6 || stop.verificationStatus === "BLOCKED"} onClick={() => onAction("v1VerifyReturnReceipt", { returnStopId: stop.id, verificationCode: code })}><PackageCheck size={18} /> Verify merchant receipt</button></div> : null}
        {stop.verificationStatus === "BLOCKED" ? <p className="order-error" role="alert">Receipt verification blocked. Keep the packages secure and contact Operations.</p> : null}
      </article>;
    })}</div>}
  </section>;
}

function CurrentV1Mission({
  mission,
  busy,
  onAction,
  onCaptureEvidence,
  onCollection,
  onRequestRecovery,
}: {
  mission: V1DeliveryMission;
  busy: boolean;
  onAction: (
    operation: V1DeliveryMissionOperation,
    options?: {
      stopId?: string;
      accountedPackageCount?: number;
      verificationCode?: string;
      objectPath?: string;
      reason?: string;
    },
  ) => void;
  onCaptureEvidence: (file: File) => void;
  onCollection: (input: {
    outcome: "COLLECTED" | "FAILED";
    method: "CASH" | "UPI";
    collectionReference?: string;
    failureReason?: string;
  }) => void;
  onRequestRecovery: (operation: RecoveryOperation) => void;
}) {
  const completed = mission.pickupStops.filter((stop) => stop.status === "COMPLETED").length;
  const [deliveryCode, setDeliveryCode] = useState("");
  const [collectionMethod, setCollectionMethod] = useState<"CASH" | "UPI">("CASH");
  const [collectionReference, setCollectionReference] = useState("");
  const [collectionFailureReason, setCollectionFailureReason] = useState("");
  const collection = mission.launchCollection;
  const finalStage = ["ALL_PACKAGES_PICKED_UP", "OUT_FOR_DELIVERY", "ARRIVED"].includes(
    mission.status,
  );
  useEffect(() => {
    setDeliveryCode("");
    setCollectionReference("");
    setCollectionFailureReason("");
  }, [mission.id, mission.status, collection?.state]);
  return (
    <section id={`delivery-mission-${mission.id}`} className="current-delivery v1-delivery-card" aria-label="Active Dastak order mission">
      <header>
        <span className="section-icon"><PackageCheck size={22} /></span>
        <div>
          <p className="eyebrow">Active Dastak mission</p>
          <h2>{missionLabel(mission.status)}</h2>
          <small>{mission.displayOrderNumber} · {completed}/{mission.pickupCount} pickups complete</small>
        </div>
      </header>

      {mission.riderSafety.escalationState === "STALLED" && (
        <p className="delivery-notice" role="status">
          <RefreshCw size={18} /> Operations detected no route progress. Keep this page open and continue the mission.
        </p>
      )}
      {mission.riderSafety.escalationState === "UNRESPONSIVE" && (
        <p className="order-error" role="alert">
          Operations marked this mission unresponsive. Contact Operations before continuing.
        </p>
      )}

      {mission.status === "ASSIGNED" && (
        <button className="primary-button delivery-next-action" type="button" disabled={busy} onClick={() => onAction("v1StartPickups")}>
          <Navigation size={18} /> Start pickups
        </button>
      )}

      {!finalStage && (
        <div className="v1-mission-stops">
          {mission.pickupStops.map((stop) => (
            <V1PickupStopCard
              key={stop.id}
              stop={stop}
              missionStarted={mission.status !== "ASSIGNED"}
              busy={busy}
              onArrive={() => onAction("v1ArriveAtPickup", { stopId: stop.id })}
              onVerify={(packageCount, code) => onAction("v1VerifyPickup", {
                stopId: stop.id,
                accountedPackageCount: packageCount,
                verificationCode: code,
              })}
            />
          ))}
        </div>
      )}

      {finalStage && mission.customerDestination && (
        <div className="v1-final-delivery">
          <div className="delivery-stop">
            <span><MapPin size={19} /></span>
            <div>
              <small>Customer destination</small>
              <strong>{mission.customerDestination.address}</strong>
              {mission.customerDestination.recipientName && (
                <p>Recipient: {mission.customerDestination.recipientName}</p>
              )}
            </div>
          </div>
          {mission.customerDestination.location && (
            <MapLink location={mission.customerDestination.location} label="Open customer route" />
          )}
          {mission.canStartFinalDelivery && (
            <button className="primary-button delivery-next-action" type="button" disabled={busy} onClick={() => onAction("v1StartFinalDelivery") }>
              <Navigation size={18} /> Start final delivery
            </button>
          )}
          {mission.canArriveCustomer && (
            <ArrivalAction arrival={mission.customerArrival} busy={busy} onArrive={() => onAction("v1ArriveAtCustomer")} />
          )}
          {mission.canVerifyCustomerPIN && (
            <div className="v1-pickup-verification">
              <label className="handoff-input">
                Customer delivery PIN
                <input
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  maxLength={6}
                  value={deliveryCode}
                  onChange={(event) =>
                    setDeliveryCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                  placeholder="000000"
                />
              </label>
              <p className="delivery-return-note">The buyer may share this in-app code with another recipient.</p>
              <button
                className="primary-button delivery-next-action"
                type="button"
                disabled={busy || deliveryCode.length !== 6}
                onClick={() => onAction("v1VerifyCustomerPIN", { verificationCode: deliveryCode })}
              >
                <PackageCheck size={18} /> Verify customer PIN
              </button>
            </div>
          )}
          {mission.finalVerification?.pinVerified && (
            <p className="delivery-notice" role="status"><Check size={18} /> Customer PIN verified.</p>
          )}
          {mission.canCaptureDeliveryEvidence && !mission.finalVerification?.evidencePresent && (
            <label className="v1-delivery-photo">
              <Camera size={20} />
              <span><strong>Capture package photo</strong><small>Required before customer handoff</small></span>
              <input
                type="file"
                accept="image/jpeg,image/png,image/heic"
                capture="environment"
                disabled={busy}
                onChange={(event) => {
                  const file = event.currentTarget.files?.[0];
                  if (file) onCaptureEvidence(file);
                  event.currentTarget.value = "";
                }}
              />
            </label>
          )}
          {mission.finalVerification?.evidencePresent && (
            <p className="delivery-notice" role="status"><Check size={18} /> Package photo secured.</p>
          )}
          {collection && collection.state !== "NOT_REQUIRED" && (
            <section className={`v1-doorstep-collection ${collection.state === "COLLECTION_RETRY_NEEDED" ? "retry" : ""}`} aria-labelledby="doorstep-collection-title">
              <header><span><Banknote size={21} /></span><div><small>AUTHORITATIVE AMOUNT DUE</small><h3 id="doorstep-collection-title">{formatPrice(collection.amountPaise ?? 0)}</h3></div><b>{collection.state === "PAYMENT_COLLECTED" ? "COLLECTED" : "PAY AT DELIVERY"}</b></header>
              {collection.state === "PAYMENT_COLLECTED" ? <p className="delivery-notice" role="status"><Check size={18} /> Payment collected by {collection.lastMethod === "CASH" ? "cash" : "UPI"}. Delivery completion is unlocked.</p> : !collection.canRecord ? <p>First confirm arrival, verify the customer PIN and secure the package photo. Payment collection unlocks after those steps.</p> : <>
                {collection.state === "COLLECTION_RETRY_NEEDED" ? <p className="order-error" role="status"><CircleAlert size={17} /> The last collection failed{collection.failureReason ? `: ${collection.failureReason}` : "."} Keep every package secure and retry.</p> : <p>Ask the recipient whether they are paying by cash or UPI, then record the actual result.</p>}
                <div className="v1-collection-methods" role="group" aria-label="Actual payment method">
                  {collection.methods.map((method) => <button type="button" key={method} aria-pressed={collectionMethod === method} disabled={busy} onClick={() => setCollectionMethod(method)}>{method === "CASH" ? <Banknote size={18} /> : <WalletCards size={18} />}{method === "CASH" ? "Cash" : "UPI"}</button>)}
                </div>
                {collectionMethod === "UPI" ? <label className="handoff-input">UPI reference (optional)<input value={collectionReference} maxLength={200} autoComplete="off" placeholder="Recipient reference" onChange={(event) => setCollectionReference(event.target.value)} /></label> : null}
                <label className="handoff-input">If collection fails, add a reason<textarea value={collectionFailureReason} maxLength={500} rows={2} placeholder="For example, recipient could not complete payment" onChange={(event) => setCollectionFailureReason(event.target.value)} /></label>
                <div className="v1-collection-actions"><button className="secondary-button" type="button" disabled={busy || collectionFailureReason.trim().length < 3 || !collection.canRecord} onClick={() => onCollection({ outcome: "FAILED", method: collectionMethod, collectionReference: collectionReference || undefined, failureReason: collectionFailureReason.trim() })}>Couldn’t collect</button><button className="primary-button" type="button" disabled={busy || !collection.canRecord} onClick={() => onCollection({ outcome: "COLLECTED", method: collectionMethod, collectionReference: collectionReference || undefined })}><Check size={18} /> Record collected</button></div>
              </>}
            </section>
          )}
          {mission.canCompleteDelivery && (
            <button className="primary-button delivery-next-action" type="button" disabled={busy} onClick={() => onAction("v1CompleteDelivery")}>
              <PackageCheck size={18} /> Complete delivery
            </button>
          )}
          {mission.finalVerification?.status === "BLOCKED" && (
            <p className="order-error" role="alert">Normal code attempts are blocked. Keep the packages secure and report the problem to Operations.</p>
          )}
        </div>
      )}

      {mission.canCancelBeforePickup && (
        <button className="danger-button v1-secondary-action" type="button" disabled={busy} onClick={() => onRequestRecovery("v1CancelBeforePickup")}>
          Release mission before pickup
        </button>
      )}
      {mission.mustUseDeliveryRecovery && (
        <div className="delivery-recovery-actions">
          <button className="danger-button v1-secondary-action" type="button" disabled={busy} onClick={() => onRequestRecovery("v1ReportCustomerUnreachable")}>
            Customer unreachable
          </button>
          <button className="danger-button v1-secondary-action" type="button" disabled={busy} onClick={() => onRequestRecovery("v1ReportDeliveryProblem")}>
            Report another delivery problem
          </button>
        </div>
      )}
      {mission.status === "ALL_PACKAGES_PICKED_UP" && (
        <p className="delivery-notice" role="status"><Check size={18} /> All packages collected. Customer destination is unlocked.</p>
      )}
      {mission.status === "DELIVERY_RECOVERY" && (
        <p className="order-error" role="alert">Operations is handling this custody issue. Keep every package secure.</p>
      )}
    </section>
  );
}

export function recoveryOptions(operation: RecoveryOperation) {
  if (operation === "v1CancelBeforePickup") {
    return ["Vehicle issue", "Unable to reach pickup", "Safety concern", "Other"];
  }
  if (operation === "v1ReportCustomerUnreachable") {
    return ["Customer not answering", "Address inaccessible", "Safety concern", "Other"];
  }
  return ["Package damaged", "Vehicle issue", "Safety concern", "Customer unavailable", "Other"];
}

function RecoveryConfirmation({ intent, busy, onDismiss, onConfirm }: {
  intent: RecoveryIntent;
  busy: boolean;
  onDismiss: () => void;
  onConfirm: (reason: string) => Promise<void>;
}) {
  const options = recoveryOptions(intent.operation);
  const [reason, setReason] = useState(options[0]);
  const [detail, setDetail] = useState("");
  const title = intent.operation === "v1CancelBeforePickup"
    ? "Release this mission?"
    : intent.operation === "v1ReportCustomerUnreachable"
      ? "Start customer recovery?"
      : "Report a custody problem?";
  const consequence = intent.operation === "v1CancelBeforePickup"
    ? "The mission will return to Operations for reassignment. This is only available before package custody begins."
    : "This moves the delivery into Operations recovery. Keep every package secure; reporting the issue does not transfer or release custody.";
  const finalReason = [reason, detail.trim()].filter(Boolean).join(" — ");

  useEffect(() => {
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !busy) onDismiss();
    };
    window.addEventListener("keydown", dismissOnEscape);
    return () => window.removeEventListener("keydown", dismissOnEscape);
  }, [busy, onDismiss]);

  return <div className="delivery-dialog-backdrop" role="presentation">
    <form className="delivery-recovery-dialog" role="dialog" aria-modal="true" aria-labelledby="delivery-recovery-title" onSubmit={(event) => {
      event.preventDefault();
      void onConfirm(finalReason);
    }}>
      <header><div><p className="eyebrow">Custody protection</p><h2 id="delivery-recovery-title">{title}</h2></div><button type="button" className="icon-button" onClick={onDismiss} disabled={busy} aria-label="Close"><X size={18} /></button></header>
      <p>{consequence}</p>
      <fieldset>
        <legend>Reason</legend>
        {options.map((option) => <label key={option}><input type="radio" name="recovery-reason" value={option} checked={reason === option} disabled={busy} onChange={() => setReason(option)} /><span>{option}</span></label>)}
      </fieldset>
      <label>Optional detail<textarea rows={3} maxLength={300} value={detail} disabled={busy} onChange={(event) => setDetail(event.target.value)} placeholder="Add details that will help Operations resolve this safely" /></label>
      <div><button className="secondary-button" type="button" onClick={onDismiss} disabled={busy}>Keep delivery</button><button className="danger-button" type="submit" disabled={busy || finalReason.length < 3}>{busy ? "Reporting…" : "Confirm and notify Operations"}</button></div>
    </form>
  </div>;
}

function ArrivalAction({ arrival, permitted = true, busy, onArrive }: {
  arrival: V1ArrivalEligibility | null | undefined;
  permitted?: boolean;
  busy: boolean;
  onArrive: () => void;
}) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, []);
  const eligible = permitted && canArriveAtDestination(arrival, now);
  const fresh = arrival?.validUntil && Date.parse(arrival.validUntil) > now;
  const hint = eligible ? "Within 50 metres. You can confirm arrival." :
    fresh && arrival?.reason === "TOO_FAR" && arrival.distanceMeters !== null
      ? `Move within 50 metres to confirm arrival · ${Math.ceil(arrival.distanceMeters)} m away.`
      : "A fresh, precise GPS position within 50 metres is required to confirm arrival.";
  return <div>
    <button className="primary-button delivery-next-action" type="button" disabled={busy || !eligible} onClick={onArrive}>
      <MapPin size={18} /> I’ve arrived
    </button>
    <p className="delivery-return-note" role="status">{hint}</p>
  </div>;
}

function V1PickupStopCard({
  stop,
  missionStarted,
  busy,
  onArrive,
  onVerify,
}: {
  stop: V1PickupStop;
  missionStarted: boolean;
  busy: boolean;
  onArrive: () => void;
  onVerify: (packageCount: number, code: string) => void;
}) {
  const [accounted, setAccounted] = useState<number[]>([]);
  const [pickupCode, setPickupCode] = useState("");
  const packageCount = stop.packageCount ?? 0;
  useEffect(() => {
    setAccounted([]);
    setPickupCode("");
  }, [stop.id, stop.status]);
  const allAccounted = packageCount > 0 && accounted.length === packageCount;

  return (
    <article className={`v1-pickup-stop ${stop.status === "COMPLETED" ? "completed" : ""}`}>
      <header>
        <span>{stop.sequence}</span>
        <div><strong>{stop.branch.displayName}</strong><small>{stop.branch.address}</small></div>
        <em>{stop.status === "COMPLETED" ? "Picked up" : stop.ready ? "Ready" : stop.runningLate ? "Merchant running late" : "Preparing"}</em>
      </header>
      {stop.branch.location && stop.status !== "COMPLETED" && (
        <MapLink location={stop.branch.location} label="Open merchant route" />
      )}
      {missionStarted && stop.status === "PENDING" && (
        <ArrivalAction arrival={stop.arrival} busy={busy} onArrive={onArrive} />
      )}
      {stop.status === "ARRIVED" && !stop.ready && (
        <p className="delivery-return-note">Waiting for the merchant to mark this pickup Ready · {formatDuration(stop.waitingSeconds)}</p>
      )}
      {stop.status === "ARRIVED" && stop.ready && packageCount > 0 && (
        <div className="v1-pickup-verification">
          <fieldset>
            <legend>Account for all {packageCount} {packageCount === 1 ? "package" : "packages"}</legend>
            {Array.from({ length: packageCount }, (_, index) => index + 1).map((number) => (
              <label key={number}>
                <input
                  type="checkbox"
                  checked={accounted.includes(number)}
                  onChange={(event) => setAccounted((current) => event.currentTarget.checked
                    ? [...current, number]
                    : current.filter((item) => item !== number))}
                />
                Package {number}
              </label>
            ))}
          </fieldset>
          <label className="handoff-input">
            Merchant pickup code
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={pickupCode}
              onChange={(event) => setPickupCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
              placeholder="000000"
            />
          </label>
          <button
            className="primary-button delivery-next-action"
            type="button"
            disabled={busy || !allAccounted || pickupCode.length !== 6}
            onClick={() => onVerify(packageCount, pickupCode)}
          >
            <PackageCheck size={18} /> Verify complete pickup
          </button>
        </div>
      )}
    </article>
  );
}

function ParcelOffer({ offer, busy, onAccept, onDecline, onExpire }: {
  offer: ParcelAssignment;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
  onExpire: () => void;
}) {
  const expired = useOfferExpiration(offer.respondBy, onExpire);
  return (
    <section className="delivery-offer" aria-label="New parcel offer">
      <header><div><p className="eyebrow">Parcel offer</p><h2>{offer.parcel.declaredContents}</h2></div><OfferTimer respondBy={offer.respondBy} /></header>
      <p className="delivery-address"><MapPin size={18} /> {offer.parcel.pickup.address}</p>
      <p className="delivery-payout"><small>You earn</small><strong>{formatPrice(offer.parcel.courierPayout.paise)}</strong></p>
      <div className="delivery-route-facts">
        <span><Navigation size={17} /> {formatDeliveryDistance(Math.round(offer.distanceMeters))} to pickup</span>
        <MapLink location={offer.parcel.pickup} label="Open pickup route" />
      </div>
      <div className="delivery-offer-actions">
        <button className="danger-button" type="button" disabled={busy || expired} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy || expired} onClick={onAccept}><Check size={18} /> {expired ? "Offer expired" : "Accept"}</button>
      </div>
    </section>
  );
}

type ParcelOperation = "startToPickup" | "confirmPickup" | "startDelivery" | "completeDelivery";

function CurrentParcel({ assignment, busy, verificationCode, onVerificationCode, onAction }: {
  assignment: ParcelAssignment;
  busy: boolean;
  verificationCode: string;
  onVerificationCode: (code: string) => void;
  onAction: (operation: ParcelOperation, code?: string) => void;
}) {
  const action = parcelAction(assignment.parcel.status);
  const headingToRecipient = ["picked_up", "in_transit"].includes(assignment.parcel.status);
  const destination = headingToRecipient ? assignment.parcel.dropoff : assignment.parcel.pickup;
  return (
    <section className="current-delivery" aria-label="Active parcel delivery">
      <header><span className="section-icon"><PackageCheck size={22} /></span><div><p className="eyebrow">Active parcel</p><h2>{parcelStatusLabel(assignment.parcel.status)}</h2></div><p className="active-delivery-payout"><small>Earnings</small><strong>{formatPrice(assignment.parcel.courierPayout.paise)}</strong></p></header>
      <div className="delivery-stop"><span><Store size={19} /></span><div><small>Pickup</small><strong>{assignment.parcel.pickup.address}</strong></div></div>
      <div className="delivery-stop"><span><MapPin size={19} /></span><div><small>Drop-off</small><strong>{assignment.parcel.dropoff.address}</strong></div></div>
      <div className="parcel-job-facts"><p><small>Contents</small><strong>{assignment.parcel.declaredContents}</strong></p><p><small>Recipient</small><strong>{assignment.parcel.recipient.name}</strong></p></div>
      <MapLink location={destination} label={headingToRecipient ? "Open drop-off route" : "Open pickup route"} />
      {action?.needsCode && <label className="handoff-input">{assignment.parcel.status === "en_route_to_pickup" ? "Sender pickup code" : "Recipient delivery code"}<input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={verificationCode} onChange={(event) => onVerificationCode(event.target.value.replace(/\D/g, "").slice(0, 6))} placeholder="000000" /></label>}
      {action && <button className="primary-button delivery-next-action" type="button" disabled={busy || (action.needsCode && verificationCode.length !== 6)} onClick={() => onAction(action.operation, action.needsCode ? verificationCode : undefined)}>{action.icon} {action.label}</button>}
    </section>
  );
}

function DeliveryOffer({ offer, busy, onAccept, onDecline, onExpire }: {
  offer: DeliveryAssignment;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
  onExpire: () => void;
}) {
  const expired = useOfferExpiration(offer.respondBy, onExpire);
  return (
    <section className="delivery-offer" aria-label="New delivery offer">
      <header><div><p className="eyebrow">New offer</p><h2>{offer.store.name}</h2></div><OfferTimer respondBy={offer.respondBy} /></header>
      <p className="delivery-address"><Store size={18} /> {offer.store.address}</p>
      <p className="delivery-payout"><small>You earn</small><strong>{formatPrice(offer.courierPayout.paise)}</strong></p>
      <DeliveryItems assignment={offer} />
      <div className="delivery-route-facts">
        <span><Navigation size={17} /> {formatDeliveryDistance(Math.round(offer.distanceMeters))} to store</span>
        <MapLink location={offer.store.pickup} label="Open pickup route" />
      </div>
      <div className="delivery-offer-actions">
        <button className="danger-button" type="button" disabled={busy || expired} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy || expired} onClick={onAccept}><Check size={18} /> {expired ? "Offer expired" : "Accept"}</button>
      </div>
    </section>
  );
}

function CurrentDelivery({ assignment, busy, verificationCode, onVerificationCode, onAction }: {
  assignment: DeliveryAssignment;
  busy: boolean;
  verificationCode: string;
  onVerificationCode: (code: string) => void;
  onAction: (operation: DeliveryJobOperation, code?: string) => void;
}) {
  const action = jobAction(assignment.orderStatus);
  const headingToCustomer = ["picked_up", "in_transit"].includes(assignment.orderStatus);
  const destination = headingToCustomer ? assignment.dropoff : assignment.store.pickup;
  return (
    <section className="current-delivery" aria-label="Active delivery">
      <header>
        <span className="section-icon"><PackageCheck size={22} /></span>
        <div><p className="eyebrow">Active delivery</p><h2>{orderStatusLabel(assignment.orderStatus)}</h2></div>
        <p className="active-delivery-payout"><small>Earnings</small><strong>{formatPrice(assignment.courierPayout.paise)}</strong></p>
      </header>
      <div className="delivery-stop">
        <span><Store size={19} /></span>
        <div><small>Pickup</small><strong>{assignment.store.name}</strong><p>{assignment.store.address}</p></div>
      </div>
      <div className="delivery-stop">
        <span><MapPin size={19} /></span>
        <div><small>Drop-off</small><strong>Customer destination</strong><p>Open directions for the verified doorstep.</p></div>
      </div>
      <DeliveryItems assignment={assignment} />
      <MapLink location={destination} label={headingToCustomer ? "Open drop-off route" : "Open pickup route"} />

      {assignment.orderStatus === "returning_to_merchant" && (
        <p className="delivery-return-note">Return the items to the merchant. The merchant will confirm receipt and close this delivery.</p>
      )}

      {action?.needsCode && (
        <label className="handoff-input">
          {assignment.orderStatus === "at_store" ? "Merchant pickup code" : "Customer delivery code"}
          <input
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={4}
            value={verificationCode}
            onChange={(event) => onVerificationCode(event.target.value.replace(/\D/g, "").slice(0, 4))}
            placeholder="0000"
          />
        </label>
      )}

      {action && (
        <button
          className="primary-button delivery-next-action"
          type="button"
          disabled={busy || (action.needsCode && verificationCode.length !== 4)}
          onClick={() => onAction(action.operation, action.needsCode ? verificationCode : undefined)}
        >
          {action.icon} {action.label}
        </button>
      )}
    </section>
  );
}

function DeliveryItems({ assignment }: { assignment: DeliveryAssignment }) {
  return (
    <ul className="delivery-items">
      {assignment.items.map((item) => <li key={item.productId}><b>{item.quantity}</b><span>{item.name}<small>{item.unitLabel}</small></span></li>)}
    </ul>
  );
}

function OfferTimer({ respondBy }: { respondBy: string }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const interval = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(interval);
  }, []);
  const seconds = Math.max(0, Math.ceil((Date.parse(respondBy) - now) / 1000));
  return <span className="offer-timer">{seconds}s</span>;
}

function MapLink({ location, label }: { location: { latitude: number; longitude: number }; label: string }) {
  return (
    <a className="map-link" href={`https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(`${location.latitude},${location.longitude}`)}&travelmode=driving`} target="_blank" rel="noreferrer">
      <Navigation size={17} /> {label}
    </a>
  );
}

function jobAction(status: DeliveryAssignment["orderStatus"]): {
  operation: DeliveryJobOperation;
  label: string;
  needsCode: boolean;
  icon: ReactNode;
} | undefined {
  switch (status) {
    case "assigned": return { operation: "startToStore", label: "Start to store", needsCode: false, icon: <Navigation size={18} /> };
    case "en_route_to_pickup": return { operation: "arriveAtStore", label: "Arrived at store", needsCode: false, icon: <Store size={18} /> };
    case "at_store": return { operation: "confirmPickup", label: "Confirm pickup", needsCode: true, icon: <PackageCheck size={18} /> };
    case "picked_up": return { operation: "startDelivery", label: "Start delivery", needsCode: false, icon: <Navigation size={18} /> };
    case "in_transit": return { operation: "completeDelivery", label: "Complete delivery", needsCode: true, icon: <Check size={18} /> };
    default: return undefined;
  }
}

function parcelAction(status: ParcelAssignment["parcel"]["status"]): {
  operation: ParcelOperation;
  label: string;
  needsCode: boolean;
  icon: ReactNode;
} | undefined {
  switch (status) {
    case "assigned": return { operation: "startToPickup", label: "Start to pickup", needsCode: false, icon: <Navigation size={18} /> };
    case "en_route_to_pickup": return { operation: "confirmPickup", label: "Confirm pickup", needsCode: true, icon: <PackageCheck size={18} /> };
    case "picked_up": return { operation: "startDelivery", label: "Start delivery", needsCode: false, icon: <Navigation size={18} /> };
    case "in_transit": return { operation: "completeDelivery", label: "Complete delivery", needsCode: true, icon: <Check size={18} /> };
    default: return undefined;
  }
}

function deliveryMethodLabel(method: string) {
  if (method === "retired") return "Retired delivery method";
  if (method === "goods_vehicle") return "Tempo / goods vehicle";
  return method === "bike" || method === "motorbike"
    ? "Motorbike"
    : method === "auto"
      ? "Auto"
      : `${method.charAt(0).toUpperCase()}${method.slice(1)}`;
}

export function deliveryNotificationTarget(hash: string): {
  kind: "workspace" | "offer" | "mission" | "return";
  entityId?: string;
} | undefined {
  const match = /^#\/deliveries(?:\/(offer|mission|return)(?:\/([^/]+))?)?\/?$/.exec(hash);
  if (!match) return undefined;
  let entityId: string | undefined;
  try {
    entityId = match[2] ? decodeURIComponent(match[2]) : undefined;
  } catch {
    return undefined;
  }
  return {
    kind: (match[1] ?? "workspace") as "workspace" | "offer" | "mission" | "return",
    ...(entityId ? { entityId } : {}),
  };
}

function availabilityPresentationChanged(
  current: PartnerAvailability | null | undefined,
  incoming: PartnerAvailability,
) {
  return !current || current.status !== incoming.status ||
    current.availableUntil !== incoming.availableUntil ||
    current.serviceZoneId !== incoming.serviceZoneId;
}

export function mergeMissionTrackingSnapshot(
  current: V1DeliveryDispatchSnapshot,
  incoming: V1DeliveryDispatchSnapshot,
  missionId: string,
  now = Date.now(),
): V1DeliveryDispatchSnapshot {
  if (current.currentMission?.id === missionId && incoming.currentMission?.id === missionId &&
    shouldApplyMissionProjection(current.currentMission, incoming.currentMission, now)) {
    return { ...current, currentMission: incoming.currentMission };
  }
  if (current.returnMission?.id === missionId && incoming.returnMission?.id === missionId &&
    shouldApplyReturnProjection(current.returnMission, incoming.returnMission, now)) {
    return { ...current, returnMission: incoming.returnMission };
  }
  return current;
}

function shouldApplyMissionProjection(
  current: V1DeliveryMission,
  incoming: V1DeliveryMission,
  now: number,
) {
  if (incoming.version < current.version) return false;
  if (incoming.version > current.version || incoming.status !== current.status) return true;
  return arrivalProjectionKey([
    current.customerArrival,
    ...current.pickupStops.map((stop) => stop.arrival),
  ], now) !== arrivalProjectionKey([
    incoming.customerArrival,
    ...incoming.pickupStops.map((stop) => stop.arrival),
  ], now);
}

function shouldApplyReturnProjection(
  current: V1ReturnMission,
  incoming: V1ReturnMission,
  now: number,
) {
  if (incoming.version < current.version) return false;
  if (incoming.version > current.version || incoming.status !== current.status) return true;
  return arrivalProjectionKey([
    current.customerArrival,
    ...current.stops.map((stop) => stop.arrival),
  ], now) !== arrivalProjectionKey([
    incoming.customerArrival,
    ...incoming.stops.map((stop) => stop.arrival),
  ], now);
}

function arrivalProjectionKey(
  arrivals: Array<V1ArrivalEligibility | null | undefined>,
  now: number,
) {
  return arrivals.map((arrival) => {
    if (!arrival) return "none";
    const distanceBand = arrival.distanceMeters === null ? "unknown" : Math.floor(arrival.distanceMeters / 10);
    const validityBand = arrival.validUntil === null ? "expired" :
      Math.max(0, Math.floor((Date.parse(arrival.validUntil) - now) / 20_000));
    return [arrival.eligible, arrival.reason, distanceBand, validityBand].join(":");
  }).join("|");
}

function deliveryWorkKindLabel(kind: DeliveryWorkHistoryItem["kind"]) {
  switch (kind) {
    case "V1_DELIVERY": return "Dastak delivery";
    case "RETURN": return "Return mission";
    case "LEGACY_DELIVERY": return "Store delivery";
    case "PARCEL": return "Parcel delivery";
  }
}

function deliveryWorkOutcomeLabel(outcome: DeliveryWorkHistoryItem["outcome"]) {
  switch (outcome) {
    case "COMPLETED": return "Completed";
    case "RETURNED": return "Returned";
    case "CANCELLED": return "Cancelled";
  }
}

function humanizeDeliveryStatus(status: string) {
  return status.toLowerCase().replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatDeliveryHistoryDate(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function fileSignature(file: File) {
  return [file.name, file.type, file.size, file.lastModified].join(":");
}
function transportLabel(transport: string) {
  if (transport === "CAR") return "Tempo / goods vehicle";
  return transport === "MOTORBIKE"
    ? "Motorbike"
    : `${transport.charAt(0)}${transport.slice(1).toLowerCase()}`;
}
function missionLabel(status: V1DeliveryMission["status"]) {
  switch (status) {
    case "ASSIGNED": return "Mission assigned";
    case "EN_ROUTE_TO_PICKUPS": return "Heading to pickups";
    case "PICKUP_IN_PROGRESS": return "Collecting packages";
    case "ALL_PACKAGES_PICKED_UP": return "All packages collected";
    case "OUT_FOR_DELIVERY": return "Out for delivery";
    case "ARRIVED": return "At customer destination";
    case "DELIVERY_RECOVERY": return "Delivery recovery";
  }
}
function formatDuration(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${minutes}:${remainder.toString().padStart(2, "0")}`;
}
function availabilityMessage(availableUntil?: string | null) {
  if (!availableUntil) return "Available for nearby orders";
  const time = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(new Date(availableUntil));
  return `Available until ${time} · Auto-offline after 15 minutes`;
}
function message(error: unknown) {
  return userFacingError(error, "The delivery service is unavailable right now.");
}
