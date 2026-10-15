import { assertMatch, assertNotMatch } from "jsr:@std/assert";
const source = await Deno.readTextFile(
  new URL("../../migrations/20261015003730_delivery_partner_order_details.sql", import.meta.url),
);
Deno.test("Delivery full-order reads require approved actor ownership in every lane", () => {
  assertMatch(source, /m\.approved_at is not null/);
  assertMatch(source, /m\.suspended_until/);
  assertMatch(source, /p\.governance_status='ACTIVE'/);
  assertMatch(source, /account\.account_state='ACTIVE'/);
  assertMatch(source, /persona\.state='DELETED'/);
  assertMatch(source, /assigned_rider_id=p_account_id/g);
  assertMatch(source, /partner_account_id=p_account_id/g);
  for (const kind of ["V1_DELIVERY", "RETURN", "LEGACY_DELIVERY", "PARCEL"]) {
    assertMatch(source, new RegExp(`p_kind='${kind}'`));
  }
  assertNotMatch(source, /\b(?:insert into|update\s+(?:private|dastak_v1)\.|delete from)\b/i);
});
Deno.test("Full-order RPC has no direct anon or authenticated execute grant", () => {
  assertMatch(
    source,
    /revoke all on function public\.dastak_delivery_partner_order_detail\(uuid,text,uuid\) from public,anon,authenticated/,
  );
  assertMatch(
    source,
    /grant execute on function public\.dastak_delivery_partner_order_detail\(uuid,text,uuid\) to service_role/,
  );
  assertMatch(source, /'deliveryAddress',case when v_terminal then null/);
  assertMatch(source, /'recipient',case when v_terminal then null/);
  assertMatch(source, /'deliveryAddress',case when terminal then null/g);
  assertMatch(source, /'platformFeePaise',o\.platform_fee_paise/);
  assertNotMatch(source, /'verificationCode'|'pin'|'providerReference'/i);
});
