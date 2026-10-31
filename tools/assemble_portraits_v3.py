#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Assemble clean/portraits_v3 from every trustworthy full-body source.

Priority for a full-body image (highest first):

  1. clean/fullbody_render/**/<中文名>.png  user-curated, high-res originals
     (mapped back to ids through the decoded LanguageWordDB names)
  2. clean/fullbody_render/**/<id>.png      already composed by the game
     (or <id>_1.png alt pose; also used through SHARED_APPEARANCE for
     isTwins/isSwitch pairs)
  3. clean/portraits_v3/rendered/*_page/<id>.png  base 3.png re-masked with its
     packed white alpha (clean; supersedes the old black-keyed v2 page)
  4. clean/portraits_v2/*_page/<id>.png     legacy full-body page (broken alpha)
  5. clean/portraits_v3/rendered/*/<id>.png Spine render of the missing ones
     (including hot-update-only patrons such as 102542-102544)

Half / head crops come from portraits_v2 (masked 2.png / 4.png pages).  When
a hot-update-only patron has no v2 crop, rendered/<kind>_half|head/<id>.png
is used (official /2 and /4 split textures).  Characters whose render was
reviewed as broken (RENDER_BAD) instead use the v2 half-body crop and are
marked "half-fallback" in coverage.csv, unless a composed full-body exists.

Names and rows come from the hot-update AllJson2 / LanguageWordDB when the
bundle ships them, merged over the base package (hot PatronsDB 118 rows vs
base 115; 102518 is 王昭君 there, 102518_1 is 甄嬛).  Values are encrypted
with a UTF-16 code-point XOR 0x1040.  The id-specific key wins over the row's
name field (BeautyDB 103209 reuses Beauty-103001 but its own key is 陆长青).

Output:
  clean/portraits_v3/heroes_full|friends_full|heroes_half|friends_half|
                    heroes_head|friends_head
  clean/portraits_v3/manifest.csv
  clean/portraits_v3/coverage.csv
  clean/portraits_v3/excluded.csv

Usage:
  python tools/assemble_portraits_v3.py
