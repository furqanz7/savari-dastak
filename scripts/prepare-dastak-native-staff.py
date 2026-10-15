"""Bake the existing CC0 GLB into native posed buffers; no downloads or new assets.
Run with the bundled Python/numpy. Output is a reproducible build asset, not user data.
The two real eyelid targets are skinned into the same relaxed pose as the face.
"""
import hashlib, json, struct
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parents[1]
source = root / "Web/MarketplaceWeb/src/assets/reimagined/staff-makehuman.glb"
out = root / "Packages/DastakUI/Sources/DastakUI/Resources/Environment"
out.mkdir(parents=True, exist_ok=True)
raw = source.read_bytes()
assert hashlib.sha256(raw).hexdigest() == "adf9f73504acff6a6747901fb804d3157c92bc37544bb3843af25e5cb838151f"
length = struct.unpack_from("<I", raw, 12)[0]
g = json.loads(raw[20:20+length])
binary = raw[28+length:]
types = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

def view(index, offset, count, dtype, width):
    v = g["bufferViews"][index]
    dt = np.dtype(dtype)
    stride = v.get("byteStride", dt.itemsize*width)
    return np.ndarray((count, width), dtype=dt, buffer=binary,
                      offset=v.get("byteOffset", 0)+offset,
                      strides=(stride, dt.itemsize)).copy()

def accessor(index):
    a = g["accessors"][index]
    w, dt = widths[a["type"]], types[a["componentType"]]
    result = view(a["bufferView"], a.get("byteOffset",0), a["count"],dt,w) if "bufferView" in a else np.zeros((a["count"], w), dtype=dt)
    if "sparse" in a:
        s = a["sparse"]
        i = s["indices"]; v = s["values"]
        ids = view(i["bufferView"],i.get("byteOffset",0),s["count"],types[i["componentType"]],1).ravel()
        result[ids] = view(v["bufferView"],v.get("byteOffset",0),s["count"],dt,w)
    return result

def quat(q):
    x,y,z,w = q
    return np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],
                     [2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],
                     [2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])

locals_ = []
parents = {}
names = {}
for i,n in enumerate(g["nodes"]):
    names[n.get("name",str(i))] = i
    m = np.array(n["matrix"]).reshape(4,4).T if "matrix" in n else np.eye(4)
    if "matrix" not in n:
        m[:3,:3] = quat(n.get("rotation",[0,0,0,1])) @ np.diag(n.get("scale",[1,1,1]))
        m[:3,3] = n.get("translation",[0,0,0])
    locals_.append(m)
    for c in n.get("children",[]): parents[c] = i

def world(i):
    return world(parents[i]) @ locals_[i] if i in parents else locals_[i]

def unit(v): return v / max(np.linalg.norm(v), 1e-10)

def direct(joint, child, desired):
    i,c = names[joint],names[child]
    inv = np.linalg.inv(world(i))
    current = unit((inv @ world(c))[:3,3])
    target = unit(inv[:3,:3] @ desired)
    axis = np.cross(current,target); sine=np.linalg.norm(axis); cosine=np.clip(np.dot(current,target),-1,1)
    if sine < 1e-9: return
    axis /= sine
    x,y,z=axis; k=np.array([[0,-z,y],[z,0,-x],[-y,x,0]])
    rotation=np.eye(3)+sine*k+(1-cosine)*(k@k)
    locals_[i][:3,:3] = locals_[i][:3,:3] @ rotation

across = unit(world(names["upperarm_l"])[:3,3]-world(names["upperarm_r"])[:3,3])
forward = unit(np.cross([0,1,0],across))
for side,sign in [("l",1),("r",-1)]:
    direct("upperarm_"+side,"lowerarm_"+side,unit(np.array([0,-1,0])+across*sign*.075-forward*.025))
    direct("lowerarm_"+side,"hand_"+side,unit(np.array([0,-1,0])+across*sign*.025+forward*.095))
    direct("hand_"+side,"middle_01_"+side,unit(np.array([0,-1,0])+forward*.055))
    fingers=unit(np.array([0,-1,0])+forward*.055)
    actual=world(names["index_01_"+side])[:3,3]-world(names["pinky_01_"+side])[:3,3]
    actual=unit(actual-fingers*np.dot(actual,fingers))
    wanted=unit(forward*sign-fingers*np.dot(forward*sign,fingers))
    angle=np.arctan2(np.dot(np.cross(actual,wanted),fingers),np.dot(actual,wanted))
    hand=names["hand_"+side]; inverse=np.linalg.inv(world(hand))
    axis=unit(inverse[:3,:3]@fingers); x,y,z=axis
    if np.linalg.det(inverse)<0: angle=-angle
    k=np.array([[0,-z,y],[z,0,-x],[-y,x,0]])
    locals_[hand][:3,:3] = locals_[hand][:3,:3] @ (np.eye(3)+np.sin(angle)*k+(1-np.cos(angle))*(k@k))

