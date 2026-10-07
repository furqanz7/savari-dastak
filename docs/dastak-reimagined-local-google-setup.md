# Local Dastak Google sign-in setup

This is a setup checklist, not completed authentication verification. Production and real Customer checkout remain unchanged. Use a separate development OAuth client and a Google account explicitly chosen by the owner. Never paste client secrets into chat or put them in `VITE_*` variables.

## Owner action

In Google Auth Platform, create or select a development **Web application** OAuth client. Configure:

- Authorized JavaScript origin: `http://127.0.0.1:5179`
- Authorized redirect URI: `http://127.0.0.1:54321/auth/v1/callback`
- If the consent app is in testing mode, authorize the chosen Google account as a test user.

The Google redirect goes to Supabase Auth, not to the frontend. Supabase then returns to the allowlisted frontend URL. These addresses are intentionally different. Use the same literal host throughout rather than mixing localhost and 127.0.0.1.

Keep the development client ID/secret in a private, Git-ignored local configuration or trusted secret store. The existing backend config expects secret variable `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET`; its name differs from the example in Supabase's guide but is valid when the configuration and supplied environment match. Provide only the configuration file path and which account is authorized; do not disclose the secret in a message.

Reference: https://supabase.com/docs/guides/auth/social-login/auth-google

## Implementation after credentials and account are available

1. Preserve the current local config. Configure only the development Google client: enable Google, supply its client ID and the private secret environment reference; retain `skip_nonce_check = false` and `email_optional = false`. Do not enable Apple or change production.
2. Align local Auth site URL and exact allowed frontend redirects with port 5179. Current checked-in values point to port 3000 and cannot verify this frontend flow unchanged. Review both root sign-in and existing account-link/reauth redirect paths before setting the allowlist.
3. Preserve the local Reimagined opt-in during the root OAuth return with a DEV/loopback-only, explicitly allowlisted redirect. Current `App.tsx` returns to `/`, dropping `?reimagined=1`. Do not carry arbitrary query parameters, tokens or external return destinations. Test that production and legacy redirects stay unchanged.
4. Supply all required real public Customer configuration through the existing local-only opt-in: variant, local API/public key, legal/support/partner URLs and VAPID public key. Do not fabricate legal/support destinations, reuse private provider credentials in the browser or weaken config validation.
5. Restart only local Dastak as needed, preserving volumes and using `--network-id dastak_reimagined_loopback --exclude vector`. Verify host bindings again. Do not reset/apply migrations to obtain a session.
6. The owner completes Google's real sign-in in the browser. Verify genuine provider identity, existing profile bootstrap, session registration and read-only catalogue/address/order requests. Account/profile bootstrap creates local auth/profile/session state; obtain explicit scope for those local writes before executing the sign-in test. Never forge provider identities/JWTs or substitute anonymous/password accounts.
7. Keep checkout disabled. Reserve/confirm tests, seed data, production deployment and native verification are separate milestones with their own boundaries.

The standalone `reimagined-preview.html` is a simulation, not the authenticated app entry. Successful preview sign-in is not evidence of OAuth or backend access.
