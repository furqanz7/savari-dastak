import assert from "node:assert/strict";

// Reachability/auth rejection only. Never supplies a real token or submits an order.
const origin = "http://127.0.0.1:54321";
for (const name of ["dastak-v1-orders", "dastak-v1-catalogue", "customer-addresses"]) {
  for (const kind of ["preflight", "missing-token", "invalid-token"]) {
    const headers = { Origin: "http://127.0.0.1:5179", "Content-Type": "application/json" };
    if (kind === "invalid-token") headers.Authorization = "Bearer synthetic-invalid-token";
    if (kind === "preflight") {
      headers["Access-Control-Request-Method"] = "POST";
      headers["Access-Control-Request-Headers"] = "authorization,content-type,apikey";
    }
    const response = await fetch(`${origin}/functions/v1/${name}`, {
      method: kind === "preflight" ? "OPTIONS" : "POST", headers,
      ...(kind === "preflight" ? {} : { body: JSON.stringify({ action: "list" }) }),
      signal: AbortSignal.timeout(15000), redirect: "error",
    });
    if (kind === "preflight") assert.ok([200, 204].includes(response.status), `${name} preflight`);
    else assert.equal(response.status, 401, `${name} ${kind}`);
    assert.ok(["*", headers.Origin].includes(response.headers.get("access-control-allow-origin")), `${name} CORS`);
    if (kind === "preflight") {
      assert.match(response.headers.get("access-control-allow-methods") ?? "", /POST/);
      assert.match(response.headers.get("access-control-allow-headers") ?? "", /authorization/i);
    }
    console.log(`${name}: ${kind} HTTP ${response.status} PASS`);
  }
}
console.log("PASS: local Edge routing, CORS and authentication rejection. Authenticated reads/writes remain unverified.");
