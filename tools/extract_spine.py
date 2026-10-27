#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract Spine skeletons (JSON + atlas) from 《叫我大掌柜》 APK.

Cocos 2.4 serializes sp.SkeletonData as:
  [0, "skeleton", atlasText, [textureNames], skeletonJson(dict), textures]
This script writes:
  C:\Users\林\Documents\大掌柜_assets\spine\<original path>.json
  C:\Users\林\Documents\大掌柜_assets\spine\<original path>.atlas
"""

import argparse
import csv
import json
import os
import sys
import zipfile

KEYS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
HEX = "0123456789abcdef"
VAL = {c: i for i, c in enumerate(KEYS)}


def decode_uuid(b64: str) -> str:
    base = b64.split("@")[0]
    if len(base) != 22:
        return base
    out = base[0] + base[1]
    for i in range(2, 22, 2):
        lhs, rhs = VAL[base[i]], VAL[base[i + 1]]
        out += HEX[lhs >> 2] + HEX[((lhs & 3) << 2) | (rhs >> 4)] + HEX[rhs & 15]
    return out[:8] + "-" + out[8:12] + "-" + out[12:16] + "-" + out[16:20] + "-" + out[20:]


def safe_path(root, rel, suffix):
    rel = rel.replace("\\", "/").lstrip("/")
    rel = "/".join(p for p in rel.split("/") if p not in ("", ".", ".."))
    return os.path.join(root, *rel.split("/")) + suffix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True)
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets")
    args = ap.parse_args()

    z = zipfile.ZipFile(args.apk)
    man = json.loads(z.read("assets/assets/resources/config.json"))
    uuids, paths, types = man["uuids"], man["paths"], man["types"]
    ti = next((i for i, t in enumerate(types) if t == "sp.SkeletonData"), -1)
    if ti < 0:
        sys.exit("sp.SkeletonData not found")

    out_root = os.path.abspath(args.out)
    rows = []
    ok = fail = 0

    def uuid_of(k):
        if isinstance(uuids, dict):
            return uuids.get(str(k)) or uuids.get(k)
        return uuids[int(k)]

    for k, meta in paths.items():
        if len(meta) < 2 or meta[1] != ti:
            continue
        rel = meta[0]
        try:
            u = decode_uuid(uuid_of(k))
            imp = "assets/assets/resources/import/%s/%s.json" % (u[:2], u)
            arr = json.loads(z.read(imp))
            payload = None
            for section in arr:
                if not isinstance(section, list):
                    continue
                for obj in section:
                    if isinstance(obj, list) and len(obj) >= 5 and isinstance(obj[4], dict):
                        payload = obj
                        break
                if payload:
                    break
            if not payload:
                raise ValueError("no SkeletonData payload")
            atlas_text = payload[2] if isinstance(payload[2], str) else ""
            skeleton = payload[4]
            jdest = safe_path(os.path.join(out_root, "spine"), rel, ".json")
            adest = safe_path(os.path.join(out_root, "spine"), rel, ".atlas")
            os.makedirs(os.path.dirname(jdest), exist_ok=True)
            with open(jdest, "w", encoding="utf-8") as f:
                json.dump(skeleton, f, ensure_ascii=False)
            with open(adest, "w", encoding="utf-8") as f:
                f.write(atlas_text)
            rows.append([rel, jdest, adest, skeleton.get("skeleton", {}).get("spine", ""), len(atlas_text)])
            ok += 1
        except Exception as e:  # noqa: BLE001
            rows.append([rel, "", "", "FAIL: %s" % e, 0])
            fail += 1

    mpath = os.path.join(out_root, "spine_manifest.csv")
    with open(mpath, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["rel", "json", "atlas", "spine_version", "atlas_chars"])
        w.writerows(rows)
    print("done ok=%d fail=%d" % (ok, fail))
    print("manifest:", mpath)


if __name__ == "__main__":
    main()