skin = g["skins"][0]
bind = accessor(skin["inverseBindMatrices"]).reshape(-1,4,4).transpose(0,2,1)
matrices=np.array([world(i)@b for i,b in zip(skin["joints"],bind)])
blob=bytearray(); meshes=[]
def write(values, dtype="<f4"):
    offset=len(blob); data=np.asarray(values,dtype=dtype).tobytes(); blob.extend(data); return offset

for mesh in g["meshes"]:
    for p in mesh["primitives"]:
        a=p["attributes"]; pos=accessor(a["POSITION"]); normals=accessor(a["NORMAL"])
        joints=accessor(a["JOINTS_0"]); weights=accessor(a["WEIGHTS_0"])
        mix=np.sum(matrices[joints]*weights[:,:,None,None],axis=1)
        points=np.einsum("nij,nj->ni",mix,np.column_stack([pos,np.ones(len(pos))]))[:,:3]
        ns=np.einsum("nij,nj->ni",mix[:,:3,:3],normals); ns/=np.maximum(np.linalg.norm(ns,axis=1)[:,None],1e-8)
        indices=accessor(p["indices"]).ravel()
        # SceneKit's UIImage upload already handles image origin; retain glTF UVs.
        uv=accessor(a["TEXCOORD_0"])
        entry={"name":mesh["name"],"count":len(pos),"indicesCount":len(indices),"material":p["material"],
               "positions":write(points),"normals":write(ns),"uv":write(uv),"indices":write(indices,"<u4")}
        if p.get("targets"):
            delta=sum((accessor(t["POSITION"]) for t in p["targets"] if "POSITION" in t),np.zeros_like(pos))
            closed=points+np.einsum("nij,nj->ni",mix[:,:3,:3],delta)
            assert np.max(np.abs(closed-points)) > .001
            entry["closed"]=write(closed)
        meshes.append(entry)
materials=[]
for i,m in enumerate(g["materials"]):
    p=m["pbrMetallicRoughness"]; t=g["textures"][p["baseColorTexture"]["index"]]
    image=g["images"][t["source"]]; v=g["bufferViews"][image["bufferView"]]
    suffix="png" if image["mimeType"]=="image/png" else "jpg"
    name=f"native-staff-{i}.{suffix}"; start=v.get("byteOffset",0)
    (out/name).write_bytes(binary[start:start+v["byteLength"]])
    entry={"texture":name,"roughness":p.get("roughnessFactor",1),"masked":m.get("alphaMode")=="MASK","doubleSided":m.get("doubleSided",False)}
    if "normalTexture" in m:
        normal=g["images"][g["textures"][m["normalTexture"]["index"]]["source"]]
        nv=g["bufferViews"][normal["bufferView"]]; start=nv.get("byteOffset",0)
        suffix="png" if normal["mimeType"]=="image/png" else "jpg"
        entry["normal"]=f"native-staff-normal-{i}.{suffix}"
        (out/entry["normal"]).write_bytes(binary[start:start+nv["byteLength"]])
    materials.append(entry)
left=world(names["hand_l"])[:3,3]; right=world(names["hand_r"])[:3,3]
assert left[1] < world(names["upperarm_l"])[1,3] and right[1] < world(names["upperarm_r"])[1,3]
(out/"native-staff.bin").write_bytes(blob)
(out/"native-staff.json").write_text(json.dumps({"version":1,"sourceSHA256":hashlib.sha256(raw).hexdigest(),"license":"CC0-1.0","meshes":meshes,"materials":materials,"hands":[left.tolist(),right.tolist()]},indent=2))
print(f"Baked {len(meshes)} meshes, {len(blob)} geometry bytes; relaxed hands {left.round(3)}, {right.round(3)}; real eyelid targets retained")
