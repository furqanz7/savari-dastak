import type { V1RestaurantMenu } from "./dastakV1";
import { fixtureId } from "./reimaginedCatalogue.testFixtures";

export function foodMenuFixture(branch = fixtureId(30)): V1RestaurantMenu {
  return {
    restaurant: { organizationId: fixtureId(31), branchId: branch, name: "Internal Kitchen", branchName: "Test Café", acceptingOrders: true, isOpen: true,
      branchStatus: "ACTIVE", merchantType: "RESTAURANT", operationalVersion: 1, softActiveOrderThreshold: 10, activeOrderCount: 0 },
    categories: [{ id: fixtureId(32), name: "Meals", sortOrder: 1, status: "ACTIVE", version: 1, items: [{ id: fixtureId(33), name: "Test Paneer Rice", description: "A test dish", basePricePaise: 15000,
      currencyCode: "INR", taxRateBps: 0, logisticsAttributes: {}, status: "ACTIVE", version: 1,
      optionGroups: [{ id: fixtureId(34), name: "Size", selectionType: "SINGLE", minimumSelections: 1, maximumSelections: 1, sortOrder: 1, status: "ACTIVE", version: 1,
        options: [{ id: fixtureId(35), name: "Large", priceDeltaPaise: 3000, sortOrder: 1, status: "ACTIVE", version: 1 }] }] }] }],
  };
}
