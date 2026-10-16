#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《大掌柜》素材流水线工具.

用法概览：
  python tools/asset_pipeline.py scan       # 扫描 data/*.json + 代码引用，生成素材清单
  python tools/asset_pipeline.py prompts    # 生成豆包/绘图模型的批量提示词和图集映射
  python tools/asset_pipeline.py slice      # 把 inbox/atlases 里的九宫格切成独立素材并抠底
  python tools/asset_pipeline.py process    # 处理 inbox/raw 里按素材 id 命名的单图
  python tools/asset_pipeline.py derive     # 从全身立绘派生服装小图标/门客卡图
  python tools/asset_pipeline.py verify     # 检查缺图、尺寸、透明通道
  python tools/asset_pipeline.py qc         # 生成 HTML 批量验收页

所有生成文件都在 build/asset_pipeline/ 下，不会污染 assets/，除非你显式执行 slice/process/derive。
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import shutil
import sys
from collections import Counter, defaultdict, deque
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageDraw
except Exception:  # Pillow 是处理图片的必需依赖
    Image = None
    ImageDraw = None


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
ASSETS_DIR = ROOT / "assets"
BUILD_DIR = ROOT / "build" / "asset_pipeline"
PROMPT_DIR = BUILD_DIR / "prompts"
INBOX_DIR = BUILD_DIR / "inbox"
RAW_DIR = INBOX_DIR / "raw"
ATLAS_DIR = INBOX_DIR / "atlases"
QC_DIR = BUILD_DIR / "qc"
LOG_DIR = BUILD_DIR / "logs"
MANIFEST_JSON = BUILD_DIR / "manifest.json"
MANIFEST_CSV = BUILD_DIR / "manifest.csv"
MISSING_CSV = BUILD_DIR / "missing.csv"
CHARACTER_BIBLE = BUILD_DIR / "character_bible.csv"
PROMPT_INDEX = BUILD_DIR / "prompt_index.csv"

ICON_SIZE_DEFAULT = 128
PORTRAIT_MAX_W_DEFAULT = 1536
PORTRAIT_MAX_H_DEFAULT = 2048
PORTRAIT_UPSCALE_H_DEFAULT = 1400


# ---------------------------------------------------------------------------
# 基础读写
# ---------------------------------------------------------------------------

def now_iso() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def ensure_dirs() -> None:
    for d in (BUILD_DIR, PROMPT_DIR, INBOX_DIR, RAW_DIR, ATLAS_DIR, QC_DIR, LOG_DIR):
        d.mkdir(parents=True, exist_ok=True)


