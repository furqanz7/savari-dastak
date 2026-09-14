// @vitest-environment jsdom
import { act, useState, type ComponentProps, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MerchantDeclineDialog, MerchantPrepChoices, MerchantRestaurantRequestCard } from "./MerchantRequestControls";
import { FulfilmentCard, MerchantDeadline, MerchantOpportunityCard } from "./MerchantV1Opportunities";
import { MerchantV1CommerceControl } from "./MerchantV1CommerceControl";
import { getV1MerchantRestaurantMenu, uploadV1GovernedMedia, upsertV1RestaurantMenuEntity, type V1MerchantFulfilment, type V1MerchantOpportunity, type V1RestaurantMenu, type V1RestaurantRequest } from "./dastakV1";
import { validateDecodableImage } from "./imageValidation";

vi.mock("./dastakV1", async (original) => ({
  ...await original<typeof import("./dastakV1")>(),
  getV1MerchantRestaurantMenu: vi.fn(),
  uploadV1GovernedMedia: vi.fn(),
  upsertV1RestaurantMenuEntity: vi.fn(),
}));
vi.mock("./imageValidation", () => ({ validateDecodableImage: vi.fn().mockResolvedValue(true) }));

let root: Root;
let host: HTMLDivElement;
beforeEach(() => {
  (globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  vi.mocked(validateDecodableImage).mockResolvedValue(true);
});
afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.clearAllMocks();
});
async function render(node: ReactNode) { await act(async () => root.render(node)); }
async function click(element: HTMLElement) { await act(async () => element.click()); }
function button(label: string, parent: ParentNode = host) {
  const result = [...parent.querySelectorAll<HTMLButtonElement>("button")].find((item) => item.textContent?.trim() === label);
  if (!result) throw new Error(`Missing button: ${label}`);
  return result;
}
async function enter(element: HTMLInputElement | HTMLTextAreaElement, value: string) {
  await act(async () => {
    const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(prototype, "value")!.set!.call(element, value);
    element.dispatchEvent(new Event("input", { bubbles: true }));
  });
}

const request: V1RestaurantRequest = {
  id: "food-request", orderId: "order", displayOrderNumber: "DSK-0001", status: "OFFERED", version: 3,
  offeredAt: "2026-09-10T00:00:00Z", softActiveOrderThreshold: 5, activeOrderCount: 6,
  softThresholdWarning: true, softThresholdIsBlocking: false,
  branch: { id: "branch", displayName: "Market Street Kitchen", isOpen: true, acceptingOrders: true, operationalVersion: 2 },
  lines: [{ orderLineId: "line", menuItemId: "dish", name: "Breakfast plate", quantity: 2, unitPricePaise: 12000, selection: { groups: [{ options: [{ name: "No chilli" }] }] } }],
};

