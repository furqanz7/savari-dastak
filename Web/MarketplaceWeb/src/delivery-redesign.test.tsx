// @vitest-environment jsdom
import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ArrivalAction, AvailabilityStatusText, CurrentV1Mission, CurrentV1ReturnMission, DeliveryNotificationStatus, RecoveryConfirmation, V1DeliveryOffer, V1PickupStopCard } from "./DeliveryPartnerView";
import { DeliveryHealthBadges, DeliveryNavigation, DeliveryRouteContext, missionDestination, missionNextStep } from "./DeliveryUI";
import type { V1ArrivalEligibility, V1DeliveryMission, V1PickupStop, V1ReturnMission, V1RiderOffer } from "./delivery";
import type { PositionFix } from "./deliveryGeolocation";

const date = "2026-09-11T10:00:00Z";
const eligible: V1ArrivalEligibility = { eligible: true, reason: "ELIGIBLE", distanceMeters: 12, radiusMeters: 50, validUntil: "2026-09-11T10:00:10Z" };
const stop: V1PickupStop = { id: "stop-1", sequence: 1, status: "PENDING", ready: true, runningLate: false, estimatedReadyAt: date, actualReadyAt: date, packageCount: 2, arrivedAt: null, waitingSeconds: 0, arrival: eligible, branch: { id: "branch-1", displayName: "Craft", address: "Market Road, Vaniyambadi", location: { latitude: 12.68, longitude: 78.62 } } };
const base: V1DeliveryMission = {
  id: "mission-1", displayOrderNumber: "DSK-260911-00000001", status: "OUT_FOR_DELIVERY", version: 4,
  transportType: "MOTORBIKE", pickupCount: 1, assignedAt: date, firstPackagePickedUpAt: date, allPackagesPickedUpAt: date,
  canCancelBeforePickup: false, mustUseDeliveryRecovery: true,
  orderLoad: { totalWeightGrams: 500, totalVolumeCubicMillimetres: 1000, longestSideMillimetres: 100, containsBulky: false, eligibleTransportTypes: ["MOTORBIKE"] },
  pickupStops: [{ ...stop, status: "COMPLETED" }], customerDestination: { address: "128 Market Street, Vaniyambadi", recipientName: "Customer", recipientPhoneNumber: null, location: { latitude: 12.69, longitude: 78.63 } },
  outForDeliveryAt: date, arrivedCustomerAt: null, deliveredAt: null,
  finalVerification: { status: "ACTIVE", failedAttempts: 0, activatedAt: date, blockedAt: null, evidenceRequired: true, evidencePresent: false, pinVerified: false }, deliveryEvidence: [],
  launchCollection: { required: true, state: "PAYMENT_DUE_AT_DELIVERY", amountPaise: 58500, methods: ["CASH", "UPI"], canRecord: false },
  canStartFinalDelivery: false, canArriveCustomer: true, canCaptureDeliveryEvidence: false, canVerifyDelivery: false, canVerifyCustomerPIN: false, canCompleteDelivery: false, customerArrival: eligible,
  riderSafety: { lastContactAt: date, lastProgressAt: date, stallDetectedAt: null, unresponsiveDetectedAt: null, escalationState: "NONE", escalatedAt: null, escalationReason: null },
};
const returning: V1ReturnMission = {
  id: "return-mission", returnId: "return-1", orderId: "order-1", version: 1, status: "ASSIGNED", transportType: "MOTORBIKE", assignedAt: date, arrivedCustomerAt: null, pickupCompletedAt: null, completedAt: null,
  customerDestination: base.customerDestination!, packageCount: 2, pickupVerification: { status: "INACTIVE", failedAttempts: 0 }, evidence: [],
  stops: [{ id: "return-stop", sequence: 1, status: "PENDING", packageCount: 2, arrivedAt: null, completedAt: null, verificationStatus: "INACTIVE", failedAttempts: 0, arrival: eligible, canArrive: false, branch: { ...stop.branch, id: "branch-1" } }],
  customerArrival: eligible, canArriveCustomer: false, canCaptureEvidence: false, canVerifyPickup: false, canCompleteReturnStops: false,
};

