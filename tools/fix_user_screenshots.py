"""Clean the three user-provided full-body screenshots (remove UI, upscale)."""
import os

import cv2
import numpy as np
from PIL import Image

SHOTS = r"C:\Users\林\Pictures\Screenshots"
OUT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3\heroes_cos"


def load(path):
    return cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)


def clean(src, boxes, crop, out_path, target_h=1600):
    im = load(src)
    mask = np.zeros(im.shape[:2], np.uint8)
    for x0, y0, x1, y1 in boxes:
        mask[y0:y1, x0:x1] = 255
    fixed = cv2.inpaint(im, mask, 7, cv2.INPAINT_TELEA)
    x0, y0, x1, y1 = crop
    fixed = fixed[y0:y1, x0:x1]
    h, w = fixed.shape[:2]
    nh = target_h
    nw = max(1, int(round(w * nh / h)))
    fixed = cv2.resize(fixed, (nw, nh), interpolation=cv2.INTER_LANCZOS4)
    # mild unsharp
    blur = cv2.GaussianBlur(fixed, (0, 0), 1.2)
    fixed = cv2.addWeighted(fixed, 1.15, blur, -0.15, 0)
    cv2.imencode(".png", fixed)[1].tofile(out_path)
    print(out_path, fixed.shape[1], fixed.shape[0])


def main():
    os.makedirs(OUT, exist_ok=True)
    # 西域风尘: 720x1280 capture
    clean(
        os.path.join(r"C:\Users\林\AppData\Local\Temp\opencode", "tap_character.png"),
        [(8, 130, 108, 430), (150, 965, 570, 1075), (605, 1090, 715, 1245)],
        (0, 50, 720, 1210),
        os.path.join(OUT, "xiao_ba_cos03.png"),
    )
    # 巾帼归阙: 547x972
    clean(
        os.path.join(SHOTS, "屏幕截图 2026-10-31 225437.png"),
        [(8, 130, 108, 420), (80, 735, 460, 860), (495, 890, 547, 972)],
        (0, 45, 547, 930),
        os.path.join(OUT, "hua_mulan_cos02.png"),
    )
    # 寒锋破虏: 546x967
    clean(
        os.path.join(SHOTS, "屏幕截图 2026-10-31 225510.png"),
        [(8, 130, 108, 420), (80, 735, 460, 860), (170, 855, 430, 920), (495, 885, 546, 967)],
        (0, 45, 546, 925),
        os.path.join(OUT, "hua_mulan_cos01.png"),
    )


if __name__ == "__main__":
    main()
