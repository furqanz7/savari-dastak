import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { Banknote, Camera, Check, CircleAlert, MapPin, Navigation, PackageCheck, Power, RefreshCw, Store, UserRound, WalletCards, X } from "lucide-react";
import {
  acceptV1DeliveryOffer,
  acceptDeliveryOffer,
  advanceV1DeliveryMission,
  advanceV1ReturnMission,
  advanceDeliveryJob,
  declineV1DeliveryOffer,
  declineDeliveryOffer,
  getDeliveryDispatch,
  getDeliveryPartnerSnapshot,
  getV1DeliveryDispatch,
  heartbeatV1DeliveryMission,
  publishDeliveryPartnerLocation,
  recordV1LaunchCollection,
  setDeliveryPartnerAvailability,
  uploadV1DeliveryEvidence,
  uploadV1ReturnEvidence,
  DeliveryRequestError,
  type DeliveryAssignment,
  type DeliveryDispatchSnapshot,
  type DeliveryJobOperation,
  type DeliveryPartnerSnapshot,
  type V1DeliveryDispatchSnapshot,
  type V1DeliveryMission,
  type V1DeliveryMissionOperation,
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
import { RefreshQueue, useOrderRealtime } from "./orderRealtime";
import { userFacingError } from "./userFacingError";

type Props = {
  accessToken: string;
  accountId: string;
  client: SupabaseClient;
  displayName?: string;
  email?: string;
  phoneNumber?: string;
  supabaseUrl: string;
  publishableKey: string;
  onSignOut: () => void;
};

type DispatchAction = "accept" | "decline" | DeliveryJobOperation;

export function DeliveryPartnerView({ accessToken, accountId, client, displayName, email, phoneNumber, supabaseUrl, publishableKey, onSignOut }: Props) {
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
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [verificationCode, setVerificationCode] = useState("");
  const [section, setSection] = useState<"deliveries" | "royalty" | "account">("deliveries");
  const refreshQueue = useRef(new RefreshQueue());
  const actionKeys = useRef(new Map<string, string>());

  const refresh = useCallback(async (showProgress = false) => {
    await refreshQueue.current.request(showProgress, async (progress) => {
      if (progress) setBusy("refresh");
      try {
        const [partnerSnapshot, v1DispatchSnapshot, dispatchSnapshot, parcelSnapshot] = await Promise.all([
          getDeliveryPartnerSnapshot(auth),
          getV1DeliveryDispatch(auth),
          getDeliveryDispatch(auth),
          getParcelPartnerSnapshot(auth),
        ]);
        setPartner(partnerSnapshot);
        setV1Dispatch(v1DispatchSnapshot);
        setDispatch(dispatchSnapshot);
        setParcelDispatch(parcelSnapshot);
        setError(undefined);
      } catch (refreshError) {
        setError(message(refreshError));
      } finally {
        setLoading(false);
        if (progress) setBusy(undefined);
      }
    });
  }, [auth]);

  useOrderRealtime({ client, accountId, accessToken, onChange: () => void refresh() });

  useEffect(() => {
    void refresh();
    const interval = window.setInterval(() => void refresh(), 30_000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    const onOnline = () => void refresh();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onOnline);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onOnline);
    };
  }, [refresh]);

  useEffect(() => {
    const mission = v1Dispatch.currentMission;
    if (!mission || mission.status === "DELIVERY_RECOVERY") return;
    const heartbeat = async () => {
      try {
        await heartbeatV1DeliveryMission({
          ...auth,
          missionId: mission.id,
          expectedVersion: mission.version,
        });
        await refresh();
      } catch {
        await refresh();
      }
    };
    const interval = window.setInterval(() => void heartbeat(), 20_000);
    return () => window.clearInterval(interval);
  }, [auth, refresh, v1Dispatch.currentMission]);

  const changeAvailability = async (online: boolean) => {
    setBusy("availability");
    setError(undefined);
    try {
      const location = online ? await currentLocation() : undefined;
      const availability = await setDeliveryPartnerAvailability({
        ...auth,
        online,
        location,
        idempotencyKey: crypto.randomUUID(),
      });
      setPartner((current) => current ? { ...current, availability } : current);
      if (online) {
        const [v1Snapshot, orderSnapshot, parcelSnapshot] = await Promise.all([
          getV1DeliveryDispatch(auth),
          getDeliveryDispatch(auth),
          getParcelPartnerSnapshot(auth),
        ]);
        setV1Dispatch(v1Snapshot);
        setDispatch(orderSnapshot);
        setParcelDispatch(parcelSnapshot);
      }
    } catch (availabilityError) {
      setError(message(availabilityError));
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
      setVerificationCode("");
      if (operation === "confirmPickup") setNotice("Pickup verified. The parcel is now in your care.");
      if (operation === "completeDelivery") setNotice("Parcel delivery verified and completed.");
    } catch (actionError) {
      setError(message(actionError));
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
      setVerificationCode("");
      if (action === "confirmPickup") setNotice("Pickup verified. The order is now in your care.");
      if (action === "completeDelivery") setNotice("Delivery verified and completed.");
    } catch (actionError) {
      setError(message(actionError));
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
      if (action === "accept") setNotice("Mission assigned. Collect every package at each pickup.");
    } catch (actionError) {
      setError(message(actionError));
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
      setVerificationCode("");
      if (operation === "v1VerifyPickup") {
        setNotice("Pickup verified. Every declared package is now in your custody.");
      }
      if (operation === "v1VerifyDelivery") {
        setNotice("Delivery verified. Every package is now in the customer’s custody.");
      }
    } catch (actionError) {
      setError(message(actionError));
    } finally {
      setBusy(undefined);
    }
  };

  const captureV1DeliveryEvidence = async (mission: V1DeliveryMission, file: File) => {
    const requestIdentity = `v1:evidence:${mission.id}:${file.name}:${file.size}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const objectPath = await uploadV1DeliveryEvidence(client, accountId, file);
      const snapshot = await advanceV1DeliveryMission({
        ...auth,
        missionId: mission.id,
        operation: "v1AddDeliveryEvidence",
        objectPath,
        idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setV1Dispatch(snapshot);
      setNotice("Package photo captured. Ask the recipient for their in-app delivery code.");
    } catch (actionError) {
      setError(message(actionError));
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
      setNotice(input.outcome === "COLLECTED"
        ? "Payment collected and recorded. Complete the customer delivery verification."
        : "Collection attempt recorded. Keep the order secure and retry before delivery.");
    } catch (actionError) {
      setError(message(actionError));
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
      if (operation === "v1VerifyReturnPickup") {
        setNotice("Return pickup verified. Every return package is now in your custody.");
      }
      if (operation === "v1VerifyReturnReceipt") {
        setNotice("Merchant receipt verified. Reverse custody was recorded exactly once.");
      }
    } catch (actionError) {
      setError(message(actionError));
    } finally {
      setBusy(undefined);
    }
  };

  const captureV1ReturnEvidence = async (mission: V1ReturnMission, file: File) => {
    const requestIdentity = `v1-return:evidence:${mission.id}:${file.name}:${file.size}`;
    const idempotencyKey = actionKeys.current.get(requestIdentity) ?? crypto.randomUUID();
    actionKeys.current.set(requestIdentity, idempotencyKey);
    setBusy(requestIdentity);
    setError(undefined);
    try {
      const objectPath = await uploadV1ReturnEvidence(client, accountId, file);
      const snapshot = await advanceV1ReturnMission({
        ...auth, returnMissionId: mission.id, operation: "v1AddReturnEvidence",
        objectPath, idempotencyKey,
      });
      actionKeys.current.delete(requestIdentity);
      setV1Dispatch(snapshot);
      setNotice("Immutable return-package photo captured.");
    } catch (actionError) {
      setError(message(actionError));
    } finally {
      setBusy(undefined);
    }
  };

  const online = partner?.availability?.status === "online";
  const hasJob = Boolean(
    v1Dispatch.currentMission || v1Dispatch.returnMission || dispatch.currentJob || parcelDispatch.currentJob,
  );

  useEffect(() => {
    if (!online || !navigator.geolocation) return;
    let lastPublishedAt = 0;
    const watch = navigator.geolocation.watchPosition(
      (position) => {
        const now = Date.now();
        if (now - lastPublishedAt < 15_000) return;
        lastPublishedAt = now;
        void publishDeliveryPartnerLocation({
          ...auth,
          location: {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
          },
          idempotencyKey: crypto.randomUUID(),
        }).then((availability) => {
          setPartner((current) => current ? { ...current, availability } : current);
        }).catch((locationError) => {
          if (locationError instanceof DeliveryRequestError && locationError.code === "partner_offline") {
            void refresh();
          }
        });
      },
      () => undefined,
      { enableHighAccuracy: true, maximumAge: 10_000, timeout: 12_000 },
    );
    return () => navigator.geolocation.clearWatch(watch);
  }, [auth, online, refresh]);

  return (
    <div className="delivery-shell">
      <nav className="workspace-tabs" role="tablist" aria-label="Delivery Partner workspace">
        <button type="button" role="tab" aria-selected={section === "deliveries"} className={section === "deliveries" ? "selected" : ""} onClick={() => setSection("deliveries")}><Navigation size={18} /> Deliveries</button>
        <button type="button" role="tab" aria-selected={section === "royalty"} className={section === "royalty" ? "selected" : ""} onClick={() => setSection("royalty")}><WalletCards size={18} /> Royalty</button>
        <button type="button" role="tab" aria-selected={section === "account"} className={section === "account" ? "selected" : ""} onClick={() => setSection("account")}><UserRound size={18} /> Account</button>
      </nav>
      {section === "royalty" ? <RoyaltyPanel auth={auth} kind="RIDER" /> : section === "account" ? <RoleAccountView
        accessToken={accessToken}
        displayName={displayName}
        email={email}
        phoneNumber={phoneNumber}
        roleName="Delivery Partner"
        persona="DELIVERY"
        deliveryPartner={partner}
        deliveryPartnerLoading={loading}
        deliveryPartnerError={partner ? undefined : error}
        supabaseUrl={supabaseUrl}
        publishableKey={publishableKey}
        onRefreshPartner={() => void refresh(true)}
        onOpenWorkspace={() => setSection("deliveries")}
        onSignOut={onSignOut}
      /> : <>
      <header className="delivery-heading">
        <div>
          <p className="eyebrow">{displayName ? `Hello, ${displayName}` : "Dastak Delivery Partner"}</p>
          <h1>Delivery</h1>
          <p>{partner?.deliveryMethod ? deliveryMethodLabel(partner.deliveryMethod) : "Delivery Partner"}</p>
        </div>
        <button className="icon-button" type="button" onClick={() => void refresh(true)} disabled={Boolean(busy)} aria-label="Refresh delivery queue" title="Refresh delivery queue">
          <RefreshCw size={19} />
        </button>
      </header>

      {error && <p className="order-error" role="alert">{error}</p>}
      {notice && <div className="delivery-notice" role="status"><Check size={18} /><span>{notice}</span><button type="button" onClick={() => setNotice(undefined)} aria-label="Dismiss confirmation"><X size={16} /></button></div>}
      {loading ? <div className="catalogue-loading" role="status"><span /> Loading delivery queue</div> : (
        <>
          <section className="delivery-availability" aria-label="Availability">
            <span className={`availability-icon ${online ? "online" : ""}`}><Power size={21} /></span>
            <div>
              <strong>{online ? "Online" : "Offline"}</strong>
              <small>{online ? availabilityMessage(partner?.availability?.availableUntil) : "Not receiving assignments"}</small>
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
            />
          )}

          {v1Dispatch.offer && !v1Dispatch.currentMission && !v1Dispatch.returnMission && (
            <V1DeliveryOffer
              offer={v1Dispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runV1OfferAction(v1Dispatch.offer!, "accept")}
              onDecline={() => void runV1OfferAction(v1Dispatch.offer!, "decline")}
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
              offer={dispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runDispatchAction(dispatch.offer!, "accept")}
              onDecline={() => void runDispatchAction(dispatch.offer!, "decline")}
            />
          )}

          {!v1Dispatch.offer && !v1Dispatch.currentMission && !v1Dispatch.returnMission && parcelDispatch.offer && (
            <ParcelOffer
              offer={parcelDispatch.offer}
              busy={Boolean(busy)}
              onAccept={() => void runParcelAction(parcelDispatch.offer!, "acknowledgeAssignment")}
              onDecline={() => void runParcelAction(parcelDispatch.offer!, "declineAssignment")}
            />
          )}

          {!v1Dispatch.offer && !v1Dispatch.currentMission && !v1Dispatch.returnMission && !v1Dispatch.completedMission && !dispatch.offer && !dispatch.currentJob && !parcelDispatch.offer && !parcelDispatch.currentJob && (
            <section className="delivery-empty">
              <Navigation size={25} />
              <div><h2>{online ? "Waiting for assignments" : "Offline"}</h2><p>{online ? "No ready orders nearby." : "Go online when available."}</p></div>
            </section>
          )}
        </>
      )}
      </>}
    </div>
  );
}

function V1DeliveryOffer({ offer, busy, onAccept, onDecline }: {
  offer: V1RiderOffer;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
}) {
  return (
    <section className="delivery-offer v1-delivery-card" aria-label="New Dastak order mission">
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
        <button className="danger-button" type="button" disabled={busy} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy} onClick={onAccept}><Check size={18} /> Accept mission</button>
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
  return <section className="current-delivery v1-delivery-card" aria-label="Active Dastak return mission">
    <header><span className="section-icon"><PackageCheck size={22} /></span><div><p className="eyebrow">Secure return mission</p><h2>{mission.status === "ASSIGNED" ? "Collect from customer" : mission.status === "AT_CUSTOMER" ? "Verify reverse pickup" : "Return to merchants"}</h2><small>{mission.packageCount} package(s) · no partial custody transfer</small></div></header>
    {mission.status !== "RETURNING_TO_MERCHANTS" ? <>
      <div className="delivery-stop"><span><MapPin size={19} /></span><div><small>Customer destination</small><strong>{mission.customerDestination.address}</strong>{mission.customerDestination.recipientName ? <p>Recipient: {mission.customerDestination.recipientName}</p> : null}</div></div>
      {mission.customerDestination.location ? <MapLink location={mission.customerDestination.location} label="Open return pickup route" /> : null}
      {mission.canArriveCustomer ? <button className="primary-button delivery-next-action" type="button" disabled={busy} onClick={() => onAction("v1ReturnArriveAtCustomer")}><MapPin size={18} /> I’ve arrived</button> : null}
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
        {stop.status === "PENDING" ? <button className="secondary-button" type="button" disabled={busy} onClick={() => onAction("v1ArriveAtReturnStop", { returnStopId: stop.id })}><MapPin size={17} /> I’ve arrived</button> : null}
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
}) {
  const completed = mission.pickupStops.filter((stop) => stop.status === "COMPLETED").length;
  const [deliveryCode, setDeliveryCode] = useState("");
  const [collectionMethod, setCollectionMethod] = useState<"CASH" | "UPI">("CASH");
  const [collectionReference, setCollectionReference] = useState("");
  const [collectionFailureReason, setCollectionFailureReason] = useState("");
  const collection = mission.launchCollection;
  const collectionSatisfied = !collection?.required || collection.state === "PAYMENT_COLLECTED";
  const finalStage = ["ALL_PACKAGES_PICKED_UP", "OUT_FOR_DELIVERY", "ARRIVED"].includes(
    mission.status,
  );
  useEffect(() => {
    setDeliveryCode("");
    setCollectionReference("");
    setCollectionFailureReason("");
  }, [mission.id, mission.status, collection?.state]);
  return (
    <section className="current-delivery v1-delivery-card" aria-label="Active Dastak order mission">
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
            <button className="primary-button delivery-next-action" type="button" disabled={busy} onClick={() => onAction("v1ArriveAtCustomer") }>
              <MapPin size={18} /> I’ve arrived
            </button>
          )}
          {collection && collection.state !== "NOT_REQUIRED" && (
            <section className={`v1-doorstep-collection ${collection.state === "COLLECTION_RETRY_NEEDED" ? "retry" : ""}`} aria-labelledby="doorstep-collection-title">
              <header><span><Banknote size={21} /></span><div><small>AUTHORITATIVE AMOUNT DUE</small><h3 id="doorstep-collection-title">{formatPrice(collection.amountPaise ?? 0)}</h3></div><b>{collection.state === "PAYMENT_COLLECTED" ? "COLLECTED" : "PAY AT DELIVERY"}</b></header>
              {collection.state === "PAYMENT_COLLECTED" ? <p className="delivery-notice" role="status"><Check size={18} /> Payment collected by {collection.lastMethod === "CASH" ? "cash" : "UPI"}. Delivery verification is unlocked.</p> : mission.status !== "ARRIVED" ? <p>Collection unlocks after you arrive at the customer. Never collect before complete package custody.</p> : <>
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
          {mission.canCaptureDeliveryEvidence && collectionSatisfied && !mission.finalVerification?.evidencePresent && (
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
          {mission.canVerifyDelivery && collectionSatisfied && (
            <div className="v1-pickup-verification">
              <label className="handoff-input">
                Customer delivery code
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
                onClick={() => onAction("v1VerifyDelivery", { verificationCode: deliveryCode })}
              >
                <PackageCheck size={18} /> Verify handoff
              </button>
            </div>
          )}
          {mission.status === "ARRIVED" && !collectionSatisfied && (
            <p className="delivery-notice" role="status"><CircleAlert size={18} /> Record the doorstep collection before taking the delivery photo or asking for the customer code.</p>
          )}
          {mission.finalVerification?.status === "BLOCKED" && (
            <p className="order-error" role="alert">Normal code attempts are blocked. Keep the packages secure and report the problem to Operations.</p>
          )}
        </div>
      )}

      {mission.canCancelBeforePickup && (
        <button className="danger-button v1-secondary-action" type="button" disabled={busy} onClick={() => onAction("v1CancelBeforePickup", { reason: "Rider cannot continue before pickup" })}>
          Release mission before pickup
        </button>
      )}
      {mission.mustUseDeliveryRecovery && (
        <div className="delivery-recovery-actions">
          <button className="danger-button v1-secondary-action" type="button" disabled={busy} onClick={() => onAction("v1ReportCustomerUnreachable", { reason: "Customer or recipient could not be reached at the delivery address" })}>
            Customer unreachable
          </button>
          <button className="danger-button v1-secondary-action" type="button" disabled={busy} onClick={() => onAction("v1ReportDeliveryProblem", { reason: "Rider reported a problem after custody began" })}>
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
        <MapLink location={stop.branch.location} label="Open pickup route" />
      )}
      {missionStarted && stop.status === "PENDING" && (
        <button className="secondary-button" type="button" disabled={busy} onClick={onArrive}>
          <MapPin size={17} /> I’ve arrived
        </button>
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

function ParcelOffer({ offer, busy, onAccept, onDecline }: {
  offer: ParcelAssignment;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
}) {
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
        <button className="danger-button" type="button" disabled={busy} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy} onClick={onAccept}><Check size={18} /> Accept</button>
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

function DeliveryOffer({ offer, busy, onAccept, onDecline }: {
  offer: DeliveryAssignment;
  busy: boolean;
  onAccept: () => void;
  onDecline: () => void;
}) {
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
        <button className="danger-button" type="button" disabled={busy} onClick={onDecline}><X size={17} /> Decline</button>
        <button className="primary-button" type="button" disabled={busy} onClick={onAccept}><Check size={18} /> Accept</button>
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
        <div><small>Drop-off</small><strong>{coordinateLabel(assignment.dropoff)}</strong></div>
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
    <a className="map-link" href={`https://maps.apple.com/?daddr=${location.latitude},${location.longitude}&dirflg=d`} target="_blank" rel="noreferrer">
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

function currentLocation() {
  if (!navigator.geolocation) return Promise.reject(new Error("Location is unavailable in this browser."));
  return new Promise<{ latitude: number; longitude: number }>((resolve, reject) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve({ latitude: position.coords.latitude, longitude: position.coords.longitude }),
      () => reject(new Error("Allow location access to go online.")),
      { enableHighAccuracy: true, timeout: 12_000, maximumAge: 30_000 },
    );
  });
}

function coordinateLabel(location: { latitude: number; longitude: number }) {
  return `${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}`;
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
function transportLabel(transport: string) {
  if (transport === "CAR") return "Tempo / goods vehicle";
  if (transport === "WALKING" || transport === "BICYCLE") return "Retired delivery method";
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
