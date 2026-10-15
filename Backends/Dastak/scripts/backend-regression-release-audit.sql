-- Read-only pre/post audit for the two owner-approved forward corrections.
begin read only;
set local statement_timeout='15s';
select jsonb_build_object(
 'history',(select jsonb_agg(jsonb_build_object('version',version,'name',name,
   'sqlMd5',md5(array_to_string(statements,''))) order by version)
   from supabase_migrations.schema_migrations),
 'media',jsonb_build_object(
   'rls',(select relrowsecurity from pg_class where oid='dastak_v1.governed_entity_media'::regclass),
   'owner',(select pg_get_userbyid(relowner) from pg_class where oid='dastak_v1.governed_entity_media'::regclass),
   'bytes',pg_total_relation_size('dastak_v1.governed_entity_media'),
   'rows',(select count(*) from dastak_v1.governed_entity_media),
   'indexes',(select jsonb_agg(indexdef order by indexname) from pg_indexes where schemaname='dastak_v1' and tablename='governed_entity_media'),
   'policies',(select count(*) from pg_policy where polrelid='dastak_v1.governed_entity_media'::regclass),
   'acl',(select relacl::text from pg_class where oid='dastak_v1.governed_entity_media'::regclass)),
 'settlement',(select jsonb_build_object('body',prosrc,'owner',pg_get_userbyid(proowner),
   'securityDefiner',prosecdef,'volatility',provolatile,'config',proconfig,'acl',proacl::text)
   from pg_proc where oid='private.post_merchant_order_settlement(private.merchant_orders,text)'::regprocedure),
 'accountCodeConstraint',(select pg_get_constraintdef(oid) from pg_constraint
   where conrelid='private.merchant_order_ledger_entries'::regclass and conname='merchant_order_ledger_entries_account_code_check'),
 'ledger',jsonb_build_object(
   'entries',(select count(*) from private.merchant_order_ledger_entries),
   'transactions',(select count(*) from private.merchant_order_ledger_transactions),
   'bytes',pg_total_relation_size('private.merchant_order_ledger_entries'),
   'invalidTransactions',(select count(*) from (
     select t.id from private.merchant_order_ledger_transactions t
     left join private.merchant_order_ledger_entries e on e.transaction_id=t.id
     group by t.id having coalesce(sum(e.amount_paise) filter(where e.side='debit'),0)<=0
       or coalesce(sum(e.amount_paise) filter(where e.side='debit'),0)<>
          coalesce(sum(e.amount_paise) filter(where e.side='credit'),0)) invalid)),
 'ledgerGuards',(select jsonb_agg(jsonb_build_object('name',tgname,'enabled',tgenabled,'definition',pg_get_triggerdef(oid)) order by tgname)
   from pg_trigger where not tgisinternal and tgrelid in (
     'private.merchant_order_ledger_entries'::regclass,'private.merchant_order_ledger_transactions'::regclass)),
 'clientDmlGrants',(select count(*) from information_schema.tables t
   cross join (values('anon'),('authenticated')) r(role)
   where t.table_type='BASE TABLE' and t.table_schema in ('public','private','audit','dastak_v1')
     and (has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'INSERT')
       or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'UPDATE')
       or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'DELETE')
       or has_table_privilege(r.role,format('%I.%I',t.table_schema,t.table_name),'TRUNCATE'))),
 'directClientMediaRead',has_table_privilege('anon','dastak_v1.governed_entity_media','SELECT')
   or has_table_privilege('authenticated','dastak_v1.governed_entity_media','SELECT'),
 'domainClientUsage',has_schema_privilege('authenticated','dastak_v1','USAGE')
) audit;
rollback;
