-- Isolated native-Postgres contract fixture, never run against production.
create schema dastak_v1;
create schema dastak_v1_api;
create role authenticated;
create role anon;
create table dastak_v1.skus(id integer primary key, variant_name text, attribute_data jsonb not null default '{}');
insert into dastak_v1.skus values(1,'Vanilla','{"productType":"Full Cream","ingredients":["Milk"]}'),(2,null,'{}');
create function dastak_v1_api.merchant_canonical_catalogue_snapshot(p_actor_id uuid,p_branch_id uuid default null,p_limit integer default 5000)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if p_actor_id is distinct from '00000000-0000-4000-8000-000000000001'::uuid then
    raise insufficient_privilege using message='fixture merchant actor denied';
  end if;
  return (select jsonb_agg(jsonb_build_object('variant', sku.variant_name, 'id',sku.id) order by sku.id) from dastak_v1.skus sku);
end;
$$;
revoke all on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer) from public;
grant usage on schema dastak_v1_api to authenticated,anon;
grant execute on function dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer) to authenticated;
create table public.product_type_original as select pg_get_functiondef(oid) as definition,proacl,prosecdef,proconfig,proowner from pg_proc where oid='dastak_v1_api.merchant_canonical_catalogue_snapshot(uuid,uuid,integer)'::regprocedure;
