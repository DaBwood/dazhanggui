#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Download missing hot-update assets listed in pch/project.manifest.

The local pch folder is only a partial extraction; project.manifest lists all
47k assets and the CDN serves them by relative path.  This tool takes asset ids
(or arbitrary path prefixes), finds every manifest key whose UUID belongs to
those entries, and downloads the missing files into pch/ with md5 checks.

Usage:
  python tools/fetch_hot_assets.py --ids 103392 103393 --dry-run
  python tools/fetch_hot_assets.py --ids 103392 103393
"""

import argparse
import gzip
import hashlib
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from astc2png import decode_astc_bytes  # noqa: E402
from etc1 import decode_pkm  # noqa: E402

B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
V = {c: i for i, c in enumerate(B64)}


def decodable_texture(data):
    """Return True if an encrypted .pkm/.astc payload decodes to an image."""
    try:
        raw = data
        if raw[:6] == b"lyqszp":
            raw = bytes(b ^ 0x70 for b in raw[6:])
        if raw[:2] == b"\x1f\x8b":
            raw = gzip.decompress(raw)
        if raw[:4] == b"PKM ":
            decode_pkm(raw)
            return True
        if raw[:4] == b"\x13\xab\xa1\x5c":
            decode_astc_bytes(data)
            return True
    except Exception:  # noqa: BLE001
        return False
    return False


def decode_uuid(value):
    if len(value) != 22:
        return value
    head = value[:2]
    for i in range(2, 22, 2):
        left, right = V[value[i]], V[value[i + 1]]
        head += "%x%x%x" % (left >> 2, ((left & 3) << 2) | (right >> 4), right & 0xF)
    return "%s-%s-%s-%s-%s" % (head[:8], head[8:12], head[12:16], head[16:20], head[20:32])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hot", default=r"C:\Users\林\Documents\大掌柜_assets\hotupdate")
    ap.add_argument("--ids", nargs="+", required=True,
                    help="BeautyDB/PatronsDB ids or path prefixes")
    ap.add_argument("--prefixes", nargs="*", default=["spine/beauty/", "newGui/Beauty/",
                                                      "spine/patrons/", "newGui/Patrons/"],
                    help="config path prefixes to consider")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    hot = os.path.abspath(args.hot)
    pch = os.path.join(hot, "pch")
    cfg = json.load(open(os.path.join(pch, "assets", "resources", "config.json"), encoding="utf-8"))
    man = json.load(open(os.path.join(pch, "project.manifest"), encoding="utf-8"))
    assets = man["assets"]
    package = man["packageUrl"].rstrip("/")

    wanted_uuids = set()
    for idx, value in cfg["paths"].items():
        path = str(value[0])
        if not any(path.startswith(pre) for pre in args.prefixes):
            continue
        if not any(path.startswith(pre + cid) for cid in args.ids for pre in args.prefixes):
            continue
        wanted_uuids.add(cfg["uuids"][int(idx)])
        wanted_uuids.add(decode_uuid(cfg["uuids"][int(idx)]))

    keys = []
    for key, info in assets.items():
        if any(u in key for u in wanted_uuids):
            keys.append((key, info))
    keys.sort()

    total = sum(info.get("size", 0) for _key, info in keys)
    print("wanted uuids", len(wanted_uuids), "manifest keys", len(keys),
          "bytes", total, "from", package)
    if args.dry_run:
        for key, info in keys:
            print(" ", key, info.get("size"), info.get("originalMd5"))
        return

    ok = skipped = failed = 0
    for key, info in keys:
        dst = os.path.join(pch, *key.split("/"))
        if os.path.exists(dst) and os.path.getsize(dst) == info.get("size"):
            skipped += 1
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        url = package + "/" + key
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
        except Exception as exc:  # noqa: BLE001
            print("FAIL", key, exc)
            failed += 1
            continue
        want = info.get("originalMd5") or info.get("md5")
        got = hashlib.md5(data).hexdigest()
        if want and got != want:
            # Texture pages are re-encrypted on the CDN with a different
            # container hash; accept them if they still decode to an image.
            if key.endswith((".pkm", ".astc")) and decodable_texture(data):
                print("md5 differs but decodes", key)
            else:
                print("MD5 MISMATCH", key, got, want)
                failed += 1
                continue
        with open(dst, "wb") as f:
            f.write(data)
        print("ok", key, len(data))
        ok += 1
    print("downloaded", ok, "skipped", skipped, "failed", failed)


if __name__ == "__main__":
    main()
