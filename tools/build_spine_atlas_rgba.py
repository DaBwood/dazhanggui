#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build an RGBA Spine atlas page by keying each packed region separately.

The raw skeleton.png is a colour atlas page followed by a *composed* white
silhouette, so the silhouette cannot be used as the atlas alpha.  Instead we
key the black background inside each atlas region and fill only holes that are
enclosed by that region, which keeps black clothing opaque and drops the gaps
between parts.
"""

import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def parse_atlas_pages(source):
    """Parse a Spine atlas into a list of pages.

    A multi-page atlas is just several page blocks concatenated:
        page-name
        size: W,H
        format: ...
        region
          rotate: ...
    Page names and region names are both unindented, so a page header is
    recognised by the following unindented ``size:`` line.  Region ``size:``
    lines are indented and therefore never match.
    """
    if os.path.exists(source):
        text = open(source, encoding="utf-8").read()
    else:
        text = source
    lines = text.splitlines()
    starts = []
    for i, line in enumerate(lines):
        if not line or line.startswith(" ") or ":" in line:
            continue
        j = i + 1
        while j < len(lines) and not lines[j].strip():
            j += 1
        if j < len(lines) and not lines[j].startswith(" ") and lines[j].strip().startswith("size:"):
            starts.append(i)
    pages = []
    for n, start in enumerate(starts):
        end = starts[n + 1] if n + 1 < len(starts) else len(lines)
        page = {"name": lines[start].strip(), "regions": []}
        cur = None
        for line in lines[start + 1:end]:
            s = line.strip()
            if not s:
                continue
            if not line.startswith(" ") and ":" not in s:
                cur = {"name": s}
                page["regions"].append(cur)
            elif cur is None and not line.startswith(" ") and ":" in s:
                k, v = s.split(":", 1)
                page[k.strip()] = v.strip()
            elif cur is not None and ":" in s:
                k, v = s.split(":", 1)
                cur[k.strip()] = v.strip()
        if "size" in page:
            w, h = page["size"].split(",")
            page["size"] = (int(w), int(h))
        pages.append(page)
    return pages


def parse_atlas(path):
    """Backwards-compatible single-page view (first page)."""
    pages = parse_atlas_pages(path)
    if not pages:
        return {}, []
    return pages[0], pages[0]["regions"]


def fill_enclosed(alpha):
    h, w = alpha.shape
    canvas = np.zeros((h + 4, w + 4), dtype=np.uint8)
    canvas[2:2 + h, 2:2 + w] = alpha.astype(np.uint8) * 255
    mask = Image.fromarray(canvas, "L")
    for point in ((0, 0), (mask.width - 1, 0), (0, mask.height - 1), (mask.width - 1, mask.height - 1)):
        ImageDraw.floodfill(mask, point, 128, thresh=0)
    arr = np.asarray(mask)
    out = np.where(arr == 128, 0, 255).astype(np.uint8)
    return out[2:2 + h, 2:2 + w]


def fill_small_holes(solid, max_frac=0.25):
    """Fill enclosed background pockets, but never the outside background.

    A thin prop (staff) splits the region into large border-touching background
    areas; those stay transparent.  Small enclosed pockets (belt gaps, dark
    clothing interiors) are filled so the part does not get holes.
    """
    h, w = solid.shape
    visited = np.zeros((h, w), bool)
    limit = max(4, int(h * w * max_frac))
    for y in range(h):
        for x in range(w):
            if solid[y, x] or visited[y, x]:
                continue
            stack = [(y, x)]
            visited[y, x] = True
            comp = []
            border = False
            while stack:
                cy, cx = stack.pop()
                comp.append((cy, cx))
                if cy == 0 or cx == 0 or cy == h - 1 or cx == w - 1:
                    border = True
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and not solid[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        stack.append((ny, nx))
            if not border and len(comp) <= limit:
                for cy, cx in comp:
                    solid[cy, cx] = True
    return solid


def build(raw_path, atlas_path, out_path, threshold=2, page_index=0, atlas_text=None,
          fill_holes=True, mask_path=None):
    """Build one RGBA atlas page from a raw colour page.

    The game stores the colour page followed by a packed white alpha mask
    (same atlas layout), so the top ``H`` rows are the colour page and the
    matching rows of the second half are its mask.  When ``mask_path`` is
    given that mask is used directly; otherwise the old per-region black
    keying is used for packages that only ship a colour page.
    """
    pages = parse_atlas_pages(atlas_text if atlas_text is not None else atlas_path)
    if not pages:
        raise ValueError("empty atlas: %s" % atlas_path)
    page = pages[page_index]
    regions = page["regions"]
    W, H = page["size"]
    im = Image.open(raw_path).convert("RGB")
    arr = np.asarray(im)[:H, :W]
    if mask_path:
        alpha = np.asarray(Image.open(mask_path).convert("L"))[:H, :W]
        out = Image.fromarray(arr, "RGB").convert("RGBA")
        out.putalpha(Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(0.3)))
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        out.save(out_path, optimize=True)
        return out.size, len(regions), []
    alpha = np.zeros((H, W), dtype=np.uint8)
    empty = []
    for r in regions:
        if "xy" not in r or "size" not in r:
            continue
        x, y = (int(v) for v in r["xy"].split(","))
        w, h = (int(v) for v in r["size"].split(","))
        # Spine packs rotated regions transposed: the rect on the page is
        # (h x w), not (w x h).  The runtime swaps the UVs itself, so we must
        # copy the packed rect exactly as stored.
        if r.get("rotate", "").strip().lower() == "true":
            w, h = h, w
        rect = arr[y:y + h, x:x + w]
        solid = rect.max(axis=2) > threshold
        if not solid.any():
            empty.append(r["name"])
            continue
        # Fill only small enclosed pockets; large border-touching background
        # areas (around thin props) must stay transparent.
        if fill_holes:
            solid = fill_small_holes(solid)
        a = (solid * 255).astype(np.uint8)
        alpha[y:y + h, x:x + w] = a
    out = Image.fromarray(arr, "RGB").convert("RGBA")
    out.putalpha(Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(0.3)))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path, optimize=True)
    return out.size, len(regions), empty


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: build_spine_atlas_rgba.py <skeleton.png> <skeleton.atlas> <out.png>")
    print(build(sys.argv[1], sys.argv[2], sys.argv[3]))
