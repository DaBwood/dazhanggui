"""Render a full-body costume by merging the base patron body with the
costume-only spineSkin bundle."""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge_costume_spine import merge
from render_hotupdate_portraits import render_one, start_server

TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--patron", required=True)
    ap.add_argument("--skins", nargs="+", required=True)
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered\costumes_merged")
    ap.add_argument("--port", type=int, default=8810)
    ap.add_argument("--time", type=float, default=1.3333)
    ap.add_argument("--hide", default="")
    ap.add_argument("--width", type=int, default=1400)
    ap.add_argument("--height", type=int, default=1800)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    root = os.path.join(TEMP, "skin_render")
    os.makedirs(root, exist_ok=True)
    for name in ("_spine_render_multi37.html", "spine-webgl-3.7.js"):
        src = os.path.join(HERE, name)
        if os.path.exists(src):
            import shutil
            shutil.copy2(src, os.path.join(root, name))
    httpd = start_server(root, args.port)
    profile = os.path.join(root, "edgeprofile")
    try:
        for skin in args.skins:
            merge(args.assets, args.patron, skin, root)
            dst = os.path.join(args.out, skin + ".png")
            ok, info = render_one(
                root, skin, dst, args.port, profile, args.width, args.height,
                args.hide, anim="idle", at=args.time, min_area=200,
                kind="skin_merge", scale=2,
                page="_spine_render_multi37.html", fmt="json")
            print(skin, "OK" if ok else "FAIL", info)
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    main()
