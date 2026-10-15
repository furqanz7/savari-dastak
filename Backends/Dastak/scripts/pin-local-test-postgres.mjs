// Version pin for an UNLINKED local/CI test project, never a hosted upgrade.
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const testPostgresVersion = '17.6.1.155';
export function pinLocalTestPostgres(input) {
  const root = realpathSync(input);
  if (existsSync(join(root,'supabase/.temp/project-ref')) || existsSync(join(root,'.env'))) {
    throw new Error('Refusing linked or environment-configured project; use a disposable test project');
  }
  const config = readFileSync(join(root,'supabase/config.toml'),'utf8');
  if (!/^project_id\s*=\s*"(?:Dastak|DastakRebuild20261016R[2-9])"\s*$/m.test(config)
      || !/^major_version\s*=\s*17\s*$/m.test(config)) throw new Error('Unexpected test project identity/version');
  const path = join(root,'supabase/.temp/postgres-version');
  if (existsSync(path)) {
    if (readFileSync(path,'utf8').trim() !== testPostgresVersion) throw new Error('Different existing runtime pin; review rather than overwrite');
    return testPostgresVersion;
  }
  mkdirSync(dirname(path),{recursive:true});
  writeFileSync(path,testPostgresVersion,{flag:'wx'});
  return testPostgresVersion;
}
if (process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  console.log(`Pinned unlinked test PostgreSQL image: ${pinLocalTestPostgres(process.argv[2] ?? fileURLToPath(new URL('../',import.meta.url)))}`);
}
