"""Build the real costume-series table.

The series name is the title on `newGui/SkinClassify/title/<classify>.png`
(and the poster in `clean/costume_series_titles`).  `SkinsInfoDB.classify`
is the series id; `Patrons_Comb` is a patron-aura combo and must not be used
as the costume series name.
"""
import csv
import os
from collections import Counter, defaultdict

ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
SRC = os.path.join(ASSETS, "clean", "costumes_v3", "series_by_classify.csv")
DST = os.path.join(ASSETS, "clean", "costumes_v3", "series_real.csv")

# Read from the series title art in clean/costume_series_titles.
SERIES = {
    "10000": "五凤来仪",
    "10001": "精忠报国",
    "10002": "清平盛世",
    "10003": "绮罗锦衣",
    "10004": "盈冠华服",
    "10005": "佳节限定",
    "10006": "百业奇装",
    "10007": "葫芦兄弟",
    "10008": "厨艺对决",
    "10009": "青藤七子",
    "10010": "百花齐放",
    "10011": "昔日活动",
    "10012": "斗罗大陆",
    "10013": "君子如剑",
    "10014": "传说厨具",
    "10015": "汴梁女团",
    "10017": "绝代双骄",
    "10019": "厨神之路",
    "10020": "传世珍宝",
    "10021": "琅琊榜",
    "10022": "盗墓笔记",
    "10023": "封神演义",
    "10024": "甄嬛传",
    "10025": "狐妖小红娘",
    "10026": "山河五岳",
    "10027": "厨神少年",
    "10028": "龙山会",       # no title art in this build; SkinVolumuDB 10028
    "20005": "凡人修仙",
}


def main():
    rows = list(csv.DictReader(open(SRC, encoding="utf-8-sig")))
    for r in rows:
        r["series"] = SERIES.get(r["classify"], "")

    unknown = sorted({r["classify"] for r in rows if not r["series"]})
    if unknown:
        raise SystemExit("unmapped classify: %s" % unknown)

    with open(DST, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["costume_id", "name", "quality", "hero_slug", "skin_id",
                    "classify", "series", "source_status", "render_status"])
        for r in rows:
            w.writerow([r["costume_id"], r["name"], r["quality"], r["hero_slug"],
                        r["skin_id"], r["classify"], r["series"],
                        r["source_status"], r["render_status"]])

    gaps = [r for r in rows if r["render_status"] not in ("rendered", "project-backup")]
    print("costumes %d  gaps %d  series %d  no-series %d" % (
        len(rows), len(gaps), len(set(r["series"] for r in rows)),
        sum(1 for r in rows if not r["series"])))
    print("\n-- gaps by series --")
    for series, n in Counter(r["series"] for r in gaps).most_common():
        print("  %-8s %2d" % (series, n))
    print("\n-- gaps detail --")
    by = defaultdict(list)
    for r in gaps:
        by[r["series"]].append(r["name"])
    for series, names in sorted(by.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        print("  %s (%d): %s" % (series, len(names), "、".join(names)))
    print("\nout", DST)


if __name__ == "__main__":
    main()
