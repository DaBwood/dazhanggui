#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build an RGBA Spine atlas page by keying each packed region separately.

The raw skeleton.png is a colour atlas page followed by a *composed* white
silhouette, so the silhouette cannot be used as the atlas alpha.  Instead we
key the black background inside each atlas region and fill only holes that are
enclosed by that region, which keeps black clothing opaque and drops the gaps
between parts.
"""

import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def parse_atlas(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    page = {}
    regions = []
    cur = None
    for line in lines:
        s = line.strip()
        if not s:
            continue
        if not line.startswith(" ") and s.startswith("size:"):
            w, h = s.split(":", 1)[1].split(",")
            page["size"] = (int(w), int(h))
        elif not line.startswith(" ") and s.startswith("format:"):
            page["format"] = s.split(":", 1)[1].strip()
        elif not line.startswith(" ") and ":" not in s:
            cur = {"name": s}
            regions.append(cur)
        elif cur is not None and ":" in s:
            k, v = s.split(":", 1)
            cur[k.strip()] = v.strip()
    return page, regions


def fill_enclosed(alpha):
    h, w = alpha.shape
    canvas = np.zeros((h + 4, w + 4), dtype=np.uint8)
    canvas[2:2 + h, 2:2 + w] = alpha.astype(np.uint8) * 255
    mask = Image.fromarray(canvas, "L")
    for point in ((0, 0), (mask.width - 1, 0), (0, mask.height - 1), (mask.width - 1, mask.height - 1)):
        ImageDraw.floodfill(mask, point, 128, thresh=0)
    arr = np.asarray(mask)
    out = np.where(arr == 128, 0, 255).astype(np.uint8)
    return out[2:2 + h, 2:2 + w]


def build(raw_path, atlas_path, out_path, threshold=2):
    page, regions = parse_atlas(atlas_path)
    W, H = page["size"]
    im = Image.open(raw_path).convert("RGB")
    arr = np.asarray(im)[:H, :W]
    alpha = np.zeros((H, W), dtype=np.uint8)
    empty = []
    for r in regions:
        if "xy" not in r or "size" not in r:
            continue
        x, y = (int(v) for v in r["xy"].split(","))
        w, h = (int(v) for v in r["size"].split(","))
        rect = arr[y:y + h, x:x + w]
        solid = rect.max(axis=2) > threshold
        if not solid.any():
            empty.append(r["name"])
            continue
        # No hole filling: the atlas background is pure black, and dark
        # clothing is not pure black.  Filling would turn thin props into
        # opaque rectangles.
        a = (solid * 255).astype(np.uint8)
        alpha[y:y + h, x:x + w] = a
    out = Image.fromarray(arr, "RGB").convert("RGBA")
    out.putalpha(Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(0.3)))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path, optimize=True)
    return out.size, len(regions), empty


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: build_spine_atlas_rgba.py <skeleton.png> <skeleton.atlas> <out.png>")
    print(build(sys.argv[1], sys.argv[2], sys.argv[3]))
