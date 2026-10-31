#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render patrons that only exist in the hot-update Cocos bundle.

The hot bundle stores each portrait as a ``sp.SkeletonData`` JSON that points
at a ``.bin`` skeleton, an embedded atlas, and one or more encrypted texture
pages (``.pkm`` ETC1 or ``.astc``).  This tool decodes those pages, keys their
black background into alpha, writes a small Spine stage, and renders it with
the official spine-webgl runtime in headless Edge.

Output defaults to clean/portraits_v3/rendered/patrons/<id>.png so the normal
assemble_portraits_v3.py pass can pick the result up.

Usage:
  python tools/render_hotupdate_portraits.py --ids 102542 102543 102544
"""

import argparse
import csv
import gzip
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

from PIL import Image
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from astc2png import decode_astc_bytes  # noqa: E402
from build_spine_atlas_rgba import build as build_atlas, parse_atlas_pages  # noqa: E402
from etc1 import decode_pkm  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"
HIDE = "dimian,cao,ground,grass,shui,bo"
PAGE = "_spine_render_multi.html"

B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
B64V = {c: i for i, c in enumerate(B64)}


def decode_uuid(value):
    """Decode Cocos' 22-char compressed UUID into a normal 8-4-4-4-12 UUID."""
    if len(value) != 22:
        return value
    head = value[:2]
    for i in range(2, 22, 2):
        left, right = B64V[value[i]], B64V[value[i + 1]]
        head += "%x%x%x" % (left >> 2, ((left & 3) << 2) | (right >> 4), right & 0xF)
    return "%s-%s-%s-%s-%s" % (head[:8], head[8:12], head[12:16], head[16:20], head[20:32])


def load_config(assets):
    path = os.path.join(assets, "hotupdate", "pch", "assets", "resources", "config.json")
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def entries_for(config, prefix):
    """Yield (path, uuid, type) for every config path starting with prefix."""
    paths = config.get("paths", {})
    uuids = config.get("uuids", [])
    for key, value in paths.items():
        if not value:
            continue
        path = str(value[0])
        if path.startswith(prefix):
            idx = int(key)
            yield path, uuids[idx] if idx < len(uuids) else "", value[1] if len(value) > 1 else None


def resource_file(assets, uuid, exts):
    full = decode_uuid(uuid)
    root = os.path.join(assets, "hotupdate", "pch", "assets", "resources")
    for sub in ("native", "import"):
        folder = os.path.join(root, sub, full[:2])
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            if not name.startswith(full):
                continue
            ext = os.path.splitext(name)[1].lower()
            if ext in exts:
                return os.path.join(folder, name)
    return ""


def find_skeleton_data(assets, cid, config, kind="patrons"):
    """Find the newest usable sp.SkeletonData for a patron/beauty id."""
    candidates = []
    for path, uuid, typ in entries_for(config, "spine/%s/%s/skeleton" % (kind, cid)):
        if typ != 5:
            continue
        full = decode_uuid(uuid)
        data_json = os.path.join(assets, "hotupdate", "pch", "assets", "resources",
                                 "import", full[:2], full + ".json")
        if not os.path.exists(data_json):
            continue
        try:
            with open(data_json, encoding="utf-8") as f:
                data = json.load(f)
            obj = data[5][0]
        except Exception:
            continue
        native = os.path.join(assets, "hotupdate", "pch", "assets", "resources",
                              "native", full[:2], full + (obj[2] or ".bin"))
        if not os.path.exists(native):
            continue
        candidates.append({
            "id": cid,
            "data_json": data_json,
            "data": native,
            "fmt": "bin" if str(obj[2]).lower() == ".bin" else "json",
            "atlas": obj[3],
            "page_names": list(obj[4]),
            "texture_refs": list(obj[5]),
            "deps": list(data[1]),
            "source": "hotupdate",
        })
    return candidates[0] if candidates else None


