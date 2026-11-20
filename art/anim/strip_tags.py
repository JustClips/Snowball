"""Copy a binary .rbxm without its Tags/AttributesSerialize property chunks, so Lune 0.10 can read the
StudAnimalPack (it rejects the pack's Tags type).  python3 art/anim/strip_tags.py IN.rbxm OUT.rbxm"""
import struct, sys
def lz4_block(src, n):
    out = bytearray(); i = 0
    while i < len(src):
        tok = src[i]; i += 1
        l = tok >> 4
        if l == 15:
            while True:
                b = src[i]; i += 1; l += b
                if b != 255: break
        out += src[i:i+l]; i += l
        if i >= len(src): break
        off = src[i] | (src[i+1] << 8); i += 2
        m = tok & 15
        if m == 15:
            while True:
                b = src[i]; i += 1; m += b
                if b != 255: break
        m += 4
        s = len(out) - off
        for k in range(m): out.append(out[s+k])
    return bytes(out)
data = open(sys.argv[1], 'rb').read()
hdr = data[:32]; p = 32; out = bytearray(hdr); dropped = 0
while p < len(data):
    name = data[p:p+4]; clen, ulen, _ = struct.unpack('<III', data[p+4:p+16])
    raw = data[p+16:p+16+(clen or ulen)]
    nxt = p + 16 + (clen or ulen)
    if name == b'PROP':
        body = lz4_block(raw, ulen) if clen else raw
        cls = struct.unpack('<I', body[:4])[0]; nl = struct.unpack('<I', body[4:8])[0]
        pname = body[8:8+nl].decode()
        if pname in ('Tags', 'AttributesSerialize') :
            dropped += 1; p = nxt; continue
    out += data[p:nxt]; p = nxt
open(sys.argv[2], 'wb').write(out); print('dropped', dropped)
