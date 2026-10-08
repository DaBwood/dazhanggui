# -*- coding: utf-8 -*-
"""tools/check_font_coverage.py —— 豆腐块扫描
配合 tools/subset_font.py 使用：子集字体不含的字，在 Web 端（拿不到系统字体兜底）会显示成方框。

做法：从 subset_font.py 里读出 UNICODES 区间（唯一真值源，改了区间本脚本自动跟随），
      再扫全工程的**字符串字面量**（.gd/.tscn 先剥注释，.json 跳过 _comment），
      报出覆盖不到的字符 + 出现位置。

用法（仓库根目录）：
    python tools/check_font_coverage.py
    有输出 = 需要处理：要么把区间加进 subset_font.py 重跑子集，要么把该字符换成已覆盖的近似字符。
"""
import os, re, sys, io, json

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUBSET = os.path.join(ROOT, "tools", "subset_font.py")


def load_ranges():
    """真值源 = subset_font.py 的 UNICODES 字面量"""
    text = open(SUBSET, encoding="utf-8").read()
    m = re.search(r'UNICODES\s*=\s*\(([^)]*)\)', text, re.S)
    if not m:
        print("读不到 subset_font.py 的 UNICODES，请检查该文件"); sys.exit(2)
    codes = re.findall(r'U\+([0-9A-Fa-f]{4,6})(?:-([0-9A-Fa-f]{4,6}))?', m.group(1))
    return [(int(a, 16), int(b, 16) if b else int(a, 16)) for a, b in codes]


RANGES = load_ranges()


def covered(ch):
    c = ord(ch)
    if c < 0x80 or ch in "\n\r\t":
        return True
    return any(a <= c <= b for a, b in RANGES)


def scan_gd(path):
    """剥掉 # 注释后再取字符串字面量，避免注释里的符号误报"""
    out = []
    for i, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        code = re.sub(r"#.*$", "", line)
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', code):
            for ch in lit:
                if not covered(ch):
                    out.append((i, ch, lit.strip()[:40]))
    return out


def walk_json(node, path="", key=""):
    if key == "_comment":
        return
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk_json(v, path, str(k))
    elif isinstance(node, list):
        for v in node:
            yield from walk_json(v, path, key)
    elif isinstance(node, str):
        for ch in node:
            if not covered(ch):
                yield (ch, node.strip()[:40])


def main():
    problems = []
    files = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        if ".godot" in dirpath.split(os.sep):
            continue
        for fn in filenames:
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            if fn.endswith((".gd", ".tscn")):
                files += 1
                for line, ch, lit in scan_gd(path):
                    problems.append((rel, line, ch, lit))
            elif fn.endswith(".json"):
                files += 1
                try:
                    data = json.load(open(path, encoding="utf-8"))
                except Exception:
                    continue
                for ch, lit in walk_json(data):
                    problems.append((rel, 0, ch, lit))
    print("扫描 %d 个文件（区间来自 subset_font.py，共 %d 段）" % (files, len(RANGES)))
    print()
    if not problems:
        print("✅ 未发现子集字体覆盖不到的显示字符")
        return 0
    print("⚠ 发现 %d 处可能显示成豆腐块：" % len(problems))
    seen = set()
    for rel, line, ch, lit in problems:
        tag = (rel, ch)
        if tag in seen:
            continue
        seen.add(tag)
        where = "%s:%d" % (rel, line) if line else rel
        print("  %s  U+%04X  %s   ← %s" % (ch, ord(ch), where, lit))
    print()
    print("处理：要么把该码位区间加进 tools/subset_font.py 的 UNICODES 后重跑子集，")
    print("      要么把它换成已覆盖的近似字符（例如 ⬜ U+2B1C → □ U+25A1）。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
