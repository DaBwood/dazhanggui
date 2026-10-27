#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ETC1/PKM decoder (numpy) for 《叫我大掌柜》 textures.

PKM layout (Cocos Android):
  "PKM " + "10" + type(u16 BE) + width(u16 BE) + height(u16 BE)
  + origWidth(u16 BE) + origHeight(u16 BE) + blocks(8 bytes each, BE)

type 0 = ETC1 RGB.  This decoder only implements ETC1 (the game's textures
are all type 0 in the sampled set).

Usage:
  python tools/etc1.py in.pkm out.png
"""

import struct
import sys

import numpy as np
from PIL import Image

MOD = np.array([
    [2, 8, -2, -8],
    [5, 17, -5, -17],
    [9, 29, -9, -29],
    [13, 42, -13, -42],
    [18, 60, -18, -60],
    [24, 80, -24, -80],
    [33, 106, -33, -106],
    [47, 183, -47, -183],
], dtype=np.int16)


def _sign_extend(v, bits):
    return (v << (32 - bits)) >> (32 - bits)


def decode_pkm(data: bytes) -> Image.Image:
    if data[:4] != b"PKM ":
        raise ValueError("not a PKM file")
    version = data[4:6]
    if version != b"10":
        raise ValueError("unsupported PKM version %r" % version)
    ptype, w, h, ow, oh = struct.unpack(">HHHHH", data[6:16])
    if ptype != 0:
        raise ValueError("unsupported PKM type %d (only ETC1=0)" % ptype)
    w = max(4, w)
    h = max(4, h)
    bw, bh = (w + 3) // 4, (h + 3) // 4
    need = bw * bh * 8
    body = data[16:16 + need]
    if len(body) < need:
        raise ValueError("truncated PKM body: %d < %d" % (len(body), need))

    blocks = np.frombuffer(body, dtype=">u8").astype(np.uint64)

    flip = ((blocks >> np.uint64(32)) & np.uint64(1)).astype(bool)
    diff = ((blocks >> np.uint64(33)) & np.uint64(1)).astype(bool)
    cw0 = ((blocks >> np.uint64(37)) & np.uint64(7)).astype(np.int64)
    cw1 = ((blocks >> np.uint64(34)) & np.uint64(7)).astype(np.int64)

    # individual mode
    ir0 = ((blocks >> np.uint64(60)) & np.uint64(0xF)).astype(np.int32)
    ir1 = ((blocks >> np.uint64(56)) & np.uint64(0xF)).astype(np.int32)
    ig0 = ((blocks >> np.uint64(52)) & np.uint64(0xF)).astype(np.int32)
    ig1 = ((blocks >> np.uint64(48)) & np.uint64(0xF)).astype(np.int32)
    ib0 = ((blocks >> np.uint64(44)) & np.uint64(0xF)).astype(np.int32)
    ib1 = ((blocks >> np.uint64(40)) & np.uint64(0xF)).astype(np.int32)
    ir0 = (ir0 << 4) | ir0
    ir1 = (ir1 << 4) | ir1
    ig0 = (ig0 << 4) | ig0
    ig1 = (ig1 << 4) | ig1
    ib0 = (ib0 << 4) | ib0
    ib1 = (ib1 << 4) | ib1

    # differential mode
    dr0 = ((blocks >> np.uint64(59)) & np.uint64(0x1F)).astype(np.int32)
    dg0 = ((blocks >> np.uint64(51)) & np.uint64(0x1F)).astype(np.int32)
    db0 = ((blocks >> np.uint64(43)) & np.uint64(0x1F)).astype(np.int32)
    dr = ((blocks >> np.uint64(56)) & np.uint64(7)).astype(np.int32)
    dg = ((blocks >> np.uint64(48)) & np.uint64(7)).astype(np.int32)
    db = ((blocks >> np.uint64(40)) & np.uint64(7)).astype(np.int32)
    dr = np.where(dr >= 4, dr - 8, dr)
    dg = np.where(dg >= 4, dg - 8, dg)
    db = np.where(db >= 4, db - 8, db)
    dr1 = dr0 + dr
    dg1 = dg0 + dg
    db1 = db0 + db
    # clamp invalid ETC1 differential values (should be ETC2 modes; rare)
    dr0 = np.clip(dr0, 0, 31)
    dg0 = np.clip(dg0, 0, 31)
    db0 = np.clip(db0, 0, 31)
    dr1 = np.clip(dr1, 0, 31)
    dg1 = np.clip(dg1, 0, 31)
    db1 = np.clip(db1, 0, 31)
    dr0 = (dr0 << 3) | (dr0 >> 2)
    dg0 = (dg0 << 3) | (dg0 >> 2)
    db0 = (db0 << 3) | (db0 >> 2)
    dr1 = (dr1 << 3) | (dr1 >> 2)
    dg1 = (dg1 << 3) | (dg1 >> 2)
    db1 = (db1 << 3) | (db1 >> 2)

    r0 = np.where(diff, dr0, ir0)
    g0 = np.where(diff, dg0, ig0)
    b0 = np.where(diff, db0, ib0)
    r1 = np.where(diff, dr1, ir1)
    g1 = np.where(diff, dg1, ig1)
    b1 = np.where(diff, db1, ib1)

    # per-pixel index m = x + y*4
    pix = np.empty((blocks.size, 16, 4), dtype=np.uint8)
    for y in range(4):
        for x in range(4):
            m = x + y * 4
            idx = (((blocks >> np.uint64(m + 16)) & np.uint64(1)) << np.uint64(1)) | \
                  ((blocks >> np.uint64(m)) & np.uint64(1))
            idx = idx.astype(np.int64)
            use1 = (y >= 2) if True else False  # placeholder, replaced below
            # flip=0: split left/right (x>=2); flip=1: split top/bottom (y>=2)
            use1 = np.where(flip, y >= 2, x >= 2)
            cw = np.where(use1, cw1, cw0)
            rr = np.where(use1, r1, r0) + MOD[cw, idx]
            gg = np.where(use1, g1, g0) + MOD[cw, idx]
            bb = np.where(use1, b1, b0) + MOD[cw, idx]
            pix[:, y * 4 + x, 0] = np.clip(rr, 0, 255)
            pix[:, y * 4 + x, 1] = np.clip(gg, 0, 255)
            pix[:, y * 4 + x, 2] = np.clip(bb, 0, 255)
            pix[:, y * 4 + x, 3] = 255

    img = pix.reshape(bh, bw, 4, 4, 4).transpose(0, 2, 1, 3, 4).reshape(bh * 4, bw * 4, 4)
    img = img[:oh if oh else h, :ow if ow else w]
    return Image.fromarray(img, "RGBA")


def main():
    if len(sys.argv) != 3:
        print("usage: python tools/etc1.py in.pkm out.png")
        return 2
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    img = decode_pkm(data)
    img.save(sys.argv[2])
    print("ok", img.size, "->", sys.argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
