import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = name => readFileSync(new URL(`../scripts/${name}`, import.meta.url), 'utf8');
for (const name of ['test-v1-wave1-concurrency.sh', 'test-v1-wave2-payment-concurrency.sh',
  'test-v1-step4a-rider-pickup-concurrency.sh', 'test-v1-step5-launch-failure-financial-concurrency.sh']) {
  test(`${name} supplies all six restored transport profiles`, () => {
    const literal = source(name).match(/'delivery\.transport_load_profiles',?\s*'(\[.*?\])'/)?.[1];
    assert.ok(literal);
    const profiles = JSON.parse(literal);
    assert.deepEqual(profiles.map(row => row.transportType), ['WALKING', 'BICYCLE', 'MOTORBIKE', 'SCOOTER', 'AUTO', 'CAR']);
    assert.deepEqual(profiles.map(row => row.maxPackageCount), [2, 3, 4, 5, 12, 20]);
  });
}
for (const name of ['test-v1-step4a-rider-pickup-concurrency.sh',
  'test-v1-step4b-final-delivery-concurrency.sh', 'test-v1-step5-launch-failure-financial-concurrency.sh']) {
  test(`${name} explicitly labels historical order versions without altering defaults`, () => {
    const sql = source(name);
    assert.match(sql, /availability_policy_version,\s*checkout_pricing_version/);
    assert.doesNotMatch(sql, /customer_availability_version/);
    assert.doesNotMatch(sql, /alter\s+column\s+(?:availability_policy_version|checkout_pricing_version)\s+set\s+default/i);
  });
}
test('current submission races retain rider/stock admission at default policy versions', () => {
  for (const name of ['test-v1-batch1-concurrency.sh', 'test-v1-wave1-concurrency.sh', 'test-v1-wave2-payment-concurrency.sh']) {
    const sql = source(name);
    assert.match(sql, /public\.dastak_v1_submit_order/);
    assert.match(sql, /pg_temp\.available_rider/);
    assert.doesNotMatch(sql, /availability_policy_version|checkout_pricing_version/);
    assert.match(sql, /stocked_store|stock_quantity=100,version=version\+1/);
  }
});
