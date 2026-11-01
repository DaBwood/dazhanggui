"""Patch spine atlases with missing regions from a donor atlas or transparent
placeholders, so the 3.8 skel bundles render instead of failing."""
import os
import re

from PIL import Image

ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
HOT = os.path.join(ASSETS, "hotupdate", "skins")
DONOR = os.path.join(HOT, "109191", "spineSkin")


def parse_atlas(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    pages = []
    current = None
    i = 0
    while i < len(lines):
        line = lines[i]
        if line and not line[0].isspace() and line.endswith(".png"):
            current = {"name": line, "regions": {}}
            pages.append(current)
            i += 1
            while i < len(lines) and (not lines[i] or lines[i][0].isspace()):
                i += 1
            continue
        if line and not line[0].isspace() and ":" not in line:
            name = line
            props = {}
            i += 1
            while i < len(lines) and (not lines[i] or lines[i][0].isspace()):
                m = re.match(r"\s*(\w+):\s*(.+)", lines[i])
                if m:
                    props[m.group(1)] = m.group(2).strip()
                i += 1
            if current:
                current["regions"][name] = props
            continue
        i += 1
    return pages


def crop_region(page_img, props):
    x, y = [int(v) for v in props["xy"].split(",")]
    w, h = [int(v) for v in props["size"].split(",")]
    if props.get("rotate") == "true":
        return page_img.crop((x, y, x + h, y + w)).rotate(90, expand=True)
    return page_img.crop((x, y, x + w, y + h))


def append_page(target_dir, atlas_path, image, region_name):
    w, h = image.size
    image.save(os.path.join(target_dir, "patch.png"))
    block = [
        "patch.png",
        "size: %d,%d" % (w, h),
        "format: RGBA8888",
        "filter: Linear,Linear",
        "repeat: none",
        region_name,
        "  rotate: false",
        "  xy: 0,0",
        "  size: %d,%d" % (w, h),
        "  orig: %d,%d" % (w, h),
        "  offset: 0,0",
        "  index: -1",
    ]
    with open(atlas_path, "a", encoding="utf-8") as f:
        f.write("\n" + "\n".join(block) + "\n")
    print("patched", target_dir, region_name, image.size)


def patch(target_id, missing, donor_region=None):
    target_dir = os.path.join(HOT, target_id, "spineSkin")
    atlas = os.path.join(target_dir, "skeleton.atlas")
    if donor_region:
        pages = parse_atlas(os.path.join(DONOR, "skeleton.atlas"))
        found = None
        for page in pages:
            if donor_region in page["regions"]:
                found = (page, page["regions"][donor_region])
                break
        if not found:
            raise SystemExit("donor region not found: " + donor_region)
        page, props = found
        donor_img = Image.open(os.path.join(DONOR, page["name"])).convert("RGBA")
        image = crop_region(donor_img, props)
    else:
        image = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    append_page(target_dir, atlas, image, missing)


def main():
    # remove old patch pages if any
    for cid in ("109255", "109256", "109269"):
        p = os.path.join(HOT, cid, "spineSkin", "patch.png")
        if os.path.exists(p):
            os.remove(p)
    patch("109255", "3qi_22")
    patch("109269", "sha1_25")
    patch("109256", "feng_17", donor_region="feng_17")


if __name__ == "__main__":
    main()
