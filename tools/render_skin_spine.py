#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render patron skin (costume) full-body portraits from skin Spine bundles.

Skin bundles live at hotupdate/skins/<skinId>/spineSkin/ and ship either
skeleton.json (Spine 3.7) or skeleton.skel (Spine 3.8), plus skeleton.atlas
and one or two .astc texture pages.  This tool decodes the ASTC pages, stages
the skeleton with the matching multi-page runtime, and renders at 2x then
Lanczos-downsamples to 1x.

Output default: clean/portraits_v3/rendered/costumes/<skinId>.png

Usage:
  python tools/render_skin_spine.py --ids 109152 109267
"""

import argparse
import csv
import gzip
import io
import os
import re
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from astc2png import decode_astc_bytes  # noqa: E402
from build_spine_atlas_rgba import parse_atlas_pages  # noqa: E402
from render_hotupdate_portraits import render_one, start_server  # noqa: E402

TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"
HERE = os.path.dirname(os.path.abspath(__file__))


def prepare_stage(root, cid, src):
    stage = os.path.join(root, "stage", "skin", cid)
    os.makedirs(stage, exist_ok=True)
    json_path = os.path.join(src, "skeleton.json")
    skel_path = os.path.join(src, "skeleton.skel")
    if os.path.exists(skel_path):
        shutil.copy2(skel_path, os.path.join(stage, "skeleton.bin"))
        page, fmt = "_spine_render_multi.html", "bin"
    elif os.path.exists(json_path):
        shutil.copy2(json_path, os.path.join(stage, "skeleton.json"))
        page, fmt = "_spine_render_multi37.html", "json"
    else:
        raise FileNotFoundError("no skeleton.json/skeleton.skel in " + src)
    shutil.copy2(os.path.join(src, "skeleton.atlas"), os.path.join(stage, "skeleton.atlas"))
    # WebGL1 cannot sample non-power-of-two textures with REPEAT wrap; such a
    # page becomes "incomplete" and samples black.  Force CLAMP for exports.
    atlas_path = os.path.join(stage, "skeleton.atlas")
    atlas_text = open(atlas_path, encoding="utf-8", errors="replace").read()
    patched = re.sub(r"(?m)^repeat:\s*xy\s*$", "repeat: none", atlas_text)
    if patched != atlas_text:
        open(atlas_path, "w", encoding="utf-8", newline="").write(patched)
    for name in os.listdir(src):
        if name.endswith(".astc"):
            im = decode_astc_bytes(open(os.path.join(src, name), "rb").read())
            im.save(os.path.join(stage, name[:-5] + ".png"))
        elif name.endswith(".png"):
            raw = open(os.path.join(src, name), "rb").read()
            if raw[:6] == b"lyqszp":
                raw = bytes(b ^ 0x70 for b in raw[6:])
                if raw[:2] == b"\x1f\x8b":
                    raw = gzip.decompress(raw)
            # Palette PNGs with a tRNS chunk can lose their transparency in
            # some WebGL texture uploads; normalise every page to RGBA.
            im = Image.open(io.BytesIO(raw)).convert("RGBA")
            im.save(os.path.join(stage, name))
    return page, fmt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered\costumes")
    ap.add_argument("--ids", nargs="+", required=True)
    ap.add_argument("--port", type=int, default=8795)
    ap.add_argument("--width", type=int, default=1400)
    ap.add_argument("--height", type=int, default=1800)
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--hide", default="")
    ap.add_argument("--anim", default="")
    # "end" samples the last frame of the clip, i.e. after the entrance.
    ap.add_argument("--time", default="0")
    # Scene-style skins keep large soft-alpha areas in their atlas; drawing
    # those pages as premultiplied shows them as washed-out rectangles.
    ap.add_argument("--pma", type=int, default=1, choices=(0, 1))
    # Effect slots that rely on additive/screen blending look like white
    # rectangles on a transparent canvas; drop them for portrait exports.
    ap.add_argument("--noblend", action="store_true")
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)
    root = os.path.join(TEMP, "skin_render")
    os.makedirs(root, exist_ok=True)
    for name in ("_spine_render_multi.html", "_spine_render_multi37.html",
                 "spine-webgl.js", "spine-webgl-3.7.js"):
        for src in (os.path.join(HERE, name), os.path.join(TEMP, "spine_batch", name), os.path.join(TEMP, name)):
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(root, name))
                break

    httpd = start_server(root, args.port)
    profile = os.path.join(root, "edgeprofile")
    rows = []
    try:
        for cid in args.ids:
            src = os.path.join(assets, "hotupdate", "skins", cid, "spineSkin")
            if not os.path.isdir(src):
                print("%s no skin spine" % cid)
                continue
            try:
                page, fmt = prepare_stage(root, cid, src)
            except Exception as exc:  # noqa: BLE001
                print("%s prep FAIL %s" % (cid, exc))
                continue
            dst = os.path.join(out_root, cid + ".png")
            extra = []
            if not args.pma:
                extra.append("pma=0")
            if args.noblend:
                extra.append("noblend=1")
            ok, info = render_one(os.path.join(root, "stage"), cid, dst, args.port, profile,
                                  args.width, args.height, args.hide,
                                  anim=args.anim, at=args.time,
                                  min_area=200, kind="skin", scale=args.scale, page=page, fmt=fmt,
                                  extra="&".join(extra))
            print("%s %s %s" % (cid, "OK" if ok else "FAIL", info))
            rows.append([cid, src, dst if ok else "", info])
    finally:
        httpd.shutdown()

    man = os.path.join(out_root, "skin_render_manifest.csv")
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["skin_id", "source", "output", "status"])
        w.writerows(rows)
    print("manifest:", man)


if __name__ == "__main__":
    main()
