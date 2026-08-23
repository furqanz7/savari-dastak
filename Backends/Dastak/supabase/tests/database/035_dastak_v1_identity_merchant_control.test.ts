import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260824000000_dastak_v1_identity_merchant_control.sql",
    import.meta.url,
  ),
);
const config = await Deno.readTextFile(
  new URL("../../config.toml", import.meta.url),
);
const merchantLaunchSurface = await Deno.readTextFile(
  new URL(
    "../../../../../Web/MarketplaceWeb/src/MerchantOrdersView.tsx",
    import.meta.url,
  ),
);
const addenda = await Deno.readTextFile(
  new URL("../../../../../docs/DASTAK_V1_LOCKED_ADDENDA.md", import.meta.url),
);

function configBlock(name: string): string {
  const block = config.match(
    new RegExp(`\\[${name.replaceAll(".", "\\.")}\\][\\s\\S]*?(?=\\n\\[|$)`),
  )?.[0];
  assert(block, `missing config block ${name}`);
  return block;
}

Deno.test("customer account creation and sessions are OAuth-only and fail closed", () => {
  assertMatch(configBlock("auth"), /enable_anonymous_sign_ins\s*=\s*false/i);
  assertMatch(configBlock("auth"), /enable_manual_linking\s*=\s*true/i);
  assertMatch(configBlock("auth.email"), /enable_signup\s*=\s*false/i);
  assertMatch(configBlock("auth.sms"), /enable_signup\s*=\s*false/i);
  assertMatch(configBlock("auth.hook.before_user_created"), /enabled\s*=\s*true/i);
  assertMatch(configBlock("auth.hook.custom_access_token"), /enabled\s*=\s*true/i);

  assertMatch(migration, /v_provider not in \('apple', 'google'\)/i);
  assertMatch(
    migration,
    /v_method not in \('oauth', 'oauth_provider\/authorization_code', 'token_refresh'\)/i,
  );
  assertMatch(migration, /provider_subject_digest/i);
  assertMatch(migration, /link_kind[^;]*'EXPLICIT'/i);
  assertMatch(migration, /customer_identity_link_intents/i);
  assertNotMatch(
    migration.match(/create function public\.dastak_custom_access_token[\s\S]*?\$\$;/i)?.[0] ?? "",
    /identity_data[^;]*(?:email|phone)|phone_number|display_name/i,
  );
});

Deno.test("customer deletion keeps business history and revokes account access", () => {
  assertMatch(migration, /drop constraint accounts_id_fkey/i);
  assertMatch(migration, /account_state = 'DELETION_PENDING'/i);
  assertMatch(migration, /account_state = 'DELETED'/i);
  assertMatch(migration, /CUSTOMER_ACCOUNT_ANONYMIZED/i);
  assertMatch(migration, /CUSTOMER_ACCOUNT_DELETED/i);
  assertNotMatch(
    migration,
    /(?:delete from|truncate|drop table)[^;]*(?:dastak_v1\.orders|payment|refund|settlement|custody)/i,
  );
});

Deno.test("V1 Merchant Web routes launch commerce through V1 controls", () => {
  assertMatch(merchantLaunchSurface, /MerchantV1CommerceControl/);
  assertNotMatch(merchantLaunchSurface, /MerchantCatalogueView/);
  assertNotMatch(merchantLaunchSurface, /value="store"/);
  assertMatch(migration, /merchant_canonical_catalogue_snapshot/i);
  assertMatch(migration, /update_merchant_sku_selection/i);
  assertMatch(migration, /p_expected_version/i);
});

Deno.test("newer locked authority captures auth and launch operating values", () => {
  assertMatch(addenda, /Apple or Google OAuth/i);
  assertMatch(addenda, /No SMS OTP/i);
  assertMatch(addenda, /Vaniyambadi/i);
  assertMatch(addenda, /3,000 m/i);
  assertMatch(addenda, /10\/15\/20 min/i);
  assertMatch(addenda, /STARTED_DISTANCE_BAND/i);
  assertMatch(addenda, /Unknown-SKU fallback per unit/i);
});
