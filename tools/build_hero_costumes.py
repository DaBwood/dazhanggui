#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render all full-body patron costumes and map skin ids to costume ids.

Reads clean/costumes_v3/inventory.csv, renders every status=full-body skin
with scenes kept (render_skin_spine.py), then copies the result to
clean/costumes_v3/heroes_cos/<costume_id>.png.

Usage:
  python tools/build_hero_costumes.py
"""

import csv
import os
import shutil
import subprocess
import sys

REPO = r"C:\Users\林\Documents\大掌柜"
ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
OUT_ROOT = os.path.join(ASSETS, "clean", "costumes_v3")
INVENTORY = os.path.join(OUT_ROOT, "inventory.csv")
RENDER_DIR = os.path.join(ASSETS, "clean", "portraits_v3", "rendered", "costumes")
TOOLS = os.path.join(REPO, "tools")


def main():
    rows = [r for r in csv.DictReader(open(INVENTORY, encoding="utf-8-sig"))
            if r["status"] == "full-body"]
    by_skin = {r["skin_id"]: r for r in rows}
    ids = list(by_skin)
    print("full-body costumes:", len(rows), "unique skins:", len(ids), flush=True)

    os.makedirs(RENDER_DIR, exist_ok=True)
    cmd = [sys.executable, "-X", "utf8", os.path.join(TOOLS, "render_skin_spine.py"),
           "--ids"] + ids + ["--out", RENDER_DIR]
    subprocess.run(cmd, check=False, cwd=REPO)

    dst_root = os.path.join(OUT_ROOT, "heroes_cos")
    os.makedirs(dst_root, exist_ok=True)
    copied = 0
    out_rows = []
    for r in rows:
        src = os.path.join(RENDER_DIR, r["skin_id"] + ".png")
        dst = os.path.join(dst_root, r["costume_id"] + ".png")
        if os.path.exists(src):
            shutil.copy2(src, dst)
            copied += 1
            out_rows.append([r["costume_id"], r["name"], r["quality"], r["hero_slug"],
                             r["patron_id"], r["skin_id"], "rendered", dst])
        else:
            out_rows.append([r["costume_id"], r["name"], r["quality"], r["hero_slug"],
                             r["patron_id"], r["skin_id"], "render-missing", ""])
    man = os.path.join(OUT_ROOT, "heroes_cos_manifest.csv")
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["costume_id", "name", "quality", "hero_slug", "patron_id",
                    "skin_id", "source", "output"])
        w.writerows(out_rows)
    print("copied", copied, "manifest", man, flush=True)


if __name__ == "__main__":
    main()
