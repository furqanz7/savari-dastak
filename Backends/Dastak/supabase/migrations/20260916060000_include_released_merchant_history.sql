-- The merchant order desk must retain completed/released fulfilments in its
-- history feed. The previous projection only selected active fulfilments,
-- leaving the UI's History queue empty even when settlement entries existed.
create or replace function dastak_v1_api.list_merchant_fulfilments(
  p_actor_id uuid,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'fulfilments', coalesce(pg_catalog.jsonb_agg(
      dastak_v1_api.merchant_fulfilment_json(p_actor_id, visible.id)
      order by visible.committed_at desc, visible.id desc
    ), '[]'::jsonb)
  )
  from (
    select fulfilment.id, fulfilment.committed_at
    from dastak_v1.fulfilments fulfilment
    where fulfilment.status in (
      'RESERVED_PREPAYMENT', 'PREPARING', 'READY', 'PICKED_UP', 'COMPLETED', 'RELEASED'
    )
      and dastak_v1_api.actor_has_wave1_merchant_permission(
        p_actor_id, fulfilment.organization_id,
        'merchant.fulfilment.manage', fulfilment.branch_id
      )
    order by fulfilment.committed_at desc, fulfilment.id desc
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  ) visible;
$$;
