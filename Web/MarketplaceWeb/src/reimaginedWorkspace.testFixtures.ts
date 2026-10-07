import type { V1Order } from "./dastakV1";

// Synthetic presentation data only. Never imported by the production entry.
export const workspaceOrderFixture: V1Order = {
  id: "11111111-1111-4111-8111-111111111111", displayOrderNumber: "TEST-1001", orderType: "RETAIL_ONLY", status: "DELIVERED", version: 4,
  createdAt: "2026-10-01T10:00:00Z", updatedAt: "2026-10-01T10:30:00Z", paidAt: "2026-10-01T10:25:00Z", deliveredAt: "2026-10-01T10:30:00Z",
  price: { snapshotKind: "FINAL", subtotalPaise: 10000, deliveryFeePaise: 2000, platformFeePaise: 200, taxPaise: 0, discountPaise: 0, totalPaise: 12200, currencyCode: "INR" },
  lines: [{ id: "22222222-2222-4222-8222-222222222222", lineType: "RETAIL_SKU", skuId: "33333333-3333-4333-8333-333333333333", name: "Synthetic test product", quantity: 1, unitPricePaise: 10000, lineTotalPaise: 10000, status: "DELIVERED" }],
  recipient: { name: "Preview customer", phoneNumber: "+919876543210" },
  deliveryAddress: { label: "Synthetic address", line1: "Test-only street", countryCode: "IN", latitude: 12, longitude: 77 },
  support: { canReportIssue: true, recovery: [], issues: [], returns: [], refunds: [] },
};