describe("Merchant request interactions", () => {
  it("uses labelled native preparation radios and retains an existing custom promise", async () => {
    function Choices() {
      const [minutes, setMinutes] = useState(25);
      return <MerchantPrepChoices value={minutes} options={[10, 15, 30, 0, 999]} onChange={setMinutes} />;
    }
    await render(<Choices />);
    expect([...host.querySelectorAll<HTMLInputElement>("input")].map((input) => input.value)).toEqual(["10", "15", "25", "30"]);
    expect(host.querySelector("legend")?.textContent).toContain("Preparation time");
    await click(host.querySelector<HTMLInputElement>('input[value="30"]')!);
    expect(host.querySelector<HTMLInputElement>('input[value="30"]')!.checked).toBe(true);
    expect(host.querySelector<HTMLInputElement>('input[value="25"]')).toBeNull();
  });

  it("keeps exact-selection confirmation and bounded preparation promises before acceptance", async () => {
    const respond = vi.fn().mockResolvedValue(true);
    const prep = vi.fn();
    await render(<MerchantRestaurantRequestCard request={request} busy={false} prepMinutes={15} onPrepMinutes={prep} onRespond={respond} />);
    expect(host.textContent).toContain("No chilli");
    expect(host.textContent).toContain("₹240.00");
    expect(button("Accept order").disabled).toBe(true);
    expect([...host.querySelectorAll<HTMLInputElement>('input[type="radio"]')].map((item) => Number(item.value))).toEqual([10, 15, 20, 30, 45, 60, 90, 120, 180, 240]);
    await click(host.querySelector<HTMLInputElement>('input[value="45"]')!);
    expect(prep).toHaveBeenCalledWith(45);
    await click(host.querySelector<HTMLInputElement>('input[type="checkbox"]')!);
    expect(button("Accept order").disabled).toBe(false); // Kitchen threshold is a warning, not a new business gate.
    await click(button("Accept order"));
    expect(respond).toHaveBeenCalledExactlyOnceWith("CONFIRM");
    expect(host.textContent).toContain("Payment is collected by the rider at delivery");
  });

  it("requires an explicit reason, retains it after failure, and closes after success", async () => {
    const respond = vi.fn().mockResolvedValueOnce(false).mockResolvedValueOnce(true);
    await render(<MerchantRestaurantRequestCard request={request} busy={false} prepMinutes={15} onPrepMinutes={() => undefined} onRespond={respond} />);
    button("Decline").focus();
    await click(button("Decline"));
    const input = host.querySelector("textarea")!;
    expect(document.activeElement).toBe(input);
    expect(document.body.style.overflow).toBe("hidden");
    expect(button("Decline request").disabled).toBe(true);
    await enter(input, "  Missing ingredient  ");
    await click(button("Decline request"));
    expect(respond).toHaveBeenLastCalledWith("DECLINE", "Missing ingredient");
    expect(host.querySelector('[role="dialog"]')).not.toBeNull();
    expect(input.value).toBe("  Missing ingredient  ");
    expect(host.querySelector('[role="alert"]')?.textContent).toContain("Your reason is kept");
    await click(button("Decline request"));
    expect(host.querySelector('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(button("Decline"));
    expect(document.body.style.overflow).toBe("");
  });

  it("traps keyboard focus and cancels without responding", async () => {
    const respond = vi.fn();
    await render(<MerchantRestaurantRequestCard request={request} busy={false} prepMinutes={15} onPrepMinutes={() => undefined} onRespond={respond} />);
    button("Decline").focus();
    await click(button("Decline"));
    await enter(host.querySelector("textarea")!, "Kitchen is closed");
    button("Decline request").focus();
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true })));
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Close decline dialog");
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    expect(host.querySelector('[role="dialog"]')).toBeNull();
    expect(respond).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(button("Decline"));
  });

  it("does not dismiss or submit a decline while its mutation is pending", async () => {
    const dismiss = vi.fn();
    const confirm = vi.fn();
    await render(<MerchantDeclineDialog orderNumber="DSK-0001" reason="Unavailable" busy onReason={() => undefined} onDismiss={dismiss} onConfirm={confirm} />);
    await act(async () => document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true })));
    await click(button("Keep request"));
    await click(button("Declining…"));
    expect(dismiss).not.toHaveBeenCalled();
    expect(confirm).not.toHaveBeenCalled();
  });
});

