import csv
import json
import os
import sys
from collections import Counter

sys.path.insert(0, r"C:\Users\林\Documents\大掌柜\tools")
from portrait_sources import load_alljson, load_names

assets = r"C:\Users\林\Documents\大掌柜_assets"
root = os.path.join(assets, "clean", "costumes_v3")
repo = r"C:\Users\林\Documents\大掌柜"
costumes = json.load(open(os.path.join(repo, "data", "costumes.json"), encoding="utf-8"))
inventory = {r["costume_id"]: r for r in csv.DictReader(open(os.path.join(root, "inventory.csv"), encoding="utf-8-sig"))}
tables = load_alljson(assets)
names = load_names(assets)

skin_tab = tables["SkinsInfoDB"]
if isinstance(skin_tab, str):
    skin_tab = json.loads(skin_tab)
skin_tab = skin_tab["SkinsInfoDB"] if isinstance(skin_tab, dict) else skin_tab
hdr = skin_tab[1]
skins = [dict(zip(hdr, r)) for r in skin_tab[2:]]
by_id = {str(s["skinId"]): s for s in skins}

pulled_map = json.load(open(r"C:\Users\林\AppData\Local\Temp\opencode\pulled_subpackages.json", encoding="utf-8"))
pulled = set(pulled_map.keys())
pulled_spine = {i for i, files in pulled_map.items() if any("/spineSkin/" in f for f in files)}
dzg_spine = set(json.load(open(r"C:\Users\林\AppData\Local\Temp\opencode\dzg_spine_ids.json", encoding="utf-8")))
dzg_skin = set(json.load(open(r"C:\Users\林\AppData\Local\Temp\opencode\dzg_skin_ids.json", encoding="utf-8")))

hot_spine = set()
hot_dir = os.path.join(assets, "hotupdate", "skins")
for cid in os.listdir(hot_dir):
    if os.path.isdir(os.path.join(hot_dir, cid, "spineSkin")):
        hot_spine.add(cid)
hot_png = {os.path.splitext(f)[0] for f in os.listdir(os.path.join(assets, "clean", "hot_skins")) if f.endswith(".png")}
astc = {f for f in os.listdir(os.path.join(assets, "clean", "costumes_astc")) if os.path.isdir(os.path.join(assets, "clean", "costumes_astc", f))}

full_spine = hot_spine | pulled_spine
full_any = full_spine | hot_png
low_spine = dzg_spine
half = astc | dzg_skin

QUALITY = {"素装": 1, "华服": 2, "锦衣": 3}


def sname(sid):
    return names.get("Skin_Name-" + str(sid), "")


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


def level(sid):
    if sid in full_spine:
        return "full_spine"
    if sid in hot_png:
        return "full_hot"
    if sid in low_spine:
        return "low_spine"
    if sid in half:
        return "half"
    return ""


rows = []
for slug, cos_list in costumes["hero_costumes"].items():
    for cos in cos_list:
        cid = cos["id"]
        inv = inventory.get(cid, {})
        cur = inv.get("skin_id", "")
        cur_status = inv.get("status", "")
        if cur_status == "full-body":
            # already rendered or failed; only flag if not rendered
            out = os.path.join(root, "heroes_cos", cid + ".png")
            if os.path.exists(out):
                continue
        q = QUALITY.get(cos["quality"], 0)
        cand = []
        for sid, s in by_id.items():
            nm = sname(sid)
            if not nm:
                continue
            if nm == cos["name"] or lev1(nm, cos["name"]):
                lv = level(sid)
                if not lv:
                    continue
                cand.append((sid, s, lv))
        cand.sort(key=lambda x: (
            0 if int(x[1]["quality"]) == q else 1,
            0 if x[2] == "full_spine" else 1 if x[2] == "full_hot" else 2 if x[2] == "low_spine" else 3,
            0 if str(x[1]["belongRole"]) == inv.get("patron_id", "") else 1,
            str(x[0])))
        best = cand[0] if cand else None
        if best:
            sid, s, lv = best
            rows.append([cid, cos["name"], cos["quality"], slug, inv.get("patron_id", ""), cur, cur_status,
                         sid, str(s["belongRole"]), sname(sid), lv, "new"])
        else:
            rows.append([cid, cos["name"], cos["quality"], slug, inv.get("patron_id", ""), cur, cur_status,
                         "", "", "", "", ""])

dst = os.path.join(root, "remap_candidates.csv")
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f)
    w.writerow(["costume_id", "name", "quality", "hero_slug", "patron_id", "current_skin",
                "current_status", "candidate_skin", "candidate_role", "candidate_name",
                "asset_level", "flag"])
    w.writerows(rows)

gaps = [r for r in rows if r[6] != "full-body" or not r[7]]
print("rows", len(rows), "gaps", len(gaps))
print("asset level", Counter(r[10] for r in gaps))
print("new full candidates", sum(1 for r in gaps if r[10] in ("full_spine", "full_hot")))
print("out", dst)
for r in gaps[:20]:
    print(r)
