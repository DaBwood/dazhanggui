#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract official half / head crops for hot-update-only patrons.

``newGui/Patrons/<id>/2`` and ``/4`` are Cocos split textures: the colour
image occupies the top half and an identically laid-out white alpha mask the
bottom half.  Masking them gives the same kind of 2.png / 4.png crop that the
base package uses for portraits_v2.

Output:
  clean/portraits_v3/rendered/patrons_half/<id>.png
  clean/portraits_v3/rendered/patrons_head/<id>.png

Usage:
  python tools/prepare_hotupdate_parts.py --ids 102542 102543 102544
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from portrait_alpha import soft_alpha  # noqa: E402
from render_hotupdate_portraits import (  # noqa: E402
    decode_texture,
    entries_for,
    load_config,
    resource_file,
)


def split_color_mask(im, low=8):
    """Cocos split texture -> RGBA image using the bottom half as alpha."""
    w, h = im.size
    if h < 4:
        raise ValueError("too small")
    half = h // 2
    color = im.crop((0, 0, w, half)).convert("RGBA")
    mask = np.asarray(im.crop((0, half, w, h)).convert("L"))
    alpha = soft_alpha(mask, low)
    arr = np.asarray(color).copy()
    arr[:, :, 3] = alpha
    out = Image.fromarray(arr, "RGBA")
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    return out


def find_gui_texture(assets, config, path_prefix):
    """Resolve a newGui ImageAsset path (type 0) to its texture file."""
    for path, uuid, typ in entries_for(config, path_prefix):
        if typ != 0:
            continue
        tex = resource_file(assets, uuid, (".pkm", ".astc", ".png"))
        if tex:
            return tex
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered")
    ap.add_argument("--kind", default="patrons", choices=("patrons", "beauty"))
    ap.add_argument("--ids", nargs="+", default=["102542", "102543", "102544"])
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    config = load_config(assets)
    kind_dir = "Patrons" if args.kind == "patrons" else "Beauty"
    half_folder = args.kind + "_half"
    head_folder = args.kind + "_head"
    # Patrons: /2 = half (186x308), /4 = head.
    # Beauties: /4 = half (square card), /2 = head.
    if args.kind == "patrons":
        layer_suffixes = (("2", half_folder), ("4", head_folder))
    else:
        layer_suffixes = (("4", half_folder), ("2", head_folder))
    os.makedirs(os.path.join(out_root, half_folder), exist_ok=True)
    os.makedirs(os.path.join(out_root, head_folder), exist_ok=True)

    for cid in args.ids:
        for suffix, folder in layer_suffixes:
            tex = find_gui_texture(assets, config, "newGui/%s/%s/%s" % (kind_dir, cid, suffix))
            if not tex:
                print("%s /%s MISSING" % (cid, suffix))
                continue
            im = decode_texture(tex)
            crop = split_color_mask(im)
            dst = os.path.join(out_root, folder, cid + ".png")
            crop.save(dst, optimize=True)
            print("%s /%s -> %s %s from %s" % (cid, suffix, crop.size, dst, os.path.basename(tex)))


if __name__ == "__main__":
    main()
