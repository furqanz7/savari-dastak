export async function verifyRazorpayPaymentSignature(
  secret: string,
  providerOrderID: string,
  providerPaymentID: string,
  suppliedSignature: string,
) {
  const expected = await hmacSHA256Hex(secret, `${providerOrderID}|${providerPaymentID}`);
  return constantTimeHexEqual(expected, suppliedSignature.toLowerCase());
}

export async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

export async function hmacSHA256Hex(secret: string, value: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(signature));
}

export function constantTimeHexEqual(left: string, right: string) {
  const a = hexBytes(left);
  const b = hexBytes(right);
  const maximum = Math.max(a.length, b.length);
  let difference = a.length ^ b.length;
  for (let index = 0; index < maximum; index += 1) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

function hexBytes(value: string) {
  if (!/^[0-9a-f]*$/i.test(value) || value.length % 2 !== 0) return new Uint8Array();
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function bytesToHex(value: Uint8Array) {
  return Array.from(value)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
