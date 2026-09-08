begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select ok(
  pg_catalog.pg_get_functiondef(
    'dastak_v1_api.fanout_pending_outbox_events(text,integer)'::regprocedure
  ) ~ 'v_event\.event_type[[:space:]]*<>[[:space:]]*''PREPARATION_STARTED''[[:space:][:print:]]*v_event\.aggregate_type[[:space:]]*=[[:space:]]*''ORDER''',
  'preparation notifications are emitted only from the canonical order event'
);

select ok(
  (
    select procedure.prosecdef
    from pg_catalog.pg_proc procedure
    where procedure.oid =
      'dastak_v1_api.fanout_pending_outbox_events(text,integer)'::regprocedure
  ),
  'the outbox publisher remains security definer'
);

select is(
  (
    select procedure.proconfig
    from pg_catalog.pg_proc procedure
    where procedure.oid =
      'dastak_v1_api.fanout_pending_outbox_events(text,integer)'::regprocedure
  ),
  array['search_path=""']::text[],
  'the outbox publisher keeps an empty search path'
);

select * from finish();
rollback;
