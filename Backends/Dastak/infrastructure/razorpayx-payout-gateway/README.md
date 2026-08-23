# Dastak fixed-egress payout gateway

This package is the only supported live RazorpayX payout-execution path. Dastak's Royalty ledger and
withdrawal reservation remain authoritative in Supabase; this service accepts only a signed request
to execute one already-authorized withdrawal. RazorpayX webhooks continue to use the Supabase
`razorpayx-payout-webhook` function.

## Contract and security

- `POST /v1/payouts` accepts only canonical JSON containing `withdrawalId`, `amountPaise`,
  `currency: "INR"`, `fundAccountReference`, the same deterministic withdrawal UUID as
  `idempotencyKey`, and an ISO timestamp.
- `x-dastak-payout-signature` is HMAC-SHA256 over the version, method, fixed path, and exact
  canonical request bytes. Requests outside the configured clock-skew window or exact replays are
  rejected before RazorpayX is called.
- The persisted replay file stores only signature digests and expiry timestamps. Run exactly one
  instance unless this store is replaced by an atomic shared implementation.
- The service exposes only `GET /healthz` and the fixed payout command. It cannot proxy arbitrary
  URLs, methods, paths, or Razorpay operations.
- The Razorpay API origin is hard-coded and the container's Deno network permission permits only its
  listener and `api.razorpay.com:443`.
- Logs contain an irreversible withdrawal fingerprint and outcome only. Never log request bodies,
  gateway signatures/secrets, API credentials, account numbers, fund-account references, UTRs, or
  provider payloads.

## Required runtime configuration

Gateway only:

- `DASTAK_PAYOUT_GATEWAY_SECRET` — at least 32 random bytes; identical to the Supabase secret.
- `RAZORPAYX_MODE` — start with `TEST`; use `LIVE` only after activation approval.
- `RAZORPAYX_KEY_ID`, `RAZORPAYX_KEY_SECRET`, `RAZORPAYX_ACCOUNT_NUMBER`.
- `RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED` — keep `false` until the allocated Elastic IP is
  actually allowlisted in the RazorpayX Live dashboard.
- `DASTAK_PAYOUT_GATEWAY_HOSTNAME` — DNS name terminating valid public TLS.
- Optional `DASTAK_PAYOUT_GATEWAY_MAX_CLOCK_SKEW_SECONDS` (default 120, allowed 30–300).

Supabase only:

- `DASTAK_PAYOUT_GATEWAY_URL=https://<gateway-hostname>`.
- `DASTAK_PAYOUT_GATEWAY_SECRET`.
- `RAZORPAYX_WEBHOOK_SECRET` and `RAZORPAYX_DESTINATION_FINGERPRINT_SECRET` remain in Supabase.
- Live RazorpayX key ID, key secret, source account, and the allowlist-confirmation flag do not
  belong in Supabase Edge Function secrets.

Non-production Supabase environments may additionally use `RAZORPAYX_MODE=TEST` with
`RAZORPAYX_TEST_KEY_ID`, `RAZORPAYX_TEST_KEY_SECRET`, and `RAZORPAYX_TEST_ACCOUNT_NUMBER` for the
existing direct Contact/Fund Account test workflow. Those are not production prerequisites.

Keep real values in AWS Secrets Manager (or an equivalently controlled secret store). Materialize
the systemd `EnvironmentFile` under `/run/dastak-payout-gateway/environment` with mode `0600` at
boot; never commit it or place it on the persistent application volume.

## AWS ap-south-1 deployment runbook

No infrastructure is created by this repository.

1. In `ap-south-1`, provision one dedicated hardened EC2 instance in a public subnet and attach one
   allocated Elastic IP to its primary network interface. Disable public SSH; administer via AWS
   Systems Manager Session Manager with least-privilege IAM.
2. Give the security group inbound TCP 443. Permit TCP 80 only if Caddy's ACME HTTP challenge is
   used. Restrict outbound to DNS via the VPC resolver and TCP 443; the application additionally
   restricts its only external HTTP destination to `api.razorpay.com`.
3. Point the gateway DNS `A` record at the Elastic IP. Install Docker Engine/Compose, place this
   exact release source at `/opt/dastak`, install `dastak-payout-gateway.service`, and enable it.
4. Load TEST credentials and the shared gateway secret from AWS Secrets Manager into the protected
   `/run` environment file. Start the unit; confirm `systemctl` restart behavior, container health,
   replay-volume persistence, and `https://<host>/healthz` through Caddy-managed TLS.
5. Send signed TEST requests only and verify timeout/retry returns the same Razorpay payout because
   the Dastak withdrawal UUID is always forwarded as `X-Payout-Idempotency`.
6. Record the Elastic IP, add exactly that IP to RazorpayX Live IP allowlisting, and obtain owner
   evidence that the dashboard change is active. Do not infer allowlisting from instance setup.
7. At an explicit live activation window, install Live credentials, set `RAZORPAYX_MODE=LIVE`, then
   and only then set `RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED=true`. Restart and verify health.
8. Set the two Supabase gateway secrets and redeploy `earnings`; leave the existing payout webhook
   endpoint and HMAC secret unchanged. Do not make a live payout until a separately authorized,
   controlled withdrawal rehearsal.

Contact/Fund Account creation remains direct only in RazorpayX TEST mode in the Supabase adapter.
Before live withdrawals, founder Merchant/Rider destinations must therefore already have approved
RazorpayX Contact/Fund Account references provisioned through an authorized fixed-egress/operations
process. This minimal payout gateway intentionally does not accept raw bank or VPA data.

## Operations

- Restart policy is `unless-stopped` at Docker level and boot activation is owned by systemd.
- Alert on unhealthy containers, restart loops, 401/409 spikes, any 5xx, provider-ambiguous
  outcomes, and replay-store write failures.
- Back up the replay volume before host replacement. Provider idempotency is still the final
  duplicate-payout guard across host loss.
- Roll back by restoring the prior image while preserving the replay volume and gateway secret.
  Never bypass the gateway with a direct live Supabase-to-RazorpayX call.
