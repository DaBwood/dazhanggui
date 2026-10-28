#!/usr/bin/env python3
"""生成门客卡片缩略图。

为什么需要：门客立绘原图约 1254x1735（解码后单张 ~8.5 MB 显存），
而卡片显示尺寸只有 ~190x300。直接把原图塞进卡片，69 张就要 531 MB 显存，
进游戏/进门客页会明显卡顿。

hero_card.gd 本来就优先读 res://assets/portraits/heroes_card/{hero_id}.png，
只是这个目录一直不存在，所以全部回落到原图。本脚本补上这个目录。

用法：
    python tools/make_hero_thumbs.py                # 默认宽 320
    python tools/make_hero_thumbs.py --width 240
    python tools/make_hero_thumbs.py --force        # 全部重生成

只读 heroes/ 与 heroes_cos/，只写 *_card/，不碰原图。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PAIRS = [
    (ROOT / "assets" / "portraits" / "heroes", ROOT / "assets" / "portraits" / "heroes_card"),
    (ROOT / "assets" / "portraits" / "heroes_cos", ROOT / "assets" / "portraits" / "heroes_cos_card"),
]


def make_one(src: Path, dst: Path, width: int, force: bool) -> tuple[bool, int, int]:
    if dst.exists() and not force and dst.stat().st_mtime >= src.stat().st_mtime:
        return False, 0, 0
    with Image.open(src) as im:
        im = im.convert("RGBA")
        w, h = im.size
        if w <= width:
            im.save(dst, "PNG", optimize=True)
            return True, dst.stat().st_size, w * h * 4
        nh = max(1, round(h * width / w))
        im = im.resize((width, nh), Image.LANCZOS)
        dst.parent.mkdir(parents=True, exist_ok=True)
        im.save(dst, "PNG", optimize=True)
        return True, dst.stat().st_size, width * nh * 4


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=320)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    total = made = 0

    for src_dir, dst_dir in PAIRS:
        if not src_dir.is_dir():
            continue
        sources = sorted(src_dir.glob("*.png"))
        if not sources:
            continue
        dst_dir.mkdir(parents=True, exist_ok=True)
        for src in sources:
            total += 1
            ok, _b, _v = make_one(src, dst_dir / src.name, args.width, args.force)
            if ok:
                made += 1
        # 清理原图已删除的缩略图
        src_names = {p.name for p in sources}
        for stale in dst_dir.glob("*.png"):
            if stale.name not in src_names:
                stale.unlink()
                print(f"  remove stale: {stale.name}")

    # 体积统计：源 vs 缩略图（解码后 = 宽 x 高 x 4）
    def scan(folder: Path) -> tuple[int, int, int]:
        n = disk = vram = 0
        for p in folder.glob("*.png"):
            with Image.open(p) as im:
                w, h = im.size
            n += 1
            disk += p.stat().st_size
            vram += w * h * 4
        return n, disk, vram

    sn, sdisk, svram = scan(PAIRS[0][0])
    dn, ddisk, dvram = scan(PAIRS[0][1]) if PAIRS[0][1].is_dir() else (0, 0, 0)

    print(f"total={total} made={made} width={args.width}")
    print(f"source: n={sn} disk={sdisk/1048576:.1f} MB vram={svram/1048576:.0f} MB")
    print(f"thumbs: n={dn} disk={ddisk/1048576:.1f} MB vram={dvram/1048576:.0f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
