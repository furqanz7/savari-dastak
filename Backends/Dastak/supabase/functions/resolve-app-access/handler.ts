import { corsPreflight, json } from "../_shared/http.ts";
import type { AuthenticateBearer } from "../bootstrap-account/handler.ts";

export type DastakApplication = "customer" | "merchant" | "admin";

export type AppAccessRoute =
  | "needs_profile"
  | "pending_approval"
  | "suspended"
  | "access_denied"
  | "active";

export type ResolveAppAccessInput = {
  accountId: string;
  application: DastakApplication;
};

export type ResolveAppAccess = (
  input: ResolveAppAccessInput,
) => Promise<{ route: AppAccessRoute }>;

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  resolveAppAccess: ResolveAppAccess;
};

const applications = new Set<DastakApplication>([
  "customer",
  "merchant",
  "admin",
]);

export async function handleResolveAppAccess(
  request: Request,
  dependencies: Dependencies,
) {
  const preflight = corsPreflight(request);
  if (preflight) return preflight;

  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.match(/^Bearer\s+\S+$/)) {
    return authenticationRequired();
  }

  let user: { accountId: string };
  try {
    user = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const application = await parseApplication(request);
  if (!application) {
    return json(
      {
        error: {
          code: "invalid_application",
          message: "A supported Dastak application is required.",
        },
      },
      400,
    );
  }

  try {
    return json(
      await dependencies.resolveAppAccess({
        accountId: user.accountId,
        application,
      }),
    );
  } catch {
    return json(
      {
        error: {
          code: "internal_error",
          message: "Application access could not be resolved.",
        },
      },
      500,
    );
  }
}

async function parseApplication(
  request: Request,
): Promise<DastakApplication | undefined> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || !("application" in body)) {
      return undefined;
    }
    const application = body.application;
    return typeof application === "string" &&
        applications.has(application as DastakApplication)
      ? application as DastakApplication
      : undefined;
  } catch {
    return undefined;
  }
}

function authenticationRequired() {
  return json(
    {
      error: {
        code: "authentication_required",
        message: "A valid bearer token is required.",
      },
    },
    401,
  );
}
