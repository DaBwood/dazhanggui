#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Turn key *DB.json tables into readable CSV/Markdown with zh_cn text."""

import csv
import json
import os
import sys
from collections import Counter

BASE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "大掌柜_assets"))
ROOT = os.path.join(BASE, "text")
OUT = os.path.join(BASE, "analysis")


def load(name, sub="cn/json/HH"):
    p = os.path.join(ROOT, sub, name + ".json")
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    return d[list(d.keys())[0]]


def rows_of(table):
    """table = [["id"], ["id", ...header], [row...], ...]"""
    header = table[1]
    out = []
    for r in table[2:]:
        if isinstance(r, list) and len(r) == len(header):
            out.append(dict(zip(header, r)))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)

    def tr(key):
        # LanguageWordDB 的 zh_cn 是字体加密（随机 CJK），不可直接读；
        # 这里保留 key（如 SystemName-1），数值/条件/价格都可读。
        return str(key)

    # SystemInfoDB: 系统开放顺序
    sys_rows = rows_of(load("SystemInfoDB"))
    sys_rows.sort(key=lambda r: (r.get("sort", 0), r.get("id", 0)))
    with open(os.path.join(OUT, "systems.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["sort", "id", "name", "conditionType", "value", "desc"])
        for r in sys_rows:
            w.writerow([r.get("sort"), r.get("id"), tr(r.get("name")), r.get("conditionType"), r.get("value"), tr(r.get("desc"))])

    # SystemGuideDB: 新手引导链
    guide = rows_of(load("SystemGuideDB"))
    chain = []
    by_id = {r.get("id"): r for r in guide}
    cur = min(by_id.keys()) if by_id else None
    seen = set()
    while cur in by_id and cur not in seen:
        seen.add(cur)
        r = by_id[cur]
        chain.append(r)
        nxt = r.get("nextID")
        cur = nxt if nxt in by_id else None
    with open(os.path.join(OUT, "guide_chain.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["step", "id", "desc", "scene", "clickRange", "nextID"])
        for i, r in enumerate(chain, 1):
            w.writerow([i, r.get("id"), tr(r.get("desc")), r.get("scene"), r.get("clickRange"), r.get("nextID")])

    # GameShopDB
    shop = rows_of(load("GameShopDB"))
    with open(os.path.join(OUT, "shop.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "name", "price", "vipLimit", "rechargeId", "reward", "sort"])
        for r in shop:
            w.writerow([r.get("id"), tr(r.get("name")), r.get("price"), r.get("vipLimit"), r.get("rechargeId"), r.get("reward"), r.get("sort")])

    # GameStageDB chapters
    stages = rows_of(load("GameStageDB"))
    ch = Counter(str(r.get("chapter", "")) for r in stages)
    with open(os.path.join(OUT, "stage_chapters.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["chapter", "stages"])
        for k, v in sorted(ch.items(), key=lambda kv: int(kv[0]) if kv[0].isdigit() else 0):
            w.writerow([k, v])

    # GamePaidDB
    paid = rows_of(load("GamePaidDB"))
    with open(os.path.join(OUT, "paid.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "price", "repeatReward", "vip"])
        for r in paid:
            w.writerow([r.get("id"), r.get("price"), r.get("repeatReward"), r.get("vip")])

    # Markdown summary
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8") as f:
        f.write("# 原作配置摘要\n\n")
        f.write("- 系统数：%d\n" % len(sys_rows))
        f.write("- 引导步数（链）：%d / 表内 %d\n" % (len(chain), len(guide)))
        f.write("- 关卡总数：%d；章节数：%d\n" % (len(stages), len(ch)))
        f.write("- 商城条目：%d；付费档位：%d\n\n" % (len(shop), len(paid)))
        f.write("> `LanguageWordDB` 的中文是字体加密，名称列保留 key（如 `SystemName-1`）；数值/条件/价格是原值。\n\n")
        f.write("## 系统开放顺序（前 40）\n\n")
        f.write("| sort | id | 名称(key) | 条件 | 值 |\n|---|---|---|---|---|\n")
        for r in sys_rows[:40]:
            f.write("| %s | %s | %s | %s | %s |\n" % (r.get("sort"), r.get("id"), tr(r.get("name")), r.get("conditionType"), r.get("value")))

    print("output:", OUT)
    print("systems", len(sys_rows), "guide", len(chain), "stages", len(stages), "shop", len(shop))


if __name__ == "__main__":
    main()
