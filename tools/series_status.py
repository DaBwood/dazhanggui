"""Join real series names with the latest coverage_rendered statuses."""
import csv
import os
from collections import Counter, defaultdict

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3"
SERIES = {
    "10000": "五凤来仪", "10001": "精忠报国", "10002": "清平盛世",
    "10003": "绮罗锦衣", "10004": "盈冠华服", "10005": "佳节限定",
    "10006": "百业奇装", "10007": "葫芦兄弟", "10008": "厨艺对决",
    "10009": "青藤七子", "10010": "百花齐放", "10011": "昔日活动",
    "10012": "斗罗大陆", "10013": "君子如剑", "10014": "传说厨具",
    "10015": "汴梁女团", "10017": "绝代双骄", "10019": "厨神之路",
    "10020": "传世珍宝", "10021": "琅琊榜", "10022": "盗墓笔记",
    "10023": "封神演义", "10024": "甄嬛传", "10025": "狐妖小红娘",
    "10026": "山河五岳", "10027": "厨神少年", "10028": "龙山会",
    "20005": "凡人修仙",
}


def main():
    base = {r["costume_id"]: r for r in csv.DictReader(
        open(os.path.join(ROOT, "series_by_classify.csv"), encoding="utf-8-sig"))}
    cov = {r["costume_id"]: r for r in csv.DictReader(
        open(os.path.join(ROOT, "coverage_rendered.csv"), encoding="utf-8-sig"))}

    rows = []
    for cid, r in base.items():
        c = cov.get(cid, {})
        cls = r["classify"]
        rows.append({
            "costume_id": cid,
            "name": r["name"],
            "quality": r["quality"],
            "hero_slug": r["hero_slug"],
            "skin_id": r["skin_id"],
            "classify": cls,
            "series": SERIES.get(cls, ""),
            "source_status": c.get("source_status", ""),
            "render_status": c.get("render_status", ""),
            "output": c.get("full", ""),
        })

    unknown = [r["costume_id"] for r in rows if not r["series"]]
    if unknown:
        raise SystemExit("unmapped series: %s" % unknown)

    full = [r for r in rows if r["render_status"] in ("rendered", "project-backup")]
    half = [r for r in rows if r["render_status"] not in ("rendered", "project-backup")
            and r["source_status"] == "head-poster-only"]
    missing = [r for r in rows if r["render_status"] not in ("rendered", "project-backup")
               and r["source_status"] == "missing"]
    failed = [r for r in rows if r["render_status"] == "render-failed"]
    print("costumes", len(rows), "full", len(full), "half", len(half),
          "missing", len(missing), "render-failed", len(failed))
    print("\n-- remaining gaps by series --")
    gaps = half + missing + failed
    for s, n in Counter(r["series"] for r in gaps).most_common():
        print("  %-8s %2d" % (s, n))
    print("\n-- detail --")
    by = defaultdict(list)
    for r in gaps:
        by[r["series"]].append(r["name"])
    for s, names in sorted(by.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        print("  %s (%d): %s" % (s, len(names), "、".join(names)))

    out = os.path.join(ROOT, "series_status.csv")
    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("\nout", out)


if __name__ == "__main__":
    main()
