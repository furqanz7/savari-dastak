create or replace function private.calculate_merchant_order_distance_terms(
  rate_row private.merchant_order_rate_cards,
  p_route_distance_m integer
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_extra_distance_m integer;
  v_extra_started_km bigint;
  v_delivery_fee_paise bigint;
  v_courier_payout_paise bigint;
begin
  if p_route_distance_m is null or p_route_distance_m not between 0 and 1000000 then
    raise exception using
      errcode = '22023',
      message = 'merchant_order_route_distance_invalid';
  end if;

  v_extra_distance_m := case
    when p_route_distance_m > (rate_row).included_distance_m
      then p_route_distance_m - (rate_row).included_distance_m
    else 0
  end;
  v_extra_started_km := pg_catalog.ceil(
    v_extra_distance_m::numeric / 1000
  )::bigint;
  v_delivery_fee_paise := (rate_row).base_delivery_fee_paise::bigint
    + v_extra_started_km * (rate_row).delivery_fee_per_started_km_paise::bigint;
  v_courier_payout_paise := (rate_row).base_courier_payout_paise::bigint
    + v_extra_started_km * (rate_row).courier_payout_per_started_km_paise::bigint;

  return pg_catalog.jsonb_build_object(
    'rateCardId', (rate_row).id,
    'rateCardVersion', (rate_row).version,
    'routeDistanceMeters', p_route_distance_m,
    'includedDistanceMeters', (rate_row).included_distance_m,
    'extraStartedKilometres', v_extra_started_km,
    'deliveryFee', pg_catalog.jsonb_build_object(
      'paise', v_delivery_fee_paise
    ),
    'courierPayout', pg_catalog.jsonb_build_object(
      'paise', v_courier_payout_paise
    ),
    'platformDeliveryMargin', pg_catalog.jsonb_build_object(
      'paise', v_delivery_fee_paise - v_courier_payout_paise
    ),
    'merchantCommissionBps', (rate_row).merchant_commission_bps
  );
end;
$$;

revoke execute on function private.calculate_merchant_order_distance_terms(
  private.merchant_order_rate_cards, integer
) from public, anon, authenticated;
grant execute on function private.calculate_merchant_order_distance_terms(
  private.merchant_order_rate_cards, integer
) to service_role;
