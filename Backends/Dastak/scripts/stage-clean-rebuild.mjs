// Stage unmodified source into a newly created, unlinked disposable project.
// Never initializes/resets a database or reads production credentials.
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const source = fileURLToPath(new URL('../supabase/', import.meta.url));
const destination = realpathSync(process.argv[2] ?? '');
if (!/^\/private\/tmp\/dastak-full-rebuild\.[A-Za-z0-9]+$/.test(destination)) throw new Error('Refusing non-disposable destination');
const config = readFileSync(join(destination, 'supabase/config.toml'), 'utf8');
if (!/^project_id = "DastakRebuild20261016(?:R[2-9])?"$/m.test(config)
    || existsSync(join(destination, 'supabase/.temp/project-ref'))
    || existsSync(join(destination, '.env'))) throw new Error('Target is linked, configured with secrets, or has the wrong identity');
const files = readdirSync(join(source, 'migrations')).filter(name => /^\d{14}_.+\.sql$/.test(name)).sort();
if (files.length !== 289 || new Set(files.map(name => name.slice(0, 14))).size !== files.length) throw new Error('Unexpected migration manifest; review before staging');
if (files.at(-2) !== '20261015214234_harden_governed_entity_media.sql'
    || files.at(-1) !== '20261015214450_legacy_order_platform_fee_ledger.sql') throw new Error('Unexpected forward corrections');
const manifest = files.map(name => ({ name, sha256: createHash('sha256').update(readFileSync(join(source, 'migrations', name))).digest('hex') }));
mkdirSync(join(destination, 'supabase/migrations'), { recursive: true });
for (const { name, sha256 } of manifest) {
  const target = join(destination, 'supabase/migrations', name);
  copyFileSync(join(source, 'migrations', name), target);
  if (createHash('sha256').update(readFileSync(target)).digest('hex') !== sha256) throw new Error(`Copy mismatch: ${name}`);
}
const chainSha256 = createHash('sha256').update(manifest.map(row => `${row.name}:${row.sha256}`).join('\n')).digest('hex');
writeFileSync(join(destination, 'rebuild-manifest.json'), JSON.stringify({ count: manifest.length, chainSha256, migrations: manifest }, null, 2) + '\n');
console.log(JSON.stringify({ destination, count: manifest.length, chainSha256, allCopiesVerified: true }));
