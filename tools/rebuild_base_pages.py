#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rebuild full-body pages from the base package's split textures.

``textures/png_from_pkm[/cn]/newGui/{Patrons,Beauty}/<id>/3.png`` is a Cocos
split texture: the colour page occupies the top half (2048 px of a 4096 px
image) and an identically laid-out white alpha mask the bottom half.  The
older portraits_v2 pages were keyed from black instead, which left large
opaque grey/white blocks and ate real parts of the character.

This tool masks the colour page with the shipped mask and writes clean RGBA
pages for the assembler to prefer over the broken v2 page.

Output:
  clean/portraits_v3/rendered/patrons_page/<id>.png
  clean/portraits_v3/rendered/beauty_page/<id>.png

Usage:
  python tools/rebuild_base_pages.py
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from portrait_alpha import soft_alpha  # noqa: E402

KINDS = (("Patrons", "patrons"), ("Beauty", "beauty"))


def build_page(src, dst, threshold=32):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    split = h // 2
    color = im.crop((0, 0, w, split))
    mask = np.asarray(im.crop((0, split, w, h)).convert("L"))
    alpha = soft_alpha(mask)
    arr = np.asarray(color.convert("RGBA")).copy()
    arr[:, :, 3] = alpha
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
    trees = [os.path.join(base, "cn", "newGui"), os.path.join(base, "newGui")]

    built = 0
    for folder, kind in KINDS:
        # cn first: it is the localised copy when both exist.
        seen = {}
        for tree in trees:
            d = os.path.join(tree, folder)
            if not os.path.isdir(d):
                continue
            for cid in sorted(os.listdir(d)):
                if not os.path.isdir(os.path.join(d, cid)):
                    continue
                src = os.path.join(d, cid, "3.png")
                if os.path.exists(src):
                    seen.setdefault(cid, src)
        for cid, src in sorted(seen.items()):
            dst = os.path.join(out_root, kind + "_page", cid + ".png")
            size = build_page(src, dst)
            built += 1
            print("%-8s %-7s %s <- %s" % (cid, kind, size, src))
    print("built", built)


if __name__ == "__main__":
    main()
