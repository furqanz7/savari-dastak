export type CustomerSection = "home" | "search" | "orders" | "wishlist" | "payments" | "account" | "parcel";

export function shouldMountV1CustomerExperience(section: CustomerSection) {
  return section !== "parcel" && section !== "account";
}
export type CustomerEntityType = "dastakV1Order" | "merchantOrder" | "parcel";
export type CustomerDestination = {
  section: CustomerSection;
  entityType?: CustomerEntityType;
  entityId?: string;
};

export function serializeCustomerDestination(destination: CustomerDestination) {
  if (destination.entityType && destination.entityId) {
    const route = destination.entityType === "dastakV1Order"
      ? "v1-orders"
      : destination.entityType === "merchantOrder" ? "orders" : "parcel";
    return `#/${route}/${destination.entityId}`;
  }
  return `#/${destination.section}`;
}

export function parseCustomerDestination(value: string | null | undefined): CustomerDestination {
  if (!value) return { section: "home" };
  if (value.startsWith("#/")) {
    const [section, entityId] = value.slice(2).split("/");
    if (section === "orders" && entityId && uuidPattern.test(entityId)) {
      return { section: "orders", entityType: "merchantOrder", entityId: entityId.toLowerCase() };
    }
    if (section === "v1-orders" && entityId && uuidPattern.test(entityId)) {
      return { section: "orders", entityType: "dastakV1Order", entityId: entityId.toLowerCase() };
    }
    if (section === "parcel" && entityId && uuidPattern.test(entityId)) {
      return { section: "parcel", entityType: "parcel", entityId: entityId.toLowerCase() };
    }
    return customerSections.has(section) ? { section: section as CustomerSection } : { section: "home" };
  }
  try {
    const source = JSON.parse(value) as Record<string, unknown>;
    if (!customerSections.has(String(source.section))) return { section: "home" };
    if (source.entityType === "dastakV1Order" || source.entityType === "merchantOrder" || source.entityType === "parcel") {
      if (typeof source.entityId === "string" && uuidPattern.test(source.entityId)) {
        return {
          section: source.section as CustomerSection,
          entityType: source.entityType,
          entityId: source.entityId.toLowerCase(),
        };
      }
    }
    return { section: source.section as CustomerSection };
  } catch {
    return { section: "home" };
  }
}

const customerSections = new Set(["home", "search", "orders", "wishlist", "payments", "account", "parcel"]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
