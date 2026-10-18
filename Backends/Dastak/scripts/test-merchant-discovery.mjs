// Isolated local Unix-socket fixture. No environment URLs or live credentials.
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
const directory = mkdtempSync(join(tmpdir(), 'dastak-merchant-discovery-'));
const data = join(directory, 'data');
function run(command,args) {
  const result = spawnSync(command,args,{ encoding:'utf8',maxBuffer:3*1024*1024 });
  if (result.status!==0) throw new Error(command+' failed: '+(result.stderr||result.stdout));
  return result.stdout;
}
let started=false;
try {
  run('initdb',['-D',data,'-A','trust','--no-locale']);
  run('pg_ctl',['-D',data,'-l',join(directory,'postgres.log'),'-o',"-k "+directory+" -c listen_addresses=''",'-w','start']); started=true;
  const args=['-h',directory,'-d','postgres','-X','-v','ON_ERROR_STOP=1'];
  process.stdout.write(run('psql',[...args,'-f','supabase/tests/merchant_discovery_fixture.sql']));
  for (const [file,name] of [
    ['20260820195404_dastak_v1_wave_1.sql','dastak_v1_api.actor_has_wave1_merchant_permission'],
    ['20260821231709_dastak_v1_canonical_catalogue_runtime.sql','dastak_v1.catalogue_prefix_query'],
  ]) {
    const source=readFileSync('supabase/migrations/'+file,'utf8');
    const start=source.indexOf('create function '+name+'('), end=source.indexOf('$$;',start);
    if(start<0||end<0) throw new Error('Original helper not found: '+name);
    process.stdout.write(run('psql',[...args,'-c',source.slice(start,end+3)]));
  }
  for(const file of ['supabase/migrations/20261018131824_merchant_catalogue_and_location_pages.sql','supabase/tests/merchant_discovery_assertions.sql'])
    process.stdout.write(run('psql',[...args,'-f',file]));
} finally {
  if(started) run('pg_ctl',['-D',data,'-m','fast','-w','stop']);
  process.stdout.write('Stopped local-only fixture; diagnostics retained at '+directory+'\n');
}
