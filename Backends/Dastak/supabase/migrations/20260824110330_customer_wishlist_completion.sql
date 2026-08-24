-- Customer Wishlist is durable account data, but it is not part of financial or
-- order history. Deleting/anonymising an account may therefore remove it.

create table dastak_v1.customer_wishlist_items (
  account_id uuid not null references public.accounts(id) on delete cascade,
  item_kind text not null check (item_kind in ('RETAIL_SKU', 'MENU_ITEM')),
  item_id uuid not null,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (account_id, item_kind, item_id)
);

create index customer_wishlist_items_recent_idx
  on dastak_v1.customer_wishlist_items (account_id, created_at desc, item_kind, item_id);

alter table dastak_v1.customer_wishlist_items enable row level security;
revoke all on table dastak_v1.customer_wishlist_items from public, anon, authenticated;

create function private.customer_wishlist_snapshot(p_account_id uuid)
returns table(response_body jsonb, response_status integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    pg_catalog.jsonb_build_object(
      'items', coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'kind', item.item_kind,
            'itemId', item.item_id,
            'createdAt', item.created_at
          )
          order by item.created_at desc, item.item_kind, item.item_id
        ) filter (where item.item_id is not null),
        '[]'::jsonb
      )
    ),
    200
  from dastak_v1.customer_wishlist_items item
  where item.account_id = p_account_id;
$$;

create function private.set_customer_wishlist_item(
  p_account_id uuid,
  p_item_kind text,
  p_item_id uuid,
  p_wished boolean
)
returns table(response_body jsonb, response_status integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_exists boolean;
  v_changed boolean := false;
  v_row_count bigint := 0;
begin
  if p_account_id is null
    or p_item_id is null
    or p_item_kind not in ('RETAIL_SKU', 'MENU_ITEM')
    or p_wished is null then
    return query select
      pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'validation_failed',
          'message', 'A valid wishlist item is required.'
        )
      ),
      400;
    return;
  end if;

  if p_item_kind = 'RETAIL_SKU' then
    select exists (
      select 1
      from dastak_v1.skus sku
      where sku.id = p_item_id and sku.status = 'ACTIVE'
    ) into v_exists;
  else
    select exists (
      select 1
      from dastak_v1.restaurant_menu_items menu_item
      where menu_item.id = p_item_id and menu_item.status = 'ACTIVE'
    ) into v_exists;
  end if;

  if p_wished and not v_exists then
    return query select
      pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object(
          'code', 'wishlist_item_unavailable',
          'message', 'This item is not currently available to save.'
        )
      ),
      409;
    return;
  end if;

  if p_wished then
    insert into dastak_v1.customer_wishlist_items (account_id, item_kind, item_id)
    values (p_account_id, p_item_kind, p_item_id)
    on conflict (account_id, item_kind, item_id) do nothing;
    get diagnostics v_row_count = row_count;
  else
    delete from dastak_v1.customer_wishlist_items item
    where item.account_id = p_account_id
      and item.item_kind = p_item_kind
      and item.item_id = p_item_id;
    get diagnostics v_row_count = row_count;
  end if;
  v_changed := v_row_count > 0;

  if v_changed then
    insert into dastak_v1.audit_events (
      actor_id,
      action,
      resource_type,
      resource_id,
      metadata
    ) values (
      p_account_id,
      case when p_wished then 'CUSTOMER_WISHLIST_ADDED' else 'CUSTOMER_WISHLIST_REMOVED' end,
      p_item_kind,
      p_item_id,
      pg_catalog.jsonb_build_object('wished', p_wished)
    );
  end if;

  return query select * from private.customer_wishlist_snapshot(p_account_id);
end;
$$;

revoke all on function private.customer_wishlist_snapshot(uuid) from public, anon, authenticated;
revoke all on function private.set_customer_wishlist_item(uuid, text, uuid, boolean)
  from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.customer_wishlist_snapshot(uuid) to service_role;
grant execute on function private.set_customer_wishlist_item(uuid, text, uuid, boolean)
  to service_role;

create function public.get_customer_wishlist(p_account_id uuid)
returns table(response_body jsonb, response_status integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.customer_wishlist_snapshot(p_account_id);
$$;

create function public.set_customer_wishlist_item(
  p_account_id uuid,
  p_item_kind text,
  p_item_id uuid,
  p_wished boolean
)
returns table(response_body jsonb, response_status integer)
language sql
security invoker
set search_path = ''
as $$
  select * from private.set_customer_wishlist_item(
    p_account_id,
    p_item_kind,
    p_item_id,
    p_wished
  );
$$;

revoke all on function public.get_customer_wishlist(uuid) from public, anon, authenticated;
revoke all on function public.set_customer_wishlist_item(uuid, text, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.get_customer_wishlist(uuid) to service_role;
grant execute on function public.set_customer_wishlist_item(uuid, text, uuid, boolean)
  to service_role;

comment on table dastak_v1.customer_wishlist_items is
  'Customer-owned saved retail SKUs and restaurant menu items; never financial truth.';
