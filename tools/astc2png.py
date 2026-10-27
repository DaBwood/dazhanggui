#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Decode 《叫我大掌柜》 .astc textures (lyqszp + XOR 0x70 + gzip + ASTC).

Usage:
  python tools/astc2png.py in.astc out.png
  python tools/astc2png.py --dir in_dir out_dir
"""

import argparse
import gzip
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, r"C:\Users\林\Documents\大掌柜_assets\_pylibs")
import texture2ddecoder  # noqa: E402


def decode_astc_bytes(raw: bytes) -> Image.Image:
    data = raw
    if data[:6] == b"lyqszp":
        data = bytes(b ^ 0x70 for b in data[6:])
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if len(data) < 16:
        raise ValueError("too short")
    magic, bx, by, bz, dx, dy, dz = struct.unpack("<IBBB3s3s3s", data[:16])
    if magic != 0x5CA1AB13:
        raise ValueError("not ASTC magic: %08x" % magic)
    w = dx[0] | (dx[1] << 8) | (dx[2] << 16)
    h = dy[0] | (dy[1] << 8) | (dy[2] << 16)
    pixels = texture2ddecoder.decode_astc(data[16:], w, h, bx, by)
    return Image.frombytes("RGBA", (w, h), pixels, "raw", "BGRA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--dir", action="store_true")
    args = ap.parse_args()

    if args.dir:
        os.makedirs(args.dst, exist_ok=True)
        n = 0
        for root, _, files in os.walk(args.src):
            for f in files:
                if not f.lower().endswith(".astc"):
                    continue
                p = os.path.join(root, f)
                rel = os.path.relpath(p, args.src)
                out = os.path.join(args.dst, os.path.splitext(rel)[0] + ".png")
                os.makedirs(os.path.dirname(out), exist_ok=True)
                try:
                    decode_astc_bytes(open(p, "rb").read()).save(out)
                    n += 1
                except Exception as e:
                    print("FAIL", rel, e)
        print("ok", n)
    else:
        decode_astc_bytes(open(args.src, "rb").read()).save(args.dst)
        print("ok", args.dst)


if __name__ == "__main__":
    main()
