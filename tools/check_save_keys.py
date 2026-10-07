# -*- coding: utf-8 -*-
"""存档字段体检：tools/check_save_keys.py
用途：本项目存档是一张扁平表（game_data.save_game() 把各系统 get_save_data() merge 到一起），
      由此有三类静默故障，本脚本做静态筛查，输出需要人工判断的三张清单：

  A. 顶层键跨系统重名  -> merge 后互相覆盖，后写的赢（真冲突，必查）
  B. 读了但没写         -> 读档永远取默认值（真 bug），或"老档迁移读取"（有意为之）
  C. 写了但没读         -> 改名残留，或只写不读的派生字段

用法：python tools/check_save_keys.py
"""
import re, os, sys, io, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = {"has", "get", "is", "size", "keys", "duplicate", "if", "and", "or", "for",
        "in", "not", "return", "true", "false", "null", "as", "print", "push_error"}


def body_of(text, header):
    m = re.search(header, text)
    if not m:
        return None
    rest = text[m.end():]
    nxt = re.search(r"(?m)^func ", rest)
    return rest[:nxt.start() if nxt else len(rest)]


def dict_literal(body):
    """取 return 后面的字典字面量，返回 (顶层键->子字典?, 命名段集合)"""
    if not body:
        return set(), set(), False
    i = body.find("{")
    if i < 0:
        return set(), set(), False
    depth, top, ns = 0, set(), set()
    j = i
    while j < len(body):
        ch = body[j]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        elif ch == '"' and depth == 1:
            m = re.match(r'"([A-Za-z_][A-Za-z0-9_]*)"\s*:\s*', body[j:])
            if m:
                key = m.group(1)
                top.add(key)
                after = body[j + m.end():].lstrip()
                if after.startswith("{"):
                    ns.add(key)
        j += 1
    return top, ns, True


writes, reads, nested_write = {}, {}, {}
files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    if ".godot" in dirpath.split(os.sep):
        continue
    for fn in filenames:
        if fn.endswith(".gd") and os.path.basename(dirpath) == "systems":
            files.append(os.path.join(dirpath, fn))

for path in sorted(files):
    fn = os.path.basename(path)
    text = open(path, encoding="utf-8", errors="replace").read()
    top, ns, _ = dict_literal(body_of(text, r"func get_save_data\(\)[^:]*:"))
    writes[fn] = top - ns                    # 顶层散键（会和其他系统同处一张表）
    nested_write[fn] = ns                    # 自带命名段（安全）
    lb = body_of(text, r"func load_save_data\([^)]*\)[^:]*:")
    r = set()
    if lb:
        pm = re.search(r"func load_save_data\(\s*([A-Za-z_][A-Za-z0-9_]*)", text)
        p = pm.group(1) if pm else "s"
        r |= set(re.findall(r'\b%s\.has\("([^"]+)"\)' % p, lb))
        r |= set(re.findall(r'\b%s\.get\("([^"]+)"' % p, lb))
        r |= set(re.findall(r'\b%s\.([A-Za-z_][A-Za-z0-9_]*)\b' % p, lb))
        r -= SKIP
    reads[fn] = r

print("扫描 %d 个系统脚本" % len(files))
print()
print("=== A. 顶层散键跨系统重名（merge 后互相覆盖，必查）===")
owner = collections.defaultdict(list)
for fn, ks in writes.items():
    for k in ks:
        owner[k].append(fn)
dups = {k: v for k, v in owner.items() if len(v) > 1}
for k, v in sorted(dups.items()):
    print("  %-26s <- %s" % (k, ", ".join(sorted(v))))
if not dups:
    print("  无冲突。")

print()
print("=== 命名段 vs 顶层散键（两代存档口径并存情况）===")
seg = sorted(fn for fn in nested_write if nested_write[fn])
flat = sorted(fn for fn in writes if writes[fn] and not nested_write[fn])
both = sorted(fn for fn in nested_write if nested_write[fn] and writes[fn])
print("  自带命名段（安全）: %s" % ", ".join(seg))
print("  纯顶层散键（同处一张表）: %s" % ", ".join(flat))
print("  两者混用: %s" % (", ".join(both) if both else "无"))

print()
print("=== B. 读了但没写（读档取默认值；也可能是老档迁移，需人工判断）===")
for fn in sorted(reads):
    miss = sorted(reads[fn] - writes[fn] - nested_write[fn])
    if miss:
        print("  %-26s %s" % (fn, ", ".join(miss)))

print()
print("=== C. 写了顶层散键但没读（改名残留或只写不读）===")
for fn in sorted(writes):
    if not writes[fn]:
        continue
    miss = sorted(writes[fn] - reads[fn])
    if miss:
        print("  %-26s %s" % (fn, ", ".join(miss)))
print()
print("提示：B 类先排除『老存档兼容读取』（如 beast_system 的 beast_fruit/aroma_fruit 是有意的旧档迁移）。")
