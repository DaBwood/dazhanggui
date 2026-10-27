#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract (and decrypt) textures from 《叫我大掌柜》 APK.

Format (verified):
  .png : b"lyqszp" + XOR 0x70 -> PNG
  .pkm : b"lyqszp" + XOR 0x70 -> gzip -> PKM (ETC1)

Usage:
  python tools/extract_textures.py --apk <apk> --out C:\Users\林\Documents\大掌柜_assets --png
  python tools/extract_textures.py --apk <apk> --out C:\Users\林\Documents\大掌柜_assets --pkm --decode
  python tools/extract_textures.py --apk <apk> --out C:\Users\林\Documents\大掌柜_assets --all --decode --jobs 8
"""

import argparse
import csv
import gzip
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

MAGIC = b"lyqszp"
XOR = 0x70
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


def build_tasks(apk, want_png, want_pkm):
    z = zipfile.ZipFile(apk)
    man = z and __import__("json").loads(z.read("assets/assets/resources/config.json"))
    uuids = man["uuids"]
    paths = man["paths"]

    def uuid_of(k):
        if isinstance(uuids, dict):
            return uuids.get(str(k)) or uuids.get(k)
        return uuids[int(k)]

    uuid_to_rel = {}
    for k, v in paths.items():
        try:
            u = decode_uuid(uuid_of(k))
        except Exception:
            continue
        uuid_to_rel.setdefault(u, v[0])

    native = [n for n in z.namelist() if n.startswith("assets/assets/resources/native/")]
    z.close()

    tasks = []
    for n in native:
        low = n.lower()
        if low.endswith(".png") and not want_png:
            continue
        if low.endswith(".pkm") and not want_pkm:
            continue
        if not (low.endswith(".png") or low.endswith(".pkm")):
            continue
        base = os.path.basename(n)
        stem = base.split("@")[0]
        u = os.path.splitext(stem)[0]
        rel = uuid_to_rel.get(u, "")
        kind = "png" if low.endswith(".png") else "pkm"
        tasks.append((n, rel or ("_uuid/" + u), kind))
    return tasks


def safe_path(root, rel, suffix):
    rel = rel.replace("\\", "/").lstrip("/")
    rel = "/".join(p for p in rel.split("/") if p not in ("", ".", ".."))
    return os.path.join(root, *rel.split("/")) + suffix


def work(args):
    apk, out_root, decode_pkm, chunk = args
    z = zipfile.ZipFile(apk)
    rows = []
    for native, rel, kind in chunk:
        try:
            data = z.read(native)
            if data[:6] == MAGIC:
                payload = bytes(b ^ XOR for b in data[6:])
            else:
                payload = data
            if kind == "png":
                dest = safe_path(os.path.join(out_root, "textures", "png"), rel, ".png")
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as f:
                    f.write(payload)
                rows.append([native, rel, "png", dest, len(payload), "", "", ""])
            else:
                raw = gzip.decompress(payload)
                dest = safe_path(os.path.join(out_root, "textures", "pkm"), rel, ".pkm")
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "wb") as f:
                    f.write(raw)
                w = h = 0
                if raw[:4] == b"PKM " and len(raw) >= 16:
                    import struct
                    _, w, h, _, _ = struct.unpack(">HHHHH", raw[6:16])
                png_dest = ""
                if decode_pkm:
                    try:
                        from etc1 import decode_pkm as dec
                        img = dec(raw)
                        png_dest = safe_path(os.path.join(out_root, "textures", "png_from_pkm"), rel, ".png")
                        os.makedirs(os.path.dirname(png_dest), exist_ok=True)
                        img.save(png_dest)
                    except Exception as e:  # noqa: BLE001
                        png_dest = "FAIL: %s" % e
                rows.append([native, rel, "pkm", dest, len(raw), w, h, png_dest])
        except Exception as e:  # noqa: BLE001
            rows.append([native, rel, kind, "", 0, "", "", "FAIL: %s" % e])
    z.close()
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True)
    ap.add_argument("--out", default=r"C:\Users\林\Documents\大掌柜_assets")
    ap.add_argument("--png", action="store_true")
    ap.add_argument("--pkm", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--decode", action="store_true", help="PKM -> PNG (ETC1)")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    want_png = args.png or args.all
    want_pkm = args.pkm or args.all
    if not (want_png or want_pkm):
        ap.error("choose --png / --pkm / --all")

    tasks = build_tasks(args.apk, want_png, want_pkm)
    if args.limit:
        tasks = tasks[: args.limit]
    print("tasks:", len(tasks), "jobs:", args.jobs)

    out_root = os.path.abspath(args.out)
    os.makedirs(out_root, exist_ok=True)

    chunk_size = max(20, len(tasks) // max(1, args.jobs * 4))
    chunks = [tasks[i:i + chunk_size] for i in range(0, len(tasks), chunk_size)]
    payload = [(args.apk, out_root, args.decode, c) for c in chunks]

    all_rows = []
    if args.jobs <= 1:
        for p in payload:
            all_rows.extend(work(p))
    else:
        # 注意：Windows 沙盒禁止命名管道，ProcessPoolExecutor 会 WinError 5；
        # 用线程池（每个 work 自己开 ZipFile，避免共享句柄）。
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            for rows in ex.map(work, payload):
                all_rows.extend(rows)

    man = os.path.join(out_root, "textures_manifest.csv")
    with open(man, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["native", "rel", "kind", "out", "bytes", "width", "height", "png"])
        w.writerows(all_rows)
    ok = sum(1 for r in all_rows if not (len(r) > 7 and str(r[7]).startswith("FAIL")))
    print("done ok=%d fail=%d" % (ok, len(all_rows) - ok))
    print("manifest:", man)


if __name__ == "__main__":
    main()
