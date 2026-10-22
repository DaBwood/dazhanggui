#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从《叫我大掌柜》APK 中提取 TextAsset（配置表 / protobuf schema）。

只依赖 Python 标准库。已验证：
  - Cocos Creator 2.4.x，resources bundle（assets/assets/resources）
  - TextAsset 的 text 字段是整段 XOR 1 的文本
  - GameConfigDB -> JSON，protobuf/* -> .proto

用法：
  python tools/extract_jwdzg.py --apk C:\\path\\jwdzg.apk --out _apk_extract
  python tools/extract_jwdzg.py --apk ... --out ... --what text
  python tools/extract_jwdzg.py --apk ... --out ... --what media   # 只拷明文媒体
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

TEXT_TYPE = "cc.TextAsset"
# 明文、可直接拷贝的 native 扩展名（纹理 .png/.pkm 是 lyqszp 加密，不在此列）
PLAIN_MEDIA = {".mp3", ".ogg", ".wav", ".atlas", ".bin", ".ttf"}
# 只处理这些类型的 native 资源，避免把 2 万多个 SpriteFrame 当失败
MEDIA_TYPES = {"cc.AudioClip", "cc.BufferAsset", "sp.SkeletonData", "cc.TTFFont"}


def decode_uuid(b64: str) -> str:
    base = b64.split("@")[0]
    if len(base) != 22:
        return base
    out = base[0] + base[1]
    for i in range(2, 22, 2):
        lhs, rhs = VAL[base[i]], VAL[base[i + 1]]
        out += HEX[lhs >> 2] + HEX[((lhs & 3) << 2) | (rhs >> 4)] + HEX[rhs & 15]
    return out[:8] + "-" + out[8:12] + "-" + out[12:16] + "-" + out[16:20] + "-" + out[20:]


def unxor(s: str) -> str:
    return "".join(chr(ord(c) ^ 1) for c in s)


def pick_text(arr):
    """在 Cocos 序列化数组里找到 [name, key, text] 三元组。"""
    for section in arr:
        if not isinstance(section, list):
            continue
        for obj in section:
            if isinstance(obj, list) and len(obj) >= 3 and isinstance(obj[2], str):
                return obj[0], obj[1], obj[2]
    return None


def classify(text: str) -> tuple:
    """返回 (扩展名, 是否 XOR 解密成功)。"""
    candidates = [(unxor(text), True), (text, False)]
    for s, dec in candidates:
        t = s.lstrip("\ufeff \r\n\t")
        if t.startswith("{") or t.startswith("["):
            return ".json", dec
        if t.startswith("syntax") or t.startswith("package ") or "message " in t[:400]:
            return ".proto", dec
    return ".txt", False


def safe_join(root: str, rel: str) -> str:
    rel = rel.replace("\\", "/").lstrip("/")
    rel = "/".join(p for p in rel.split("/") if p not in ("", ".", ".."))
    return os.path.join(root, *rel.split("/"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True)
    ap.add_argument("--out", default="_apk_extract")
    ap.add_argument("--what", choices=["text", "media", "all"], default="text")
    ap.add_argument("--limit", type=int, default=0, help="只处理前 N 项（调试用）")
    args = ap.parse_args()

    if not os.path.isfile(args.apk):
        sys.exit("APK not found: " + args.apk)

    z = zipfile.ZipFile(args.apk)
    cfg_path = "assets/assets/resources/config.json"
    if cfg_path not in z.namelist():
        sys.exit("Not a Cocos 2.4 resources bundle: " + cfg_path)

    man = json.loads(z.read(cfg_path))
    uuids = man["uuids"]
    paths = man["paths"]
    types = man["types"]
    text_idx = next((i for i, t in enumerate(types) if t == TEXT_TYPE), -1)
    if text_idx < 0:
        sys.exit("cc.TextAsset type not found")

    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)
    manifest = []
    ok = fail = 0

    def uuid_of(idx):
        if isinstance(uuids, dict):
            return uuids.get(str(idx)) or uuids.get(idx)
        return uuids[int(idx)]

    # native 目录一次建索引：uuid -> [entry, ...]（含 @sub 子资源）
    native_map = {}
    for n in z.namelist():
        if n.startswith("assets/assets/resources/native/"):
            base = os.path.basename(n)
            stem = base.split("@")[0]
            u = os.path.splitext(stem)[0]
            native_map.setdefault(u, []).append(n)

    for key, meta in paths.items():
        if args.limit and len(manifest) >= args.limit:
            break
        rel = meta[0]
        type_idx = meta[1] if len(meta) > 1 else -1
        if isinstance(type_idx, list):
            type_idx = type_idx[0] if type_idx else -1
        want_text = args.what in ("text", "all") and type_idx == text_idx
        type_name = types[type_idx] if isinstance(type_idx, int) and 0 <= type_idx < len(types) else ""
        want_media = args.what in ("media", "all") and not want_text and type_name in MEDIA_TYPES
        if not (want_text or want_media):
            continue

        try:
            uuid = decode_uuid(uuid_of(key))
            if want_text:
                imp = "assets/assets/resources/import/%s/%s.json" % (uuid[:2], uuid)
                arr = json.loads(z.read(imp))
                got = pick_text(arr)
                if not got:
                    raise ValueError("no text payload")
                _name, _key, raw = got
                body = unxor(raw)
                ext_out, decrypted = classify(raw)
                if not decrypted:
                    body = raw
                dest = safe_join(out_root, "text" + os.sep + rel + ext_out)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "w", encoding="utf-8") as f:
                    f.write(body)
                manifest.append([rel, dest, len(body), ext_out, "xor1" if decrypted else "plain"])
                ok += 1
            else:
                copied = 0
                for n in native_map.get(uuid, []):
                    ext2 = os.path.splitext(n)[1].lower()
                    if ext2 not in PLAIN_MEDIA:
                        continue  # 纹理/图集贴图等加密资源跳过
                    dest = safe_join(out_root, "media" + os.sep + rel + ext2)
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    with open(dest, "wb") as f:
                        f.write(z.read(n))
                    manifest.append([rel, dest, os.path.getsize(dest), ext2, "plain"])
                    ok += 1
                    copied += 1
                if copied == 0:
                    manifest.append([rel, "", 0, "", "skip-texture"])
        except Exception as e:  # noqa: BLE001
            fail += 1
            manifest.append([rel, "", 0, "", "FAIL: %s" % e])

    man_path = os.path.join(out_root, "manifest.csv")
    with open(man_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["source_path", "output", "size", "ext", "cipher"])
        w.writerows(manifest)

    print("ok=%d fail=%d out=%s" % (ok, fail, out_root))
    print("manifest=%s" % man_path)


if __name__ == "__main__":
    main()
