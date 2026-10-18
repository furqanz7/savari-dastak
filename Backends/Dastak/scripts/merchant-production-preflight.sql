-- Metadata-only production preflight. No application RPCs or mutations.
begin read only;
set local statement_timeout='15s';
set local lock_timeout='2s';
select jsonb_build_object(
 'observedAt',clock_timestamp(),
 'readOnly',current_setting('transaction_read_only'),
 'serverVersion',current_setting('server_version'),
 'history',(select jsonb_agg(jsonb_build_object('version',version,'name',name,
   'statementCount',cardinality(statements),'receiptMd5',md5(array_to_string(statements,''))) order by version)
   from supabase_migrations.schema_migrations),
 'functions',(select jsonb_agg(jsonb_build_object('signature',s.signature,
   'present',p.oid is not null,'body',p.prosrc,'owner',pg_get_userbyid(p.proowner),
   'securityDefiner',p.prosecdef,'volatility',p.provolatile,'config',p.proconfig,'acl',p.proacl::text)
   order by s.signature) from (values
   ('dastak_v1_api.list_merchant_fulfilments(uuid,integer)'),
   ('dastak_v1_api.assert_authenticated_actor(uuid)'),
   ('dastak_v1_api.actor_has_wave1_merchant_permission(uuid,uuid,text,uuid)'),
   ('dastak_v1_api.merchant_fulfilment_json(uuid,uuid)'),
   ('dastak_v1_api.merchant_opportunity_json(uuid,uuid)'),
   ('dastak_v1_api.restaurant_request_json(uuid,uuid)'),
   ('dastak_v1.catalogue_prefix_query(text)'),
   ('dastak_v1_api.actor_can_manage_royalty_subject(uuid,dastak_v1.settlement_subject_type,uuid,boolean)'),
   ('dastak_v1_api.get_royalty_snapshot(uuid,text)'),
   ('dastak_v1_api.register_royalty_payout_destination(uuid,text,uuid,text,text,text,text,jsonb)'),
   ('dastak_v1_api.request_royalty_withdrawal(uuid,text,uuid,bigint,text)'),
   ('dastak_v1_api.post_balanced_financial_transaction(text,text,bigint,text,dastak_v1.settlement_subject_type,uuid,text,dastak_v1.settlement_subject_type,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,jsonb)'),
   ('public.dastak_v1_merchant_order_detail(uuid,text,uuid)'),
   ('public.dastak_v1_merchant_fulfilment_history(uuid,timestamptz,uuid,integer)'),
   ('public.dastak_v1_merchant_inventory_page(uuid,text,boolean,integer,text,uuid)'),
   ('public.dastak_v1_merchant_locations_page(integer,uuid,uuid)'),
   ('public.dastak_v1_merchant_royalty_controls_snapshot(uuid)'),
   ('public.dastak_v1_request_merchant_royalty_withdrawal_checked(uuid,uuid,bigint,text,uuid,bigint)')
   ) s(signature) left join pg_proc p on p.oid=to_regprocedure(s.signature)),
 'historyIndex',to_regclass('dastak_v1.fulfilments_merchant_history_cursor_idx') is not null,
 'fulfilments',(select jsonb_build_object('estimatedRows',c.reltuples,'tableBytes',pg_relation_size(c.oid),
   'totalBytes',pg_total_relation_size(c.oid),'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,
   'indexes',(select jsonb_agg(jsonb_build_object('name',i.indexrelid::regclass::text,'definition',pg_get_indexdef(i.indexrelid),
      'ready',i.indisready,'valid',i.indisvalid)) from pg_index i where i.indrelid=c.oid),
   'locks',(select count(*) from pg_locks l where l.relation=c.oid and l.pid<>pg_backend_pid()),
   'waitingLocks',(select count(*) from pg_locks l where l.relation=c.oid and not l.granted))
   from pg_class c where c.oid='dastak_v1.fulfilments'::regclass),
 'clientDmlViolations',(select count(*) from information_schema.tables t
   cross join (values('anon'),('authenticated')) r(role)
   where t.table_type='BASE TABLE' and t.table_schema in ('public','private','audit','dastak_v1')
   and (has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'INSERT')
    or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'UPDATE')
    or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'DELETE')
    or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'TRUNCATE')
    or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'TRIGGER'))),
 'domainClientUsage',has_schema_privilege('authenticated','dastak_v1','USAGE'),
 'financialGuards',(select jsonb_agg(jsonb_build_object('table',tgrelid::regclass::text,'name',tgname,'enabled',tgenabled,
   'definition',pg_get_triggerdef(oid)) order by tgrelid,tgname)
   from pg_trigger where not tgisinternal and tgrelid in (
    'dastak_v1.financial_journal_transactions'::regclass,'dastak_v1.financial_journal_lines'::regclass,
    'private.merchant_order_ledger_entries'::regclass,'private.merchant_order_ledger_transactions'::regclass)),
 'retentionJob',(select jsonb_build_object('active',active,'commandSha256',encode(sha256(convert_to(command,'UTF8')),'hex'))
   from cron.job where jobname='dastak-successful-cron-history-retention'),
 'activity',jsonb_build_object(
   'otherActiveSessions',(select count(*) from pg_stat_activity where state='active' and pid<>pg_backend_pid()),
   'transactionsOlderThanMinute',(select count(*) from pg_stat_activity where xact_start<now()-interval '1 minute' and pid<>pg_backend_pid()))
) preflight;
rollback;