const fulfilment: V1MerchantFulfilment = {
  id: "fulfilment", orderId: "order", displayOrderNumber: "DSK-0002", orderStatus: "PREPARING", status: "PREPARING", version: 4,
  branch: { id: "branch", displayName: "Market Street" }, promisedPrepMinutes: 15, secondsRemaining: 500, runningLate: false, lateSeconds: 0,
  packages: [], evidence: [], problemReports: [], lines: [],
  riderMatchEligibility: { eligible: false, evaluatedAt: "2026-09-10T00:00:00Z", thresholdSeconds: 300, requiredFulfilmentCount: 1, satisfiedFulfilmentCount: 0 },
  canDeclarePackages: false, canAddEvidence: false, canMarkReady: false, readyIsIrreversible: true,
};
function cardProps(overrides: Partial<ComponentProps<typeof FulfilmentCard>> = {}): ComponentProps<typeof FulfilmentCard> {
  return { fulfilment, trackingDelayed: false, busy: false, packageCount: 1, irreversibleConfirmed: false, reportingProblem: false, problemReason: "",
    onPackageCount: vi.fn(), onEvidenceFile: vi.fn(), onIrreversibleConfirm: vi.fn(), onDeclarePackages: vi.fn(), onAddPhoto: vi.fn(), onMarkReady: vi.fn(), onStartProblem: vi.fn(), onCancelProblem: vi.fn(), onProblemReason: vi.fn(), onRecoveryLine: vi.fn(), onReportProblem: vi.fn(), ...overrides };
}

describe("Merchant preparation presentation", () => {
  it("keeps long product names and pack details in the flexible item-description column", async () => {
    const longLine = {
      orderLineId: "long-line",
      name: "4700 BC x Netflix Gourmet Cheese and Caramel Popcorn Small Tin",
      quantity: 12,
      variant: "Movie Night Collector Edition with an unusually descriptive flavour",
      packSize: "75 g x 6",
    };
    await render(<FulfilmentCard {...cardProps({ fulfilment: { ...fulfilment, lines: [longLine] } })} />);
    const line = host.querySelector(".merchant-order-lines li")!;
    expect(line.querySelector(":scope > .merchant-line-quantity")?.textContent).toBe("12×");
    expect(line.querySelector(":scope > span > strong")?.textContent).toBe(longLine.name);
    expect(line.querySelector(":scope > span > small")?.textContent).toBe(`${longLine.variant} · ${longLine.packSize}`);
  });

  it("does not turn disabled server capabilities into available actions", async () => {
    await render(<FulfilmentCard {...cardProps()} />);
    expect(host.querySelector<HTMLInputElement>('input[type="number"]')!.disabled).toBe(true);
    expect(host.querySelector<HTMLInputElement>('input[type="file"]')!.disabled).toBe(true);
    expect(button("Mark Ready").disabled).toBe(true);
    expect(host.textContent).not.toContain("Declare package count");
    expect(host.querySelectorAll(".merchant-preparation-step")).toHaveLength(3);
  });

  it("keeps irreversible Ready confirmation separate from server permission", async () => {
    const ready = vi.fn();
    const capable = { ...fulfilment, canDeclarePackages: true, canAddEvidence: true, canMarkReady: true };
    await render(<FulfilmentCard {...cardProps({ fulfilment: capable, onMarkReady: ready })} />);
    expect(button("Declare package count").disabled).toBe(false);
    expect(host.querySelector<HTMLInputElement>('input[type="file"]')!.disabled).toBe(false);
    expect(button("Mark Ready").disabled).toBe(true);
    await render(<FulfilmentCard {...cardProps({ fulfilment: capable, irreversibleConfirmed: true, onMarkReady: ready })} />);
    await click(button("Mark Ready"));
    expect(ready).toHaveBeenCalledTimes(1);
    await render(<FulfilmentCard {...cardProps({ fulfilment: { ...capable, canMarkReady: false }, irreversibleConfirmed: true })} />);
    expect(button("Mark Ready").disabled).toBe(true);
  });

  it("shows completed lifecycle status without active preparation controls in History", async () => {
    await render(<FulfilmentCard {...cardProps({ fulfilment: { ...fulfilment, orderStatus: "DELIVERED", status: "PICKED_UP" } })} />);
    expect(host.textContent).toContain("delivered");
    expect(host.textContent).toContain("This order is in History");
    expect(host.querySelector(".v1-ready-workflow")).toBeNull();
    expect(host.querySelector(".v1-report-problem")).toBeNull();
  });

  it("updates only the deadline component each second and removes actions at expiry", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-10T00:00:00Z"));
    const rendered = vi.fn();
    function Parent() { rendered(); return <MerchantDeadline deadline="2026-09-10T00:00:02Z" />; }
    await render(<Parent />);
    await act(async () => vi.advanceTimersByTime(1000));
    expect(rendered).toHaveBeenCalledTimes(1);
    expect(host.textContent).toContain("0:01 to respond");
    const opportunity = { id: "offer", displayOrderNumber: "DSK-0003", status: "OFFERED", expiresAt: "2026-09-10T00:00:02Z", branch: fulfilment.branch, lines: [], prepTimeOptionsMinutes: [10, 15], reservationState: "NONE" } as unknown as V1MerchantOpportunity;
    await render(<MerchantOpportunityCard opportunity={opportunity} busy={false} confirmed prepMinutes={10} onConfirmed={() => undefined} onPrepMinutes={() => undefined} onUnavailable={() => undefined} onAccept={() => undefined} />);
    expect(button("Accept and hold items").disabled).toBe(false);
    await act(async () => vi.advanceTimersByTime(1100));
    expect(host.textContent).toContain("Expired");
    expect(host.textContent).not.toContain("Accept and hold items");
  });
});

