# Cashier asset provenance

## Active local study: MakeHuman cashier (2026-09-30)

`staff-makehuman.glb` replaces the Ready Player Me avatar in the DEV-only study.
Its source assets are CC0-1.0, not subject to the old avatar's unresolved commercial permission.
The owner requested production deployment on 2026-10-07. The CC0 replacement is now bundled with fingerprinted asset URLs for the opt-in Reimagined Grocery and Café rooms. Physical-device performance review is still outstanding; this release is not a claim of final AAA graphics or device certification. The historical RPM assets below remain excluded from the production build.

- Body, modelling targets and `game_engine` rig: [MPFB 2.0.17 source](https://github.com/makehumancommunity/mpfb2/tree/v2.0.17/src/mpfb/data), MakeHuman Community. Asset licensing is distinct from the authoring tool's GPL code; [official asset-license explanation](https://static.makehumancommunity.org/about/license.html).
- Skin `young_asian_male`, collared-shirt/trouser set `male_casualsuit01`, hair `short02`, brows `eyebrow001`, lashes `eyelashes01`, low-poly eyes and brown eye material: [MakeHuman system assets CC0 pack](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html). Downloaded from the official mirror; selected entries were ZIP CRC-checked. Core MHCLO/MHMAT files explicitly record their September 2020 CC0 release and Data Collection AB, Joel Palmius and Jonas Hauquier provenance.
- `eyeBlinkLeft` and `eyeBlinkRight`: [Faceunits 01](https://static.makehumancommunity.org/assets/assetpacks/faceunits01.html), Mika Suominen. The [official pack index](https://static.makehumancommunity.org/assets/assetpacks.html) identifies functional asset packs as CC0.

Authored locally using isolated Blender Python 5.2.2 / MPFB 2.0.17: adult male proportions, fitted clothing, hidden/helper geometry removed, skin texture capped at 1024 and other textures at 512, two blink shapes transferred to lids/lashes, textured PBR export, and corrected opaque/alpha-tested surface semantics. Runtime adapts the game-engine rig to keyboard-rest IK, subtle skeletal breathing and a terminal-directed head pose. No real person's likeness is used. This is not final AAA/photoreal quality.

Reproduce with `scripts/prepare-reimagined-cashier.py`; arguments select extracted assets, MPFB source and a disposable authoring directory. The script makes no network requests and saves no user preferences. No authoring tool is added to the web application's dependencies. Source control-file hashes and configuration are recorded in `staff-makehuman.manifest.json`.

Export: 3,839,276 bytes; SHA-256 `adf9f73504acff6a6747901fb804d3157c92bc37544bb3843af25e5cb838151f`.
Original RPM assets are preserved below as historical candidates, not loaded by this study.

## Superseded prototype: Ready Player Me

File: `staff-rpm.glb` (original `rpm.glb`). **Local evaluation only; not cleared for production.**

Source: [Babylon.js Assets / Mixamo Characters / rpm.glb](https://github.com/BabylonJS/Assets/blob/master/mixamo/Characters/rpm.glb).
Attribution: Ready Player Me / Wolf3D; Babylon.js Assets contributors.
The repository declares CC BY 4.0 unless overridden. However, Ready Player Me's own [published avatar guidance](https://readyplayerme.hashnode.dev/how-to-create-3d-characters-for-your-unity-game-with-our-avatar-sdk) distinguishes non-commercial public avatars from developer commercial use. The origin/permission for this particular redistributed avatar has not been confirmed. **Do not ship this avatar or infer commercial clearance from the repository-wide notice.** The renderer uses a DEV-only literal source URL so Vite does not bundle this character for production. Replace with an explicitly licensed final staff asset before release.

Modifications: glTF Transform texture resize to 1024, plus runtime scaling, clothing recolour, terminal pose, skeletal breathing and blink morphs. This is a prototype character, **not** the final photoreal staff asset or a representation of an actual Dastak employee.

`staff-rpm-idle.glb` is the offline-optimized local preview derivative, with the same licensing restriction. `scripts/prepare-reimagined-staff.mjs` retains body geometry, skin and both blink targets, removes 244 unused facial targets and uniform textures already disabled at runtime, and prunes orphaned data. The original remains unchanged. Size: 10,361,672 → 1,308,120 bytes (87% smaller). Reproduce with an existing glTF Transform 4.x installation via `DASTAK_GLTF_MODULES=/path/to/node_modules node scripts/prepare-reimagined-staff.mjs`; the script makes no network requests or package installations. The optimized derivative also remains excluded from production.

`store-light.env`: [Babylon.js Assets / environments / studio.env](https://github.com/BabylonJS/Assets/blob/master/environments/studio.env), unmodified, CC BY 4.0 per the repository README. Attribution: Babylon.js Assets contributors.

Store meshes and procedural material/packaging textures are constructed in `reimaginedGroceryScene.ts`. Fictional shelf packaging is decorative, not customer inventory. The older generated JPEGs remain as art-direction history and are no longer the Grocery renderer.

## Scanned store materials (2026-09-30)

Study 03 supersedes this warm material direction with locally generated porcelain and painted retail surfaces. The following six scans are preserved as historical source assets but are no longer imported by the Grocery renderer.

- `wood_floor-{color,normal,arm}.jpg`: [Wood Floor, Poly Haven](https://polyhaven.com/a/wood_floor), Dimitrios Savva. Unmodified 1K JPEG diffuse, OpenGL normal and packed ambient-occlusion/roughness/metalness maps.
- `brick_wall_001-{color,normal,arm}.jpg`: [Brick Wall 001, Poly Haven](https://polyhaven.com/a/brick_wall_001), photography Dimitrios Savva, processing Rob Tuytel. Unmodified 1K JPEG maps as above.
- Both asset pages explicitly list CC0. Downloads were checked against the MD5 hashes returned by Poly Haven's asset API. Six files total 2,598,695 bytes. They are served locally by the application; browsing the scene makes no requests to Poly Haven.
