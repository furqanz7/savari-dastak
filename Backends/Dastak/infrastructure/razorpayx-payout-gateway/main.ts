import { RazorpayXClient, type RazorpayXMode } from "../../supabase/functions/_shared/razorpayx.ts";
import { handlePayoutGateway } from "./handler.ts";
import { executeRazorpayXPayout } from "./provider.ts";
import { FileReplayStore } from "./replay-store.ts";

const mode = requiredEnvironment("RAZORPAYX_MODE") as RazorpayXMode;
if (mode !== "TEST" && mode !== "LIVE") throw new Error("RAZORPAYX_MODE must be TEST or LIVE");
const provider = new RazorpayXClient({
  keyId: requiredEnvironment("RAZORPAYX_KEY_ID"),
  keySecret: requiredEnvironment("RAZORPAYX_KEY_SECRET"),
  accountNumber: requiredEnvironment("RAZORPAYX_ACCOUNT_NUMBER"),
  mode,
  liveEgressAllowlistConfirmed:
    Deno.env.get("RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED") === "true",
});
const gatewaySecret = requiredGatewaySecret();
const maxClockSkewMilliseconds = integerEnvironment(
  "DASTAK_PAYOUT_GATEWAY_MAX_CLOCK_SKEW_SECONDS",
  120,
  30,
  300,
) * 1_000;
const port = integerEnvironment("PORT", 8_080, 1_024, 65_535);
const replayStore = await FileReplayStore.open(
  Deno.env.get("DASTAK_PAYOUT_GATEWAY_REPLAY_STORE") ??
    "/var/lib/dastak-payout-gateway/replay.jsonl",
);

Deno.serve(
  {
    hostname: "0.0.0.0",
    port,
    onListen: () => console.info(JSON.stringify({ event: "payout_gateway_listening", port, mode })),
  },
  (request) =>
    handlePayoutGateway(request, {
      secret: gatewaySecret,
      maxClockSkewMilliseconds,
      replayStore,
      executeProviderPayout: (payoutRequest) => executeRazorpayXPayout(provider, payoutRequest),
      log: (entry) => console.info(JSON.stringify(entry)),
    }),
);

function requiredEnvironment(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function requiredGatewaySecret() {
  const value = requiredEnvironment("DASTAK_PAYOUT_GATEWAY_SECRET");
  if (new TextEncoder().encode(value).length < 32) {
    throw new Error("DASTAK_PAYOUT_GATEWAY_SECRET must contain at least 32 bytes");
  }
  return value;
}

function integerEnvironment(name: string, fallback: number, minimum: number, maximum: number) {
  const raw = Deno.env.get(name);
  const value = raw === undefined ? fallback : Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}
