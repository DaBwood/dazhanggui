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

print("classify -> series")
for c in sorted(set(str(s["classify"]) for s in skins)):
    print(" ", c, "count", sum(1 for s in skins if str(s["classify"]) == c),
          "name", names.get("PROTAGONIST_FASHION_TAGNAME_" + c, "") or names.get("Patrons_Comb-" + c, ""))

rows = []
for slug, cos_list in costumes["hero_costumes"].items():
    for c in cos_list:
        cid = c["id"]
        i = inv.get(cid, {})
        cv = cov.get(cid, {})
        sid = i.get("skin_id", "")
        s = by_id.get(sid, {})
        cls = str(s.get("classify", ""))
        series = names.get("PROTAGONIST_FASHION_TAGNAME_" + cls, "") or names.get("Patrons_Comb-" + cls, "")
        rows.append([cid, c["name"], c["quality"], slug, sid, cls, series,
                     i.get("status", ""), cv.get("render_status", "")])

gaps = [r for r in rows if r[8] not in ("rendered", "project-backup")]
print("\n-- gaps by classify series --")
for s, n in Counter((r[5], r[6]) for r in gaps).most_common(40):
    print("  %-6s %-12s %d" % (s[0], s[1] or "(no series)", n))
print("\n-- all by classify --")
for s, n in Counter((r[5], r[6]) for r in rows).most_common(40):
    print("  %-6s %-12s %d" % (s[0], s[1] or "(no series)", n))

dst = os.path.join(assets, "clean", "costumes_v3", "series_by_classify.csv")
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["costume_id", "name", "quality", "hero_slug", "skin_id", "classify", "series",
                "source_status", "render_status"])
    w.writerows(rows)
print("out", dst)
