#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compare the project's 117-friend roster with portraits_v3.

Reads data/friends.json, maps each display name to its BeautyDB id through
clean/portraits_v3/names.csv, then checks the actual full/half/head files.

Output:
  clean/portraits_v3/friends_117_check.csv

Usage:
  python tools/check_friends.py
"""

import argparse
import csv
import json
import os


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=r"C:\Users\林\Documents\大掌柜")
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    root = os.path.join(os.path.abspath(args.assets), "clean", "portraits_v3")
    project = json.load(open(os.path.join(repo, "data", "friends.json"), encoding="utf-8"))
    rows = [r for r in csv.DictReader(open(os.path.join(root, "names.csv"), encoding="utf-8-sig"))
            if r["type"] == "beauty"]
    by_name = {r["name"]: r for r in rows}

    def path(layer, cid):
        folder = {"full": "friends_full", "half": "friends_half", "head": "friends_head"}[layer]
        rel = "%s/%s.png" % (folder, cid)
        return rel if os.path.exists(os.path.join(root, rel)) else ""

    out = []
    for key, rec in project.items():
        name = rec.get("name", "")
        a = by_name.get(name)
        if not a:
            out.append([name, key, "", "absent", "no BeautyDB row", "", "", ""])
            continue
        cid = a["id"]
        full, half, head = path("full", cid), path("half", cid), path("head", cid)
        status = "full" if full else ("half-only" if half else "missing")
        note = "" if status == "full" else "art files not shipped in this package"
        out.append([name, key, cid, status, note, full, half, head])

    project_names = {rec.get("name", "") for rec in project.values()}
    extras = []
    for name, a in by_name.items():
        if name in project_names:
            continue
        cid = a["id"]
        full, half, head = path("full", cid), path("half", cid), path("head", cid)
        status = "full" if full else ("half-only" if half else "missing")
        extras.append([name, "", cid, status, "extra in BeautyDB, not in friends.json", full, half, head])

    dst = os.path.join(root, "friends_117_check.csv")
    with open(dst, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["project_name", "key", "id", "status", "note", "full", "half", "head"])
        w.writerows(out)
        w.writerows(extras)

    from collections import Counter
    print("project:", len(project))
    print("status:", Counter(r[3] for r in out))
    print("extras:", len(extras), Counter(r[3] for r in extras))
    print("out:", dst)


if __name__ == "__main__":
    main()
