FROM denoland/deno:alpine-2.8.2@sha256:e2a641dfee05544402cf0b149a41458bd373a8f47bff6544834177ded55d662d

WORKDIR /app

COPY supabase/functions/deno.json supabase/functions/deno.lock ./supabase/functions/
COPY supabase/functions/_shared/payout-gateway.ts ./supabase/functions/_shared/payout-gateway.ts
COPY supabase/functions/_shared/razorpayx.ts ./supabase/functions/_shared/razorpayx.ts
COPY infrastructure/razorpayx-payout-gateway/handler.ts ./infrastructure/razorpayx-payout-gateway/handler.ts
COPY infrastructure/razorpayx-payout-gateway/provider.ts ./infrastructure/razorpayx-payout-gateway/provider.ts
COPY infrastructure/razorpayx-payout-gateway/replay-store.ts ./infrastructure/razorpayx-payout-gateway/replay-store.ts
COPY infrastructure/razorpayx-payout-gateway/main.ts ./infrastructure/razorpayx-payout-gateway/main.ts

RUN mkdir -p /var/lib/dastak-payout-gateway \
  && chown -R deno:deno /var/lib/dastak-payout-gateway \
  && deno cache \
    --config supabase/functions/deno.json \
    --lock supabase/functions/deno.lock \
    --frozen \
    infrastructure/razorpayx-payout-gateway/main.ts

USER deno

EXPOSE 8080
VOLUME ["/var/lib/dastak-payout-gateway"]

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD ["deno", "eval", "--allow-net=127.0.0.1:8080", "const r=await fetch('http://127.0.0.1:8080/healthz');if(!r.ok)Deno.exit(1)"]

CMD ["deno", "run", "--cached-only", "--no-prompt", "--allow-env=PORT,DASTAK_PAYOUT_GATEWAY_SECRET,DASTAK_PAYOUT_GATEWAY_MAX_CLOCK_SKEW_SECONDS,DASTAK_PAYOUT_GATEWAY_REPLAY_STORE,RAZORPAYX_MODE,RAZORPAYX_KEY_ID,RAZORPAYX_KEY_SECRET,RAZORPAYX_ACCOUNT_NUMBER,RAZORPAYX_LIVE_EGRESS_ALLOWLIST_CONFIRMED", "--allow-net=0.0.0.0:8080,api.razorpay.com:443", "--allow-read=/var/lib/dastak-payout-gateway", "--allow-write=/var/lib/dastak-payout-gateway", "infrastructure/razorpayx-payout-gateway/main.ts"]
