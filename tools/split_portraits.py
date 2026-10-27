#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Split 《叫我大掌柜》 hero/friend portrait pages into transparent PNGs.

The ETC1 texture page stores a colour copy on top and a white alpha mask below,
separated by a black band.  This script:
  1. finds the black band and cuts colour / mask
  2. crops both to their content bounding boxes
  3. resizes the mask to the colour bbox and applies it as alpha

Usage:
  python tools/split_portraits.py --assets C:\\Users\\林\\Documents\\大掌柜_assets --out C:\\Users\\林\\Documents\\大掌柜_assets\\clean
"""

import argparse
import csv
import os
import sys

import numpy as np
from PIL import Image


def split_portrait(path: str) -> tuple:
    im = Image.open(path).convert("RGB")
    arr = np.asarray(im).astype(np.int16)
    gray = arr.mean(axis=2)
    h, w = gray.shape

    # 1) first long near-black horizontal band after the top 8%
    dark = gray < 16
    row_dark = dark.mean(axis=1)
    best = None
    in_band = False
    for y in range(int(h * 0.08), h - 4):
        if row_dark[y] > 0.92:
            if not in_band:
                start = y
                in_band = True
        elif in_band:
            end = y
            in_band = False
            if best is None or (end - start) > (best[1] - best[0]):
                best = (start, end)
    if best is None:
        best = (h // 2, h // 2 + 1)
    cut = (best[0] + best[1]) // 2

    top = arr[:cut]
    bot = arr[cut:]

    # 2) colour bbox: saturated pixels
    mx = top.max(axis=2)
    mn = top.min(axis=2)
    colorful = ((mx - mn) > 24) & (mx > 24)
    ys, xs = np.where(colorful)
    if len(xs) == 0:
        ys, xs = np.where(top.max(axis=2) > 24)
    if len(xs) == 0:
        raise ValueError("no colour pixels")
    cy0, cy1 = int(ys.min()), int(ys.max()) + 1
    cx0, cx1 = int(xs.min()), int(xs.max()) + 1

    # 3) mask bbox: bright near-white pixels below the band
    white = bot.mean(axis=2) > 235
    ys, xs = np.where(white)
    if len(xs) == 0:
        raise ValueError("no alpha mask")
    my0, my1 = int(ys.min()), int(ys.max()) + 1
    mx0, mx1 = int(xs.min()), int(xs.max()) + 1

    color = Image.fromarray(top[cy0:cy1, cx0:cx1].astype(np.uint8), "RGB")
    mask = Image.fromarray((white[my0:my1, mx0:mx1] * 255).astype(np.uint8), "L")
    if mask.size != color.size:
        mask = mask.resize(color.size, Image.LANCZOS)
    out = color.convert("RGBA")
    out.putalpha(mask)

    alpha = np.asarray(out)[:, :, 3]
    rgb = np.asarray(out)[:, :, :3].mean(axis=2)
    black = float(((alpha > 128) & (rgb < 10)).mean())
    return out, black


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--kind", choices=["patrons", "beauty", "all"], default="all")
    args = ap.parse_args()

    base = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    jobs = []
    if args.kind in ("patrons", "all"):
        jobs.append(("patrons", os.path.join(base, "textures", "png_from_pkm", "cn", "newGui", "Patrons"),
                     os.path.join(out_root, "heroes")))
    if args.kind in ("beauty", "all"):
        jobs.append(("beauty", os.path.join(base, "textures", "png_from_pkm", "cn", "newGui", "Beauty"),
                     os.path.join(out_root, "friends")))

    rows = []
    ok = fail = 0
    for kind, src_root, dst_root in jobs:
        os.makedirs(dst_root, exist_ok=True)
        if not os.path.isdir(src_root):
            print("missing", src_root)
            continue
        for name in sorted(os.listdir(src_root)):
            d = os.path.join(src_root, name)
            if not os.path.isdir(d):
                continue
            # main full-body page is 3.png; fall back to the largest png
            cand = os.path.join(d, "3.png")
            if not os.path.exists(cand):
                pngs = [os.path.join(d, f) for f in os.listdir(d) if f.lower().endswith(".png")]
                if not pngs:
                    rows.append([kind, name, "", "", "", "no-png"])
                    fail += 1
                    continue
                cand = max(pngs, key=os.path.getsize)
            try:
                img, black = split_portrait(cand)
                dst = os.path.join(dst_root, name + ".png")
                img.save(dst)
                status = "ok" if black <= 0.02 else "artifacts"
                rows.append([kind, name, cand, dst, img.size, black, status])
                ok += 1
            except Exception as e:  # noqa: BLE001
                rows.append([kind, name, cand, "", "", "", "FAIL: %s" % e])
                fail += 1

    man = os.path.join(out_root, "portraits_manifest.csv")
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "source", "output", "size", "black_ratio", "status"])
        w.writerows(rows)
    print("ok=%d fail=%d" % (ok, fail))
    print("manifest:", man)


if __name__ == "__main__":
    main()
