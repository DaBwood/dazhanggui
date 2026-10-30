#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render missing beauty/patron full-body portraits from Spine skeletons.

The game ships most portraits as a Spine atlas plus a separate JSON/BIN
skeleton.  Some pages are already composed in newGui/3.png, but many are only
packed atlas parts; this script renders those skeletons to transparent PNGs
with the official spine-webgl runtime in headless Edge.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_spine_atlas_rgba import build as build_atlas  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"
HIDE = "dimian,cao,ground,grass,shui,bo"


def resolve(assets, kind, cid):
    candidates = [
        ("bin", "media/spine/%s/%s" % (kind, cid), "textures/png_from_pkm/spine/%s/%s" % (kind, cid)),
        ("bin", "media/cn/spine/%s/%s" % (kind, cid), "textures/png_from_pkm/cn/spine/%s/%s" % (kind, cid)),
        ("json", "spine/spine/%s/%s" % (kind, cid), "textures/png_from_pkm/spine/%s/%s" % (kind, cid)),
        ("json", "spine/cn/spine/%s/%s" % (kind, cid), "textures/png_from_pkm/cn/spine/%s/%s" % (kind, cid)),
    ]
    for fmt, data_rel, tex_rel in candidates:
        data_dir = os.path.join(assets, *data_rel.split("/"))
        tex_dir = os.path.join(assets, *tex_rel.split("/"))
        data_file = "skeleton.bin" if fmt == "bin" else "skeleton.json"
        if (os.path.exists(os.path.join(data_dir, data_file))
                and os.path.exists(os.path.join(data_dir, "skeleton.atlas"))
                and os.path.exists(os.path.join(tex_dir, "skeleton.png"))):
            return {
                "fmt": fmt,
                "atlas": os.path.join(data_dir, "skeleton.atlas"),
                "data": os.path.join(data_dir, data_file),
                "texture": os.path.join(tex_dir, "skeleton.png"),
            }
    return None


def load_ids(assets, kind):
    path = os.path.join(assets, "text", "cn", "allJson", "AllJson2.json")
    data = json.load(open(path, encoding="utf-8"))
    key = "PatronsDB" if kind == "patrons" else "BeautyDB"
    table = data[key]
    if isinstance(table, str):
        table = json.loads(table)
    table = table[key] if isinstance(table, dict) else table
    return [str(r[0]) for r in table[2:]]


def composed_ids(assets, kind):
    out = set()
    render_dir = os.path.join(assets, "clean", "fullbody_render")
    for dirpath, _dirs, files in os.walk(render_dir):
        for f in files:
            if f.endswith(".png") and "_preview" not in f:
                out.add(f[:-4].split("_")[0])
    page_dir = os.path.join(assets, "clean", "portraits_v2",
                            "friends_page" if kind == "beauty" else "heroes_page")
    if os.path.isdir(page_dir):
        for f in os.listdir(page_dir):
            if f.endswith(".png"):
                out.add(f[:-4])
    return out


def prepare_stage(stage_root, kind, cid, src):
    d = os.path.join(stage_root, kind, cid)
    os.makedirs(d, exist_ok=True)
    shutil.copy2(src["atlas"], os.path.join(d, "skeleton.atlas"))
    shutil.copy2(src["data"], os.path.join(d, "skeleton.bin" if src["fmt"] == "bin" else "skeleton.json"))
    build_atlas(src["texture"], src["atlas"], os.path.join(d, "skeleton.png"))


def start_server(root, port):
    class Quiet(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root, **kwargs)

        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Quiet)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return httpd


def render_one(stage_root, kind, cid, fmt, out_path, port, profile):
    page = "_spine_render37.html" if fmt == "json" else "_spine_render.html"
    url = ("http://127.0.0.1:%d/%s?id=%s&type=%s&w=1200&h=1600&hide=%s"
           % (port, page, cid, kind, HIDE))
    raw = out_path + ".raw.png"
    cmd = [
        EDGE, "--headless=new", "--no-first-run",
        "--user-data-dir=" + profile,
        "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
        "--hide-scrollbars", "--window-size=1200,1600",
        "--default-background-color=00000000",
        "--virtual-time-budget=15000",
        "--screenshot=" + raw, url,
    ]
    try:
        subprocess.run(cmd, timeout=90, capture_output=True)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    if not os.path.exists(raw) or os.path.getsize(raw) < 20000:
        return False, "blank"
    im = Image.open(raw).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        return False, "empty alpha"
    im = im.crop(bbox)
    im.save(out_path, optimize=True)
    os.remove(raw)
    return True, "%dx%d" % im.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered")
    ap.add_argument("--kind", choices=["beauty", "patrons", "both"], default="both")
    ap.add_argument("--port", type=int, default=8767)
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)
    base_root = os.path.join(TEMP, "spine_batch")
    stage_root = os.path.join(base_root, "stage")
    os.makedirs(stage_root, exist_ok=True)

    for f in ("_spine_render.html", "_spine_render37.html", "spine-webgl.js", "spine-webgl-3.7.js"):
        src = os.path.join(TEMP, f)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(base_root, f))

    httpd = start_server(base_root, args.port)
    profile = os.path.join(base_root, "edgeprofile")
    rows = []
    kinds = ["patrons", "beauty"] if args.kind == "both" else [args.kind]
    for kind in kinds:
        ids = load_ids(assets, kind)
        done = composed_ids(assets, kind)
        for dirpath, _d, files in os.walk(out_root):  # keep reruns idempotent
            for f in files:
                if f.endswith(".png"):
                    done.add(f[:-4].split("_")[0])
        missing = [i for i in ids if i not in done]
        print("%s: %d ids, %d already composed, %d to render" % (kind, len(ids), len(done), len(missing)))
        for cid in missing:
            src = resolve(assets, kind, cid)
            if not src:
                rows.append([kind, cid, "", "", "no-skeleton"])
                print("  %s no skeleton" % cid)
                continue
            try:
                prepare_stage(stage_root, kind, cid, src)
            except Exception as exc:  # noqa: BLE001
                rows.append([kind, cid, src["texture"], "", "prep FAIL: %s" % exc])
                print("  %s prep FAIL %s" % (cid, exc))
                continue
            dst = os.path.join(out_root, kind, cid + ".png")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            ok, info = render_one(stage_root, kind, cid, src["fmt"], dst, args.port, profile)
            rows.append([kind, cid, src["texture"], dst if ok else "", info])
            print("  %s %s %s" % (cid, "OK" if ok else "FAIL", info))
    httpd.shutdown()

    man = os.path.join(out_root, "render_manifest.csv")
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        import csv
        w = csv.writer(f)
        w.writerow(["kind", "id", "source", "output", "status"])
        w.writerows(rows)
    print("manifest:", man)


if __name__ == "__main__":
    main()
