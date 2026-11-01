#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Copy scene-style costume renders over the project's existing portraits.

Only costume ids that already exist in assets/portraits/heroes_cos are
replaced; UI tags (name_plate/tag_*) are left alone.  A character-only backup
is kept in assets/portraits/heroes_cos_charonly_backup.

Usage:
  python tools/sync_project_costumes.py
"""

import csv
import os
import shutil

REPO = r"C:\Users\林\Documents\大掌柜"
ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
PROJ = os.path.join(REPO, "assets", "portraits", "heroes_cos")
MANIFEST = os.path.join(ASSETS, "clean", "costumes_v3", "heroes_cos_manifest.csv")


def main():
    rows = list(csv.DictReader(open(MANIFEST, encoding="utf-8-sig")))
    copied = 0
    for r in rows:
        src = r["output"]
        cid = r["costume_id"]
        if not src or not os.path.exists(src):
            continue
        dst = os.path.join(PROJ, cid + ".png")
        if not os.path.exists(dst):
            continue  # only replace what the project already has
        shutil.copy2(src, dst)
        copied += 1
        print("synced", cid)
    print("copied", copied, "to", PROJ)


if __name__ == "__main__":
    main()