def load_json(path: Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def rel_to_root(path: Path | str) -> str:
    p = Path(path)
    if p.is_absolute():
        try:
            return p.relative_to(ROOT).as_posix()
        except ValueError:
            return p.as_posix()
    return p.as_posix().lstrip("./")


def image_info(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"exists": False, "w": None, "h": None, "mode": None}
    if Image is None:
        return {"exists": True, "w": None, "h": None, "mode": None}
    try:
        with Image.open(path) as im:
            return {"exists": True, "w": im.width, "h": im.height, "mode": im.mode}
    except Exception as exc:
        return {"exists": True, "w": None, "h": None, "mode": f"ERROR:{exc}"}


# ---------------------------------------------------------------------------
# 1. 素材清单：扫描 data/*.json 和代码里的资源引用
# ---------------------------------------------------------------------------

def build_manifest() -> dict[str, Any]:
    heroes = load_json(DATA_DIR / "heroes.json")
    friends = load_json(DATA_DIR / "friends.json")
    costumes = load_json(DATA_DIR / "costumes.json")
    items = load_json(DATA_DIR / "items.json")
    beasts = load_json(DATA_DIR / "beasts.json")
    fishing = load_json(DATA_DIR / "fishing.json")
    cuzhi = load_json(DATA_DIR / "cuzhi.json")
    guardian = load_json(DATA_DIR / "guardian.json")
    tokens = load_json(DATA_DIR / "tokens.json")
    side_skill = load_json(DATA_DIR / "side_skill.json")
    hero_talents = load_json(DATA_DIR / "hero_talents.json")
    hero_auras = load_json(DATA_DIR / "hero_auras.json")

    items_cfg: dict[str, Any] = items.get("config", {}) if isinstance(items, dict) else {}
    records: dict[str, dict[str, Any]] = {}

    def add(
        category: str,
        target: str,
        asset_id: str,
        name: str,
        generation: str,
        size: str = "icon",
        group: str = "",
        owner_id: str = "",
        owner_name: str = "",
        source: str = "",
        hint: str = "",
        meta: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        target = str(target).replace("\\", "/")
        asset_id = str(asset_id)
        name = str(name)
        if target in records:
            return records[target]
        key = f"{category}:{owner_id + ':' if owner_id else ''}{asset_id}"
        rec = {
            "key": key,
            "category": category,
            "asset_id": asset_id,
            "name": name,
            "owner_id": owner_id,
            "owner_name": owner_name,
            "target": target,
            "generation": generation,
            "size": size,
            "group": group,
            "source": source,
            "hint": str(hint or ""),
            "meta": meta or {},
        }
        records[target] = rec
        return rec

    def add_skill(name: str, source: str, hint: str = "", group: str = "skill_icons") -> None:
        name = str(name or "").strip()
        if not name:
            return
        add(
            "skill_icon",
            f"assets/skill_icons/{name}.png",
            name,
            name,
            "icon_sheet",
            size="icon",
            group=group,
            source=source,
            hint=hint,
        )

    # ---- 门客/挚友基础立绘 ----
    for hid, hero in heroes.items():
        if not isinstance(hero, dict):
            continue
        hname = str(hero.get("name", hid))
        add(
            "hero_portrait",
            f"assets/portraits/heroes/{hid}.png",
            hid,
            hname,
            "portrait",
            size="portrait",
            group="hero_portraits",
            owner_id=hid,
            owner_name=hname,
            source="heroes.json",
            meta={"category": hero.get("category", ""), "quality": hero.get("quality", "")},
        )
        add(
            "hero_card",
            f"assets/portraits/heroes_card/{hid}.png",
            hid,
            hname,
            "derive_card",
            size="card",
            group="hero_cards",
            owner_id=hid,
            owner_name=hname,
            source="heroes.json",
            meta={"source_target": f"assets/portraits/heroes/{hid}.png"},
        )
        for sk in hero.get("aptitude_skills", []) or []:
            if isinstance(sk, dict):
                add_skill(sk.get("name", ""), "heroes.json:aptitude_skills")
        for sk in hero.get("shop_skills", []) or []:
            if isinstance(sk, dict):
                add_skill(sk.get("name", ""), "heroes.json:shop_skills")

    for fid, friend in friends.items():
        if not isinstance(friend, dict):
            continue
        fname = str(friend.get("name", fid))
        add(
            "friend_portrait",
            f"assets/portraits/friends/{fid}.png",
            fid,
            fname,
            "portrait",
            size="portrait",
            group="friend_portraits",
            owner_id=fid,
            owner_name=fname,
            source="friends.json",
            meta={"category": friend.get("category", "")},
        )

    # ---- 服装：全身立绘 + 服装图标 ----
    owner_kinds = {
        "hero": {"source": heroes, "portrait_category": "hero_portrait", "dir": "heroes"},
        "friend": {"source": friends, "portrait_category": "friend_portrait", "dir": "friends"},
    }
    for owner_kind, cfg in owner_kinds.items():
        owner_map = cfg["source"]
        costume_key = "hero_costumes" if owner_kind == "hero" else "friend_costumes"
        for owner_id, arr in (costumes.get(costume_key, {}) or {}).items():
            owner = owner_map.get(owner_id, {}) if isinstance(owner_map, dict) else {}
            owner_name = str(owner.get("name", owner_id)) if isinstance(owner, dict) else str(owner_id)
            for cos in arr or []:
                if not isinstance(cos, dict):
                    continue
                cid = str(cos.get("id", "")).strip()
                if not cid:
                    continue
                cname = str(cos.get("name", cid))
                quality = str(cos.get("quality", ""))
                series = str(cos.get("series", ""))
                add(
                    "costume_full",
                    f"assets/costumes/{cid}.png",
                    cid,
                    cname,
                    "costume_sheet",
                    size="portrait",
                    group=f"costume_{owner_kind}:{owner_id}",
                    owner_id=owner_id,
                    owner_name=owner_name,
                    source="costumes.json",
                    hint=f"{quality} {series}".strip(),
                    meta={"quality": quality, "series": series, "owner_kind": owner_kind},
                )
                add(
                    "costume_icon",
                    f"assets/skill_icons/{cid}.png",
                    cid,
                    cname,
                    "derive_costume",
                    size="icon",
                    group=f"costume_icon:{owner_kind}:{owner_id}",
                    owner_id=owner_id,
                    owner_name=owner_name,
                    source="costumes.json",
                    hint=f"{quality} {series}".strip(),
                    meta={
                        "quality": quality,
                        "series": series,
                        "owner_kind": owner_kind,
                        "source_target": f"assets/costumes/{cid}.png",
                    },
                )

    # ---- 技能图标：门客天赋/店铺技能/守护灵/信物/副业/虫师/天赋/光环 ----
    for phase in guardian.get("phases", []) or []:
        if isinstance(phase, dict):
            add_skill(phase.get("skill_name", ""), "guardian.json:phases", hint=str(phase.get("name", "")))

    for sk in tokens.get("skills", []) or []:
        if isinstance(sk, dict):
            add_skill(sk.get("name", ""), "tokens.json:skills")
    for _owner, tcfg in (tokens.get("tokens", {}) or {}).items():
        if isinstance(tcfg, dict):
            add_skill(tcfg.get("skill_name", ""), "tokens.json:tokens")

    for _key, scfg in (side_skill.get("skills", {}) or {}).items():
        if isinstance(scfg, dict):
            add_skill(scfg.get("name", ""), "side_skill.json:skills")

    # 极·职业之道：运行时由 side_skill.json 的职业书道具名派生
    for _cat, book_id in (side_skill.get("career_books", {}) or {}).items():
        book = items_cfg.get(book_id)
        if isinstance(book, dict) and book.get("name"):
            add_skill("极·" + str(book["name"]), "derived:side_skill.career_books")

    for _hid, hcfg in (hero_talents.get("heroes", {}) or {}).items():
        if not isinstance(hcfg, dict):
            continue
        tiers = hcfg.get("tiers", {}) or {}
        if not isinstance(tiers, dict):
            continue
        for _tier, arr in tiers.items():
            for t in arr or []:
                if isinstance(t, dict):
                    add_skill(t.get("name", ""), "hero_talents.json", hint=str(t.get("desc", "")))

    for _sname, scfg in (hero_auras.get("series", {}) or {}).items():
        if not isinstance(scfg, dict):
            continue
        for sk in scfg.get("skills", []) or []:
            if isinstance(sk, dict):
                add_skill(sk.get("name", ""), "hero_auras.json:series")
        special = scfg.get("special", {})
        if isinstance(special, dict):
            for _sp_name, sp in special.items():
                if not isinstance(sp, dict):
                    continue
                for sk_name in sp.get("skills", []) or []:
                    if isinstance(sk_name, str):
                        add_skill(sk_name, "hero_auras.json:series.special")
    for _hid, hcfg in (hero_auras.get("hero_auras", {}) or {}).items():
        if isinstance(hcfg, dict):
            for sk in hcfg.get("skills", []) or []:
                if isinstance(sk, dict):
                    add_skill(sk.get("name", ""), "hero_auras.json:hero_auras")

    # 促织图标与虫师副业技能共用 assets/skill_icons/{促织名}.png
    for cricket in cuzhi.get("crickets", []) or []:
        if not isinstance(cricket, dict):
            continue
        cname = str(cricket.get("name", "")).strip()
        if not cname:
            continue
        add(
            "cricket_icon",
            f"assets/skill_icons/{cname}.png",
            cname,
            cname,
            "icon_sheet",
            size="icon",
            group="cricket_icons",
            source="cuzhi.json:crickets",
            hint=f"{cricket.get('career', '')}系 {cricket.get('quality', '')}星",
            meta={"cricket_id": cricket.get("id", ""), "career": cricket.get("career", ""), "quality": cricket.get("quality", "")},
        )

    # ---- 道具图标 ----
    for iid, item in items_cfg.items():
        if not isinstance(item, dict):
            continue
        add(
            "item_icon",
            f"assets/items/{iid}.png",
            iid,
            str(item.get("name", iid)),
            "icon_sheet",
            size="icon",
            group="item_icons",
            source="items.json:config",
            hint=str(item.get("desc", "")),
            meta={"desc": item.get("desc", ""), "use": item.get("use", "")},
        )

    # ---- 珍兽图标 ----
    for bid, beast in (beasts or {}).items():
        if not isinstance(beast, dict):
            continue
        add(
            "beast_icon",
            f"assets/beasts/{bid}.png",
            bid,
            str(beast.get("name", bid)),
            "icon_sheet",
            size="icon",
            group="beast_icons",
            source="beasts.json",
            hint=f"{beast.get('quality', '')} {beast.get('aptitude', '')}资质".strip(),
            meta={"quality": beast.get("quality", ""), "aptitude": beast.get("aptitude", "")},
        )

    # ---- 渔获/渔具图标 ----
    fishing_items: dict[str, dict[str, Any]] = {}

    def walk_fishing(node: Any, parent_key: str = "") -> None:
        if isinstance(node, dict):
            if "id" in node and "name" in node and ("quality" in node or parent_key in ("gears", "fish_equip")):
                fishing_items[str(node["id"])] = node
            for k, v in node.items():
                walk_fishing(v, str(k))
        elif isinstance(node, list):
            for v in node:
                walk_fishing(v, parent_key)

    walk_fishing(fishing)
    for fid, fish in fishing_items.items():
        add(
            "fishing_icon",
            f"assets/fishing/{fid}.png",
            fid,
            str(fish.get("name", fid)),
            "icon_sheet",
            size="icon",
            group="fishing_icons",
            source="fishing.json",
            hint=f"{fish.get('quality', '')} {fish.get('kind', '')}".strip(),
            meta={"quality": fish.get("quality", ""), "kind": fish.get("kind", "")},
        )

    # ---- 代码中的静态 UI 资源引用 ----
    literal_paths: set[str] = set()
    for p in list(ROOT.rglob("*.gd")) + list(ROOT.rglob("*.tscn")):
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for m in re.finditer(r"res://assets/[^\"'\s]+?\.(?:png|jpg|jpeg|webp|svg|tres)", text):
            raw = m.group(0)
            if any(ch in raw for ch in "%{}<>"):
                continue
            literal_paths.add(raw.replace("res://", "", 1))
    for target in sorted(literal_paths):
        add(
            "ui_asset",
            target,
            Path(target).stem,
            Path(target).stem,
            "none",
            size="unknown",
            group="ui_assets",
            source="code_literal",
        )

    # ---- 项目里已经存在、但上面的契约没覆盖到的图，也纳入清单 ----
    if ASSETS_DIR.exists() and Image is not None:
        for p in ASSETS_DIR.rglob("*.png"):
            target = rel_to_root(p)
            if target not in records:
                add(
                    "existing_asset",
                    target,
                    p.stem,
                    p.stem,
                    "none",
                    size="unknown",
                    group="existing_assets",
                    source="filesystem",
                )

    # ---- 补齐磁盘状态 ----
    for rec in records.values():
        info = image_info(ROOT / rec["target"])
        rec["exists"] = bool(info["exists"])
        rec["existing_w"] = info["w"]
        rec["existing_h"] = info["h"]
        rec["existing_mode"] = info["mode"]
        rec["status"] = "exists" if info["exists"] else "missing"

    asset_list = sorted(records.values(), key=lambda r: (r["category"], r["target"]))
    counts: dict[str, Counter] = defaultdict(Counter)
    for rec in asset_list:
        counts[rec["category"]]["total"] += 1
        counts[rec["category"]][rec["status"]] += 1

    return {
        "generated_at": now_iso(),
        "project_root": str(ROOT),
        "asset_count": len(asset_list),
        "counts": {k: dict(v) for k, v in sorted(counts.items())},
        "assets": asset_list,
    }


def manifest_rows(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for rec in manifest.get("assets", []):
        rows.append(
            {
                "category": rec.get("category", ""),
                "asset_id": rec.get("asset_id", ""),
                "name": rec.get("name", ""),
                "owner_id": rec.get("owner_id", ""),
                "owner_name": rec.get("owner_name", ""),
                "target": rec.get("target", ""),
                "generation": rec.get("generation", ""),
                "size": rec.get("size", ""),
                "group": rec.get("group", ""),
                "source": rec.get("source", ""),
                "hint": rec.get("hint", ""),
                "exists": rec.get("exists", False),
                "existing_w": rec.get("existing_w", ""),
                "existing_h": rec.get("existing_h", ""),
                "existing_mode": rec.get("existing_mode", ""),
            }
        )
    return rows


def cmd_scan(_args: argparse.Namespace) -> int:
    ensure_dirs()
    manifest = build_manifest()
    write_json(MANIFEST_JSON, manifest)
    write_csv(MANIFEST_CSV, manifest_rows(manifest))
    print(f"[scan] 素材契约已生成: {MANIFEST_CSV}")
    print(f"[scan] 总计 {manifest['asset_count']} 条")
    for category, c in manifest.get("counts", {}).items():
        print(f"  {category:20s} total={c.get('total', 0):4d} missing={c.get('missing', 0):4d} exists={c.get('exists', 0):4d}")
    return 0

# ---------------------------------------------------------------------------
# 2. 提示词生成：角色设定表 + 批量图集任务
# ---------------------------------------------------------------------------

STYLE_BLOCK = """【统一美术规范】
- 项目：《大掌柜》国风经营/江湖题材，2D 厚涂半写实，宋代市井 + 武侠幻想混合风。
- 统一光源：左上方 45° 柔光；主体边缘干净，色彩浓郁但不过曝。
- 背景：除特别说明外，背景必须为纯洋红 #FF00FF，且不能有渐变、地面阴影、纹理、纯色幕布褶皱。
- 画面内不要出现文字、水印、logo、边框、UI、签名、阿拉伯数字。
- 不要裁切主体；人物四肢、武器、道具必须完整入画。"""

NEGATIVE_BLOCK = "文字、水印、logo、边框、签名、多个主体、跨格、裁切、低清、模糊、畸变手指、多余肢体、渐变背景、地面阴影、彩色描边"


def character_bible_template(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    assets = manifest.get("assets", [])
    rows: list[dict[str, Any]] = []
    for rec in assets:
        cat = rec.get("category", "")
        if cat not in ("hero_portrait", "friend_portrait"):
            continue
        owner_id = rec.get("owner_id", "")
        is_hero = cat == "hero_portrait"
        rows.append(
            {
                "id": owner_id,
                "type": "hero" if is_hero else "friend",
                "name": rec.get("name", owner_id),
                "category": rec.get("meta", {}).get("category", ""),
                "quality": rec.get("meta", {}).get("quality", ""),
                "canon_description": "",
                "appearance_keywords": "",
                "reference_image": rec.get("target", ""),
                "notes": "",
            }
        )
    rows.sort(key=lambda r: (r["type"], r["id"]))
    return rows


def ensure_character_bible(manifest: dict[str, Any]) -> None:
    if CHARACTER_BIBLE.exists():
        return
    rows = character_bible_template(manifest)
    write_csv(CHARACTER_BIBLE, rows, list(rows[0].keys()) if rows else ["id"])
    kimi_doc = BUILD_DIR / "character_bible_prompt_for_kimi.md"
    kimi_doc.write_text(
        "# 给 Kimi 的角色设定补全任务\n\n"
        "请读取 `character_bible.csv`，补全两列：\n\n"
        "- `canon_description`：80~150 字，说明该角色的身份、时代/职业、气质、标志性外貌。\n"
        "- `appearance_keywords`：10~20 个中文关键词，描述 AI 绘画需要锁定的外观特征。\n\n"
        "要求：\n"
        "1. 不要修改 csv 的列名、行顺序、id、name、reference_image。\n"
        "2. 历史/小说人物遵循大众认知；原创角色按名字和类别合理创作。\n"
        "3. 输出仍是 UTF-8 CSV，直接覆盖 `character_bible.csv`。\n\n"
        "补全后放回 `build/asset_pipeline/character_bible.csv`，再运行：\n\n"
        "```bash\npython tools/asset_pipeline.py prompts\n```\n",
        encoding="utf-8",
    )


def load_character_bible() -> dict[str, dict[str, str]]:
    rows = read_csv(CHARACTER_BIBLE)
    return {str(r.get("id", "")): r for r in rows if r.get("id")}


def _safe_filename(s: str) -> str:
    s = re.sub(r"[^0-9A-Za-z_\-]+", "_", s or "")
    return s.strip("_") or "task"


def _task_save(rec: dict[str, Any]) -> dict[str, Any]:
    return {
        "key": rec.get("key", ""),
        "category": rec.get("category", ""),
        "asset_id": rec.get("asset_id", ""),
        "name": rec.get("name", ""),
        "owner_id": rec.get("owner_id", ""),
        "owner_name": rec.get("owner_name", ""),
        "target": rec.get("target", ""),
        "size": rec.get("size", ""),
        "generation": rec.get("generation", ""),
        "group": rec.get("group", ""),
        "meta": rec.get("meta", {}),
    }


def _make_task(kind: str, group: str, cells: list[dict[str, Any]], reference_image: str = "", title: str = "") -> dict[str, Any]:
    n = max(1, len(cells))
    if kind == "portrait_single":
        cols, rows = 1, 1
    elif kind == "costume_sheet":
        if n <= 1:
            cols, rows = 1, 1
        elif n <= 2:
            cols, rows = 2, 1
        elif n <= 4:
            cols, rows = 2, 2
        else:
            cols, rows = 2, 3
    else:
        if n <= 1:
            cols, rows = 1, 1
        elif n <= 2:
            cols, rows = 2, 1
        elif n <= 4:
            cols, rows = 2, 2
        elif n <= 6:
            cols, rows = 3, 2
        else:
            cols, rows = 3, 3
    cells = cells[: cols * rows]
    for i, cell in enumerate(cells):
        cell["index"] = i
        cell["row"] = i // cols
        cell["col"] = i % cols
    return {
        "task_id": "",
        "kind": kind,
        "group": group,
        "title": title or group,
        "rows": rows,
        "cols": cols,
        "reference_image": reference_image,
        "cells": cells,
    }


def build_generation_tasks(manifest: dict[str, Any], max_costume_cells: int = 6, icon_batch: int = 9) -> list[dict[str, Any]]:
    """只给缺失素材排任务；已存在的素材不重复生成。"""
    assets = manifest.get("assets", [])
    tasks: list[dict[str, Any]] = []

    costume_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for rec in assets:
        if rec.get("category") == "costume_full" and not rec.get("exists"):
            costume_groups[rec.get("group", "")].append(rec)

    covered_portraits: set[str] = set()
    for group, recs in sorted(costume_groups.items()):
        if not recs:
            continue
        recs.sort(key=lambda r: r.get("asset_id", ""))
        owner_id = recs[0].get("owner_id", "")
        owner_kind = recs[0].get("meta", {}).get("owner_kind", "")
        portrait_category = "hero_portrait" if owner_kind == "hero" else "friend_portrait"
        portrait = next(
            (r for r in assets if r.get("category") == portrait_category and r.get("owner_id") == owner_id),
            None,
        )
        chunks = [recs[i : i + max_costume_cells] for i in range(0, len(recs), max_costume_cells)]
        for ci, chunk in enumerate(chunks):
            cells: list[dict[str, Any]] = []
            for rec in chunk:
                saves = [_task_save(rec)]
                if ci == 0 and rec is chunk[0] and portrait is not None and not portrait.get("exists"):
                    saves.append(_task_save(portrait))
                    covered_portraits.add(portrait.get("key", ""))
                label = rec.get("name", rec.get("asset_id", ""))
                hint = rec.get("hint", "")
                cells.append({"label": f"{label}{('（' + hint + '）') if hint else ''}", "saves": saves})
            title = f"{recs[0].get('owner_name', owner_id)} 的服装图集"
            ref_img = (portrait or {}).get("target", "") if portrait and portrait.get("exists") else ""
            tasks.append(_make_task("costume_sheet", group, cells, reference_image=ref_img, title=title))

    for rec in assets:
        if rec.get("category") not in ("hero_portrait", "friend_portrait"):
            continue
        if rec.get("exists") or rec.get("key") in covered_portraits:
            continue
        cell = {"label": rec.get("name", rec.get("asset_id", "")), "saves": [_task_save(rec)]}
        tasks.append(_make_task("portrait_single", rec.get("group", "portrait_single"), [cell], title=rec.get("name", "")))

    icon_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for rec in assets:
        if rec.get("generation") == "icon_sheet" and not rec.get("exists"):
            icon_groups[rec.get("group", "icon_sheet")].append(rec)

    for group, recs in sorted(icon_groups.items()):
        recs.sort(key=lambda r: (r.get("category", ""), r.get("asset_id", "")))
        for i in range(0, len(recs), icon_batch):
            chunk = recs[i : i + icon_batch]
            cells = []
            for rec in chunk:
                hint = rec.get("hint", "")
                label = rec.get("name", rec.get("asset_id", ""))
                cells.append({"label": f"{label}{('：' + hint) if hint else ''}", "saves": [_task_save(rec)]})
            tasks.append(_make_task("icon_sheet", group, cells, title=f"{group} 图标图集"))

    for i, task in enumerate(tasks, 1):
        task["task_id"] = f"task_{i:04d}"
        safe_group = _safe_filename(task.get("group", "task"))
        task["filename_base"] = f"{task['task_id']}_{task['kind']}_{safe_group}"
        task["image_name"] = f"{task['filename_base']}.png"
        task["output_path"] = str((ATLAS_DIR / task["image_name"]).relative_to(ROOT)).replace("\\", "/")
    return tasks

def _grid_position_name(index: int, cols: int) -> str:
    row = index // cols
    col = index % cols
    return f"第{row + 1}行第{col + 1}列"


def render_task_prompt(task: dict[str, Any], bible: dict[str, dict[str, str]]) -> str:
    kind = task.get("kind", "")
    cols = int(task.get("cols", 1))
    rows = int(task.get("rows", 1))
    cells = task.get("cells", [])
    ref = task.get("reference_image", "")
    lines: list[str] = []
    lines.append(f"===== {task.get('task_id', '')} / {task.get('title', '')} =====")
    lines.append(f"类型：{kind}")
    lines.append(f"网格：{cols} 列 × {rows} 行")
    lines.append(f"输出文件名：{task.get('image_name', '')}")
    if ref:
        lines.append(f"参考图：{ref}（如果有上传参考图的能力，请优先使用它锁定角色面部/发型/体型/配色）")
    lines.append("")

    owner_id = ""
    if cells and cells[0].get("saves"):
        owner_id = str(cells[0]["saves"][0].get("owner_id", ""))
    bible_row = bible.get(owner_id, {}) if owner_id else {}

    if kind == "portrait_single":
        save = cells[0]["saves"][0]
        lines.append("【画面内容】")
        lines.append(f"角色：{save.get('name', '')}")
        if bible_row:
            if bible_row.get("canon_description"):
                lines.append(f"设定：{bible_row.get('canon_description')}")
            if bible_row.get("appearance_keywords"):
                lines.append(f"外貌锁定：{bible_row.get('appearance_keywords')}")
        lines.append("要求：全身或七分身立绘，正面或四分之三侧身，自然站姿，人物位于画面中央，脚底或衣摆完整入画。")
    elif kind == "costume_sheet":
        lines.append("【画面内容】")
        if cells and cells[0].get("saves"):
            first = cells[0]["saves"][0]
            lines.append(f"角色：{first.get('owner_name') or first.get('name', '')}")
        if bible_row:
            if bible_row.get("canon_description"):
                lines.append(f"设定：{bible_row.get('canon_description')}")
            if bible_row.get("appearance_keywords"):
                lines.append(f"外貌锁定：{bible_row.get('appearance_keywords')}")
        lines.append("要求：同一角色的多套服装立绘。所有格子的脸型、发型、发色、体型、肤色必须完全一致，只改变服装、配饰、姿态和手持物。每格一个完整全身/七分身立绘，脚底尽量对齐同一水平线，主体不跨格。")
        lines.append("")
        lines.append("【单元格顺序】")
        for cell in cells:
            saves = cell.get("saves", [])
            if not saves:
                continue
            first = saves[0]
            extra = "；此格同时作为该角色的基础立绘候选" if len(saves) > 1 else ""
            lines.append(f"{_grid_position_name(int(cell.get('index', 0)), cols)}：{first.get('name', '')}（{first.get('meta', {}).get('quality', '')} {first.get('meta', {}).get('series', '')}）{extra}")
    else:
        lines.append("【画面内容】")
        lines.append("生成一组游戏图标。每个图标独立居中，风格、光源、视角、描边粗细保持一致；图标之间不要分割线，四周留出 8%~12% 的纯洋红空隙。")
        lines.append("")
        lines.append("【单元格顺序】")
        for cell in cells:
            saves = cell.get("saves", [])
            if not saves:
                continue
            save = saves[0]
            hint = save.get("hint", "")
            lines.append(f"{_grid_position_name(int(cell.get('index', 0)), cols)}：{save.get('name', '')}{('：' + hint) if hint else ''}")
    lines.append("")
    lines.append(STYLE_BLOCK)
    lines.append(f"【负向词】{NEGATIVE_BLOCK}")
    lines.append("")
    lines.append("【交付方式】")
    lines.append(f"生成后保存为：{task.get('output_path', '')}")
    lines.append(f"如果下载文件名不同，请重命名为：{task.get('image_name', '')}")
    return "\n".join(lines) + "\n"


def write_generation_tasks(tasks: list[dict[str, Any]], manifest: dict[str, Any]) -> None:
    ensure_character_bible(manifest)
    bible = load_character_bible()
    index_rows: list[dict[str, Any]] = []

    for task in tasks:
        filename_base = task.get("filename_base", task.get("task_id", "task"))
        prompt_path = PROMPT_DIR / f"{filename_base}.txt"
        mapping_path = PROMPT_DIR / f"{filename_base}.json"
        prompt_path.write_text(render_task_prompt(task, bible), encoding="utf-8")
        write_json(mapping_path, task)
        cells = task.get("cells", [])
        save_count = sum(len(c.get("saves", [])) for c in cells)
        index_rows.append(
            {
                "task_id": task.get("task_id", ""),
                "kind": task.get("kind", ""),
                "title": task.get("title", ""),
                "grid": f"{task.get('cols')}x{task.get('rows')}",
                "cells": len(cells),
                "asset_saves": save_count,
                "prompt_file": str(prompt_path.relative_to(ROOT)).replace("\\", "/"),
                "mapping_file": str(mapping_path.relative_to(ROOT)).replace("\\", "/"),
                "save_image_as": task.get("image_name", ""),
                "output_path": task.get("output_path", ""),
                "reference_image": task.get("reference_image", ""),
            }
        )

    write_csv(PROMPT_INDEX, index_rows)
    readme = PROMPT_DIR / "README.md"
    readme.write_text(
        "# 批量提示词目录\n\n"
        "本目录由 `tools/asset_pipeline.py prompts` 生成。\n\n"
        "任务文件：\n"
        "- `task_XXXX_*.txt`：直接复制给豆包/绘图模型的提示词。\n"
        "- `task_XXXX_*.json`：单元格到素材路径的映射，`slice` 命令会读取它。\n\n"
        "工作流：\n"
        "1. 先补全 `build/asset_pipeline/character_bible.csv`。\n"
        "2. 运行 `python tools/asset_pipeline.py prompts`。\n"
        "3. 按提示词生成图片，保存到 `build/asset_pipeline/inbox/atlases/`。\n"
        "4. 运行 `python tools/asset_pipeline.py slice` 自动切图、抠底、命名并写入 assets。\n"
        "5. 运行 `python tools/asset_pipeline.py qc` 批量验收。\n",
        encoding="utf-8",
    )


def cmd_prompts(args: argparse.Namespace) -> int:
    ensure_dirs()
    manifest = build_manifest()
    write_json(MANIFEST_JSON, manifest)
    write_csv(MANIFEST_CSV, manifest_rows(manifest))
    ensure_character_bible(manifest)
    tasks = build_generation_tasks(
        manifest,
        max_costume_cells=int(args.max_costume_cells),
        icon_batch=int(args.icon_batch),
    )
    write_generation_tasks(tasks, manifest)
    kind_counter = Counter(t.get("kind", "") for t in tasks)
    group_counter = Counter(t.get("group", "") for t in tasks)
    print(f"[prompts] 生成任务 {len(tasks)} 个，输出目录：{PROMPT_DIR}")
    print("  按类型：" + ", ".join(f"{k}={v}" for k, v in kind_counter.items()))
    print("  按分组：" + ", ".join(f"{k}={v}" for k, v in sorted(group_counter.items())))
    print(f"  角色设定表：{CHARACTER_BIBLE}")
    print(f"  任务索引：{PROMPT_INDEX}")
    return 0

# ---------------------------------------------------------------------------
# 3. 图片处理：切图、抠纯色底、裁剪透明边、缩放到项目尺寸
# ---------------------------------------------------------------------------

def _require_pil() -> None:
    if Image is None or ImageDraw is None:
        raise SystemExit("需要 Pillow：请先安装 python -m pip install pillow")


def _trim_alpha(im: "Image.Image") -> "Image.Image":
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox:
        return im.crop(bbox)
    return im


def remove_chroma_bg(im: "Image.Image", tolerance: int = 60) -> "Image.Image":
    """用 Pillow 的 floodfill 从边缘去掉纯洋红/纯绿幕/纯白底。

    生成提示词统一要求 #FF00FF 洋红底；这里不写死颜色，而是从四角/边缘取种子，
    因此白底、绿幕也能处理。如果输入本身已经有明显透明通道，则直接返回。
    """
    _require_pil()
    im = im.convert("RGBA")
    w, h = im.size
    alpha = im.getchannel("A")
    low, _high = alpha.getextrema()
    if low < 250:
        return im
    seeds = [
        (0, 0), (max(0, w - 1), 0), (0, max(0, h - 1)), (max(0, w - 1), max(0, h - 1)),
        (w // 2, 0), (w // 2, max(0, h - 1)), (0, h // 2), (max(0, w - 1), h // 2),
    ]
    for seed in seeds:
        if 0 <= seed[0] < w and 0 <= seed[1] < h:
            try:
                ImageDraw.floodfill(im, seed, (0, 0, 0, 0), thresh=max(0, int(tolerance)))
            except Exception:
                pass
    return im


def fit_max(im: "Image.Image", max_w: int = 0, max_h: int = 0, min_h: int = 0, allow_upscale: bool = False) -> "Image.Image":
    """只缩小/按需放大，补齐透明画布由调用方决定；这里返回裁剪后的主体。"""
    _require_pil()
    if im.mode != "RGBA":
        im = im.convert("RGBA")
    w, h = im.size
    if w <= 0 or h <= 0:
        return im
    scale = 1.0
    if max_w and w > max_w:
        scale = min(scale, max_w / w)
    if max_h and h > max_h:
        scale = min(scale, max_h / h)
    if min_h and h < min_h and allow_upscale:
        scale = max(scale, min_h / h)
    if abs(scale - 1.0) > 0.001:
        im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    return im


def fit_icon(im: "Image.Image", size: int = ICON_SIZE_DEFAULT) -> "Image.Image":
    """把主体等比放进 size×size 透明方画布，四周留白，不裁切。"""
    _require_pil()
    im = _trim_alpha(im.convert("RGBA"))
    w, h = im.size
    if w <= 0 or h <= 0:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scale = min(size / w, size / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((size - nw) // 2, (size - nh) // 2))
    return canvas


def process_for_save(im: "Image.Image", save: dict[str, Any], args: argparse.Namespace) -> "Image.Image":
    cat = save.get("category", "")
    out = remove_chroma_bg(im, tolerance=int(args.tolerance))
    out = _trim_alpha(out)
    if cat in ("skill_icon", "cricket_icon", "costume_icon", "item_icon", "beast_icon", "fishing_icon"):
        return fit_icon(out, size=int(args.icon_size))
    if cat in ("hero_portrait", "friend_portrait", "costume_full"):
        return fit_max(
            out,
            max_w=int(args.portrait_max_w),
            max_h=int(args.portrait_max_h),
            min_h=int(args.upscale_min_height),
            allow_upscale=bool(args.allow_upscale),
        )
    if cat == "hero_card":
        return fit_max(out, max_w=int(args.card_max_w), max_h=int(args.card_max_h))
    return out


def _find_task_image(task: dict[str, Any]) -> Path | None:
    exact = ATLAS_DIR / task.get("image_name", "")
    if exact.exists():
        return exact
    stems = {task.get("task_id", ""), task.get("filename_base", "")}
    for p in ATLAS_DIR.glob("*.png"):
        if p.stem in stems:
            return p
    # 再宽松一点：文件名以 task_id 开头
    tid = task.get("task_id", "")
    if tid:
        for p in ATLAS_DIR.glob(f"{tid}*.png"):
            return p
    return None


def cmd_slice(args: argparse.Namespace) -> int:
    _require_pil()
    ensure_dirs()
    tasks = []
    for p in sorted(PROMPT_DIR.glob("task_*.json")):
        try:
            tasks.append(load_json(p))
        except Exception as exc:
            print(f"[slice] 跳过损坏映射 {p.name}: {exc}")
    if not tasks:
        print(f"[slice] 没有任务映射，请先运行：python tools/asset_pipeline.py prompts")
        return 1

    saved = 0
    sliced_tasks = 0
    missing_images: list[str] = []
    for task in tasks:
        img_path = _find_task_image(task)
        if img_path is None:
            missing_images.append(task.get("image_name", task.get("task_id", "")))
            continue
        try:
            with Image.open(img_path) as src:
                atlas = src.convert("RGBA")
        except Exception as exc:
            print(f"[slice] 打不开 {img_path}: {exc}")
            continue
        cols = max(1, int(task.get("cols", 1)))
        rows = max(1, int(task.get("rows", 1)))
        w, h = atlas.size
        for cell in task.get("cells", []):
            idx = int(cell.get("index", 0))
            col = idx % cols
            row = idx // cols
            left = round(col * w / cols)
            right = round((col + 1) * w / cols)
            top = round(row * h / rows)
            bottom = round((row + 1) * h / rows)
            inset = int(args.inset)
            if right - left <= inset * 2 or bottom - top <= inset * 2:
                continue
            crop = atlas.crop((left + inset, top + inset, right - inset, bottom - inset))
            for save in cell.get("saves", []):
                out = process_for_save(crop, save, args)
                target = ROOT / save.get("target", "")
                target.parent.mkdir(parents=True, exist_ok=True)
                if not args.dry_run:
                    out.save(target, "PNG")
                saved += 1
        sliced_tasks += 1
        print(f"[slice] {task.get('task_id')} <- {img_path.name} ({cols}x{rows})")

    print(f"[slice] 完成：处理 {sliced_tasks}/{len(tasks)} 个图集，写出 {saved} 个素材")
    if missing_images:
        print(f"[slice] 尚未放入 atlas 的任务 {len(missing_images)} 个，例如：")
        for name in missing_images[:12]:
            print(f"    {name}")
        print("  提示：把生成图按提示词里的文件名放进 build/asset_pipeline/inbox/atlases/")
    return 0

# ---------------------------------------------------------------------------
# 4. 单图处理 / 派生 / 校验 / QC
# ---------------------------------------------------------------------------

def _build_stem_lookup(manifest: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    lookup: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for rec in manifest.get("assets", []):
        stems = {Path(rec.get("target", "")).stem, str(rec.get("asset_id", ""))}
        for stem in stems:
            if stem:
                lookup[stem].append(rec)
    return lookup


def cmd_process(args: argparse.Namespace) -> int:
    _require_pil()
    ensure_dirs()
    manifest = build_manifest()
    stem_lookup = _build_stem_lookup(manifest)
    source_dir = Path(args.input) if args.input else RAW_DIR
    source_dir.mkdir(parents=True, exist_ok=True)

    manual_map: dict[str, str] = {}
    if args.map:
        for row in read_csv(Path(args.map)):
            fn = (row.get("filename") or row.get("input") or "").strip()
            key = (row.get("key") or row.get("asset_id") or "").strip()
            if fn and key:
                manual_map[Path(fn).stem] = key

    done = 0
    skipped: list[str] = []
    for p in sorted(source_dir.rglob("*")):
        if not p.is_file() or p.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
            continue
        stem = p.stem
        recs: list[dict[str, Any]] = []
        if stem in manual_map:
            wanted = manual_map[stem]
            recs = [r for r in manifest.get("assets", []) if r.get("key") == wanted or r.get("asset_id") == wanted]
        else:
            recs = stem_lookup.get(stem, [])
        if len(recs) != 1:
            skipped.append(f"{p.name} -> {len(recs)} 个候选，跳过")
            continue
        rec = recs[0]
        save = _task_save(rec)
        try:
            with Image.open(p) as src:
                out = process_for_save(src.convert("RGBA"), save, args)
            target = ROOT / save.get("target", "")
            target.parent.mkdir(parents=True, exist_ok=True)
            if not args.dry_run:
                out.save(target, "PNG")
            done += 1
            print(f"[process] {p.name} -> {save.get('target')}")
        except Exception as exc:
            skipped.append(f"{p.name}: {exc}")
    print(f"[process] 完成 {done} 个；跳过 {len(skipped)} 个")
    for msg in skipped[:20]:
        print("  " + msg)
    return 0


def _derive_bust(src: Path, dst: Path, args: argparse.Namespace) -> bool:
    if not src.exists():
        return False
    if dst.exists() and not args.overwrite:
        return False
    try:
        with Image.open(src) as im:
            im = _trim_alpha(im.convert("RGBA"))
            w, h = im.size
            crop_h = max(1, int(h * float(args.bust_ratio)))
            crop = im.crop((0, 0, w, crop_h))
            out = fit_icon(crop, size=int(args.icon_size))
        dst.parent.mkdir(parents=True, exist_ok=True)
        out.save(dst, "PNG")
        return True
    except Exception as exc:
        print(f"[derive] 失败 {src} -> {dst}: {exc}")
        return False


def _derive_card(src: Path, dst: Path, args: argparse.Namespace) -> bool:
    if not src.exists():
        return False
    if dst.exists() and not args.overwrite:
        return False
    try:
        with Image.open(src) as im:
            im = _trim_alpha(im.convert("RGBA"))
            w, h = im.size
            target_ratio = float(args.card_max_w) / max(1, float(args.card_max_h))
            if w / h > target_ratio:
                new_w = int(h * target_ratio)
                left = (w - new_w) // 2
                im = im.crop((left, 0, left + new_w, h))
            else:
                new_h = int(w / target_ratio)
                top = max(0, (h - new_h) // 2)
                im = im.crop((0, top, w, top + new_h))
            out = fit_max(im, max_w=int(args.card_max_w), max_h=int(args.card_max_h))
        dst.parent.mkdir(parents=True, exist_ok=True)
        out.save(dst, "PNG")
        return True
    except Exception as exc:
        print(f"[derive] 失败 {src} -> {dst}: {exc}")
        return False


def cmd_derive(args: argparse.Namespace) -> int:
    _require_pil()
    ensure_dirs()
    manifest = build_manifest()
    done = 0
    for rec in manifest.get("assets", []):
        cat = rec.get("category", "")
        if cat == "costume_icon":
            src = ROOT / rec.get("meta", {}).get("source_target", "")
            dst = ROOT / rec.get("target", "")
            if _derive_bust(src, dst, args):
                done += 1
        elif cat == "hero_card":
            src = ROOT / rec.get("meta", {}).get("source_target", "")
            dst = ROOT / rec.get("target", "")
            if _derive_card(src, dst, args):
                done += 1
    print(f"[derive] 派生完成 {done} 个（服装图标来自全身立绘，门客卡来自立绘）")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    ensure_dirs()
    manifest = build_manifest()
    write_json(MANIFEST_JSON, manifest)
    write_csv(MANIFEST_CSV, manifest_rows(manifest))
    missing_rows: list[dict[str, Any]] = []
    warnings: list[str] = []
    for rec in manifest.get("assets", []):
        if not rec.get("exists"):
            missing_rows.append(
                {
                    "category": rec.get("category", ""),
                    "asset_id": rec.get("asset_id", ""),
                    "name": rec.get("name", ""),
                    "target": rec.get("target", ""),
                    "generation": rec.get("generation", ""),
                    "group": rec.get("group", ""),
                    "source": rec.get("source", ""),
                }
            )
            continue
        cat = rec.get("category", "")
        w, h = rec.get("existing_w"), rec.get("existing_h")
        if cat in ("skill_icon", "cricket_icon", "costume_icon", "item_icon", "beast_icon", "fishing_icon"):
            if w and h and (w != int(args.icon_size) or h != int(args.icon_size)):
                warnings.append(f"尺寸不是 {args.icon_size}×{args.icon_size}: {rec.get('target')} ({w}x{h})")
            if rec.get("existing_mode") not in ("RGBA", "LA", "P"):
                warnings.append(f"可能没有透明通道: {rec.get('target')} ({rec.get('existing_mode')})")
        if cat in ("hero_portrait", "friend_portrait", "costume_full") and w and h:
            if w > int(args.portrait_max_w) or h > int(args.portrait_max_h):
                warnings.append(f"立绘超过上限 {args.portrait_max_w}x{args.portrait_max_h}: {rec.get('target')} ({w}x{h})")

    write_csv(MISSING_CSV, missing_rows, ["category", "asset_id", "name", "target", "generation", "group", "source"])
    print(f"[verify] 契约 {manifest.get('asset_count')} 条，缺失 {len(missing_rows)} 条，警告 {len(warnings)} 条")
    for category, c in manifest.get("counts", {}).items():
        print(f"  {category:20s} total={c.get('total', 0):4d} missing={c.get('missing', 0):4d} exists={c.get('exists', 0):4d}")
    if missing_rows:
        print(f"  缺失清单：{MISSING_CSV}")
    if warnings:
        for msg in warnings[:30]:
            print("  [warn] " + msg)
        if len(warnings) > 30:
            print(f"  ... 还有 {len(warnings) - 30} 条警告")
    return 0


def cmd_qc(args: argparse.Namespace) -> int:
    ensure_dirs()
    manifest = build_manifest()
    html_rows: list[str] = []
    for rec in manifest.get("assets", []):
        target = rec.get("target", "")
        path = ROOT / target
        exists = rec.get("exists")
        if exists:
            try:
                rel = os.path.relpath(path, QC_DIR).replace("\\", "/")
            except Exception:
                rel = "../../../" + target
            img = f'<img loading="lazy" src="{rel}" alt="">'
        else:
            img = '<div class="missing-box">缺</div>'
        cls = "card ok" if exists else "card missing"
        size = f"{rec.get('existing_w')}x{rec.get('existing_h')}" if exists else "-"
        html_rows.append(
            f'<div class="{cls}">{img}<div class="meta"><b>{rec.get("name", "")}</b>'
            f'<span>{rec.get("category", "")}</span><code>{target}</code><small>{size}</small></div></div>'
        )
    html = """<!doctype html><meta charset="utf-8"><title>大掌柜素材 QC</title>
<style>
body{font-family:system-ui,'Microsoft YaHei',sans-serif;background:#16181d;color:#eee;margin:16px}
h1{font-size:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.card{background:#23262e;border:1px solid #333;border-radius:10px;padding:8px;text-align:center;font-size:12px}
.card.missing{border-color:#e74c3c;background:#2a1d1d}
.card img{max-width:100%;height:120px;object-fit:contain;display:block;margin:0 auto 6px;background:#101114}
.missing-box{height:120px;line-height:120px;color:#e74c3c;font-size:28px}
.meta b{display:block;color:#ffd479}
.meta span{display:block;color:#8fd3ff;margin:2px 0}
.meta code{display:block;color:#aaa;word-break:break-all;font-size:10px}
.meta small{color:#777}
</style><h1>大掌柜素材 QC · __TIME__ · 缺图红框</h1><div class="grid">__CARDS__</div>"""
    html = html.replace("__TIME__", now_iso()).replace("__CARDS__", "\n".join(html_rows))
    out = QC_DIR / "index.html"
    out.write_text(html, encoding="utf-8")
    print(f"[qc] 已生成：{out}")
    return 0


# ---------------------------------------------------------------------------
# 5. CLI
# ---------------------------------------------------------------------------

def _add_image_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--tolerance", type=int, default=60, help="纯色背景抠图容差，默认 60")
    p.add_argument("--icon-size", type=int, default=ICON_SIZE_DEFAULT, help="图标最终边长，默认 128")
    p.add_argument("--portrait-max-w", type=int, default=PORTRAIT_MAX_W_DEFAULT, help="立绘最大宽度")
    p.add_argument("--portrait-max-h", type=int, default=PORTRAIT_MAX_H_DEFAULT, help="立绘最大高度")
    p.add_argument("--upscale-min-height", type=int, default=PORTRAIT_UPSCALE_H_DEFAULT, help="立绘低于此高度时放大，0=禁止")
    p.add_argument("--allow-upscale", action="store_true", help="允许 AI 原图被放大")
    p.add_argument("--card-max-w", type=int, default=600, help="门客卡图最大宽度")
    p.add_argument("--card-max-h", type=int, default=800, help="门客卡图最大高度")
    p.add_argument("--dry-run", action="store_true", help="只试跑不写文件")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="《大掌柜》素材流水线工具")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_scan = sub.add_parser("scan", help="扫描并生成素材契约清单")
    p_scan.set_defaults(func=cmd_scan)

    p_prompts = sub.add_parser("prompts", help="生成批量提示词和图集映射")
    p_prompts.add_argument("--max-costume-cells", type=int, default=6, help="单张服装图集最多放几套服装")
    p_prompts.add_argument("--icon-batch", type=int, default=9, help="图标图集每张最多几个图标")
    p_prompts.set_defaults(func=cmd_prompts)

    p_slice = sub.add_parser("slice", help="切图集、抠底、写入 assets")
    _add_image_args(p_slice)
    p_slice.add_argument("--inset", type=int, default=2, help="每个格子内缩像素，避免网格线")
    p_slice.set_defaults(func=cmd_slice)

    p_process = sub.add_parser("process", help="处理 inbox/raw 里按素材 id 命名的单图")
    _add_image_args(p_process)
    p_process.add_argument("--input", type=str, default="", help="输入目录，默认 build/asset_pipeline/inbox/raw")
    p_process.add_argument("--map", type=str, default="", help="可选映射 CSV，列 filename,key")
    p_process.set_defaults(func=cmd_process)

    p_derive = sub.add_parser("derive", help="从全身立绘派生服装图标/门客卡图")
    _add_image_args(p_derive)
    p_derive.add_argument("--bust-ratio", type=float, default=0.46, help="服装图标从全身立绘顶部裁切比例")
    p_derive.add_argument("--overwrite", action="store_true", help="覆盖已存在的派生图")
    p_derive.set_defaults(func=cmd_derive)

    p_verify = sub.add_parser("verify", help="检查缺图、尺寸、透明通道")
    p_verify.add_argument("--icon-size", type=int, default=ICON_SIZE_DEFAULT)
    p_verify.add_argument("--portrait-max-w", type=int, default=PORTRAIT_MAX_W_DEFAULT)
    p_verify.add_argument("--portrait-max-h", type=int, default=PORTRAIT_MAX_H_DEFAULT)
    p_verify.set_defaults(func=cmd_verify)

    p_qc = sub.add_parser("qc", help="生成 HTML 批量验收页")
    p_qc.set_defaults(func=cmd_qc)

    return parser


def main(argv: list[str] | None = None) -> int:
    ensure_dirs()
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())