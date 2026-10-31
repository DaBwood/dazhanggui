#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rebuild half / head crops from the base package's split textures.

Base ``newGui/{Patrons,Beauty}/<id>/2.png`` and ``/4.png`` are also Cocos
split textures: colour page on top, packed white alpha mask on the bottom.
The old portraits_v2 halves/heads keyed black, which left rectangular blocks
and ate parts of the character.

Layer convention:
  Patrons: /2 = half (186x~308), /4 = head
  Beauty:  /4 = half (square card), /2 = head

Output:
  clean/portraits_v3/rendered/patrons_half|patrons_head/<id>.png
  clean/portraits_v3/rendered/beauty_half|beauty_head/<id>.png

Usage:
  python tools/rebuild_base_parts.py
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from portrait_alpha import soft_alpha  # noqa: E402

KINDS = (
    ("Patrons", "patrons", "2", "4"),
    ("Beauty", "beauty", "4", "2"),
)


def build_part(src, dst):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    split = h // 2
    color = im.crop((0, 0, w, split)).convert("RGBA")
    mask = np.asarray(im.crop((0, split, w, h)).convert("L"))
    arr = np.asarray(color).copy()
    arr[:, :, 3] = soft_alpha(mask)
    out = Image.fromarray(arr, "RGBA")
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst, optimize=True)
    return out.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered")
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    base = os.path.join(assets, "textures", "png_from_pkm")
    # Default tree first; the cn copy is a fallback for localised-only assets.
    trees = [os.path.join(base, "newGui"), os.path.join(base, "cn", "newGui")]

    built = 0
    for folder, kind, half_suffix, head_suffix in KINDS:
        found = {}
        for tree in trees:
            d = os.path.join(tree, folder)
            if not os.path.isdir(d):
                continue
            for cid in sorted(os.listdir(d)):
                if not os.path.isdir(os.path.join(d, cid)):
                    continue
                for suffix in (half_suffix, head_suffix):
                    src = os.path.join(d, cid, suffix + ".png")
                    if os.path.exists(src):
                        found.setdefault((cid, suffix), src)
        for (cid, suffix), src in sorted(found.items()):
            layer = "half" if suffix == half_suffix else "head"
            dst = os.path.join(out_root, kind + "_" + layer, cid + ".png")
            size = build_part(src, dst)
            built += 1
            print("%-8s %-7s %-4s %s <- %s" % (cid, kind, layer, size, src))
    print("built", built)


if __name__ == "__main__":
    main()
