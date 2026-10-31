#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Give every portrait in clean/portraits_v3 a human-readable Chinese name.

The canonical output stays id-based (heroes_full/102110.png); this tool only
adds parallel directories with hard links named <id>_<name>.png plus a
names.csv index, so id-based tooling keeps working.

Names come from the base LanguageWordDB merged with the hot-update copy
(UTF-16 code-point XOR 0x1040; the hot text is additionally XOR 1).
Project-side display names come from data/heroes.json (109 patrons); two art
names differ from the project spelling and are aliased below.  Statuses
(full / half-fallback / missing) come from coverage.csv.

Output:
  clean/portraits_v3/heroes_full_named/<id>_<name>.png   (+ half/head)
  clean/portraits_v3/friends_full_named/<id>_<name>.png  (+ half/head)
  clean/portraits_v3/names.csv

Usage:
  python tools/label_portraits.py
"""

import argparse
import csv
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from portrait_sources import load_alljson, load_names, load_records, record_name  # noqa: E402

# Art-side name -> project-side name (same character, different spelling).
PROJECT_ALIAS = {
    "费机关": "贾机关",
    "皮影戏人": "皮影匠人",
}

# Same art name, two different appearances: keep both, flag in names.csv.
DUPLICATE_NAME_NOTE = {
    ("beauty", "103001"): "shares appearanceId with 103209 (陆长青), different art",
    ("beauty", "103209"): "BeautyDB row reuses Beauty-103001; id-specific name is 陆长青",
}

# Source caveats worth keeping visible in names.csv.
PATRON_NOTE = {
    "102518": "art shared with Beauty 103365 (isTwins/isSwitch); hot-update 王昭君 spine not shipped",
    "102542": "hot-update Spine render; double-page atlas",
    "102543": "hot-update Spine render",
    "102544": "hot-update Spine render; official pose is the lotus-boat scene, lower body inside the boat",
}

# New hot-update beauty rows whose spine/newGui files are listed in config.json
# but are not present in the shipped bundle (no full/half/head art to extract).
BEAUTY_MISSING_NOTE = {
    cid: "hot-update BeautyDB row; spine/newGui files not shipped"
    for cid in ("103392", "103393", "103394", "103395", "103396", "103397", "103398")
}

DIRS = (
    ("patrons", "heroes_full", "full"),
    ("patrons", "heroes_half", "half"),
    ("patrons", "heroes_head", "head"),
    ("beauty", "friends_full", "full"),
    ("beauty", "friends_half", "half"),
    ("beauty", "friends_head", "head"),
)


def load_project_names(repo):
    path = os.path.join(repo, "data", "heroes.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {v["name"]: k for k, v in data.items() if isinstance(v, dict) and "name" in v}


def safe_filename(name):
    for ch in '\\/:*?"<>|':
        name = name.replace(ch, "_")
    return name.strip() or "unnamed"


def link_or_copy(src, dst):
    if os.path.exists(dst):
        os.remove(dst)
    try:
        os.link(src, dst)
        return "hardlink"
    except OSError:
        shutil.copy2(src, dst)
        return "copy"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--repo", default=r"C:\Users\林\Documents\大掌柜")
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    root = os.path.join(assets, "clean", "portraits_v3")
    names = load_names(assets)
    tables = load_alljson(assets)
    project = load_project_names(os.path.abspath(args.repo))

    status = {}
    with open(os.path.join(root, "coverage.csv"), encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            status[(row["type"], row["id"])] = row

    # type in coverage.csv is patron/beauty; keep the mapping explicit.
    cov_kind = {"patrons": "patron", "beauty": "beauty"}

    records = {kind: load_records(assets, kind, tables) for kind in ("patrons", "beauty")}
    info = {}
    for kind, rows in records.items():
        for rec in rows:
            cid = str(rec["id"])
            name = record_name(names, kind, rec)
            info[(kind, cid)] = {
                "name": name,
                "quality": rec.get("quality", ""),
                "appearance": rec.get("appearanceId", ""),
            }

    out_rows = []
    linked = 0
    for kind, dirname, layer in DIRS:
        src_dir = os.path.join(root, dirname)
        dst_dir = os.path.join(root, dirname + "_named")
        if os.path.isdir(dst_dir):
            shutil.rmtree(dst_dir)
        os.makedirs(dst_dir, exist_ok=True)
        if not os.path.isdir(src_dir):
            continue
        for fname in sorted(os.listdir(src_dir)):
            if not fname.lower().endswith(".png"):
                continue
            cid = os.path.splitext(fname)[0]
            meta = info.get((kind, cid), {})
            name = meta.get("name", "") or "unknown"
            dst = os.path.join(dst_dir, "%s_%s.png" % (cid, safe_filename(name)))
            link_or_copy(os.path.join(src_dir, fname), dst)
            linked += 1

    # names.csv: one row per character that has any v3 image.
    for kind in ("patrons", "beauty"):
        for rec in records[kind]:
            cid = str(rec["id"])
            cov = status.get((cov_kind[kind], cid))
            if not cov:
                continue  # excluded (see excluded.csv)
            meta = info[(kind, cid)]
            name = meta["name"]
            proj = PROJECT_ALIAS.get(name, name)
            note = DUPLICATE_NAME_NOTE.get((kind, cid), "")
            if kind == "patrons":
                note = PATRON_NOTE.get(cid, note)
            else:
                note = BEAUTY_MISSING_NOTE.get(cid, note)
            project_name = ""
            if kind == "patrons":
                project_name = proj if proj in project else ""
                if name != proj:
                    note = (note + "; " if note else "") + "project name: " + proj
            prefix = "heroes" if kind == "patrons" else "friends"
            paths = []
            for layer_name in ("full", "half", "head"):
                rel = "%s_%s/%s.png" % (prefix, layer_name, cid)
                paths.append(rel if os.path.exists(os.path.join(root, rel)) else "")
            out_rows.append([
                cov["type"], cid, name, project_name,
                meta["quality"], cov["status"], note,
                paths[0], paths[1], paths[2],
            ])

    with open(os.path.join(root, "names.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["type", "id", "name", "project_name", "quality", "status", "note",
                    "full", "half", "head"])
        w.writerows(out_rows)

    # roster_109.csv: the project's authoritative 109-patron roster, matched
    # against this asset pack (art names are aliased to project spellings).
    by_project_name = {}
    for rec in records["patrons"]:
        cid = str(rec["id"])
        cov = status.get(("patron", cid))
        if not cov:
            continue
        name = info[("patrons", cid)]["name"]
        by_project_name.setdefault(PROJECT_ALIAS.get(name, name), (cid, name, cov))

    roster_rows = []
    for project_name, _key in project.items():
        hit = by_project_name.get(project_name)
        if hit:
            cid, art_name, cov = hit
            note = "" if art_name == project_name else "art name: " + art_name
            roster_rows.append([project_name, art_name, cid, cov["status"], note])
        else:
            roster_rows.append([project_name, "", "", "absent-in-assets",
                                "no patron row / text / art in this asset version"])

    with open(os.path.join(root, "roster_109.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["project_name", "art_name", "id", "status", "note"])
        w.writerows(roster_rows)

    present = sum(1 for r in roster_rows if r[3] != "absent-in-assets")
    print("named files:", linked)
    print("names.csv rows:", len(out_rows))
    print("roster_109: %d/%d present" % (present, len(roster_rows)))


if __name__ == "__main__":
    main()
