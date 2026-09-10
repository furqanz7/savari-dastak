import {
  DastakV1RequestError,
  getV1MerchantCanonicalCatalogue,
  getV1MerchantRestaurantMenu,
  type DastakV1Auth,
} from "./dastakV1";

export type MerchantBranch = {
  id: string;
  branchName: string;
  organizationName: string;
  merchantType: string;
};

export type MerchantCommerceProbeFailure =
  | "not_applicable"
  | "session"
  | "access"
  | "connectivity"
  | "service";

export type MerchantBranchDiscovery = {
  branches: MerchantBranch[];
  failures: MerchantCommerceProbeFailure[];
};

export function merchantCommerceKind(branch: MerchantBranch): "retail" | "restaurant" | undefined {
  if (branch.merchantType === "RETAIL") return "retail";
  if (branch.merchantType === "RESTAURANT_CAFE") return "restaurant";
  return undefined;
}

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export function classifyMerchantCommerceProbeFailure(error: unknown): MerchantCommerceProbeFailure {
  if (!(error instanceof DastakV1RequestError)) return "service";
  if (error.status === 401 || error.code === "authentication_required") return "session";
  if (error.status === 403 || error.code === "access_denied") return "access";
  if (error.status === 0 || error.code === "network_error" || error.code === "request_timeout") return "connectivity";
  if (error.status === 404 || error.code === "not_found") return "not_applicable";
  return "service";
}

export async function discoverDefaultMerchantBranches(auth: DastakV1Auth, fetcher: Fetcher = fetch): Promise<MerchantBranchDiscovery> {
  const [retail, restaurant] = await Promise.allSettled([
    getV1MerchantCanonicalCatalogue({ ...auth, limit: 1 }, fetcher),
    getV1MerchantRestaurantMenu(auth, fetcher),
  ]);
  const branches: MerchantBranch[] = [];
  const failures: MerchantCommerceProbeFailure[] = [];
  if (retail.status === "fulfilled") branches.push(retailBranch(retail.value.branch));
  else failures.push(classifyMerchantCommerceProbeFailure(retail.reason));
  if (restaurant.status === "fulfilled") branches.push(restaurantBranch(restaurant.value.restaurant));
  else failures.push(classifyMerchantCommerceProbeFailure(restaurant.reason));
  return { branches: mergeMerchantBranches([], branches), failures };
}

export async function classifyMerchantBranch(
  auth: DastakV1Auth,
  candidate: { id: string; displayName: string },
  fetcher: Fetcher = fetch,
): Promise<MerchantBranch> {
  try {
    const menu = await getV1MerchantRestaurantMenu({ ...auth, branchId: candidate.id }, fetcher);
    return restaurantBranch(menu.restaurant);
  } catch (restaurantError) {
    if (classifyMerchantCommerceProbeFailure(restaurantError) !== "not_applicable") throw restaurantError;
  }
  const catalogue = await getV1MerchantCanonicalCatalogue({ ...auth, branchId: candidate.id, limit: 1 }, fetcher);
  return retailBranch(catalogue.branch);
}

export function mergeMerchantBranches(current: MerchantBranch[], incoming: MerchantBranch[]) {
  const branches = new Map(current.map((branch) => [branch.id, branch]));
  incoming.forEach((branch) => branches.set(branch.id, branch));
  return [...branches.values()].sort((left, right) =>
    left.organizationName.localeCompare(right.organizationName) || left.branchName.localeCompare(right.branchName));
}

export function merchantBranchStorageKey(accountId: string) {
  return `dastak.merchant.activeBranch.v1:${accountId}`;
}

export function readPersistedMerchantBranch(accountId: string, storage: Pick<Storage, "getItem"> = localStorage) {
  try { return storage.getItem(merchantBranchStorageKey(accountId)) ?? undefined; }
  catch { return undefined; }
}

export function persistMerchantBranch(accountId: string, branchId: string, storage: Pick<Storage, "setItem"> = localStorage) {
  try { storage.setItem(merchantBranchStorageKey(accountId), branchId); }
  catch { /* Branch selection remains usable when storage is unavailable. */ }
}

function retailBranch(branch: {
  branchId: string; branchName: string; organizationName: string; merchantType: string;
}): MerchantBranch {
  return { id: branch.branchId, branchName: branch.branchName, organizationName: branch.organizationName, merchantType: branch.merchantType };
}

function restaurantBranch(restaurant: {
  branchId: string; branchName: string; name: string; merchantType: string;
}): MerchantBranch {
  return { id: restaurant.branchId, branchName: restaurant.branchName, organizationName: restaurant.name, merchantType: restaurant.merchantType };
}
