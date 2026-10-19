"""离线预览：直接读 tavern_view.gd 的 UI_INFO 布局表渲染信息弹窗（2x）。
不参与游戏运行；改锚点后重跑本脚本即可看效果，避免真机往返。"""
import os
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GD = os.path.join(ROOT, "ui", "pages", "tavern_view.gd")
A = os.path.join(ROOT, "assets", "tavern")
FONT = r"C:\Windows\Fonts\msyh.ttc"

src = open(GD, encoding="utf-8").read()
block = re.search(r"const UI_INFO\s*:?=\s*\{(.*?)\n\}", src, re.S).group(1)


def rect(key):
    vals = re.search(r'"%s":\s*\[([^\]]+)\]' % key, block).group(1)
    return [float(x) for x in vals.split(",")]


def num(key):
    return float(re.search(r'"%s":\s*([0-9.]+)' % key, block).group(1))


def vec(key):
    vals = re.search(r'"%s":\s*Vector2\(([^)]+)\)' % key, block).group(1)
    return [float(x) for x in vals.split(",")]


PW, PH = vec("popup")
W, H = int(PW * 2), int(PH * 2)


def f(sz):
    return ImageFont.truetype(FONT, sz)


def px(fx, fy):
    return (fx * W, fy * H)


canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
bg = Image.open(os.path.join(A, "酒肆信息弹窗.png")).convert("RGBA").resize((W, H), Image.LANCZOS)
canvas.alpha_composite(bg)
d = ImageDraw.Draw(canvas)

# 左签条（两个字竖直堆叠）
tag = rect("tag")
tx = (tag[0] + tag[2]) / 2 * W
d.text((tx, (tag[1] + 0.25 * (tag[3] - tag[1])) * H), "酒", font=f(44), fill=(90, 61, 38, 255), anchor="mm")
d.text((tx, (tag[1] + 0.75 * (tag[3] - tag[1])) * H), "肆", font=f(44), fill=(90, 61, 38, 255), anchor="mm")

# 招牌 + 改名
tr = rect("title_row")
title_font = f(38)
x0, y0 = tr[0] * W, (tr[1] + tr[3]) / 2 * H
d.text((x0, y0), "招牌：红尘酒楼", font=title_font, fill=(74, 48, 24, 255), anchor="lm")
tw = d.textlength("招牌：红尘酒楼", font=title_font)
rim = Image.open(os.path.join(A, "酒楼改名.png")).convert("RGBA")
rim = rim.resize((rim.width * 2, rim.height * 2), Image.LANCZOS)
canvas.alpha_composite(rim, (int(x0 + tw + 14), int(y0 - rim.height / 2)))

# 等级
lv = rect("level")
d.text((lv[0] * W, (lv[1] + lv[3]) / 2 * H), "等级：1", font=f(30), fill=(107, 82, 54, 255), anchor="lm")

# 简介（按 intro 宽度折行）
intro = "方圆十里内最豪华的酒肆，吃喝玩乐一应俱全。童叟无欺，概不赊账。"
ir = rect("intro")
ifont = f(26)
maxw = int((ir[2] - ir[0]) * W)
line, lines = "", []
for ch in intro:
    if d.textlength(line + ch, font=ifont) <= maxw:
        line += ch
    else:
        lines.append(line)
        line = ch
lines.append(line)
ty = ir[1] * H
for ln in lines:
    d.text((ir[0] * W, ty), ln, font=ifont, fill=(122, 99, 72, 255), anchor="la")
    ty += 36

# 丝带标题
rb = rect("ribbon")
d.text(((rb[0] + rb[2]) / 2 * W, (rb[1] + rb[3]) / 2 * H), "接待客人收益", font=f(38), fill=(255, 255, 255, 235), anchor="mm")

rows = [
    ("银条收益", "100", "", os.path.join(A, "银条.png")),
    ("门客百业经验", "21", "22", os.path.join(A, "百业经验.png")),
    ("挚友才艺经验", "210", "220", os.path.join(A, "才艺经验.png")),
]
row_keys = ["row1", "row2", "row3"]
for (label, cur, nxt, icon), key in zip(rows, row_keys):
    lab_f, val_f = f(32), f(34)
    lw = d.textlength(label, font=lab_f)
    cw = d.textlength(cur, font=val_f)
    nw = d.textlength("→ " + nxt, font=val_f) if nxt else 0
    block_w = lw + 16 + cw + (12 + nw if nxt else 0)
    if icon:
        block_w += 56
    sx = W / 2 - block_w / 2
    cy = (num(key) + num("row_h") / 2) * H
    if icon:
        im = Image.open(icon).convert("RGBA")
        im.thumbnail((48, 48), Image.LANCZOS)
        canvas.alpha_composite(im, (int(sx + 4), int(cy - im.height / 2)))
        sx += 56
    d.text((sx, cy), label, font=lab_f, fill=(90, 61, 38, 255), anchor="lm")
    sx += lw + 16
    d.text((sx, cy), cur, font=val_f, fill=(63, 42, 21, 255), anchor="lm")
    sx += cw
    if nxt:
        d.text((sx + 12, cy), "→ " + nxt, font=val_f, fill=(46, 139, 87, 255), anchor="lm")

# 知名度
fm = rect("fame")
fame_f = f(32)
fame_txt = "知名度  100 / 6000"
fw = d.textlength(fame_txt, font=fame_f)
fx = W / 2 - (fw + 56) / 2
fy = (fm[1] + fm[3]) / 2 * H
im = Image.open(os.path.join(A, "知名度.png")).convert("RGBA")
im.thumbnail((44, 44), Image.LANCZOS)
canvas.alpha_composite(im, (int(fx + 2), int(fy - im.height / 2)))
fame_col = (46, 139, 87, 255) if 100 >= 6000 else (192, 57, 43, 255)
d.text((fx + 56, fy), fame_txt, font=fame_f, fill=fame_col, anchor="lm")

# 升级钮
bt = rect("button")
bx0, by0 = px(bt[0], bt[1])
bx1, by1 = px(bt[2], bt[3])
d.rounded_rectangle([bx0, by0, bx1, by1], radius=16, fill=(201, 160, 80, 255), outline=(154, 116, 51, 255), width=4)
d.text(((bx0 + bx1) / 2, (by0 + by1) / 2), "升级", font=f(40), fill=(58, 38, 19, 255), anchor="mm")

# 右上朱红圆钮
cx, cy, r = W - 56 + 23, 12 + 23, 46
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(178, 58, 48, 255), outline=(125, 36, 29, 255), width=4)
d.text((cx, cy - 3), "×", font=f(44), fill=(255, 245, 230, 255), anchor="mm")

# 叠到场景底色上，便于看边缘
scene = Image.new("RGBA", (W + 80, H + 80), (40, 30, 24, 255))
scene.alpha_composite(canvas, (40, 40))
out = os.path.join(ROOT, "docs", "preview_tavern_info.png")
scene.convert("RGB").save(out)
print("saved", out)
