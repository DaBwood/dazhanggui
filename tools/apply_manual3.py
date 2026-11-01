"""Apply the three manually restored full-body images and finish 214/214."""
import csv
import os

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3"
HEROES = os.path.join(ROOT, "heroes_cos")
SKINS = {
    "109255": "hua_mulan_cos01",
    "109256": "hua_mulan_cos02",
    "109269": "xiao_ba_cos03",
}


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write(path, rows, fields):
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    p = os.path.join(ROOT, "inventory.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["skin_id"] in SKINS:
            r["spine"] = "1"
            r["status"] = "full-body"
    write(p, rows, fields)

    p = os.path.join(ROOT, "coverage_rendered.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["skin_id"] in SKINS:
            r["source_status"] = "full-body"
            r["render_status"] = "rendered"
            r["full"] = os.path.join(HEROES, r["costume_id"] + ".png")
            r["note"] = "manual restored from in-game full-body"
    write(p, rows, fields)

    p = os.path.join(ROOT, "heroes_cos_manifest.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    by_costume = {r["costume_id"]: r for r in rows}
    cov = {r["skin_id"]: r for r in read(os.path.join(ROOT, "coverage_rendered.csv"))}
    for skin, costume in SKINS.items():
        r = cov[skin]
        path = os.path.join(HEROES, costume + ".png")
        if costume in by_costume:
            row = by_costume[costume]
            row["source"] = "rendered"
            row["output"] = path
            row["note"] = "manual restored from in-game full-body"
        else:
            rows.append({
                "costume_id": costume,
                "name": r["name"],
                "quality": r["quality"],
                "hero_slug": r["hero_slug"],
                "patron_id": r["patron_id"],
                "skin_id": skin,
                "source": "rendered",
                "output": path,
                "note": "manual restored from in-game full-body",
            })
    write(p, rows, fields)
    print("done")


if __name__ == "__main__":
    main()
