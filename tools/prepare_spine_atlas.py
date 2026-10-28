#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build a renderable RGBA atlas page from a two-page spine skeleton.png.

The raw page is:  colour atlas page (W x H)  +  black band  +  white mask.
The mask is cropped to the colour content bbox, so it must be resized and
placed back at that bbox before it can be used as the page alpha.
"""

import os
import re
import sys

import numpy as np
from PIL import Image


def page_size(atlas_path):
    text = open(atlas_path, encoding="utf-8").read()
    m = re.search(r"^size:\s*(\d+)\s*,\s*(\d+)", text, re.M)
    if not m:
        raise ValueError("no page size in atlas")
    return int(m.group(1)), int(m.group(2))


def long_bands(row_dark, min_len=40):
    bands = []
    in_band = False
    start = 0
    for y, v in enumerate(row_dark):
        if v > 0.92:
            if not in_band:
                start = y
                in_band = True
        elif in_band:
            if y - start >= min_len:
                bands.append((start, y))
            in_band = False
    if in_band and len(row_dark) - start >= min_len:
        bands.append((start, len(row_dark)))
    return bands


def prepare(raw_path, atlas_path, out_path):
    W, H = page_size(atlas_path)
    im = Image.open(raw_path).convert("RGB")
    arr = np.asarray(im)
    if arr.shape[0] < H:
        raise ValueError("raw page shorter than atlas page")

    top = arr[:H, :W]
    mx = top.max(axis=2)
    ys, xs = np.where(mx > 8)
    if len(xs) == 0:
        raise ValueError("no colour content")
    cx0, cx1 = int(xs.min()), int(xs.max()) + 1
    cy0, cy1 = int(ys.min()), int(ys.max()) + 1

    gray = arr.mean(axis=2)
    bands = long_bands((gray < 16).mean(axis=1))
    mask_start = None
    for b0, b1 in bands:
        if b0 >= H - 8:
            mask_start = b1
            break
    if mask_start is None:
        raise ValueError("no mask page band")
    mask_end = len(arr)
    for b0, b1 in bands:
        if b0 >= mask_start + 8:
            mask_end = b0
            break
    mask_region = arr[mask_start:mask_end, :W]
    white = mask_region.mean(axis=2) > 235
    ys, xs = np.where(white)
    if len(xs) == 0:
        raise ValueError("no mask content")
    mx0, mx1 = int(xs.min()), int(xs.max()) + 1
    my0, my1 = int(ys.min()), int(ys.max()) + 1
    mask = Image.fromarray((white[my0:my1, mx0:mx1] * 255).astype(np.uint8), "L")

    cw, ch = cx1 - cx0, cy1 - cy0
    if mask.size != (cw, ch):
        mask = mask.resize((cw, ch), Image.LANCZOS)

    alpha = Image.new("L", (W, H), 0)
    alpha.paste(mask, (cx0, cy0))
    out = Image.fromarray(top, "RGB").convert("RGBA")
    out.putalpha(alpha)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path, optimize=True)
    return out.size, (cx0, cy0, cx1, cy1), (mx0, my0, mx1, my1)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: prepare_spine_atlas.py <skeleton.png> <skeleton.atlas> <out.png>")
    print(prepare(sys.argv[1], sys.argv[2], sys.argv[3]))
