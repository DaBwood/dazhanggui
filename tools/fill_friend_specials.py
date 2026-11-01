"""Fill friend costumes that share patron art or use the base beauty portrait."""
import csv
import json
import os
import shutil

REPO = r"C:\Users\林\Documents\大掌柜"
ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
ROOT = os.path.join(ASSETS, "clean", "costumes_v3")
INV = os.path.join(ROOT, "friend_costume_inventory.csv")
OUT = os.path.join(ROOT, "friends_cos")
COV = os.path.join(ROOT, "friends_coverage.csv")
FRIENDS_FULL = os.path.join(ASSETS, "clean", "portraits_v3", "friends_full")


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def main():
    inv = read(INV)
    heroes = json.load(open(os.path.join(REPO, "data", "costumes.json"),
                            encoding="utf-8"))["hero_costumes"]
    hero_by_skin = {}
    for cos_list in heroes.values():
        for c in cos_list:
            # skin id is filled from inventory later; use a separate mapping file
            pass
    # patron costume id -> skin id from the hero inventory
    hero_inv = read(os.path.join(ROOT, "inventory.csv"))
    hero_skin_to_costume = {r["skin_id"]: r["costume_id"] for r in hero_inv}

    existing = {}
    if os.path.exists(COV):
        existing = {r["costume_id"]: r for r in read(COV)}

    rows = []
    filled = 0
    for r in inv:
        cid = r["costume_id"]
        skin = r["skin_id"]
        dst = os.path.join(OUT, cid + ".png")
        status = existing.get(cid, {}).get("status", "")
        if os.path.exists(dst):
            status = status or "rendered"
        elif skin and skin in hero_skin_to_costume:
            src = os.path.join(ROOT, "heroes_cos", hero_skin_to_costume[skin] + ".png")
            if os.path.exists(src):
                shutil.copy2(src, dst)
                status = "shared-patron"
                filled += 1
        elif r["beauty_id"]:
            src = os.path.join(FRIENDS_FULL, r["beauty_id"] + ".png")
            if os.path.exists(src):
                shutil.copy2(src, dst)
                status = "base-portrait"
                filled += 1
        rows.append([cid, r["name"], r["quality"], r["friend_slug"],
                     r["friend_name"], r["beauty_id"], skin, status or "missing", dst if os.path.exists(dst) else ""])

    with open(COV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["costume_id", "name", "quality", "friend_slug", "friend_name",
                    "beauty_id", "skin_id", "status", "output"])
        w.writerows(rows)
    print("filled", filled, "total", len(rows),
          "rendered", sum(1 for r in rows if r[7] == "rendered"),
          "shared", sum(1 for r in rows if r[7] == "shared-patron"),
          "base", sum(1 for r in rows if r[7] == "base-portrait"),
          "missing", sum(1 for r in rows if r[7] == "missing"))
    print(COV)


if __name__ == "__main__":
    main()