const menu: V1RestaurantMenu = {
  restaurant: { organizationId: "org", branchId: "branch", name: "Market Kitchen", branchName: "Market Street", acceptingOrders: true, isOpen: true, branchStatus: "ACTIVE", merchantType: "RESTAURANT_CAFE", operationalVersion: 2, softActiveOrderThreshold: 5, activeOrderCount: 1 },
  categories: [{ id: "category", name: "Breakfast", sortOrder: 0, status: "ACTIVE", version: 1, items: [{ id: "dish", name: "Dosa", description: "Freshly made", basePricePaise: 5000, currencyCode: "INR", taxRateBps: 0, logisticsAttributes: {}, status: "ACTIVE", version: 1, optionGroups: [] }] }],
};
const auth = { supabaseUrl: "https://example.supabase.co", publishableKey: "public", accessToken: "test-token" };
const branch = { id: "branch", branchName: "Market Street", organizationName: "Market Kitchen", merchantType: "RESTAURANT_CAFE" };

describe("Merchant menu redesign preserves drafts and writes", () => {
  it("offers governed banner and optional dish photo uploads with clearer customer choices", async () => {
    const mediaMenu = structuredClone(menu);
    mediaMenu.restaurant.mediaVersion = 2;
    mediaMenu.categories[0].items[0].mediaVersion = 3;
    vi.mocked(getV1MerchantRestaurantMenu).mockResolvedValue(mediaMenu);
    vi.mocked(uploadV1GovernedMedia).mockResolvedValue({ mediaVersion: 3 });
    await render(<MerchantV1CommerceControl auth={auth} branch={branch} onSessionExpired={() => undefined} />);
    expect(host.textContent).toContain("Restaurant banner");
    expect(host.textContent).toContain("Dish photo");
    expect(host.textContent).toContain("Customer choices & extras");
    expect(host.textContent).toContain("Sizes, flavours, preparation choices or paid extras");
    const inputs = host.querySelectorAll<HTMLInputElement>('input[type="file"]');
    const file = new File(["image"], "cafe.jpg", { type: "image/jpeg", lastModified: 5 });
    Object.defineProperty(inputs[0], "files", { configurable: true, value: [file] });
    await act(async () => {
      inputs[0].dispatchEvent(new Event("change", { bubbles: true }));
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(vi.mocked(uploadV1GovernedMedia)).toHaveBeenCalledWith(expect.objectContaining({
      entityType: "RESTAURANT_BRANCH_BANNER", entityId: "branch", expectedMediaVersion: 2,
      file, sourceReference: "Merchant-owned image: cafe.jpg", reason: "Update restaurant banner",
    }));
  });

  it("preserves a dirty dish while searching and requires explicit reconciliation with newer server data", async () => {
    vi.mocked(getV1MerchantRestaurantMenu).mockResolvedValue(menu);
    await render(<MerchantV1CommerceControl auth={auth} branch={branch} onSessionExpired={() => undefined} />);
    const name = host.querySelector<HTMLInputElement>('[aria-label="Menu item name"]')!;
    await enter(name, "My draft dosa");
    const search = host.querySelector<HTMLInputElement>('[aria-label="Search your menu"]')!;
    await enter(search, "not-found");
    expect(host.textContent).toContain("No matching dishes");
    expect(name.closest("[hidden]")).not.toBeNull();
    await enter(search, "");
    expect(host.querySelector<HTMLInputElement>('[aria-label="Menu item name"]')!.value).toBe("My draft dosa");
    expect(name.closest("[hidden]")).toBeNull();
    const newer = structuredClone(menu);
    newer.categories[0].items[0] = { ...newer.categories[0].items[0], version: 2, name: "Server dosa" };
    vi.mocked(getV1MerchantRestaurantMenu).mockResolvedValue(newer);
    await act(async () => window.dispatchEvent(new Event("focus")));
    expect(name.value).toBe("My draft dosa");
    expect(name.disabled).toBe(true);
    expect(button("Save changes").disabled).toBe(true);
    await click(button("Use latest"));
    expect(name.value).toBe("Server dosa");
    expect(name.disabled).toBe(false);
    expect(button("Save changes").disabled).toBe(true);
    await enter(name, "Updated dosa");
    vi.mocked(upsertV1RestaurantMenuEntity).mockResolvedValue({ entityId: "dish", entityType: "ITEM", menu: newer });
    await click(button("Save changes"));
    expect(vi.mocked(upsertV1RestaurantMenuEntity).mock.calls[0][0]).toMatchObject({ entityType: "ITEM", entityId: "dish", expectedVersion: 2, payload: { name: "Updated dosa" } });
  });

  it("refreshes pristine menu fields without a stale warning", async () => {
    vi.mocked(getV1MerchantRestaurantMenu).mockResolvedValue(menu);
    await render(<MerchantV1CommerceControl auth={auth} branch={branch} onSessionExpired={() => undefined} />);
    const newer = structuredClone(menu);
    newer.categories[0].items[0] = { ...newer.categories[0].items[0], version: 2, name: "New server name" };
    vi.mocked(getV1MerchantRestaurantMenu).mockResolvedValue(newer);
    await act(async () => window.dispatchEvent(new Event("focus")));
    expect(host.querySelector<HTMLInputElement>('[aria-label="Menu item name"]')!.value).toBe("New server name");
    expect(host.querySelector(".merchant-v1-draft-warning")).toBeNull();
    expect(host.querySelector("details summary")?.textContent).toBe("Add to your menu");
  });

  it("hides a category as inactive and immediately renders the authoritative menu response", async () => {
    vi.mocked(getV1MerchantRestaurantMenu).mockResolvedValue(menu);
    const hidden = structuredClone(menu);
    hidden.categories[0] = { ...hidden.categories[0], status: "INACTIVE", version: 2 };
    vi.mocked(upsertV1RestaurantMenuEntity).mockResolvedValue({
      entityId: "category",
      entityType: "CATEGORY",
      menu: hidden,
    });

    await render(<MerchantV1CommerceControl auth={auth} branch={branch} onSessionExpired={() => undefined} />);
    await click(button("Hide"));

    expect(vi.mocked(upsertV1RestaurantMenuEntity)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(upsertV1RestaurantMenuEntity).mock.calls[0][0]).toMatchObject({
      branchId: "branch",
      entityType: "CATEGORY",
      entityId: "category",
      expectedVersion: 1,
      payload: {
        name: "Breakfast",
        description: "",
        sortOrder: 0,
        status: "INACTIVE",
      },
    });
    expect(host.textContent).toContain("1 items · inactive");
    expect(button("Activate")).toBeTruthy();
    expect(host.textContent).not.toContain("Menu update needs attention");
  });
});
