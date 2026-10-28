#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract every available patron / beauty portrait from the unpacked assets.

Why this exists
---------------
`split_portraits.py` only reads `cn/newGui/{Patrons,Beauty}` (26 + 34 ids),
which is just the small CN supplement.  The bulk of the art lives in:

  textures/png_from_pkm/newGui/Patrons       134 dirs, 53 full-body 3.png
  textures/png_from_pkm/newGui/Beauty         85 dirs,  8 full-body 3.png
  textures/png_from_pkm/spine/patrons         85 full-body pages
  textures/png_from_pkm/spine/beauty          80 full-body pages
  textures/png_from_pkm/cn/spine/patrons      11 full-body pages

`newGui/*/3.png` and `2.png`/`4.png` are colour page + white alpha mask pages
and are split with `split_portraits.split_portrait`.  `spine/*/skeleton.png`
is a colour render on a pure-black background (the lower half is a body
silhouette, not a reliable alpha mask), so we key out black and fill enclosed
holes instead.

Output (outside the Godot project, under the unpacked assets):
  clean/portraits_v2/heroes_full/    best full-body per patron id
  clean/portraits_v2/heroes_page/    full-body 3.png pages
  clean/portraits_v2/heroes_half/    half-body 2.png pages
  clean/portraits_v2/heroes_head/    square 1.png heads
  clean/portraits_v2/friends_full/   best full-body per beauty id
  clean/portraits_v2/friends_page/   full-body 3.png pages
  clean/portraits_v2/friends_half/   half-body 4.png pages
  clean/portraits_v2/friends_head/   square 1.png heads
  clean/portraits_v2/manifest.csv
  clean/portraits_v2/coverage.csv

Usage:
  python tools/extract_portrait_sets.py
  python tools/extract_portrait_sets.py --assets C:\\...\\大掌柜_assets --out C:\\...\\clean\\portraits_v2