def decode_texture(path):
    data = open(path, "rb").read()
    low = path.lower()
    if low.endswith(".pkm"):
        if data[:6] == b"lyqszp":
            data = bytes(b ^ 0x70 for b in data[6:])
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
        return decode_pkm(data)
    if low.endswith(".astc"):
        return decode_astc_bytes(data)
    if low.endswith(".png"):
        return Image.open(path).convert("RGBA")
    raise ValueError("unsupported texture: %s" % path)


def prepare_stage(assets, stage_root, cid, src, fill_holes=True, use_mask=True, kind="patrons"):
    d = os.path.join(stage_root, kind, cid)
    os.makedirs(d, exist_ok=True)
    shutil.copy2(src["data"], os.path.join(d, "skeleton.bin" if src["fmt"] == "bin" else "skeleton.json"))
    atlas_text = src["atlas"]
    with open(os.path.join(d, "skeleton.atlas"), "w", encoding="utf-8", newline="") as f:
        f.write(atlas_text)

    pages = parse_atlas_pages(atlas_text)
    if len(pages) != len(src["page_names"]):
        raise ValueError("atlas has %d pages, SkeletonData lists %d" % (len(pages), len(src["page_names"])))
    for index, (page, texture_ref) in enumerate(zip(pages, src["texture_refs"])):
        uuid = src["deps"][int(texture_ref)]
        tex_path = resource_file(assets, uuid, (".pkm", ".astc", ".png"))
        if not tex_path:
            raise FileNotFoundError("texture %s for page %s" % (uuid, page["name"]))
        raw = decode_texture(tex_path)
        raw_path = os.path.join(d, "_raw_%d.png" % index)
        raw.save(raw_path)
        out_path = os.path.join(d, page["name"])
        mask_path = None
        if use_mask and raw.height >= page["size"][1] * 2:
            # Hot pages ship the colour page on top and an identically
            # laid-out white alpha mask in the bottom half.
            mask_path = os.path.join(d, "_mask_%d.png" % index)
            raw.crop((0, raw.height // 2, raw.width, raw.height)).save(mask_path)
        size, regions, empty = build_atlas(raw_path, None, out_path, page_index=index, atlas_text=atlas_text,
                                           fill_holes=fill_holes, mask_path=mask_path)
        os.remove(raw_path)
        if mask_path:
            os.remove(mask_path)
        print("    page %d %s -> %s (%d regions, %d empty) from %s"
              % (index, page["name"], size, regions, len(empty), os.path.basename(tex_path)))
    return d


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


def drop_small_components(im, min_area=200):
    """Clear detached alpha specks left over from hidden scene slots."""
    if min_area <= 0:
        return im
    arr = np.array(im.convert("RGBA"))
    alpha = arr[:, :, 3]
    solid = alpha > 8
    h, w = solid.shape
    seen = np.zeros((h, w), bool)
    ys, xs = np.nonzero(solid)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        comp = []
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(comp) < min_area:
            for y, x in comp:
                arr[y, x, 3] = 0
    return Image.fromarray(arr, "RGBA")


def render_one(stage_root, cid, out_path, port, profile, width, height, hide, anim="", at=0.0,
               min_area=200, kind="patrons", scale=2):
    rw, rh = width * scale, height * scale
    url = ("http://127.0.0.1:%d/%s?id=%s&type=%s&w=%d&h=%d&hide=%s"
           % (port, PAGE, cid, kind, rw, rh, hide))
    if anim:
        url += "&anim=%s&time=%s" % (anim, at)
    raw = out_path + ".raw.png"
    cmd = [
        EDGE, "--headless=new", "--no-first-run",
        "--user-data-dir=" + profile,
        "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
        "--hide-scrollbars", "--window-size=%d,%d" % (rw, rh),
        "--default-background-color=00000000",
        "--virtual-time-budget=20000",
        "--screenshot=" + raw, url,
    ]
    try:
        subprocess.run(cmd, timeout=120, capture_output=True)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    if not os.path.exists(raw) or os.path.getsize(raw) < 20000:
        return False, "blank"
    im = Image.open(raw).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        return False, "empty alpha"
    im = im.crop(bbox)
    if scale > 1:
        im = im.resize((max(1, im.width // scale), max(1, im.height // scale)), Image.LANCZOS)
    im = drop_small_components(im, min_area)
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    im.save(out_path, optimize=True)
    os.remove(raw)
    return True, "%dx%d" % im.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered\patrons")
    ap.add_argument("--ids", nargs="+", default=["102542", "102543", "102544"])
    ap.add_argument("--kind", default="patrons", choices=("patrons", "beauty"))
    ap.add_argument("--port", type=int, default=8768)
    ap.add_argument("--width", type=int, default=1400)
    ap.add_argument("--height", type=int, default=1800)
    ap.add_argument("--hide", default=HIDE)
    ap.add_argument("--anim", default="")
    ap.add_argument("--time", type=float, default=0.0)
    ap.add_argument("--no-fill-holes", action="store_true")
    ap.add_argument("--key-black", action="store_true",
                    help="ignore the packed white mask and key black per region")
    ap.add_argument("--min-area", type=int, default=200,
                    help="drop detached alpha components smaller than this")
    ap.add_argument("--scale", type=int, default=2,
                    help="supersampling factor (render at scale x then Lanczos down)")
    ap.add_argument("--hide-map", default="",
                    help="JSON {id: {hide, anim, time}} overriding --hide/--anim")
    ap.add_argument("--append-manifest", action="store_true")
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)
    config = load_config(assets)
    hide_map = {}
    if args.hide_map:
        with open(args.hide_map, encoding="utf-8") as f:
            hide_map = json.load(f)

    base_root = os.path.join(TEMP, "spine_batch_hot")
    stage_root = os.path.join(base_root, "stage")
    os.makedirs(stage_root, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    for name in (PAGE, "spine-webgl.js"):
        candidates = (
            os.path.join(here, name),
            os.path.join(TEMP, "spine_batch", name),
            os.path.join(TEMP, name),
        )
        for src in candidates:
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(base_root, name))
                break

    httpd = start_server(base_root, args.port)
    profile = os.path.join(base_root, "edgeprofile_hot")
    rows = []
    try:
        for cid in args.ids:
            src = find_skeleton_data(assets, cid, config, args.kind)
            if not src:
                rows.append([cid, "", "", "no-skeleton"])
                print("%s no hot skeleton" % cid)
                continue
            try:
                prepare_stage(assets, stage_root, cid, src, fill_holes=not args.no_fill_holes,
                              use_mask=not args.key_black, kind=args.kind)
            except Exception as exc:  # noqa: BLE001
                rows.append([cid, src.get("data_json", ""), "", "prep FAIL: %s" % exc])
                print("%s prep FAIL %s" % (cid, exc))
                continue
            dst = os.path.join(out_root, cid + ".png")
            spec = hide_map.get(cid, {})
            hide = spec.get("hide", args.hide)
            anim = spec.get("anim", args.anim)
            at = float(spec.get("time", args.time))
            ok, info = render_one(stage_root, cid, dst, args.port, profile,
                                  args.width, args.height, hide,
                                  anim, at, args.min_area, args.kind, args.scale)
            rows.append([cid, src["data_json"], dst if ok else "", info])
            print("%s %s %s" % (cid, "OK" if ok else "FAIL", info))
    finally:
        httpd.shutdown()

    man = os.path.join(out_root, "hotupdate_render_manifest.csv")
    header = ["id", "source", "output", "status"]
    merged = []
    if args.append_manifest and os.path.exists(man):
        with open(man, encoding="utf-8-sig", newline="") as f:
            old = list(csv.reader(f))
        if old and old[0] == header:
            merged = [r for r in old[1:] if r and r[0] not in {row[0] for row in rows}]
        else:
            merged = [r for r in old if r and r[0] not in {row[0] for row in rows}]
    merged.extend(rows)
    merged.sort(key=lambda r: r[0])
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(merged)
    print("manifest:", man)


if __name__ == "__main__":
    main()
