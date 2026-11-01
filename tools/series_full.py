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

skin_tab = tables["SkinsInfoDB"]
if isinstance(skin_tab, str):
    skin_tab = json.loads(skin_tab)
skin_tab = skin_tab["SkinsInfoDB"] if isinstance(skin_tab, dict) else skin_tab
hdr = skin_tab[1]
skins = [dict(zip(hdr, r)) for r in skin_tab[2:]]
by_id = {str(s["skinId"]): s for s in skins}

vol_tab = tables["SkinVolumuDB"]
if isinstance(vol_tab, str):
    vol_tab = json.loads(vol_tab)
vol_tab = vol_tab["SkinVolumuDB"] if isinstance(vol_tab, dict) else vol_tab
vh = vol_tab[1]
vols = [dict(zip(vh, r)) for r in vol_tab[2:]]
skin_volume = {}
for v in vols:
    vn = names.get("Skin_Volumu_Name-" + str(v["id"]), "")
    for sid in str(v["skinIdList"]).split("|"):
        if sid and sid not in skin_volume:
            skin_volume[sid] = (str(v["id"]), vn)

rows = []
for slug, cos_list in costumes["hero_costumes"].items():
    for c in cos_list:
        cid = c["id"]
        i = inv.get(cid, {})
        cv = cov.get(cid, {})
        sid = i.get("skin_id", "")
        s = by_id.get(sid, {})
        cls = str(s.get("classify", ""))
        comb = names.get("Patrons_Comb-" + cls, "")
        fashion = names.get("PROTAGONIST_FASHION_TAGNAME_" + cls, "")
        vol = skin_volume.get(sid, ("", ""))
        series = comb or fashion or vol[1] or "未分类"
        rows.append([cid, c["name"], c["quality"], slug, sid, cls, comb, fashion, vol[0], vol[1],
                     series, i.get("status", ""), cv.get("render_status", "")])

gaps = [r for r in rows if r[12] not in ("rendered", "project-backup")]
print("costumes", len(rows), "gaps", len(gaps), "no-series", sum(1 for r in rows if r[10] == "未分类"))
print("\n-- gaps by series (comb/fashion/volume) --")
for s, n in Counter(r[10] for r in gaps).most_common(50):
    print("  %-12s %d" % (s, n))

dst = os.path.join(assets, "clean", "costumes_v3", "series_full.csv")
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["costume_id", "name", "quality", "hero_slug", "skin_id", "classify",
                "comb", "fashion_tag", "volume_id", "volume_name", "series",
                "source_status", "render_status"])
    w.writerows(rows)
print("out", dst)
