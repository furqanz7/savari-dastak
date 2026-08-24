import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
  MatchingSheet,
  OrdersSection,
} from "./DastakV1CustomerExperience";
import {
  canReorderV1Order,
  customerPhoneNumber,
  deliveryAddressLine,
  deliveredDurationLabel,
  isIssueEvidenceRequired,
  isV1OrderActive,
  orderJourneyLabel,
  orderJourneyStep,
  orderLineDetail,
  orderSearchText,
  statusAssurance,
  statusMessage,
  statusTitle,
} from "./v1OrderPresentation";
import type { V1Order } from "./dastakV1";

describe("customer V1 Orders experience", () => {
  it("uses accurate customer lifecycle language and active classification", () => {
    expect(statusTitle("PAYMENT_EXPIRED")).toBe("Payment window expired");
    expect(statusMessage("DASTAK_FULFILMENT_FAILURE")).toContain("recovery");
    expect(statusAssurance("DASTAK_FULFILMENT_FAILURE")).not.toContain("No completed payment");
    expect(isV1OrderActive("OUT_FOR_DELIVERY")).toBe(true);
    expect(isV1OrderActive("DASTAK_FULFILMENT_FAILURE")).toBe(false);
    expect(orderJourneyStep("OUT_FOR_DELIVERY")).toBe(4);
    expect(orderJourneyLabel("OUT_FOR_DELIVERY")).toBe("On the way");
    expect(orderJourneyStep("PAYMENT_EXPIRED")).toBeUndefined();
  });

  it("renders mixed-order identity in history without retail-only copy", () => {
    const markup = renderToStaticMarkup(<OrdersSection
      orders={[orderFixture()]}
      loading={false}
      loadingMore={false}
      canLoadMore
      imageUrlForLine={() => null}
      onRefresh={() => undefined}
      onLoadMore={() => undefined}
      onOpen={() => undefined}
      onReorder={() => undefined}
    />);

    expect(markup).toContain("Dastak Cafe");
    expect(markup).toContain("Preparing your order");
    expect(markup).toContain("Preparing");
    expect(markup).toContain("Active");
    expect(markup).toContain("Past");
    expect(markup).not.toContain("Ongoing");
    expect(markup).not.toContain("Search your orders");
    expect(markup).not.toContain(">All<");
    expect(markup).not.toContain("Retail order");
    expect(markup).not.toContain("lucide-chevron-right");
  });

  it("renders immutable destination, food options, receipt, timeline, ETA and live map", () => {
    const order = orderFixture();
    order.status = "OUT_FOR_DELIVERY";
    order.customerState = "ON_THE_WAY";
    order.delivery = {
      state: "ON_THE_WAY",
      verificationStatus: "ACTIVE",
      deliveryCode: "654321",
      outForDeliveryAt: "2026-08-24T09:20:00Z",
      recipientAccountRequired: false,
      riderLocation: { latitude: 12.684, longitude: 78.624 },
      riderLocationUpdatedAt: "2026-08-24T09:21:00Z",
      distanceToDestinationMeters: 725,
    };

    const markup = renderToStaticMarkup(<MatchingSheet
      order={order}
      busy={false}
      imageUrlForLine={() => null}
      onDismiss={() => undefined}
      onCancel={() => undefined}
      onPay={() => undefined}
      onReorder={() => undefined}
      onRefresh={() => undefined}
      onReportIssue={async () => true}
    />);

    expect(markup).toContain("Dastak Cafe");
    expect(markup).toContain("Large · Extra shot");
    expect(markup).toContain("12 Market Road");
    expect(markup).toContain("A Customer · +91 98765 43210");
    expect(markup).toContain("LIVE DELIVERY");
    expect(markup).toContain("725 m");
    expect(markup).toContain("On the way");
    expect(markup).toContain("Bill summary");
    expect(markup).toContain("Timeline");
    expect(markup).toContain("Dastak platform fee");
    expect(markup).toContain("Paid online via Razorpay");
    expect(markup).toContain("Download receipt");
    expect(markup).not.toMatch(/retail merchant|pickup route/i);
  });

  it("presents an unpaid matching order as an in-progress order, not a receipt", () => {
    const order = orderFixture();
    order.status = "MATCHING";
    order.customerState = "FINDING_ITEMS";
    order.paidAt = undefined;
    order.fullySecuredAt = undefined;

    const markup = renderToStaticMarkup(<MatchingSheet
      order={order}
      busy={false}
      imageUrlForLine={() => null}
      onDismiss={() => undefined}
      onCancel={() => undefined}
      onPay={() => undefined}
      onReorder={() => undefined}
      onRefresh={() => undefined}
      onReportIssue={async () => true}
    />);

    expect(markup).toContain("Finding every item");
    expect(markup).toContain("In progress");
    expect(markup).toContain("Order summary");
    expect(markup).toContain("Current basket total");
    expect(markup).not.toContain("Download receipt");
    expect(markup).not.toMatch(/retail merchant|wave 1|wave 2/i);
  });

  it("requires evidence for product-condition issues", () => {
    expect(isIssueEvidenceRequired("DAMAGED")).toBe(true);
    expect(isIssueEvidenceRequired("WRONG_SKU")).toBe(true);
    expect(isIssueEvidenceRequired("DELIVERY_PROBLEM")).toBe(false);
    expect(isIssueEvidenceRequired("OTHER")).toBe(false);
  });

  it("presents selected food options rather than dropping add-ons", () => {
    expect(orderLineDetail(orderFixture().lines[1])).toBe("Large · Extra shot");
  });

  it("normalizes customer-facing address and phone formatting", () => {
    expect(deliveryAddressLine({
      label: "Home",
      line1: "128, Mandi street,, neelfield,",
      line2: "CL Road, Vaniyambadi, Tamil Nadu",
      city: "Vaniyambadi",
      state: "Tamil Nadu",
      postalCode: "635751",
      countryCode: "IN",
      latitude: 12.68,
      longitude: 78.62,
    })).toBe("CL Road, Vaniyambadi, Tamil Nadu, 128, Mandi street, neelfield, 635751");
    expect(customerPhoneNumber("+919876543210")).toBe("+91 98765 43210");
  });

  it("supports truthful order search, delivery duration and reorder eligibility", () => {
    const order = orderFixture();
    order.status = "DELIVERED";
    order.deliveredAt = "2026-08-24T09:21:00Z";
    expect(orderSearchText(order)).toContain("filter coffee");
    expect(orderSearchText(order)).toContain("dv1-0001");
    expect(deliveredDurationLabel(order)).toBe("Delivered in 21 min");
    expect(canReorderV1Order(order.status)).toBe(true);
    expect(canReorderV1Order("PREPARING")).toBe(false);
  });
});

