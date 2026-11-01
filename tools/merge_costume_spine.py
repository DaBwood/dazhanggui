"""Merge a base patron body with a costume-only spineSkin package.

The hot-update `spineSkin` bundles for basic outfits contain clothes, hair,
face and effects but not the body skin.  Their skeleton reuses the base
patron's bones; the game draws the base body underneath.  This tool creates a
single merged skeleton (base body slots + costume slots) and a two-page atlas,
so `render_skin_spine.py`-style WebGL rendering produces the full character.
"""
import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from astc2png import decode_astc_bytes
from render_missing_portraits import resolve

TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"
HERE = os.path.dirname(os.path.abspath(__file__))

# Base slots that are body skin rather than the default costume/hair/effects.
BODY_SLOTS = {
    "shengti",
    "yshoubi",
    "zshouwan",
    "yshouwan",
    "yshouzhang",
    "zshouzhang",
    "yjiao",
    "zjiao",
    "eh01",
    "eh02",
    "tou",
}


def rewrite_atlas(text, page_name, prefix):
    out = []
    page_seen = False
    for line in text.splitlines():
        if not page_seen and line.strip().endswith(".png") and not line.startswith(" "):
            out.append(page_name)
            page_seen = True
            continue
        if line and not line[0].isspace() and ":" not in line:
            out.append(prefix + line.strip())
        else:
            out.append(line)
    return "\n".join(out)


def merge(assets, patron_id, skin_id, stage_root):
    base = resolve(assets, "patrons", patron_id)
    if not base:
        raise SystemExit("base patron not found: " + patron_id)
    base_data = json.load(open(base["data"], encoding="utf-8"))
    base_atlas = open(base["atlas"], encoding="utf-8").read()

    skin_dir = os.path.join(assets, "hotupdate", "skins", skin_id, "spineSkin")
    skin_data = json.load(open(os.path.join(skin_dir, "skeleton.json"), encoding="utf-8"))
    skin_atlas = open(os.path.join(skin_dir, "skeleton.atlas"), encoding="utf-8").read()

    stage = os.path.join(stage_root, "stage", "skin_merge", skin_id)
    os.makedirs(stage, exist_ok=True)
    shutil.copy2(base["texture"], os.path.join(stage, "base.png"))
    astc = os.path.join(skin_dir, "skeleton.astc")
    if os.path.exists(astc):
        decode_astc_bytes(open(astc, "rb").read()).save(os.path.join(stage, "costume.png"))
    else:
        png = os.path.join(skin_dir, "skeleton.png")
        if not os.path.exists(png):
            raise SystemExit("no costume texture: " + skin_dir)
        shutil.copy2(png, os.path.join(stage, "costume.png"))

    merged = {
        "skeleton": skin_data["skeleton"],
        "bones": skin_data["bones"],
        "slots": [],
        "skins": {"default": {}},
        "animations": skin_data.get("animations", {}),
    }
    if "transform" in skin_data:
        merged["transform"] = skin_data["transform"]

    base_skin = base_data.get("skins", {}).get("default", {})
    for slot in base_data["slots"]:
        name = slot["name"]
        if name not in BODY_SLOTS:
            continue
        slot = dict(slot)
        att = slot.get("attachment")
        if att:
            new_att = "base_" + att
            slot["attachment"] = new_att
            for key, value in base_skin.get(name, {}).items():
                value = dict(value)
                if value.get("parent"):
                    value["parent"] = "base_" + value["parent"]
                merged["skins"]["default"].setdefault(name, {})["base_" + key] = value
        merged["slots"].append(slot)

    for slot in skin_data["slots"]:
        merged["slots"].append(dict(slot))
    for slot_name, atts in skin_data.get("skins", {}).get("default", {}).items():
        dst = merged["skins"]["default"].setdefault(slot_name, {})
        for key, value in atts.items():
            dst[key] = value

    merged_path = os.path.join(stage, "skeleton.json")
    with open(merged_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False)
    combined_atlas = (rewrite_atlas(base_atlas, "base.png", "base_") + "\n"
                      + rewrite_atlas(skin_atlas, "costume.png", ""))
    with open(os.path.join(stage, "skeleton.atlas"), "w", encoding="utf-8") as f:
        f.write(combined_atlas)
    return stage


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--patron", required=True)
    ap.add_argument("--skin", required=True)
    ap.add_argument("--stage-root", default=os.path.join(TEMP, "skin_render"))
    args = ap.parse_args()
    stage = merge(args.assets, args.patron, args.skin, args.stage_root)
    print(stage)


if __name__ == "__main__":
    main()
