import { PayoutGatewayClient } from "../_shared/payout-gateway.ts";
import { RazorpayXClient } from "../_shared/razorpayx.ts";

type ReadEnvironment = (name: string) => string | undefined;
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export function payoutGatewayFromEnvironment(
  readEnvironment: ReadEnvironment = Deno.env.get,
  fetcher: Fetcher = fetch,
) {
  return new PayoutGatewayClient({
    baseUrl: requiredEnvironment(readEnvironment, "DASTAK_PAYOUT_GATEWAY_URL"),
    secret: requiredEnvironment(readEnvironment, "DASTAK_PAYOUT_GATEWAY_SECRET"),
  }, fetcher);
}

export function razorpayXTestDestinationClientFromEnvironment(
  readEnvironment: ReadEnvironment = Deno.env.get,
  fetcher: Fetcher = fetch,
) {
  if (readEnvironment("RAZORPAYX_MODE") !== "TEST") {
    throw new Error(
      "Direct RazorpayX access is disabled outside TEST; live provider operations require fixed egress",
    );
  }
  return new RazorpayXClient({
    keyId: requiredEnvironment(readEnvironment, "RAZORPAYX_TEST_KEY_ID"),
    keySecret: requiredEnvironment(readEnvironment, "RAZORPAYX_TEST_KEY_SECRET"),
    accountNumber: requiredEnvironment(readEnvironment, "RAZORPAYX_TEST_ACCOUNT_NUMBER"),
    mode: "TEST",
  }, fetcher);
}

function requiredEnvironment(readEnvironment: ReadEnvironment, name: string) {
  const value = readEnvironment(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}
