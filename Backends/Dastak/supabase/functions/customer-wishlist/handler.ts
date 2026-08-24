import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

type RpcResult = { responseBody: unknown; responseStatus: number };

export type WishlistMutation = {
  accountId: string;
  itemKind: "RETAIL_SKU" | "MENU_ITEM";
  itemId: string;
  wished: boolean;
};

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  snapshot: (accountId: string) => Promise<RpcResult>;
  setItem: (input: WishlistMutation) => Promise<RpcResult>;
};

export async function handleCustomerWishlist(request: Request, dependencies: Dependencies) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();

  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  if (!body) return validationError();

  if (body.operation === "snapshot") {
    return runRpc(
      () => dependencies.snapshot(actor.accountId),
      "Your Wishlist could not be loaded.",
    );
  }

  if (body.operation === "set") {
    const itemKind = body.itemKind === "RETAIL_SKU" || body.itemKind === "MENU_ITEM"
      ? body.itemKind
      : null;
    const itemId = uuid(body.itemId);
    if (!itemKind || !itemId || typeof body.wished !== "boolean") return validationError();
    return runRpc(
      () =>
        dependencies.setItem({
          accountId: actor.accountId,
          itemKind,
          itemId,
          wished: body.wished as boolean,
        }),
      "Your Wishlist could not be updated.",
    );
  }

  return validationError();
}

async function runRpc(operation: () => Promise<RpcResult>, fallback: string) {
  try {
    const result = await operation();
    return json(result.responseBody, result.responseStatus);
  } catch {
    return json({ error: { code: "internal_error", message: fallback } }, 500);
  }
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json({
    error: { code: "validation_failed", message: "A valid Wishlist item is required." },
  }, 400);
}

function uuid(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
