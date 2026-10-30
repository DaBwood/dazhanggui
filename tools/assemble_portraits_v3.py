#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Assemble clean/portraits_v3 from every trustworthy full-body source.

Priority for a full-body image (highest first):

  1. clean/fullbody_render/<id>.png        already composed by the game
  2. clean/fullbody_render/<id>_1.png      alt pose of the same character
  3. clean/portraits_v2/*_page/<id>.png    full-body 3.png colour page
  4. clean/portraits_v3/rendered/*/<id>.png  Spine render of the missing ones
  5. reuse map                             shared appearanceId art

Half / head crops are copied from portraits_v2 (they come from the masked
2.png / 4.png pages and were never affected by the atlas-page problem).
Characters whose render was reviewed as broken (RENDER_BAD) instead use the
v2 half-body crop and are marked "half-fallback" in coverage.csv.

Output:
  clean/portraits_v3/heroes_full|friends_full|heroes_half|friends_half|
                    heroes_head|friends_head
  clean/portraits_v3/manifest.csv
  clean/portraits_v3/coverage.csv

Usage:
  python tools/assemble_portraits_v3.py
"""

import argparse
import csv
import json
import os
import shutil

# appearanceId 1025350 is shared by 102535..102539; only 102535 has art.
REUSE = {cid: "102535" for cid in ("102536", "102537", "102538", "102539")}

# Spine renders reviewed as broken / scene-garbage on the contact sheets
# (their atlas colour page is effect debris, and the v2 full crops of the same
# ids are atlas garbage too) => no trustworthy full body; fall back to v2 half.
RENDER_BAD = {
    "patrons": {"102517", "102519", "102523", "102540"},
    "beauty": {"103379", "103382", "103388", "103390"},
}


def load_ids(assets, kind):
    path = os.path.join(assets, "text", "cn", "allJson", "AllJson2.json")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    key = "PatronsDB" if kind == "patrons" else "BeautyDB"
    table = data[key]
    if isinstance(table, str):
        table = json.loads(table)
    table = table[key] if isinstance(table, dict) else table
    header = table[1]
    return [dict(zip(header, row)) for row in table[2:]]


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


def index_tree(root, suffixes=(".png",)):
    """Same as index_dir but walks subdirectories too (e.g. fullbody_render/门客)."""
    out = {}
    if not os.path.isdir(root):
        return out
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            base, ext = os.path.splitext(name)
            if ext.lower() not in suffixes or base.endswith("_preview"):
                continue
            out.setdefault(base, os.path.join(dirpath, name))
    return out


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

    composed = index_tree(os.path.join(clean, "fullbody_render"))
    rows = []

    plan = {
        "patrons": ("heroes", "patrons"),
        "beauty": ("friends", "beauty"),
    }
    for kind, (prefix, render_kind) in plan.items():
        page = index_dir(os.path.join(v2, prefix + "_page"))
        half = index_dir(os.path.join(v2, prefix + "_half"))
        head = index_dir(os.path.join(v2, prefix + "_head"))
        drawn = index_dir(os.path.join(rendered, render_kind))
        dst_full = os.path.join(out_root, prefix + "_full")
        dst_half = os.path.join(out_root, prefix + "_half")
        dst_head = os.path.join(out_root, prefix + "_head")
        for d in (dst_full, dst_half, dst_head):
            os.makedirs(d, exist_ok=True)

        for rec in load_ids(assets, kind):
            cid = str(rec["id"])
            bad = RENDER_BAD.get(kind, ())
            src = ""
            how = ""
            for tag, table in (("composed", composed), ("page", page), ("rendered", drawn)):
                if tag == "rendered" and cid in bad:
                    continue  # reviewed as broken / scene-garbage
                if cid in table:
                    src, how = table[cid], tag
                    break
                if tag == "composed" and cid + "_1" in table:
                    src, how = table[cid + "_1"], "composed:" + cid + "_1"
                    break
            if not src and cid in REUSE:
                donor = REUSE[cid]
                for tag, table in (("composed", composed), ("page", page), ("rendered", drawn)):
                    if donor in table:
                        src, how = table[donor], "reuse:" + donor
                        break

            if src:
                dst = os.path.join(dst_full, cid + ".png")
                shutil.copy2(src, dst)
                rows.append([kind, cid, rec.get("name", ""), "full", how, src, dst])

            for tag, table, dst_dir in (("half", half, dst_half), ("head", head, dst_head)):
                src2, how2 = table.get(cid), "v2"
                if not src2 and cid in REUSE and REUSE[cid] in table:
                    src2, how2 = table[REUSE[cid]], "reuse:" + REUSE[cid]
                if src2:
                    dst = os.path.join(dst_dir, cid + ".png")
                    shutil.copy2(src2, dst)
                    rows.append([kind, cid, rec.get("name", ""), tag, how2, src2, dst])

    with open(os.path.join(out_root, "manifest.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "name", "layer", "source_kind", "source", "output"])
        w.writerows(rows)

    # ---- coverage -------------------------------------------------------
    produced = {}
    for kind, cid, _name, layer, _how, _src, dst in rows:
        produced.setdefault((kind, cid), {})[layer] = dst

    with open(os.path.join(out_root, "coverage.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["type", "id", "name", "quality", "full", "half", "head", "status"])
        for kind in ("patrons", "beauty"):
            for rec in load_ids(assets, kind):
                cid = str(rec["id"])
                got = produced.get((kind, cid), {})
                full, half, head = got.get("full", ""), got.get("half", ""), got.get("head", "")
                if full:
                    status = "full"
                elif half and cid in RENDER_BAD.get(kind, ()):
                    status = "half-fallback"
                else:
                    status = "half-only" if half else "missing"
                w.writerow(["patron" if kind == "patrons" else "beauty", cid,
                            rec.get("name", ""), rec.get("quality", ""),
                            full, half, head, status])

    counts = {}
    for kind, cid, _n, layer, _h, _s, _d in rows:
        counts[(kind, layer)] = counts.get((kind, layer), 0) + 1
    print("out:", out_root)
    for key in sorted(counts):
        print("  %-16s %d" % ("%s/%s" % key, counts[key]))


if __name__ == "__main__":
    main()
