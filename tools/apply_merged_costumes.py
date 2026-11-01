"""Copy merged spineSkin renders into heroes_cos and update the CSVs."""
import csv
import os
import shutil

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3"
MERGE = r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered\costumes_merged"
HEROES = os.path.join(ROOT, "heroes_cos")

ROWS = {
    "hu_lu_xianren_cos02": ("109098", "风吟"),
    "hu_lu_xianren_cos03": ("109067", "金雷"),
    "hu_lu_xianren_cos04": ("109066", "阳焱"),
    "hu_lu_xianren_cos05": ("109065", "龙幽"),
    "hu_lu_xianren_cos06": ("109099", "影"),
    "hu_lu_xianren_cos07": ("109100", "海无量"),
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
    os.makedirs(HEROES, exist_ok=True)
    for costume, (skin, name) in ROWS.items():
        src = os.path.join(MERGE, skin + ".png")
        dst = os.path.join(HEROES, costume + ".png")
        if not os.path.exists(src):
            raise SystemExit("missing merge render: " + src)
        shutil.copy2(src, dst)
        print("copy", skin, "->", costume)

    # inventory
    p = os.path.join(ROOT, "inventory.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["costume_id"] in ROWS:
            r["spine"] = "1"
            r["status"] = "full-body"
    write(p, rows, fields)

    # coverage
    p = os.path.join(ROOT, "coverage_rendered.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["costume_id"] in ROWS:
            r["source_status"] = "full-body"
            r["render_status"] = "rendered"
            r["full"] = os.path.join(HEROES, r["costume_id"] + ".png")
            r["note"] = "base patron + costume spineSkin (merged)"
    write(p, rows, fields)

    # manifest
    p = os.path.join(ROOT, "heroes_cos_manifest.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    have = {r["costume_id"] for r in rows}
    for costume, (skin, name) in ROWS.items():
        if costume in have:
            continue
        rows.append({
            "costume_id": costume,
            "name": name,
            "quality": "素装",
            "hero_slug": "hu_lu_xianren",
            "patron_id": "102501",
            "skin_id": skin,
            "source": "rendered",
            "output": os.path.join(HEROES, costume + ".png"),
            "note": "base patron + costume spineSkin (merged)",
        })
    write(p, rows, fields)
    print("manifest rows", len(rows))


if __name__ == "__main__":
    main()
