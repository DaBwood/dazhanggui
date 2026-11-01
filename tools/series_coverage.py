import csv
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, r"C:\Users\林\Documents\大掌柜\tools")
from portrait_sources import load_alljson, load_names

assets = r"C:\Users\林\Documents\大掌柜_assets"
repo = r"C:\Users\林\Documents\大掌柜"
costumes = json.load(open(os.path.join(repo, "data", "costumes.json"), encoding="utf-8"))
tables = load_alljson(assets)
names = load_names(assets)

inv = {r["costume_id"]: r for r in csv.DictReader(open(os.path.join(assets, "clean", "costumes_v3", "inventory.csv"), encoding="utf-8-sig"))}
cov = {r["costume_id"]: r for r in csv.DictReader(open(os.path.join(assets, "clean", "costumes_v3", "coverage_rendered.csv"), encoding="utf-8-sig"))}

vol_tab = tables["SkinVolumuDB"]
if isinstance(vol_tab, str):
    vol_tab = json.loads(vol_tab)
vol_tab = vol_tab["SkinVolumuDB"] if isinstance(vol_tab, dict) else vol_tab
vh = vol_tab[1]
vols = [dict(zip(vh, r)) for r in vol_tab[2:]]

skin_to_series = defaultdict(list)
series_names = {}
for v in vols:
    vid = str(v["id"])
    nm = names.get("Skin_Volumu_Name-" + vid, "")
    series_names[vid] = nm
    for sid in str(v["skinIdList"]).split("|"):
        if sid:
            skin_to_series[sid].append((vid, nm))

rows = []
for slug, cos_list in costumes["hero_costumes"].items():
    for c in cos_list:
        cid = c["id"]
        i = inv.get(cid, {})
        cv = cov.get(cid, {})
        sid = i.get("skin_id", "")
        series = skin_to_series.get(sid, [])
        sname = series[0][1] if series else ""
        rows.append([cid, c["name"], c["quality"], slug, sid,
                     sname, c.get("series", ""), i.get("status", ""), cv.get("render_status", "")])

dst = os.path.join(assets, "clean", "costumes_v3", "series_coverage.csv")
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["costume_id", "name", "quality", "hero_slug", "skin_id",
                "game_series", "project_series", "source_status", "render_status"])
    w.writerows(rows)

gaps = [r for r in rows if r[8] not in ("rendered", "project-backup")]
print("costumes", len(rows), "gaps", len(gaps))
print("\n-- gaps by game series --")
for s, n in Counter(r[5] or "(no series)" for r in gaps).most_common(40):
    print("  %-12s %d" % (s, n))
print("\n-- all project series counts --")
for s, n in Counter(r[6] or "(project empty)" for r in rows).most_common(30):
    print("  %-12s %d" % (s, n))
print("\n-- series totals in SkinVolumuDB --")
for v in vols[:20]:
    print(" ", v["id"], series_names[str(v["id"])], v["skinIdList"])
print("out", dst)
