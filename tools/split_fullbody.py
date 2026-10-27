#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Split full-body patron/beauty Spine textures into transparent PNGs.

The full-body art is stored as a one-bone Spine skeleton; its texture lives in
`textures/png[_from_pkm]/<same relative path>/skeleton.png` and is a colour
page + white alpha mask.
"""

import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from split_portraits import split_portrait  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    base = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    spine_root = os.path.join(base, "spine")
    tex_roots = [
        os.path.join(base, "textures", "png_from_pkm"),
        os.path.join(base, "textures", "png"),
    ]

    roots = [
        ("heroes_full", os.path.join(spine_root, "spine", "patrons")),
        ("heroes_full", os.path.join(spine_root, "cn", "spine", "patrons")),
        ("friends_full", os.path.join(spine_root, "spine", "beauty")),
        ("friends_full", os.path.join(spine_root, "cn", "spine", "beauty")),
    ]

    def find_tex(d):
        rel = os.path.relpath(d, spine_root)
        for tr in tex_roots:
            p = os.path.join(tr, rel, "skeleton.png")
            if os.path.exists(p):
                return p
        return ""

    rows = []
    ok = fail = 0
    seen = set()
    for kind, root in roots:
        dst_root = os.path.join(out_root, kind)
        os.makedirs(dst_root, exist_ok=True)
        if not os.path.isdir(root):
            print("missing", root)
            continue
        for name in sorted(os.listdir(root)):
            d = os.path.join(root, name)
            if not os.path.isdir(d) or name == "000000":
                continue
            if (kind, name) in seen:
                continue
            src = find_tex(d)
            if not src:
                rows.append([kind, name, d, "", "", "", "no-skeleton-png"])
                fail += 1
                continue
            try:
                img, black = split_portrait(src)
                dst = os.path.join(dst_root, name + ".png")
                img.save(dst)
                status = "ok" if black <= 0.02 else "artifacts"
                rows.append([kind, name, src, dst, img.size, black, status])
                seen.add((kind, name))
                ok += 1
            except Exception as e:  # noqa: BLE001
                rows.append([kind, name, src, "", "", "", "FAIL: %s" % e])
                fail += 1

    man = os.path.join(out_root, "fullbody_manifest.csv")
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "source", "output", "size", "black_ratio", "status"])
        w.writerows(rows)
    print("ok=%d fail=%d" % (ok, fail))
    print("manifest:", man)


if __name__ == "__main__":
    main()