describe("Delivery rider workspace interactions", () => {
  let host: HTMLDivElement;
  let root: Root;
  beforeEach(() => {
    vi.useFakeTimers(); vi.setSystemTime(new Date(date));
    (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    host = document.createElement("div"); document.body.append(host); root = createRoot(host);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); vi.useRealTimers(); vi.restoreAllMocks(); });
  const render = async (node: ReactNode) => { await act(async () => root.render(node)); };
  const button = (name: string) => {
    const result = [...host.querySelectorAll("button")].find((item) => item.textContent?.trim() === name);
    expect(result, `button ${name}`).toBeDefined(); return result!;
  };
  const click = async (target: HTMLElement) => { await act(async () => target.click()); };
  const input = async (target: HTMLInputElement, value: string) => {
    await act(async () => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(target, value);
      target.dispatchEvent(new Event("input", { bubbles: true }));
    });
  };
  const actions = () => ({ onAction: vi.fn(), onCaptureEvidence: vi.fn(), onCollection: vi.fn(), onRequestRecovery: vi.fn() });

  it("uses accessible rider navigation and Earnings terminology", async () => {
    const onChange = vi.fn();
    await render(<DeliveryNavigation section="history" onChange={onChange} />);
    expect(button("History").getAttribute("aria-current")).toBe("page");
    expect(host.querySelector('[role="tab"]')).toBeNull();
    await click(button("Earnings")); expect(onChange).toHaveBeenCalledWith("royalty");
    expect(host.textContent).not.toContain("Royalty");
  });

  it("gives each normal mission phase its next action without deriving arrival from broad order status", async () => {
    await render(<CurrentV1Mission mission={{ ...base, status: "ARRIVED", arrivedCustomerAt: date, canVerifyCustomerPIN: true }} busy={false} {...actions()} />);
    expect(host.querySelector('[aria-label="Next required action"]')?.textContent).toContain("You’ve arrived · verify the PIN");
    expect(host.querySelector('.rider-progress [aria-current="step"]')?.textContent).toContain("Handoff");
    expect(host.querySelector('.rider-handoff-progress [aria-current="step"]')?.textContent).toContain("PIN");
    expect(host.querySelector('input[type="file"]')).toBeNull();
    expect(host.textContent).not.toContain("Record collected");
    expect(host.textContent).not.toContain("Complete delivery");
  });

  it("keeps arrival locked by the server flag even when the distance projection is eligible", async () => {
    const onArrive = vi.fn();
    await render(<ArrivalAction arrival={eligible} permitted={false} busy={false} onArrive={onArrive} />);
    expect(button("I’ve arrived").disabled).toBe(true); await click(button("I’ve arrived")); expect(onArrive).not.toHaveBeenCalled();
    await render(<ArrivalAction arrival={{ ...eligible, eligible: false, reason: "TOO_FAR", distanceMeters: 82 }} busy={false} onArrive={onArrive} />);
    expect(host.textContent).toContain("82 m away"); expect(button("I’ve arrived").disabled).toBe(true);
  });

  it("expires arrival eligibility locally without refreshing the workspace", async () => {
    const onArrive = vi.fn();
    await render(<ArrivalAction arrival={eligible} busy={false} onArrive={onArrive} />);
    expect(button("I’ve arrived").disabled).toBe(false);
    await click(button("I’ve arrived")); expect(onArrive).toHaveBeenCalledTimes(1);
    await act(async () => vi.advanceTimersByTime(10_000));
    expect(button("I’ve arrived").disabled).toBe(true);
  });

  it("verifies the full six-digit customer PIN without exposing later handoff actions", async () => {
    const handlers = actions();
    await render(<CurrentV1Mission mission={{ ...base, status: "ARRIVED", canVerifyCustomerPIN: true }} busy={false} {...handlers} />);
    expect(button("Verify customer PIN").disabled).toBe(true);
    await input(host.querySelector('input[inputmode="numeric"]')!, "12a3456");
    await click(button("Verify customer PIN"));
    expect(handlers.onAction).toHaveBeenCalledWith("v1VerifyCustomerPIN", { verificationCode: "123456" });
    expect(host.querySelector('input[type="file"]')).toBeNull();
  });

  it("shows the photo stage only when the authoritative capability opens it", async () => {
    await render(<CurrentV1Mission mission={{ ...base, status: "ARRIVED", canCaptureDeliveryEvidence: true, finalVerification: { ...base.finalVerification!, pinVerified: true } }} busy {...actions()} />);
    expect(host.querySelector('[aria-label="Next required action"]')?.textContent).toContain("Take the package photo");
    expect(host.querySelector<HTMLInputElement>('input[type="file"]')?.disabled).toBe(true);
    expect(host.textContent).not.toContain("Record collected");
  });

  it("requires explicit confirmation of actual payment, keeps cancellation harmless and restores keyboard focus", async () => {
    const handlers = actions();
    await render(<CurrentV1Mission mission={{ ...base, status: "ARRIVED", arrivedCustomerAt: date, finalVerification: { ...base.finalVerification!, pinVerified: true, evidencePresent: true }, launchCollection: { ...base.launchCollection!, canRecord: true } }} busy={false} {...handlers} />);
    await click(button("UPI"));
    button("Record collected").focus(); await click(button("Record collected"));
    expect(handlers.onCollection).not.toHaveBeenCalled();
    expect(host.querySelector('[role="dialog"]')?.textContent).toContain("₹585 by UPI");
    expect(document.activeElement?.textContent).toBe("Not yet");
    await click(button("Not yet")); expect(handlers.onCollection).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(button("Record collected"));
    await click(button("Record collected")); await click(button("Payment received"));
    expect(handlers.onCollection).toHaveBeenCalledExactlyOnceWith({ outcome: "COLLECTED", method: "UPI", collectionReference: undefined });
    expect(host.textContent).not.toContain("Complete delivery");
  });

  it("only exposes completion after the server opens it", async () => {
    const handlers = actions();
    await render(<CurrentV1Mission mission={{ ...base, status: "ARRIVED", canCompleteDelivery: true, finalVerification: { ...base.finalVerification!, pinVerified: true, evidencePresent: true }, launchCollection: { ...base.launchCollection!, state: "PAYMENT_COLLECTED", lastMethod: "CASH" } }} busy={false} {...handlers} />);
    await click(button("Complete delivery")); expect(handlers.onAction).toHaveBeenCalledWith("v1CompleteDelivery");
    expect(host.textContent).not.toContain("Record collected");
  });

  it("requires every package and the merchant code at pickup", async () => {
    const onVerify = vi.fn();
    await render(<V1PickupStopCard stop={{ ...stop, status: "ARRIVED" }} missionStarted busy={false} onArrive={vi.fn()} onVerify={onVerify} />);
    expect(host.textContent).toContain("You’ve arrived at this pickup");
    await input(host.querySelector('input[inputmode="numeric"]')!, "123456");
    const boxes = host.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
    await click(boxes[0]); expect(button("Verify complete pickup").disabled).toBe(true);
    await click(boxes[1]); await click(button("Verify complete pickup"));
    expect(onVerify).toHaveBeenCalledWith(2, "123456");
  });

  it("keeps return arrival and blocked merchant receipts protected", async () => {
    const onAction = vi.fn();
    await render(<CurrentV1ReturnMission mission={returning} busy={false} onAction={onAction} onCaptureEvidence={vi.fn()} />);
    expect(button("I’ve arrived").disabled).toBe(true);
    await render(<CurrentV1ReturnMission mission={{ ...returning, status: "RETURNING_TO_MERCHANTS" }} busy={false} onAction={onAction} onCaptureEvidence={vi.fn()} />);
    expect(button("I’ve arrived").disabled).toBe(true);
    expect(host.querySelector('a')?.textContent).toContain("Open merchant route");
    await render(<CurrentV1ReturnMission mission={{ ...returning, status: "RETURNING_TO_MERCHANTS", stops: [{ ...returning.stops[0], status: "ARRIVED", verificationStatus: "BLOCKED" }] }} busy={false} onAction={onAction} onCaptureEvidence={vi.fn()} />);
    await input(host.querySelector('input[inputmode="numeric"]')!, "123456");
    expect(button("Verify merchant receipt").disabled).toBe(true); expect(onAction).not.toHaveBeenCalled();
  });

  it("shows urgency and disables both offer actions at expiry with one reconciliation", async () => {
    const onExpire = vi.fn(); const onAccept = vi.fn();
    const offer: V1RiderOffer = { id: "offer-1", missionId: base.id, displayOrderNumber: base.displayOrderNumber, status: "OFFERED", poolRound: 1, transportType: "MOTORBIKE", distanceMeters: 120, offeredAt: date, respondBy: eligible.validUntil!, secondsRemaining: 10, pickupCount: 1, orderLoad: base.orderLoad, pickupStops: [stop] };
    await render(<V1DeliveryOffer offer={offer} busy={false} onAccept={onAccept} onDecline={vi.fn()} onExpire={onExpire} />);
    expect(host.querySelector('.offer-timer')?.classList.contains("urgent")).toBe(true);
    await act(async () => vi.advanceTimersByTime(11_000));
    expect(button("Offer expired").disabled).toBe(true); expect(button("Decline").disabled).toBe(true);
    await click(button("Offer expired")); expect(onAccept).not.toHaveBeenCalled();
    await act(async () => vi.advanceTimersByTime(20_000)); expect(onExpire).toHaveBeenCalledTimes(1);
  });

  it("confirms recovery with bounded reasons and prevents keyboard escape/submission while busy", async () => {
    const onConfirm = vi.fn().mockResolvedValue(undefined); const onDismiss = vi.fn();
    const intent = { mission: base, operation: "v1ReportDeliveryProblem" as const };
    await render(<RecoveryConfirmation intent={intent} busy={false} onConfirm={onConfirm} onDismiss={onDismiss} />);
    expect(host.textContent).toContain("does not transfer or release custody");
    const radios = host.querySelectorAll<HTMLInputElement>('input[type="radio"]');
    await click(radios[2]); await click(button("Confirm and notify Operations"));
    expect(onConfirm).toHaveBeenCalledWith("Safety concern");
    await render(<RecoveryConfirmation intent={intent} busy error="Reconnecting. Keep packages secure." onConfirm={onConfirm} onDismiss={onDismiss} />);
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    await act(async () => host.querySelector('form')!.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })));
    expect(onDismiss).not.toHaveBeenCalled(); expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(host.querySelector('[role="dialog"]')?.textContent).toContain("Reconnecting. Keep packages secure.");
  });

  it("clearly distinguishes GPS age, update-channel health and browser suspension", async () => {
    const fix: PositionFix = { latitude: 12.69, longitude: 78.63, accuracyMeters: 12, timestamp: Date.now(), recordedAt: date };
    const peekLocation = () => fix;
    await render(<DeliveryHealthBadges gps="tracking" realtime="subscribed" peekLocation={peekLocation} />);
    expect(host.textContent).toContain("GPS live · foreground"); expect(host.textContent).toContain("Updates connected");
    await act(async () => vi.advanceTimersByTime(30_000)); expect(host.textContent).toContain("GPS stale");
    await render(<DeliveryHealthBadges gps="background_limited" realtime="degraded" peekLocation={peekLocation} />);
    expect(host.textContent).toContain("Tracking suspended"); expect(host.textContent).toContain("Updates reconnecting");
  });

  it("reads map position from the mission controller without owning GPS or hiding stale state", async () => {
    const fix: PositionFix = { latitude: 12.69, longitude: 78.63, accuracyMeters: 12, timestamp: Date.now(), recordedAt: date };
    await render(<DeliveryRouteContext destination={missionDestination(base, null)} gps="tracking" peekLocation={() => fix} />);
    expect(host.textContent).toContain("128 Market Street");
    expect(host.querySelector('a')?.href).toContain("https://www.google.com/maps/dir/");
    const initialSource = host.querySelector('iframe')?.src;
    await act(async () => vi.advanceTimersByTime(5_000)); expect(host.querySelector('iframe')?.src).toBe(initialSource);
    await click(button("My position")); expect(host.textContent).toContain("Live GPS · foreground tracking");
    await act(async () => vi.advanceTimersByTime(25_000)); expect(host.textContent).toContain("Last-known GPS · not live");
    expect(host.querySelector('iframe')?.title).toBe("Map: Your last GPS position");
  });

  it("offers explicit availability renewal near expiry without automatically extending it", async () => {
    const onRenew = vi.fn();
    await render(<AvailabilityStatusText online availability={{ status: "online", availableUntil: "2026-09-11T10:02:00Z", location: null, serviceZoneId: null, stateVersion: 2 }} onRenew={onRenew} />);
    expect(host.textContent).toContain("Expiring soon"); expect(onRenew).not.toHaveBeenCalled();
    await click(button("Renew availability")); expect(onRenew).toHaveBeenCalledTimes(1);
  });

  it("lets a rider opt into alerts from Account after dismissing onboarding", async () => {
    const enable = vi.fn().mockResolvedValue(undefined);
    await render(<DeliveryNotificationStatus inAccount controller={{ status: "dismissed", shouldPrompt: false, enable, dismiss: vi.fn(), refresh: vi.fn() }} />);
    await click(button("Enable alerts")); expect(enable).toHaveBeenCalledOnce();
  });

  it("selects only the applicable normal/return destination and keeps recovery custody prominent", () => {
    expect(missionDestination({ ...base, status: "EN_ROUTE_TO_PICKUPS", pickupStops: [stop], customerDestination: null }, null)?.name).toBe("Craft");
    expect(missionDestination(base, null)?.label).toBe("Customer destination");
    expect(missionDestination(null, returning)?.label).toBe("Return pickup");
    expect(missionDestination(null, { ...returning, status: "RETURNING_TO_MERCHANTS" })?.name).toBe("Craft");
    expect(missionNextStep({ ...base, status: "DELIVERY_RECOVERY" }).title).toBe("Keep every package secure");
  });
});
