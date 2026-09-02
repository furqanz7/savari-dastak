const EMPTY_ERROR_MESSAGES = new Set([
  "",
  "{}",
  "[]",
  "[object object]",
  "null",
  "undefined",
  "unknown error",
]);

const INTERNAL_ERROR_PATTERNS = [
  /\b(?:postgres|postgrest|sqlstate|plpgsql|service[_ -]?role|row level security|rls|permission denied for)\b/i,
  /\b(?:pgrst|pg[a-z0-9]{3,}|42p\d{2}|22p\d{2}|23505|42501)\b/i,
  /\b(?:stack trace|typeerror:|referenceerror:|syntaxerror:)\b/i,
];

type ErrorRecord = Record<string, unknown>;

export function userFacingError(error: unknown, fallback: string) {
  const message = readableErrorMessage(error);
  if (!message) return fallback;

  const lowered = message.toLowerCase();
  if (isConnectivityFailure(lowered)) {
    return "Dastak could not connect. Check your internet connection and try again.";
  }
  if (isExpiredSession(lowered, errorCode(error))) {
    return "Your session has expired. Sign in again to continue.";
  }
  if (isRateLimited(lowered, errorCode(error))) {
    return "Too many attempts were made. Wait a moment, then try again.";
  }
  if (INTERNAL_ERROR_PATTERNS.some((pattern) => pattern.test(message))) return fallback;
  return message;
}

export function readableErrorMessage(error: unknown) {
  const candidate = extractMessage(error, 0);
  if (typeof candidate !== "string") return undefined;
  const normalized = candidate.trim().replace(/\s+/g, " ");
  if (EMPTY_ERROR_MESSAGES.has(normalized.toLowerCase())) return undefined;
  if (normalized.length > 320 || looksLikeMarkup(normalized) || looksLikeSerializedData(normalized)) {
    return undefined;
  }
  return normalized;
}

function extractMessage(value: unknown, depth: number): unknown {
  if (depth > 3 || value == null) return undefined;
  if (typeof value === "string") return value;
  if (value instanceof Error) return value.message;
  if (typeof value !== "object" || Array.isArray(value)) return undefined;

  const record = value as ErrorRecord;
  for (const key of ["message", "error_description", "error", "detail"] as const) {
    const candidate = extractMessage(record[key], depth + 1);
    if (typeof candidate === "string") return candidate;
  }
  return undefined;
}

function errorCode(error: unknown) {
  if (!error || typeof error !== "object") return "";
  const record = error as ErrorRecord;
  if (typeof record.code === "string") return record.code.toLowerCase();
  if (record.error && typeof record.error === "object") {
    const nested = (record.error as ErrorRecord).code;
    if (typeof nested === "string") return nested.toLowerCase();
  }
  return "";
}

function isConnectivityFailure(message: string) {
  return message.includes("network") || message.includes("failed to fetch") ||
    message.includes("load failed") || message.includes("offline") ||
    message.includes("internet connection");
}

function isExpiredSession(message: string, code: string) {
  return code === "jwt_expired" || code === "refresh_token_not_found" ||
    message.includes("jwt expired") || message.includes("refresh token not found") ||
    message.includes("invalid refresh token");
}

function isRateLimited(message: string, code: string) {
  return code.includes("rate_limit") || code === "over_request_rate_limit" ||
    message.includes("too many requests");
}

function looksLikeMarkup(value: string) {
  return /^\s*</.test(value) || /<\/?(?:html|body|script|style)\b/i.test(value);
}

function looksLikeSerializedData(value: string) {
  if (!/^[{[]/.test(value)) return false;
  try {
    const parsed = JSON.parse(value);
    return typeof parsed === "object" && parsed !== null;
  } catch {
    return false;
  }
}
