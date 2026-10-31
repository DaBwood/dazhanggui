#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Shared data sources for the portrait tools.

The base package and the Cocos hot-update bundle store the same two configs
in different shapes:

* base ``text/cn/allJson/AllJson2.json``          plain JSON
* base ``text/cn/zh_cn/json/LanguageWordDB.json`` plain JSON, values XOR 0x1040
* hot  ``.../import/a2/a24cc4af-....json``        Asset JSON, text at [5][0][2]
* hot  ``.../import/b9/b992b378-....json``        same, but every char XOR 1

The hot bundle is a strict superset of the base tables (PatronsDB 115 -> 118,
BeautyDB 118 -> 125), so the hot copy wins when it exists.
"""

import json
import os

HOT_ALLJSON = ("import", "a2", "a24cc4af-f247-4958-a13e-cd2d4852bb84.json")
HOT_LANGUAGE = ("import", "b9", "b992b378-9a36-492d-9866-a72ce0565373.json")


def _hot_root(assets):
    return os.path.join(assets, "hotupdate", "pch", "assets", "resources")


def _hot_text(assets, rel, xor_one):
    path = os.path.join(_hot_root(assets), *rel)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    try:
        text = data[5][0][2]
    except (IndexError, TypeError):
        return None
    if xor_one:
        text = "".join(chr(ord(c) ^ 1) for c in text)
    return text


def load_alljson(assets):
    """Return the merged AllJson2 tables (hot wins over base)."""
    merged = {}
    base_path = os.path.join(assets, "text", "cn", "allJson", "AllJson2.json")
    if os.path.exists(base_path):
        with open(base_path, encoding="utf-8") as f:
            merged.update(json.load(f))
    text = _hot_text(assets, HOT_ALLJSON, xor_one=False)
    if text:
        merged.update(json.loads(text))
    return merged


def decode_name(value):
    return "".join(chr(ord(c) ^ 0x1040) if ord(c) > 0x1000 else c for c in value)


def load_names(assets):
    """Return {language-key: Chinese name}, hot update winning."""
    names = {}
    base_path = os.path.join(assets, "text", "cn", "zh_cn", "json", "LanguageWordDB.json")
    if os.path.exists(base_path):
        with open(base_path, encoding="utf-8") as f:
            rows = json.load(f)["LanguageWordDB"][2:]
        for r in rows:
            if len(r) > 1:
                names[str(r[0])] = decode_name(str(r[1]))
    text = _hot_text(assets, HOT_LANGUAGE, xor_one=True)
    if text:
        for r in json.loads(text)["LanguageWordDB"][2:]:
            if len(r) > 1:
                names[str(r[0])] = decode_name(str(r[1]))
    return names


def load_records(assets, kind, tables=None):
    """Return the PatronsDB / BeautyDB rows as dicts."""
    data = tables if tables is not None else load_alljson(assets)
    key = "PatronsDB" if kind == "patrons" else "BeautyDB"
    table = data[key]
    if isinstance(table, str):
        table = json.loads(table)
    table = table[key] if isinstance(table, dict) else table
    header = table[1]
    return [dict(zip(header, row)) for row in table[2:]]


def record_name(names, kind, rec):
    """Name for a DB row, preferring the id-specific language key."""
    prefix = "Patrons" if kind == "patrons" else "Beauty"
    cid = str(rec["id"])
    for key in (prefix + "-" + cid, prefix + "-" + cid + "_1", str(rec.get("name", ""))):
        if key in names:
            return names[key]
    return ""