"""

import argparse
import csv
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from portrait_sources import load_alljson, load_names, load_records, record_name  # noqa: E402

# PatronsDB rows that are not distinct roster characters (see excluded.csv):
#   102526..102529  小柒 repeats of 102525 (byte-identical skeleton/atlas/png)
#   102536..102539  小八 repeats of 102535 (shared appearanceId 1025350)
#   102506          哥伦布 - not in the project's 109-patron roster
EXCLUDE = {
    "patrons": {"102506", "102526", "102527", "102528", "102529",
                "102536", "102537", "102538", "102539"},
    "beauty": set(),
}

EXCLUDE_REASON = {
    "102526": "duplicate of 102525 (小柒)",
    "102527": "duplicate of 102525 (小柒)",
    "102528": "duplicate of 102525 (小柒)",
    "102529": "duplicate of 102525 (小柒)",
    "102536": "duplicate of 102535 (小八)",
    "102537": "duplicate of 102535 (小八)",
    "102538": "duplicate of 102535 (小八)",
    "102539": "duplicate of 102535 (小八)",
    "102506": "non-patron (哥伦布)",
}

# Patron/beauty pairs that share one appearance (isTwins/isSwitch).
# 102518 (王昭君) has beautyId 103365, so its art is the beauty's art.
# The five 同名 patrons (马湘兰…寇白门) reuse the beauty crops for half/head;
# their full image is already the composed Chinese-named file.
SHARED_APPEARANCE = {
    ("patrons", "102518"): ("beauty", "103365"),
    ("patrons", "102415"): ("beauty", "103307"),
    ("patrons", "102425"): ("beauty", "103308"),
    ("patrons", "102435"): ("beauty", "103309"),
    ("patrons", "102445"): ("beauty", "103310"),
    ("patrons", "102455"): ("beauty", "103311"),
}

# Spine renders reviewed as broken / scene-garbage on the contact sheets
# (their atlas colour page is effect debris, and the v2 full crops of the same
# ids are atlas garbage too).  A composed file (Chinese-named or id-named) is
# checked first; these ids only fall back to the v2 half when none exists.
RENDER_BAD = {
    "patrons": {"102517", "102519", "102523", "102540"},
    "beauty": {"103379", "103382", "103388", "103390"},
}


def index_dir(root, suffixes=(".png",)):
    out = {}
    if not os.path.isdir(root):
        return out
    for name in os.listdir(root):
        base, ext = os.path.splitext(name)
        if ext.lower() not in suffixes or base.endswith("_preview"):
            continue
        out.setdefault(base, os.path.join(root, name))
    return out


def build_name_index(assets, names, records):
    """name -> canonical id for each kind (first row wins, so 小柒 -> 102525)."""
    index = {"patrons": {}, "beauty": {}}
    for kind in ("patrons", "beauty"):
        for rec in records[kind]:
            nm = record_name(names, kind, rec)
            if nm:
                index[kind].setdefault(nm, str(rec["id"]))
    return index


def index_composed(root, name_index):
    """Index fullbody_render, which mixes id-named and Chinese-named files.

    Returns (by_id, by_name):
      by_id   numeric basenames (102110.png / 102110_1.png) -> id
      by_name Chinese basenames -> id; files under a 门客 directory belong to
              patrons, everything else to beauty.
    """
    by_id = {}
    by_name = {"patrons": {}, "beauty": {}}
    if not os.path.isdir(root):
        return by_id, by_name
    for dirpath, _dirs, files in os.walk(root):
        kind = "patrons" if "门客" in dirpath.split(os.sep) else "beauty"
        for name in files:
            base, ext = os.path.splitext(name)
            if ext.lower() != ".png" or base.endswith("_preview"):
                continue
            path = os.path.join(dirpath, name)
            if re.fullmatch(r"\d+(_\d+)?", base):
                cid = base.split("_")[0]
                if cid not in by_id or base == cid:
                    by_id[cid] = path
            else:
                cid = name_index[kind].get(base)
                if cid:
                    by_name[kind].setdefault(cid, path)
    return by_id, by_name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3")
    args = ap.parse_args()

    assets = os.path.abspath(args.assets)
    out_root = os.path.abspath(args.out)
    clean = os.path.join(assets, "clean")
    v2 = os.path.join(clean, "portraits_v2")
    rendered = os.path.join(out_root, "rendered")
    tables = load_alljson(assets)
    names = load_names(assets)
    records = {kind: load_records(assets, kind, tables) for kind in ("patrons", "beauty")}
    name_index = build_name_index(assets, names, records)
    composed, composed_named = index_composed(os.path.join(clean, "fullbody_render"), name_index)
    rows = []
    excluded_rows = []

    plan = {
        "patrons": ("heroes", "patrons"),
        "beauty": ("friends", "beauty"),
    }
    src_tables = {}
    for kind, (prefix, render_kind) in plan.items():
        src_tables[kind] = {
            "prefix": prefix,
            "render_kind": render_kind,
            "page": index_dir(os.path.join(v2, prefix + "_page")),
            "page_clean": index_dir(os.path.join(rendered, render_kind + "_page")),
            "half": index_dir(os.path.join(v2, prefix + "_half")),
            "head": index_dir(os.path.join(v2, prefix + "_head")),
            "drawn": index_dir(os.path.join(rendered, render_kind)),
            "drawn_half": index_dir(os.path.join(rendered, render_kind + "_half")),
            "drawn_head": index_dir(os.path.join(rendered, render_kind + "_head")),
        }

    def pick_full(kind, cid):
        t = src_tables[kind]
        alias = SHARED_APPEARANCE.get((kind, cid))
        if cid in composed_named[kind]:
            return composed_named[kind][cid], "composed-named"
        if alias:
            ak, acid = alias
            at = src_tables[ak]
            if acid in composed_named[ak]:
                return composed_named[ak][acid], "composed-named-shared"
            if acid in composed:
                return composed[acid], "composed-shared"
            if acid in at["page_clean"]:
                return at["page_clean"][acid], "page-clean-shared"
            if acid in at["page"]:
                return at["page"][acid], "page-shared"
        if cid in composed:
            return composed[cid], "composed"
        if cid in t["page_clean"]:
            return t["page_clean"][cid], "page-clean"
        if cid in t["page"]:
            return t["page"][cid], "page"
        if cid not in RENDER_BAD.get(kind, ()) and cid in t["drawn"]:
            return t["drawn"][cid], "rendered"
        return "", ""

    def pick_layer(kind, cid, layer):
        t = src_tables[kind]
        alias = SHARED_APPEARANCE.get((kind, cid))
        if cid in t[layer]:
            return t[layer][cid], "v2"
        if alias:
            ak, acid = alias
            at = src_tables[ak]
            if acid in at[layer]:
                return at[layer][acid], "v2-shared"
        hot = t["drawn_" + layer]
        if cid in hot:
            return hot[cid], "hotupdate"
        return "", ""

    for kind, (prefix, render_kind) in plan.items():
        dst_full = os.path.join(out_root, prefix + "_full")
        dst_half = os.path.join(out_root, prefix + "_half")
        dst_head = os.path.join(out_root, prefix + "_head")
        for d in (dst_full, dst_half, dst_head):
            os.makedirs(d, exist_ok=True)

        for rec in records[kind]:
            cid = str(rec["id"])
            name = record_name(names, kind, rec)
            if cid in EXCLUDE.get(kind, ()):
                excluded_rows.append([kind, cid, name, rec.get("quality", ""),
                                      EXCLUDE_REASON.get(cid, "excluded")])
                continue

            src, how = pick_full(kind, cid)
            if src:
                dst = os.path.join(dst_full, cid + ".png")
                shutil.copy2(src, dst)
                rows.append([kind, cid, name, "full", how, src, dst])

            for layer, dst_dir in (("half", dst_half), ("head", dst_head)):
                src, how = pick_layer(kind, cid, layer)
                if src:
                    dst = os.path.join(dst_dir, cid + ".png")
                    shutil.copy2(src, dst)
                    rows.append([kind, cid, name, layer, how, src, dst])

    with open(os.path.join(out_root, "manifest.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "name", "layer", "source_kind", "source", "output"])
        w.writerows(rows)

    with open(os.path.join(out_root, "excluded.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "name", "quality", "reason"])
        w.writerows(excluded_rows)

    # ---- coverage -------------------------------------------------------
    produced = {}
    for kind, cid, _name, layer, _how, _src, dst in rows:
        produced.setdefault((kind, cid), {})[layer] = dst

    with open(os.path.join(out_root, "coverage.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["type", "id", "name", "quality", "full", "half", "head", "status"])
        for kind in ("patrons", "beauty"):
            for rec in records[kind]:
                cid = str(rec["id"])
                if cid in EXCLUDE.get(kind, ()):
                    continue
                name = record_name(names, kind, rec)
                got = produced.get((kind, cid), {})
                full, half, head = got.get("full", ""), got.get("half", ""), got.get("head", "")
                if full:
                    status = "full"
                elif half and cid in RENDER_BAD.get(kind, ()):
                    status = "half-fallback"
                else:
                    status = "half-only" if half else "missing"
                w.writerow(["patron" if kind == "patrons" else "beauty", cid,
                            name, rec.get("quality", ""),
                            full, half, head, status])

    counts = {}
    for kind, cid, _n, layer, _h, _s, _d in rows:
        counts[(kind, layer)] = counts.get((kind, layer), 0) + 1
    print("out:", out_root)
    for key in sorted(counts):
        print("  %-16s %d" % ("%s/%s" % key, counts[key]))
    print("excluded:", len(excluded_rows))


if __name__ == "__main__":
    main()
