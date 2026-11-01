import csv
import json
import os
import sys

sys.path.insert(0, r"C:\Users\林\Documents\大掌柜\tools")
from portrait_sources import load_alljson, load_names, load_records, record_name

repo = r"C:\Users\林\Documents\大掌柜"
assets = r"C:\Users\林\Documents\大掌柜_assets"
costumes = json.load(open(os.path.join(repo, "data", "costumes.json"), encoding="utf-8"))
heroes = json.load(open(os.path.join(repo, "data", "heroes.json"), encoding="utf-8"))
tables = load_alljson(assets)
names = load_names(assets)
tar_ids = set(json.load(open(r"C:\Users\林\AppData\Local\Temp\opencode\skin_tar_ids.json", encoding="utf-8")))

slug_to_id = {}
# Prefer the canonical roster id. Duplicate patron rows (102526-29 小柒,
# 102536-39 小八) share the same name but carry empty placeholder skins.
roster_path = os.path.join(assets, "clean", "portraits_v3", "roster_109.csv")
roster = {}
if os.path.exists(roster_path):
    for row in csv.DictReader(open(roster_path, encoding="utf-8-sig")):
        if row.get("project_name") and row.get("id"):
            roster[row["project_name"]] = row["id"]
for slug, h in heroes.items():
    cid = roster.get(h.get("name", ""))
    if cid:
        slug_to_id[slug] = cid
for rec in load_records(assets, "patrons", tables):
    nm = record_name(names, "patrons", rec)
    for slug, h in heroes.items():
        if slug not in slug_to_id and h.get("name") == nm:
            slug_to_id[slug] = str(rec["id"])

skin_tab = tables["SkinsInfoDB"]
if isinstance(skin_tab, str):
    skin_tab = json.loads(skin_tab)
skin_tab = skin_tab["SkinsInfoDB"] if isinstance(skin_tab, dict) else skin_tab
hdr = skin_tab[1]
skins = [dict(zip(hdr, r)) for r in skin_tab[2:]]
QUALITY = {"素装": 1, "华服": 2, "锦衣": 3}


def skin_name(sid):
    return names.get("Skin_Name-" + str(sid), "")


def has_spine(sid):
    return os.path.isdir(os.path.join(assets, "hotupdate", "skins", sid, "spineSkin")) or sid in tar_ids


def has_hot(sid):
    return os.path.exists(os.path.join(assets, "clean", "hot_skins", sid + ".png"))


def has_astc(sid):
    return os.path.isdir(os.path.join(assets, "clean", "costumes_astc", sid))


def lev1(a, b):
    if a == b:
        return True
    if abs(len(a) - len(b)) > 1:
        return False
    if len(a) == len(b):
        return sum(1 for x, y in zip(a, b) if x != y) == 1
    if len(a) > len(b):
        a, b = b, a
    i = j = 0
    skipped = False
    while i < len(a) and j < len(b):
        if a[i] == b[j]:
            i += 1
            j += 1
        elif skipped:
            return False
        else:
            skipped = True
            j += 1
    return True


rows = []
for slug, cos_list in costumes["hero_costumes"].items():
    pid = slug_to_id.get(slug, "")
    patron_skins = sorted([s for s in skins if str(s["belongRole"]) == pid], key=lambda s: int(s["sort"]))
    for idx, cos in enumerate(cos_list):
        q = QUALITY.get(cos["quality"], 0)
        exact = [s for s in patron_skins if skin_name(s["skinId"]) == cos["name"]]
        fuzzy = [s for s in patron_skins if lev1(skin_name(s["skinId"]), cos["name"])]
        cand = [s for s in exact if int(s["quality"]) == q] or [s for s in fuzzy if int(s["quality"]) == q]
        how = "name"
        if not cand:
            cand = exact or fuzzy
        if not cand and idx < len(patron_skins):
            cand = [patron_skins[idx]]
            how = "order"
        cand.sort(key=lambda s: (
            0 if (has_spine(str(s["skinId"])) or has_hot(str(s["skinId"]))) else 1,
            0 if str(s["skinId"]).startswith("109") else 1,
            int(s["sort"])))
        skin = cand[0] if cand else None
        sid = str(skin["skinId"]) if skin else ""
        spine, hot, astc = has_spine(sid), has_hot(sid), has_astc(sid)
        if spine:
            status = "full-body"
        elif astc:
            status = "head-poster-only"
        else:
            status = "missing"
        rows.append([cos["id"], cos["name"], cos["quality"], slug, pid, sid, how,
                     int(spine), int(hot), int(astc), status])

out = os.path.join(assets, "clean", "costumes_v3")
os.makedirs(out, exist_ok=True)
dst = os.path.join(out, "inventory.csv")
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["costume_id", "name", "quality", "hero_slug", "patron_id", "skin_id",
                "mapping", "spine", "hot_png", "astc", "status"])
    w.writerows(rows)

from collections import Counter
print("costumes", len(rows))
print("status", Counter(r[10] for r in rows))
print("out", dst)
