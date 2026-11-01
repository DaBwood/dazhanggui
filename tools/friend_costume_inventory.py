"""Map data/costumes.json friend costumes to SkinsInfoDB beauty skins."""
import csv
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from portrait_sources import load_alljson, load_names, load_records, record_name

REPO = r"C:\Users\林\Documents\大掌柜"
ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
OUT = os.path.join(ASSETS, "clean", "costumes_v3", "friend_costume_inventory.csv")


def main():
    names = load_names(ASSETS)
    tables = load_alljson(ASSETS)
    skins_tab = tables["SkinsInfoDB"]
    if isinstance(skins_tab, str):
        skins_tab = json.loads(skins_tab)
    skins_tab = skins_tab["SkinsInfoDB"] if isinstance(skins_tab, dict) else skins_tab
    hdr = skins_tab[1]
    skins = [dict(zip(hdr, r)) for r in skins_tab[2:]]
    beauty = load_records(ASSETS, "beauty", tables)
    by_name = defaultdict(list)
    for r in beauty:
        by_name[record_name(names, "beauty", r)].append(str(r["id"]))
    by_role = defaultdict(list)
    for s in skins:
        if s["type"] == 2:
            by_role[str(s["belongRole"])].append(s)

    friend_data = json.load(open(os.path.join(REPO, "data", "friends.json"), encoding="utf-8"))
    costumes = json.load(open(os.path.join(REPO, "data", "costumes.json"), encoding="utf-8"))["friend_costumes"]

    rows = []
    for slug, cos_list in costumes.items():
        fname = friend_data.get(slug, {}).get("name", "")
        bids = by_name.get(fname, [])
        bid = bids[0] if len(bids) == 1 else (bids[0] if bids else "")
        pool = by_role.get(bid, [])
        used = set()
        for c in cos_list:
            cid = c["id"]
            cname = c["name"]
            sid = ""
            mapping = ""
            for s in pool:
                if str(s["skinId"]) in used:
                    continue
                sn = names.get("Skin_Name-" + str(s["skinId"]), "")
                if sn == cname:
                    sid = str(s["skinId"])
                    mapping = "name"
                    break
            if not sid:
                # fallback: first unused skin in sort order
                for s in sorted(pool, key=lambda x: int(x["sort"])):
                    if str(s["skinId"]) not in used:
                        sid = str(s["skinId"])
                        mapping = "sort"
                        break
            if sid:
                used.add(sid)
            rows.append([cid, cname, c.get("quality", ""), slug, fname, bid, sid, mapping])

    with open(OUT, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["costume_id", "name", "quality", "friend_slug", "friend_name",
                    "beauty_id", "skin_id", "mapping"])
        w.writerows(rows)
    print("friends", len(costumes), "costumes", len(rows),
          "mapped", sum(1 for r in rows if r[6]),
          "unmapped", sum(1 for r in rows if not r[6]))
    print("out", OUT)


if __name__ == "__main__":
    main()
