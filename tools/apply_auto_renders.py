"""Apply every usable render in costumes_auto to heroes_cos/CSVs."""
import csv
import os
import shutil

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3"
AUTO = r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered\costumes_auto"
HEROES = os.path.join(ROOT, "heroes_cos")


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write(path, rows, fields):
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    if not os.path.isdir(AUTO):
        print("no auto render dir")
        return
    cov = {r["skin_id"]: r for r in read(os.path.join(ROOT, "coverage_rendered.csv"))}
    applied = []
    for name in sorted(os.listdir(AUTO)):
        if not name.endswith(".png"):
            continue
        skin = name[:-4]
        r = cov.get(skin)
        if not r:
            print("no costume for skin", skin)
            continue
        if r["render_status"] in ("rendered", "project-backup"):
            continue
        shutil.copy2(os.path.join(AUTO, name), os.path.join(HEROES, r["costume_id"] + ".png"))
        applied.append(skin)
        print("apply", skin, "->", r["costume_id"], r["name"])
    if not applied:
        print("nothing to apply")
        return
    aset = set(applied)

    p = os.path.join(ROOT, "inventory.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["skin_id"] in aset:
            r["spine"] = "1"
            r["status"] = "full-body"
    write(p, rows, fields)

    p = os.path.join(ROOT, "coverage_rendered.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["skin_id"] in aset:
            r["source_status"] = "full-body"
            r["render_status"] = "rendered"
            r["full"] = os.path.join(HEROES, r["costume_id"] + ".png")
            r["note"] = "series gallery spineSkin (auto)"
    write(p, rows, fields)

    p = os.path.join(ROOT, "heroes_cos_manifest.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    have = {r["costume_id"] for r in rows}
    for r in rows:
        pass
    cov = {r["skin_id"]: r for r in read(os.path.join(ROOT, "coverage_rendered.csv"))}
    for skin in applied:
        r = cov[skin]
        if r["costume_id"] in have:
            continue
        rows.append({
            "costume_id": r["costume_id"],
            "name": r["name"],
            "quality": r["quality"],
            "hero_slug": r["hero_slug"],
            "patron_id": r["patron_id"],
            "skin_id": skin,
            "source": "rendered",
            "output": os.path.join(HEROES, r["costume_id"] + ".png"),
            "note": "series gallery spineSkin (auto)",
        })
    write(p, rows, fields)
    print("applied", len(applied), "manifest", len(rows))


if __name__ == "__main__":
    main()
