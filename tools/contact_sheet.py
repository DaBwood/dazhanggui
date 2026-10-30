#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build thumbnail contact sheets so the rendered portraits can be reviewed.

Usage:
  python tools/contact_sheet.py <dir> [out.png] [--cols 8] [--cell 190]
"""

import argparse
import math
import os

from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--cell", type=int, default=190)
    args = ap.parse_args()

    files = sorted(f for f in os.listdir(args.src) if f.lower().endswith(".png"))
    cell = args.cell
    cols = args.cols
    rows = math.ceil(len(files) / cols)
    out = Image.new("RGBA", (cols * cell, rows * (cell + 16)), (255, 255, 255, 255))
    d = ImageDraw.Draw(out)
    for i, name in enumerate(files):
        im = Image.open(os.path.join(args.src, name)).convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 0, 255, 255))
        bg.alpha_composite(im)
        th = bg.copy()
        th.thumbnail((cell - 4, cell - 4))
        x = (i % cols) * cell
        y = (i // cols) * (cell + 16)
        out.alpha_composite(th, (x + (cell - th.width) // 2, y + (cell - th.height) // 2))
        d.text((x + 2, y + cell + 1), name[:-4], fill=(0, 0, 0, 255))
    dst = args.out or os.path.join(args.src, "_sheet.png")
    out.save(dst)
    print(dst, out.size)


if __name__ == "__main__":
    main()
