// SQL preparation only; this module has no database/CLI/network transport.
// The executable rehearsal refuses anything except an isolated local target.
import { readFileSync,readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { validateMerchantRebuildManifest } from './merchant-rebuild-manifest.mjs';
const directory=new URL('../supabase/migrations/',import.meta.url);
const receipt=JSON.parse(readFileSync(new URL('../../../docs/evidence/dastak-merchant-production-preflight-2026-10-19.json',import.meta.url),'utf8'));
const sha=text=>createHash('sha256').update(text).digest('hex');
const quote=text=>"'"+text.replaceAll("'","''")+"'";
export function merchantReleaseSource() {
  const rows=readdirSync(directory).filter(name=>/^\d{14}_.+\.sql$/.test(name)).sort()
    .map(name=>({name,sql:readFileSync(new URL(name,directory),'utf8')}));
  validateMerchantRebuildManifest({count:rows.length,chainSha256:receipt.sourceChainSha256,
    migrations:rows.map(({name,sql})=>({name,sha256:sha(sql)}))});
  return rows;
}
export function buildMerchantReleaseSQL({commit=false,lockMilliseconds=2000,statementMilliseconds=15000}={}) {
  if(typeof commit!=='boolean'||!Number.isSafeInteger(lockMilliseconds)||lockMilliseconds<50||lockMilliseconds>2000
    ||!Number.isSafeInteger(statementMilliseconds)||statementMilliseconds<50||statementMilliseconds>15000
    ||lockMilliseconds>=statementMilliseconds)throw Error('Invalid bounded release options');
  const rows=merchantReleaseSource(),candidates=rows.slice(291),before=rows.slice(0,291);
  const expectedVersions=before.map(row=>quote(row.name.slice(0,14))).join(',');
  const signatures=receipt.functions.filter(row=>row.present).map(row=>row.signature);
  const oldChecks=receipt.functions.filter(row=>row.present).map(row=>`if not exists(select 1 from pg_proc where oid=to_regprocedure(${quote(row.signature)})
    and encode(sha256(convert_to(btrim(replace(prosrc,E'\\r\\n',E'\\n'),E' \\t\\r\\n'),'UTF8')),'hex')=${quote(row.normalizedBodySha256)}
    and pg_get_userbyid(proowner)=${quote(row.owner)} and prosecdef=${row.securityDefiner} and provolatile=${quote(row.volatility)}) then
    raise exception 'Prerequisite function drift'; end if;`).join('\n');
  const publics=receipt.functions.filter(row=>!row.present).map(row=>row.signature);
  const publicChecks=publics.map(signature=>`if to_regprocedure(${quote(signature)}) is not null then raise exception 'New RPC already exists'; end if;`).join('\n');
  const statements=candidates.map(row=>`${row.sql}\n;
insert into supabase_migrations.schema_migrations(version,name,statements)
values(${quote(row.name.slice(0,14))},${quote(row.name.slice(15,-4))},array[${quote(row.sql)}]);`).join('\n');
  const grantChecks=publics.map(signature=>{
    const service=signature.includes('royalty');
    return `if to_regprocedure(${quote(signature)}) is null or has_function_privilege('anon',${quote(signature)},'execute')
      or has_function_privilege('authenticated',${quote(signature)},'execute')<>${!service}
      or has_function_privilege('service_role',${quote(signature)},'execute')<>${service}
      then raise exception 'New RPC grants mismatch'; end if;`;
  }).join('\n');
  return `begin;
set local lock_timeout='${lockMilliseconds}ms';
set local statement_timeout='${statementMilliseconds}ms';
select pg_advisory_xact_lock(20261019,291295);
do $release_guard$ begin
 if (select count(*) from supabase_migrations.schema_migrations)<>291
   or exists(select 1 from supabase_migrations.schema_migrations where version not in (${expectedVersions})) then
   raise exception 'Unexpected migration baseline'; end if;
 ${oldChecks}
 ${publicChecks}
 if to_regclass('dastak_v1.fulfilments_merchant_history_cursor_idx') is not null then raise exception 'Unrecorded history index'; end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='dastak_v1_api'
  and p.proname in ('merchant_detail_fields','merchant_detail_record','merchant_order_detail','merchant_fulfilment_is_history',
   'merchant_fulfilment_history','merchant_inventory_page','merchant_locations_page','merchant_royalty_controls_snapshot','request_merchant_royalty_withdrawal_checked'))
  then raise exception 'Unrecorded private function'; end if;
end $release_guard$;
create temporary table merchant_release_history_guard on commit drop as select version,name,statements from supabase_migrations.schema_migrations;
create temporary table merchant_release_functions_guard on commit drop as select oid,prosrc,proowner,prosecdef,provolatile,proconfig,proacl
 from pg_proc where oid=any(array[${signatures.map(s=>`to_regprocedure(${quote(s)})`).join(',')}]);
${statements}
do $release_verify$ begin
 if (select count(*) from supabase_migrations.schema_migrations)<>295 then raise exception 'History count mismatch'; end if;
 if exists(select 1 from merchant_release_history_guard b left join supabase_migrations.schema_migrations a using(version)
   where a.version is null or a.name is distinct from b.name or a.statements is distinct from b.statements) then raise exception 'Old history changed'; end if;
 if exists(select 1 from merchant_release_functions_guard b left join pg_proc a using(oid)
   where a.oid is null or a.proowner<>b.proowner or a.prosecdef<>b.prosecdef or a.provolatile<>b.provolatile
     or a.proconfig is distinct from b.proconfig or a.proacl is distinct from b.proacl
     or (a.oid<>'dastak_v1_api.list_merchant_fulfilments(uuid,integer)'::regprocedure and a.prosrc<>b.prosrc)) then raise exception 'Existing dependency or grants changed'; end if;
 if not exists(select 1 from pg_index where indexrelid=to_regclass('dastak_v1.fulfilments_merchant_history_cursor_idx') and indisvalid and indisready)
   then raise exception 'History index not valid'; end if;
 ${grantChecks}
end $release_verify$;
select json_build_object('history',295,'lockTimeout',current_setting('lock_timeout'),'statementTimeout',current_setting('statement_timeout'),
 'readOnly',current_setting('transaction_read_only'),'transactionId',txid_current(),'mode',${quote(commit?'commit':'rollback')}) merchant_release_verification;
${commit?'commit':'rollback'};
`;
}