function orderFixture(): V1Order {
  return {
    id: "44444444-4444-4444-8444-444444444444",
    displayOrderNumber: "DV1-0001",
    orderType: "MIXED",
    status: "PREPARING",
    version: 8,
    customerState: "PREPARING",
    fulfilmentProgress: {
      state: "PREPARING",
      estimatedReadyAt: "2026-08-24T09:30:00Z",
      runningLate: false,
    },
    restaurant: {
      organizationId: "11111111-1111-4111-8111-111111111111",
      branchId: "22222222-2222-4222-8222-222222222222",
      name: "Dastak Cafe",
      branchName: "Main Road",
    },
    deliveryAddress: {
      label: "Home",
      line1: "12 Market Road",
      city: "Vaniyambadi",
      state: "Tamil Nadu",
      postalCode: "635751",
      countryCode: "IN",
      latitude: 12.68,
      longitude: 78.62,
      instructions: "Call at gate",
    },
    recipient: { name: "A Customer", phoneNumber: "+919876543210" },
    price: {
      snapshotKind: "FINAL_PAYABLE",
      subtotalPaise: 24000,
      deliveryFeePaise: 2000,
      platformFeePaise: 520,
      discountPaise: 1000,
      taxPaise: 500,
      totalPaise: 25500,
      currencyCode: "INR",
    },
    lines: [
      {
        id: "55555555-5555-4555-8555-555555555555",
        lineType: "RETAIL_SKU",
        skuId: "33333333-3333-4333-8333-333333333333",
        name: "Rice",
        packSize: "1 kg",
        quantity: 2,
        unitPricePaise: 9500,
        lineTotalPaise: 19000,
        status: "SECURED",
      },
      {
        id: "66666666-6666-4666-8666-666666666666",
        lineType: "FOOD_MENU_ITEM",
        menuItemId: "77777777-7777-4777-8777-777777777777",
        name: "Filter Coffee",
        quantity: 1,
        unitPricePaise: 5000,
        lineTotalPaise: 5000,
        status: "SECURED",
        foodSelection: {
          options: [
            {
              id: "88888888-8888-4888-8888-888888888888",
              groupId: "99999999-9999-4999-8999-999999999999",
              groupName: "Size",
              name: "Large",
              priceDeltaPaise: 500,
            },
            {
              id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
              groupId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
              groupName: "Add-ons",
              name: "Extra shot",
              priceDeltaPaise: 500,
            },
          ],
        },
      },
    ],
    submittedAt: "2026-08-24T09:00:00Z",
    fullySecuredAt: "2026-08-24T09:05:00Z",
    paidAt: "2026-08-24T09:08:00Z",
    createdAt: "2026-08-24T09:00:00Z",
    updatedAt: "2026-08-24T09:20:00Z",
  };
}
