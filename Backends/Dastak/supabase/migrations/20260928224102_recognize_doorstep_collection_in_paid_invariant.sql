-- A launch payment is authorized by an immutable successful doorstep collection,
-- not by a provider payment row. Keep the existing monitor body and privileges;
-- replace only its paid-authority predicate, failing closed if it has drifted.
do $patch$
declare
  v_definition text;
  v_old text := $old$    and not exists (
      select 1 from dastak_v1.payments payment
      where payment.order_id = customer_order.id and payment.status = 'SUCCEEDED'
    )$old$;
  v_new text := $new$    and not exists (
      select 1 from dastak_v1.payments payment
      where payment.order_id = customer_order.id and payment.status = 'SUCCEEDED'
    )
    and not exists (
      select 1 from dastak_v1.launch_payment_collection_attempts collection
      where collection.order_id = customer_order.id
        and collection.outcome = 'COLLECTED'
        and collection.collected_at = customer_order.paid_at
    )$new$;
begin
  select pg_catalog.pg_get_functiondef(procedure.oid)
    into v_definition
  from pg_catalog.pg_proc procedure
  join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'dastak_v1_api'
    and procedure.proname = 'run_invariant_monitors'
    and pg_catalog.pg_get_function_identity_arguments(procedure.oid) = 'p_worker_id text';

  if v_definition is null or pg_catalog.strpos(v_definition, v_old) = 0 then
    raise exception 'expected paid-authority monitor predicate was not found';
  end if;
  if pg_catalog.strpos(
    pg_catalog.substr(v_definition, pg_catalog.strpos(v_definition, v_old) + pg_catalog.length(v_old)),
    v_old
  ) > 0 then
    raise exception 'paid-authority monitor predicate was ambiguous';
  end if;

  execute pg_catalog.replace(v_definition, v_old, v_new);
end
$patch$;
