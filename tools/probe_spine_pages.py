#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Probe the two-page layout of spine/*/skeleton.png files."""

import sys

import numpy as np
from PIL import Image


def probe(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im)
    g = a.mean(2)
    rd = (g < 16).mean(1)
    bands = []
    in_band = False
    start = 0
    for y, v in enumerate(rd):
        if v > 0.92:
            if not in_band:
                start = y
                in_band = True
        elif in_band:
            bands.append((start, y))
            in_band = False
    if in_band:
        bands.append((start, len(rd)))
    print(path)
    print("  size", im.size, "black bands", bands)
    # content bbox of the top page and of the region after the first band
    cuts = [0] + [b[1] for b in bands] + [im.height]
    for i in range(len(cuts) - 1):
        y0, y1 = cuts[i], cuts[i + 1]
        if y1 - y0 < 20:
            continue
        page = a[y0:y1]
        mx = page.max(2)
        ys, xs = np.where(mx > 8)
        if len(xs) == 0:
            print("  page", i, (y0, y1), "empty")
            continue
        print("  page", i, (y0, y1), "bbox", (int(xs.min()), int(ys.min()) + y0, int(xs.max()) + 1, int(ys.max()) + 1 + y0))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        probe(p)
