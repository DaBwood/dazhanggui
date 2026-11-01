"""Apply the 20 on-device spineSkin gap renders to heroes_cos/CSVs."""
import csv
import os
import shutil

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3"
SRC = r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v3\rendered\costumes_gap"
HEROES = os.path.join(ROOT, "heroes_cos")

SKINS = [
    "109008", "109094", "109041", "109093", "109112", "109158", "109090",
    "109054", "109055", "109056", "109057", "109032", "109194", "109195",
    "109193", "109192", "109191", "109111", "109113", "109119",
]


def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write(path, rows, fields):
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    cov = {r["skin_id"]: r for r in read(os.path.join(ROOT, "coverage_rendered.csv"))}
    by_skin = {s: cov[s] for s in SKINS}
    os.makedirs(HEROES, exist_ok=True)
    for skin, r in by_skin.items():
        src = os.path.join(SRC, skin + ".png")
        if not os.path.exists(src):
            print("skip missing render", skin)
            continue
        shutil.copy2(src, os.path.join(HEROES, r["costume_id"] + ".png"))
        print("copy", skin, "->", r["costume_id"])

    p = os.path.join(ROOT, "inventory.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["skin_id"] in by_skin:
            r["spine"] = "1"
            r["status"] = "full-body"
    write(p, rows, fields)

    p = os.path.join(ROOT, "coverage_rendered.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    for r in rows:
        if r["skin_id"] in by_skin:
            r["source_status"] = "full-body"
            r["render_status"] = "rendered"
            r["full"] = os.path.join(HEROES, r["costume_id"] + ".png")
            r["note"] = ("effect/rock form" if r["skin_id"] == "109057"
                         else "device spineSkin (on-demand)")
    write(p, rows, fields)

    p = os.path.join(ROOT, "heroes_cos_manifest.csv")
    rows = read(p)
    fields = list(rows[0].keys())
    have = {r["costume_id"] for r in rows}
    for skin, r in by_skin.items():
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
            "note": "effect/rock form" if skin == "109057" else "device spineSkin (on-demand)",
        })
    write(p, rows, fields)
    print("manifest rows", len(rows))


if __name__ == "__main__":
    main()
