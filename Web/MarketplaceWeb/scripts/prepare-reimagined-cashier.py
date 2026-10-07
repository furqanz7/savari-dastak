"""Offline CC0 cashier authoring. Requires bpy 5.2.2 and MPFB 2.0.17.

Usage: python prepare-reimagined-cashier.py --mpfb-source PATH_TO_SRC
       --assets PATH_TO_EXTRACTED_CC0_PACKS --scratch TEMP_DIR --output FILE.glb
No network, user preference saves, or production operations are performed.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mpfb-source', type=Path, required=True)
parser.add_argument('--assets', type=Path, required=True)
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.scratch.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(args.mpfb_source.resolve()))

import bpy

# Legacy source registration needs an extension resource location. Isolate that
# process-local hook and all authoring caches; never save Blender preferences.
bpy.utils.extension_path_user = lambda package, **kwargs: str(args.scratch)
import mpfb
addon = bpy.context.preferences.addons.new()
addon.module = 'mpfb'
mpfb.register()
from mpfb.services import HumanService, TargetService, LocationService, ExportService, FaceService
LocationService._second_root = str(args.assets.resolve())
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

macro = TargetService.get_default_macro_info_dict()
# .5 is the young-adult boundary; values below it interpolate toward a child.
macro.update(gender=1.0, age=.58, muscle=.48, weight=.47)
macro['race'] = dict(asian=.7, caucasian=.2, african=.1)
human = HumanService.create_human(macro_detail_dict=macro)
human.name = 'DastakCashierBody'
TargetService.bake_targets(human)
skin = args.assets / 'skins/young_asian_male/young_asian_male.mhmat'
HumanService.set_character_skin(str(skin), human, skin_type='GAMEENGINE')
rig = HumanService.add_builtin_rig(human, 'game_engine')
rig.name = 'DastakCashierRig'
sources = [skin]
for folder, name, kind in [
    ('eyes/low-poly', 'low-poly', 'Eyes'),
    ('eyebrows/eyebrow001', 'eyebrow001', 'Eyebrows'),
    ('eyelashes/eyelashes01', 'eyelashes01', 'Eyelashes'),
    ('hair/short02', 'short02', 'Hair'),
    ('clothes/male_casualsuit01', 'male_casualsuit01', 'Clothes'),
]:
    path = args.assets / folder / f'{name}.mhclo'
    if not path.is_file(): raise FileNotFoundError(path)
    sources.append(path)
    HumanService.add_mhclo_asset(str(path), human, asset_type=kind,
                               material_type='GAMEENGINE', subdiv_levels=0)

# Keep just the two necessary facial targets, not the whole 52-expression set.
for side in ['Left', 'Right']:
    path = args.assets / 'targets/faceunits' / f'eyeBlink{side}.target'
    sources.append(path)
    TargetService.load_target(human, str(path), weight=0.0, name=f'eyeBlink{side}')
FaceService.interpolate_targets(human)
ExportService.bake_modifiers_remove_helpers(human, bake_masks=True,
                                           bake_subdiv=True, remove_helpers=True)

for obj in bpy.context.scene.objects:
    if obj.type != 'MESH': continue
    for poly in obj.data.polygons: poly.use_smooth = True

# The casual outfit is a textured shirt/trouser set, not a floating primitive.
# Preserve its fold normals and keep the authored fabric texture.
for mat in bpy.data.materials:
    if not mat.use_nodes: continue
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            node.inputs['Metallic'].default_value = 0
            node.inputs['Roughness'].default_value = .62 if mat.name.endswith('.body') else .88
        if node.type != 'TEX_IMAGE' or not node.image: continue
        image = node.image
        cap = 1024 if 'diffuse3' in image.name else 512
        width, height = image.size
        if max(width, height) > cap:
            scale = cap / max(width, height)
            image.scale(round(width * scale), round(height * scale))
        image.pack()

# Pre-curl fingers slightly so keyboard-rest IK does not leave rigid flat hands.
for bone in rig.pose.bones:
    if bone.name.startswith(('index_02', 'middle_02', 'ring_02', 'pinky_02')):
        bone.rotation_mode = 'XYZ'
        bone.rotation_euler.x = .13

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = rig
args.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(args.output.resolve()), export_format='GLB',
                          use_selection=True, export_animations=False,
                          export_morph=True, export_skins=True,
                          export_image_format='AUTO', export_extras=False)
# MPFB's MakeSkin materials default to transparency even for opaque skin and
# garments. Preserve embedded textures, but normalize glTF surface semantics.
# Hair/brow/lash cards need alpha testing, not expensive sorting/see-through skin.
blob = args.output.read_bytes()
json_length = struct.unpack_from('<I', blob, 12)[0]
gltf = json.loads(blob[20:20 + json_length])
for mat in gltf['materials']:
    cards = any(token in mat['name'] for token in ['short02', 'eyebrow001', 'eyelashes01'])
    mat['alphaMode'] = 'MASK' if cards else 'OPAQUE'
    if cards:
        mat['alphaCutoff'] = .35
        mat['doubleSided'] = True
    else:
        mat.pop('alphaCutoff', None)
        mat['doubleSided'] = False
payload = json.dumps(gltf, separators=(',', ':')).encode()
payload += b' ' * (-len(payload) % 4)
remaining_chunks = blob[20 + json_length:]
args.output.write_bytes(struct.pack('<III', 0x46546C67, 2, 20 + len(payload) + len(remaining_chunks))
                        + struct.pack('<II', len(payload), 0x4E4F534A) + payload + remaining_chunks)
manifest = {
    'authoring': {'bpy': bpy.app.version_string, 'mpfb': list(mpfb.VERSION)},
    'macro': macro, 'license': 'CC0-1.0',
    'sources': [{'path': str(path.relative_to(args.assets)),
                 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for path in sources],
    'bytes': args.output.stat().st_size,
    'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
    'bones': [bone.name for bone in rig.data.bones],
    'blinkTargets': ['eyeBlinkLeft', 'eyeBlinkRight'],
}
args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'export': str(args.output), 'bytes': manifest['bytes'], 'sha256': manifest['sha256']}))