"""

import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from split_portraits import split_portrait  # noqa: E402


# ---------------------------------------------------------------- config ids
def load_config_ids(assets):
    path = os.path.join(assets, "text", "cn", "allJson", "AllJson2.json")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    def rows(key):
        value = data[key]
        if isinstance(value, str):
            value = json.loads(value)
        table = value[key] if isinstance(value, dict) else value
        header = table[1]
        return [dict(zip(header, row)) for row in table[2:]]

    patrons = {str(r["id"]): r for r in rows("PatronsDB")}
    beauties = {str(r["id"]): r for r in rows("BeautyDB")}
    return patrons, beauties


# ------------------------------------------------------------- alpha helpers
def _fill_enclosed_holes(alpha):
    """alpha: bool HxW.  Fill black holes that are not connected to the border."""
    h, w = alpha.shape
    canvas = np.zeros((h + 4, w + 4), dtype=np.uint8)
    canvas[2:2 + h, 2:2 + w] = alpha.astype(np.uint8) * 255
    mask = Image.fromarray(canvas, "L")
    for point in ((0, 0), (mask.width - 1, 0), (0, mask.height - 1), (mask.width - 1, mask.height - 1)):
        ImageDraw.floodfill(mask, point, 128, thresh=0)
    arr = np.asarray(mask)
    out = np.where(arr == 128, 0, 255).astype(np.uint8)
    return out[2:2 + h, 2:2 + w]


def _colour_page_only(arr):
    """Drop the white alpha-silhouette page stacked under the colour page.

    `spine/*/skeleton.png` is  colour page  +  black band  +  white mask page.
    Only the top page is the illustration; the mask is a body silhouette and
    must not be treated as colour.
    """
    gray = arr.mean(axis=2)
    h = gray.shape[0]
    row_dark = (gray < 16).mean(axis=1)
    best = None
    in_band = False
    start = 0
    for y in range(int(h * 0.05), h - 4):
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
        return arr
    cut = (best[0] + best[1]) // 2
    return arr[:cut]


def color_key_page(path):
    """RGBA from a full-body page rendered on a pure black background."""
    im = Image.open(path)
    rgba = im.convert("RGBA")
    alpha = np.asarray(rgba)[:, :, 3]
    if int(alpha.min()) < 250:  # already has real alpha
        bbox = rgba.getbbox()
        return rgba.crop(bbox) if bbox else rgba, 0.0

    rgb = im.convert("RGB")
    arr = np.asarray(rgb).astype(np.int16)
    arr = _colour_page_only(arr)
    mx = arr.max(axis=2)
    ys, xs = np.where(mx > 8)
    if len(xs) == 0:
        raise ValueError("no colour pixels")
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    crop = arr[y0:y1, x0:x1]
    solid = crop.max(axis=2) > 8
    alpha_arr = _fill_enclosed_holes(solid)
    alpha_img = Image.fromarray(alpha_arr, "L").filter(ImageFilter.GaussianBlur(0.5))
    out = Image.fromarray(crop.astype(np.uint8), "RGB").convert("RGBA")
    out.putalpha(alpha_img)

    # black_ratio is only a rough quality flag for this method
    a = np.asarray(out)[:, :, 3]
    c = np.asarray(out)[:, :, :3].mean(axis=2)
    black = float(((a > 128) & (c < 10)).mean())
    return out, black


# ------------------------------------------------------------------- scan
def iter_dirs(root):
    if not os.path.isdir(root):
        return
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name)
        if os.path.isdir(path) and name != "000000":
            yield name, path


def process_jobs(assets, out_root):
    jobs = [
        # kind, source rel, filename, method
        ("heroes_full", "textures/png_from_pkm/spine/patrons", "skeleton.png", "color"),
        ("heroes_full", "textures/png_from_pkm/cn/spine/patrons", "skeleton.png", "color"),
        ("heroes_page", "textures/png_from_pkm/newGui/Patrons", "3.png", "mask"),
        ("heroes_page", "textures/png_from_pkm/cn/newGui/Patrons", "3.png", "mask"),
        ("heroes_half", "textures/png_from_pkm/newGui/Patrons", "2.png", "mask"),
        ("heroes_half", "textures/png_from_pkm/cn/newGui/Patrons", "2.png", "mask"),
        ("heroes_head", "textures/png_from_pkm/newGui/Patrons", "1.png", "mask"),
        ("heroes_head", "textures/png_from_pkm/cn/newGui/Patrons", "1.png", "mask"),
        ("friends_full", "textures/png_from_pkm/spine/beauty", "skeleton.png", "color"),
        ("friends_page", "textures/png_from_pkm/newGui/Beauty", "3.png", "mask"),
        ("friends_page", "textures/png_from_pkm/cn/newGui/Beauty", "3.png", "mask"),
        ("friends_half", "textures/png_from_pkm/newGui/Beauty", "4.png", "mask"),
        ("friends_half", "textures/png_from_pkm/cn/newGui/Beauty", "4.png", "mask"),
        ("friends_head", "textures/png_from_pkm/newGui/Beauty", "1.png", "mask"),
        ("friends_head", "textures/png_from_pkm/cn/newGui/Beauty", "1.png", "mask"),
    ]

    rows = []
    seen = set()
    for kind, rel, filename, method in jobs:
        src_root = os.path.join(assets, *rel.split("/"))
        dst_root = os.path.join(out_root, kind)
        os.makedirs(dst_root, exist_ok=True)
        for cid, folder in iter_dirs(src_root):
            if (kind, cid) in seen:
                continue  # first source wins (top-level before cn supplement)
            src = os.path.join(folder, filename)
            if not os.path.exists(src):
                continue
            dst = os.path.join(dst_root, cid + ".png")
            try:
                if method == "color":
                    img, black = color_key_page(src)
                else:
                    img, black = split_portrait(src)
                img.save(dst, optimize=True)
                # For colour-key pages the ratio only means "lots of dark paint",
                # not a failed mask, so only flag mask-split pages.
                status = "ok" if (method == "color" or black <= 0.02) else "artifacts"
                rows.append([kind, cid, src, dst, "%dx%d" % img.size, "%.4f" % black, method, status])
                seen.add((kind, cid))
            except Exception as exc:  # noqa: BLE001
                rows.append([kind, cid, src, "", "", "", method, "FAIL: %s" % exc])
    return rows


# ---------------------------------------------------------------- coverage
def write_coverage(out_root, patrons, beauties, rows):
    produced = {}
    for kind, cid, _src, dst, size, _black, _method, status in rows:
        if dst and status in ("ok", "artifacts"):
            produced.setdefault(kind, {})[cid] = (dst, size, status)

    def pick(kind, cid):
        return produced.get(kind, {}).get(cid)

    with open(os.path.join(out_root, "coverage.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["type", "id", "name_key", "quality", "full", "full_size", "half", "half_size", "head", "status"])
        for cid, rec in patrons.items():
            full = pick("heroes_full", cid) or pick("heroes_page", cid)
            half = pick("heroes_half", cid)
            head = pick("heroes_head", cid)
            status = "full" if full else ("half-only" if half else "missing")
            w.writerow(["patron", cid, rec.get("name", ""), rec.get("quality", ""),
                        full[0] if full else "", full[1] if full else "",
                        half[0] if half else "", half[1] if half else "",
                        head[0] if head else "", status])
        for cid, rec in beauties.items():
            full = pick("friends_full", cid) or pick("friends_page", cid)
            half = pick("friends_half", cid)
            head = pick("friends_head", cid)
            status = "full" if full else ("half-only" if half else "missing")
            w.writerow(["beauty", cid, rec.get("name", ""), rec.get("quality", ""),
                        full[0] if full else "", full[1] if full else "",
                        half[0] if half else "", half[1] if half else "",
                        head[0] if head else "", status])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v2")
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)

    patrons, beauties = load_config_ids(assets)
    rows = process_jobs(assets, out_root)

    with open(os.path.join(out_root, "manifest.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "source", "output", "size", "black_ratio", "method", "status"])
        w.writerows(rows)

    write_coverage(out_root, patrons, beauties, rows)

    counts = {}
    for kind, _cid, _src, dst, _size, _black, _method, status in rows:
        if dst and status in ("ok", "artifacts"):
            counts[kind] = counts.get(kind, 0) + 1
    print("out:", out_root)
    for kind in sorted(counts):
        print("  %-14s %d" % (kind, counts[kind]))
    print("manifest:", os.path.join(out_root, "manifest.csv"))
    print("coverage:", os.path.join(out_root, "coverage.csv"))


if __name__ == "__main__":
    main()
