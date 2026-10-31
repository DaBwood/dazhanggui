#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Restore portraits_v3 patron layers from the imported game-project set.

After the portraits are imported, the working source folders
(clean/portraits_v2, clean/fullbody_render) can be cleaned up.  The project
keeps the tested output under assets/portraits/:
  heroes/<slug>.png       full body
  heroes_card/<slug>.png  half body (186x308)
  hero_head/<slug>.png    head (134x134)

This tool maps the project's pinyin slugs back to PatronsDB ids through
data/heroes.json and names.csv, then copies the three layers into v3.

Usage:
  python tools/restore_hero_layers.py
"""

import argparse
import csv
import json
import os
import shutil

# Project-side name -> art-side name (see label_portraits.PROJECT_ALIAS).
PROJECT_TO_ART = {
    "贾机关": "费机关",
    "皮影匠人": "皮影戏人",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=r"C:\Users\林\Documents\大掌柜")
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    root = os.path.join(os.path.abspath(args.assets), "clean", "portraits_v3")
    src_root = os.path.join(repo, "assets", "portraits")
    heroes = json.load(open(os.path.join(repo, "data", "heroes.json"), encoding="utf-8"))
    rows = [r for r in csv.DictReader(open(os.path.join(root, "names.csv"), encoding="utf-8-sig"))
            if r["type"] == "patron"]
    by_name = {r["name"]: r["id"] for r in rows}

    layers = (("heroes", "heroes_full"), ("heroes_card", "heroes_half"), ("hero_head", "heroes_head"))
    copied = 0
    missing = []
    for slug, rec in heroes.items():
        name = rec.get("name", "")
        art = PROJECT_TO_ART.get(name, name)
        cid = by_name.get(art)
        if not cid:
            missing.append((slug, name, "no v3 row"))
            continue
        for src_name, dst_name in layers:
            src = os.path.join(src_root, src_name, slug + ".png")
            if not os.path.exists(src):
                missing.append((slug, name, "no " + src_name))
                continue
            dst = os.path.join(root, dst_name, cid + ".png")
            shutil.copy2(src, dst)
            copied += 1
    print("copied", copied)
    print("missing", len(missing))
    for x in missing[:20]:
        print(" ", x)


if __name__ == "__main__":
    main()
