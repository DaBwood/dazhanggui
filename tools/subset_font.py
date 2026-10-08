#!/usr/bin/env python3
# 字体子集化：msyh.ttc(19.7MB,且微软雅黑授权禁止随产品分发) → Noto Sans SC 常用汉字区子集(约2~3MB)
# 用法（在仓库根目录）：
#   1) pip install fonttools
#   2) python tools/subset_font.py "NotoSansSC-Regular.otf 的路径"     （也可以不带参数，运行时把文件拖进窗口回车）
# 产出：fonts/NotoSansSC-Subset.otf（或 .ttf，扩展名跟随源文件）
# 口径：不按工程用字扫描（玩家自定义名字/商会名会踩缺字），直接取全套常用区：
#   ASCII + CJK 统一汉字 U+4E00-9FA5 + 全角标点 U+FF00-FFEF + 中文标点 U+3000-303F
import os, sys, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNICODES = "U+0020-007E,U+2000-206F,U+3000-303F,U+4E00-9FA5,U+FF00-FFEF"

try:
    import fontTools  # noqa: F401
except ImportError:
    sys.exit("未安装 fontTools，请先运行：pip install fonttools")

raw = sys.argv[1] if len(sys.argv) > 1 else input("把 NotoSansSC-Regular.otf（或 .ttf）拖进本窗口，然后回车：")
src = raw.strip().strip('"').strip("'")
if not os.path.isfile(src):
    sys.exit("找不到字体源文件：" + src)

ext = ".otf" if src.lower().endswith(".otf") else ".ttf"
OUT = os.path.join(ROOT, "fonts", "NotoSansSC-Subset" + ext)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
print("源文件: %s (%.1f MB)" % (src, os.path.getsize(src) / 1e6))
print("裁剪: 全套常用汉字 + ASCII + 全角/中文标点 ...")
cmd = [sys.executable, "-m", "fontTools.subset", src, "--unicodes=" + UNICODES,
       "--output-file=" + OUT, "--layout-features=*", "--no-hinting", "--desubroutinize"]
r = subprocess.run(cmd)
if r.returncode != 0:
    sys.exit("fontTools.subset 执行失败（看上方报错）")
print("完成 -> %s (%.2f MB)" % (OUT, os.path.getsize(OUT) / 1e6))
print("接着做：等编辑器导入该字体 → 项目设置→GUI→Theme→自定义字体 选它（或清空）→ 再删 fonts/msyh.ttc 和 msyh.ttc.import")
