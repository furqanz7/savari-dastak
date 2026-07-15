import { json } from "../_shared/http.ts";

export type AuthenticateBearer = (bearerToken: string) => Promise<{ accountId: string }>;
export type IsActiveOwner = (accountId: string) => Promise<boolean>;
export type SignEvidenceDownload = (input: {
  bucket: string;
  objectPath: string;
  expiresIn: number;
}) => Promise<string>;

type Dependencies = {
  authenticateBearer: AuthenticateBearer;
  isActiveOwner: IsActiveOwner;
  signDownload: SignEvidenceDownload;
};

type EvidenceRequest = { bucket: string; objectPath: string; operation: "download" };

const bucket = "savari-evidence";
const selfOwnedRoot = "savari-driver";
const ownerOnlyRoots = new Set(["merchant", "pharmacy", "prescription", "receipt"]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const evidenceUrlExpirySeconds = 300;

export async function handleIssueEvidenceUrl(request: Request, dependencies: Dependencies) {
  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+\S+$/.test(authorization)) return authenticationRequired();

  let actor: { accountId: string };
  try {
    actor = await dependencies.authenticateBearer(authorization);
  } catch {
    return authenticationRequired();
  }

  const body = await parseBody(request);
  if (!body || !isValidRequest(body)) return validationError();

  const path = parsePath(body.objectPath);
  if (!path) return validationError();

  if (path.root === selfOwnedRoot) {
    if (path.ownerId !== actor.accountId) return accessDenied();
  } else {
    try {
      if (!await dependencies.isActiveOwner(actor.accountId)) return accessDenied();
    } catch {
      return json({
        error: { code: "internal_error", message: "The evidence URL could not be issued." },
      }, 500);
    }
  }

  try {
    const signedUrl = await dependencies.signDownload({
      bucket,
      objectPath: body.objectPath,
      expiresIn: evidenceUrlExpirySeconds,
    });
    return json({ signedUrl, expiresIn: evidenceUrlExpirySeconds });
  } catch {
    return json({
      error: {
        code: "evidence_url_unavailable",
        message: "The evidence URL could not be issued.",
      },
    }, 502);
  }
}

async function parseBody(request: Request): Promise<unknown | undefined> {
  try {
    return await request.json();
  } catch {
    return undefined;
  }
}

function isValidRequest(value: unknown): value is EvidenceRequest {
  return !!value && typeof value === "object" &&
    "bucket" in value && value.bucket === bucket &&
    "objectPath" in value && typeof value.objectPath === "string" &&
    "operation" in value && value.operation === "download";
}

function parsePath(objectPath: string): { root: string; ownerId: string } | undefined {
  const segments = objectPath.split("/");
  if (segments.length !== 3 || segments.some((segment) => !segment)) return undefined;
  const [root, ownerId] = segments;
  if ((!ownerOnlyRoots.has(root) && root !== selfOwnedRoot) || !uuidPattern.test(ownerId)) {
    return undefined;
  }
  return { root, ownerId };
}

function authenticationRequired() {
  return json({
    error: { code: "authentication_required", message: "A valid bearer token is required." },
  }, 401);
}

function validationError() {
  return json({
    error: {
      code: "validation_failed",
      message: "bucket, objectPath, and download operation are required.",
    },
  }, 400);
}

function accessDenied() {
  return json({
    error: { code: "access_denied", message: "You cannot access this evidence object." },
  }, 403);
}
