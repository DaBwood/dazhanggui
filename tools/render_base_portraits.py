#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Re-render base-package Spine portraits with their packed alpha masks.

Base Spine textures are also 2x tall: the colour atlas page on top and an
identically laid-out white mask in the bottom half.  The old renderer keyed
black instead, leaving opaque grey/white rectangles around ships, clouds and
props.  This tool masks each page, stages it and renders with spine-webgl.

Output defaults to clean/portraits_v3/rendered/<kind>/<id>.png.

Usage:
  python tools/render_base_portraits.py --kind patrons --ids 102533 102541
"""

import argparse
import os
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_spine_atlas_rgba import build as build_atlas, parse_atlas_pages  # noqa: E402
from render_hotupdate_portraits import render_one, start_server  # noqa: E402
from render_missing_portraits import resolve  # noqa: E402

TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"
HIDE = "dimian,cao,ground,grass,shui,bo"


def prepare_stage(stage_root, kind, cid, src):
    d = os.path.join(stage_root, kind, cid)
    os.makedirs(d, exist_ok=True)
    shutil.copy2(src["data"], os.path.join(d, "skeleton.bin" if src["fmt"] == "bin" else "skeleton.json"))
    atlas_text = open(src["atlas"], encoding="utf-8").read()
    with open(os.path.join(d, "skeleton.atlas"), "w", encoding="utf-8", newline="") as f:
        f.write(atlas_text)

    pages = parse_atlas_pages(atlas_text)
    tex_dir = os.path.dirname(src["texture"])
    for index, page in enumerate(pages):
        tex = os.path.join(tex_dir, page["name"])
        if not os.path.exists(tex):
            tex = os.path.join(tex_dir, "skeleton.png" if index == 0 else "skeleton%d.png" % (index + 1))
        page_h = page["size"][1]
        mask_path = None
        out_path = os.path.join(d, page["name"])
        im = Image.open(tex)
        if im.height >= page_h * 2:
            # Packed mask: bottom half, same layout as the colour page.
            mask_path = os.path.join(d, "_mask_%d.png" % index)
            im.crop((0, im.height // 2, im.width, im.height // 2 + page_h)).save(mask_path)
        size, regions, empty = build_atlas(tex, None, out_path, page_index=index,
                                           atlas_text=atlas_text, mask_path=mask_path)
        if mask_path:
            os.remove(mask_path)
        print("    page %d %s -> %s (%d regions) mask=%s"
              % (index, page["name"], size, regions, bool(mask_path)))
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered")
    ap.add_argument("--kind", choices=("patrons", "beauty"), default="patrons")
    ap.add_argument("--ids", nargs="+", required=True)
    ap.add_argument("--port", type=int, default=8778)
    ap.add_argument("--width", type=int, default=1400)
    ap.add_argument("--height", type=int, default=1800)
    ap.add_argument("--hide", default=HIDE)
    ap.add_argument("--min-area", type=int, default=200)
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.join(os.path.abspath(args.out), args.kind)
    os.makedirs(out_root, exist_ok=True)
    base_root = os.path.join(TEMP, "spine_batch_base")
    stage_root = os.path.join(base_root, "stage")
    os.makedirs(stage_root, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("_spine_render_multi.html", "spine-webgl.js"):
        for src in (os.path.join(here, name), os.path.join(TEMP, "spine_batch", name), os.path.join(TEMP, name)):
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(base_root, name))
                break

    httpd = start_server(base_root, args.port)
    profile = os.path.join(base_root, "edgeprofile")
    try:
        for cid in args.ids:
            src = resolve(assets, args.kind, cid)
            if not src:
                print("%s no base skeleton" % cid)
                continue
            try:
                prepare_stage(stage_root, args.kind, cid, src)
            except Exception as exc:  # noqa: BLE001
                print("%s prep FAIL %s" % (cid, exc))
                continue
            dst = os.path.join(out_root, cid + ".png")
            ok, info = render_one(stage_root, cid, dst, args.port, profile,
                                  args.width, args.height, args.hide,
                                  min_area=args.min_area, kind=args.kind, scale=args.scale)
            print("%s %s %s" % (cid, "OK" if ok else "FAIL", info))
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    main()
