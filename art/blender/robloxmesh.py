"""Load a Roblox v6/v7 .mesh (Draco COREMESH + SKINNING chunks) into numpy arrays, and fetch
pack meshes/textures by asset id (Open Cloud asset delivery, env ROBLOXAPIKEY, cached in
art/out/petmesh/). Needs `pip install DracoPy numpy`. Used by art/blender/pet_preview.py."""
import struct, numpy as np, DracoPy
def load(path):
    d = open(path, 'rb').read()
    assert d.startswith(b'version 7') or d.startswith(b'version 6'), d[:12]
    p = d.index(b'\n') + 1
    out = {}
    while p < len(d):
        name = d[p:p+8].rstrip(b'\x00'); ver, size = struct.unpack('<II', d[p+8:p+16]); body = d[p+16:p+16+size]; p += 16 + size
        if name == b'COREMESH':
            m = DracoPy.decode(body[4:])
            out['pos'] = np.asarray(m.points, dtype=float); out['faces'] = np.asarray(m.faces, dtype=int)
            uv = None
            for a in m.attributes if hasattr(m, 'attributes') else []:
                if a['attribute_type'] == 3: uv = np.asarray(a['data'], dtype=float)
            if uv is None and getattr(m, 'tex_coord', None) is not None: uv = np.asarray(m.tex_coord, dtype=float)
            out['uv'] = uv
        elif name == b'SKINNING':
            n = struct.unpack('<I', body[:4])[0]; q = 4
            sk = np.frombuffer(body[q:q+n*8], dtype=np.uint8).reshape(n, 8); q += n*8
            nb = struct.unpack('<I', body[q:q+4])[0]; q += 4
            bones = []
            for i in range(nb):
                ni, par, lp, cull = struct.unpack('<IHHf', body[q:q+12]); rot = struct.unpack('<9f', body[q+12:q+48]); pos = struct.unpack('<3f', body[q+48:q+60]); q += 60
                bones.append([ni, par])
            ns = struct.unpack('<I', body[q:q+4])[0]; q += 4; names = body[q:q+ns]; q += ns
            for b in bones: b[0] = names[b[0]:names.index(b'\x00', b[0])].decode()
            nsub = struct.unpack('<I', body[q:q+4])[0]; q += 4
            subsets = []
            for i in range(nsub):
                fb, fl, vb, vl, nbi = struct.unpack('<5I', body[q:q+20]); bi = struct.unpack('<26H', body[q+20:q+72]); q += 72
                subsets.append((vb, vl, bi[:nbi]))
            idx = np.zeros((n, 4), dtype=int)
            for vb, vl, bi in subsets:
                for v in range(vb, vb+vl):
                    idx[v] = [bi[k] if k < len(bi) else 0 for k in sk[v, :4]]
            out['bone_names'] = [b[0] for b in bones]; out['skin_idx'] = idx; out['skin_w'] = sk[:, 4:].astype(float) / 255.0
    return out

import gzip, json, os, time, urllib.request

def fetch(asset_id, path):
    """Download an asset's bytes (gunzipped) to path, once."""
    if os.path.exists(path):
        return path
    key = os.environ["ROBLOXAPIKEY"]
    err = None
    for i in range(5):
        try:
            r = urllib.request.Request(f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{asset_id}", headers={"x-api-key": key})
            loc = json.load(urllib.request.urlopen(r))["location"]
            data = urllib.request.urlopen(loc).read()
            if data[:2] == b"\x1f\x8b":
                data = gzip.decompress(data)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)
            return path
        except Exception as e:  # proxy hiccups: retry
            err = e
            time.sleep(2 + 2 * i)
    raise RuntimeError(f"fetch {asset_id}: {err}")
