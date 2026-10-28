#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Classify portrait PNGs as composed figures vs exploded sprite atlases.

A composed full-body has one dominant connected silhouette.  A Spine atlas
page that was never assembled has many similar-sized islands.
"""

import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\portraits_v2"


def comp_stats(path, maxdim=320):
    im = Image.open(path).convert("RGBA")
    im.thumbnail((maxdim, maxdim), Image.LANCZOS)
    a = np.asarray(im)[:, :, 3] > 40
    h, w = a.shape
    if not a.any():
        return 0, 0.0, 0.0
    seen = np.zeros((h, w), bool)
    sizes = []
    for y in range(h):
        for x in np.where(a[y] & ~seen[y])[0]:
            if seen[y, x]:
                continue
            q = deque([(y, x)])
            seen[y, x] = True
            n = 0
            while q:
                cy, cx = q.popleft()
                n += 1
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            sizes.append(n)
    total = sum(sizes)
    sizes.sort(reverse=True)
    big = [s for s in sizes if s > total * 0.002]
    return len(big), (sizes[0] / total if total else 0.0), total / (h * w)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else ROOT
    for kind in sorted(os.listdir(root)):
        d = os.path.join(root, kind)
        if not os.path.isdir(d):
            continue
        rows = []
        for f in sorted(os.listdir(d)):
            if not f.endswith(".png"):
                continue
            n, largest, fill = comp_stats(os.path.join(d, f))
            rows.append((f, n, largest, fill))
        exploded = [r for r in rows if r[1] > 3 and r[2] < 0.80]
        print("%s: total=%d exploded=%d" % (kind, len(rows), len(exploded)))
        if exploded:
            print("   " + ", ".join("%s(%d,%.2f)" % (f, n, l) for f, n, l, _ in exploded))


if __name__ == "__main__":
    main()
