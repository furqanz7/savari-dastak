// Bake just the two eyelid deltas before GPU skeletal deformation. Keeping
// morph textures out of the skinned body shader avoids a separate rendering
// path for the body versus the eyes/clothes on browser GPU implementations.
export function createBlinkPlayback(waitForRenderedClosure = false) {
  let previous = 0;
  let pendingClosure = false;
  let renderedClosureAt: number | undefined;
  const ease = (value: number) => { const t = Math.max(0, Math.min(1, value)); return t * t * (3 - 2 * t); };
  const playback = (time: number) => {
    if (time < previous) { pendingClosure = false; renderedClosureAt = undefined; }
    if (waitForRenderedClosure && pendingClosure) {
      previous = time;
      // A skipped/unready character draw must not consume the entire blink.
      // Opening begins only after the body actually draws with closed eyes.
      if (renderedClosureAt === undefined) return 1;
      const opening = time - renderedClosureAt - .06;
      if (opening < 0) return 1;
      if (opening < .18) return 1 - ease(opening / .18);
      pendingClosure = false;
    }
    const phase = (time % 6.7) - 4.79;
    const closure = 4.89 + Math.floor((time - 4.89) / 6.7) * 6.7;
    // On a slow device, adjacent rendered frames can straddle the entire
    // blink. Render the crossed closure once rather than silently skipping it.
    const crossedClosure = time >= 4.89 && previous < closure && time >= closure;
    previous = time;
    const weight = crossedClosure ? 1 : phase < 0 ? 0 : phase < .10 ? ease(phase / .10)
      : phase < .14 ? 1 : 1 - ease((phase - .14) / .18);
    if (waitForRenderedClosure && weight > .95) { pendingClosure = true; renderedClosureAt = undefined; }
    return weight;
  };
  playback.markClosedRendered = (time: number) => {
    if (pendingClosure && renderedClosureAt === undefined) renderedClosureAt = time;
  };
  return playback;
}

export function createEyelidBuffer(base: ArrayLike<number>, targets: ArrayLike<number>[]) {
  if (targets.some(target => target.length !== base.length)) throw new Error("Eyelid target size mismatch");
  const original = Float32Array.from(base);
  const data = original.slice();
  const indices: number[] = [], deltas: number[] = [];
  for (let i = 0; i < original.length; i++) {
    const delta = targets.reduce((sum, target) => sum + target[i] - original[i], 0);
    if (Math.abs(delta) > 1e-8) { indices.push(i); deltas.push(delta); }
  }
  return { data, changedCoordinates: indices.length, update(weight: number) {
    const value = Number.isFinite(weight) ? Math.max(0, Math.min(1, weight)) : 0;
    for (let i = 0; i < indices.length; i++) data[indices[i]] = original[indices[i]] + deltas[i] * value;
  } };
}
