// Offline, optional build tool. Uses an existing glTF Transform 4.x installation;
// no downloads, model API calls, or changes to the original evaluation asset.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { stat } from "node:fs/promises";
import path from "node:path";

const require = createRequire(import.meta.url);
const modules = process.env.DASTAK_GLTF_MODULES;
const resolve = name => modules ? path.join(modules, name) : name;
const { NodeIO } = require(resolve("@gltf-transform/core"));
const { prune } = require(resolve("@gltf-transform/functions"));
const input = fileURLToPath(new URL("../src/assets/reimagined/staff-rpm.glb", import.meta.url));
const output = input.replace(".glb", "-idle.glb");
const io = new NodeIO();
const doc = await io.read(input);
const root = doc.getRoot();
// This renderer poses the skeleton itself. Refuse future animation-bearing
// assets instead of silently breaking morph-weight animation channels.
assert.equal(root.listAnimations().length, 0, "Review animated replacements before optimizing");
const geometry = root.listMeshes().flatMap(m => m.listPrimitives().map(p => p.getAttribute("POSITION").getCount()));
const skinCount = root.listSkins().length;
let removedTargets = 0;
for (const mesh of root.listMeshes()) {
  const primitives = mesh.listPrimitives();
  const targets = primitives[0].listTargets();
  const indices = targets.flatMap((t, i) => /^eyeBlink(Left|Right)$/.test(t.getName()) ? [i] : []);
  for (const primitive of primitives) {
    const all = primitive.listTargets();
    assert.deepEqual(all.map(t => t.getName()), targets.map(t => t.getName()));
    for (let i = 0; i < all.length; i++) if (!indices.includes(i)) {
      primitive.removeTarget(all[i]); removedTargets++;
    }
  }
  mesh.setWeights(indices.map(i => mesh.getWeights()[i] ?? 0));
  for (const node of root.listNodes()) if (node.getMesh() === mesh && node.getWeights().length) {
    node.setWeights(indices.map(i => node.getWeights()[i] ?? 0));
  }
}
// These maps are already disabled by the runtime's plain uniform material.
for (const material of root.listMaterials()) if (/Outfit_Top|Outfit_Bottom/.test(material.getName())) {
  material.setBaseColorTexture(null).setNormalTexture(null).setMetallicRoughnessTexture(null).setOcclusionTexture(null);
}
await doc.transform(prune());
await io.write(output, doc);
const check = (await io.read(output)).getRoot();
assert.deepEqual(check.listMeshes().flatMap(m => m.listPrimitives().map(p => p.getAttribute("POSITION").getCount())), geometry);
assert.equal(check.listSkins().length, skinCount);
for (const mesh of check.listMeshes()) for (const primitive of mesh.listPrimitives()) {
  assert.ok(primitive.listTargets().every(t => /^eyeBlink(Left|Right)$/.test(t.getName())));
}
const before = (await stat(input)).size, after = (await stat(output)).size;
assert.ok(after < before);
console.log(JSON.stringify({ before, after, savedPercent: Math.round(100 * (1 - after / before)), removedTargets, output }));
