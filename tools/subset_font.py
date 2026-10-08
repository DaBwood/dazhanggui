#!/usr/bin/env python3
# 字体子集化：msyh.ttc(19.7MB,且微软雅黑授权禁止随产品分发) → Noto Sans SC 常用区子集(约3~4MB)
# 用法（在仓库根目录）：
#   1) pip install fonttools
#   2) python tools/subset_font.py "NotoSansSC-Regular.otf 的路径"     （也可以不带参数，运行时把文件拖进窗口回车）
# 产出：fonts/NotoSansSC-Subset.otf（或 .ttf，扩展名跟随源文件）
# 口径：不按工程用字扫描（玩家自定义名字/商会名会踩缺字），取全套常用区：
#   ASCII + Latin-1(×·²§) + 数学运算(≥≤≈≠−) + 箭头(→) + 圈号数字(①) + 几何符号(●▶) + 杂项符号(★⚠) + 装饰符(✕✓)
#   + 中文标点 + CJK 统一汉字。真 emoji(🔒👤🎁 等)不进字体——UI 里的已在代码层剥离。
import os, sys, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNICODES = ("U+0020-007E,U+0080-00FF,U+2000-206F,U+2190-21FF,U+2200-22FF,U+2300-23FF,"
            "U+2460-24FF,U+2500-257F,U+25A0-25FF,U+2600-26FF,U+2700-27BF,"
            "U+3000-303F,U+4E00-9FA5,U+FF00-FFEF")


def main():
    try:
        import fontTools  # noqa: F401
    except ImportError:
        print("未安装 fontTools，请先运行：pip install fonttools")
        return
    raw = sys.argv[1] if len(sys.argv) > 1 else input("把 NotoSansSC-Regular.otf（或 .ttf）拖进本窗口，然后回车：")
    src = raw.strip().strip('"').strip("'")
    if not os.path.isfile(src):
        print("找不到字体源文件：" + src)
        return
    ext = ".otf" if src.lower().endswith(".otf") else ".ttf"
    out = os.path.join(ROOT, "fonts", "NotoSansSC-Subset" + ext)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    print("源文件: %s (%.1f MB)" % (src, os.path.getsize(src) / 1e6))
    print("裁剪: 常用汉字 + Latin-1 + 数学/箭头/圈号/几何/杂项符号 ...")
    cmd = [sys.executable, "-m", "fontTools.subset", src, "--unicodes=" + UNICODES,
           "--output-file=" + out, "--layout-features=*", "--no-hinting", "--desubroutinize"]
    r = subprocess.run(cmd)
    if r.returncode != 0:
        print("fontTools.subset 执行失败（看上方报错）")
        return
    print("完成 -> %s (%.2f MB)" % (out, os.path.getsize(out) / 1e6))
    print("接着做：重启编辑器 → 全工程扫一眼有没有还冒豆腐块的地方（真 emoji 已剥离，理论上清零）")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
    finally:
        try:
            input("\n按回车键关闭窗口...")
        except EOFError:
            pass
