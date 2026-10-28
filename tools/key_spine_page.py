#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Colour-key a spine atlas page with a border-connected background."""

import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


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


def key(path, out_path):
    im = Image.open(path).convert("RGB")
    arr = np.asarray(im).astype(np.int16)
    # top page only: first long black band after the top 5%
    gray = arr.mean(2)
    row_dark = (gray < 16).mean(1)
    cut = len(row_dark)
    in_band = False
    start = 0
    for y in range(int(len(row_dark) * 0.05), len(row_dark) - 4):
        if row_dark[y] > 0.92:
            if not in_band:
                start = y
                in_band = True
        elif in_band:
            if y - start > 40:
                cut = start
                break
            in_band = False
    arr = arr[:cut]
    mx = arr.max(2)
    ys, xs = np.where(mx > 8)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    crop = arr[y0:y1, x0:x1]
    solid = crop.max(2) > 8
    # add a transparent ring so the outside background is border-connected
    padded = np.zeros((solid.shape[0] + 2, solid.shape[1] + 2), bool)
    padded[1:-1, 1:-1] = solid
    alpha = fill_enclosed(padded)[1:-1, 1:-1]
    alpha_img = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(0.5))
    out = Image.fromarray(crop.astype(np.uint8), "RGB").convert("RGBA")
    out.putalpha(alpha_img)
    out.save(out_path)
    return out.size


if __name__ == "__main__":
    print(key(sys.argv[1], sys.argv[2]))
