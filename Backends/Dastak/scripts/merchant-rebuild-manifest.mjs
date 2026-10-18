// Reviewed local-only 18 October source pin. A new chain requires review,
// not merely increasing a migration count or accepting a caller-supplied hash.
import { createHash } from 'node:crypto';
export const merchantChainHash = '631b55eee8ea11249c5831599b81d3b10176b313ab73c5802004bdf2a678657f';
export function validateMerchantRebuildManifest(manifest) {
  const rows = manifest?.migrations;
  if (manifest?.count !== 295 || !Array.isArray(rows) || rows.length !== 295
      || rows.some(row => !/^\d{14}_.+\.sql$/.test(row.name) || !/^[a-f0-9]{64}$/.test(row.sha256))
      || new Set(rows.map(row => row.name.slice(0,14))).size !== 295
      || rows.some((row,index) => index > 0 && rows[index-1].name >= row.name)) throw new Error('Unreviewed Merchant rebuild manifest');
  const hash = createHash('sha256').update(rows.map(row => `${row.name}:${row.sha256}`).join('\n')).digest('hex');
  if (hash !== merchantChainHash || manifest.chainSha256 !== hash) throw new Error('Merchant rebuild source fingerprint changed');
  return manifest;
}
