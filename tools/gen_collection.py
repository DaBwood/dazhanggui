# -*- coding: utf-8 -*-
# ============================================================
# 藏品配置生成器：从 藏品.xlsx 生成 data/collection.json
# 用法: python tools/gen_collection.py <藏品.xlsx> [输出路径]
# 零第三方依赖（xlsx 本质是 zip+xml，用标准库直接解析）
# ============================================================
import json, re, sys, zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"

# ---------- 最小 xlsx 读取 ----------
def read_xlsx(path):
	z = zipfile.ZipFile(path)
	shared = []
	if "xl/sharedStrings.xml" in z.namelist():
		root = ET.fromstring(z.read("xl/sharedStrings.xml"))
		for si in root.findall(NS + "si"):
			shared.append("".join(t.text or "" for t in si.iter(NS + "t")))
	wb = ET.fromstring(z.read("xl/workbook.xml"))
	rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
	relmap = {rel.get("Id"): rel.get("Target") for rel in rels}
	sheets = {}
	for sh in wb.iter(NS + "sheet"):
		target = relmap[sh.get(RID)]
		if not target.startswith("xl/"):
			target = "xl/" + target
		root = ET.fromstring(z.read(target))
		rows = []
		for row in root.iter(NS + "row"):
			cells = {}
			for c in row.findall(NS + "c"):
				col = re.match(r"[A-Z]+", c.get("r")).group()
				v = c.find(NS + "v")
				is_el = c.find(NS + "is")
				if v is None:
					# 【修复】内联字符串单元格：无论 t 属性是什么，只要有 <is> 子节点就读取
					if is_el is not None:
						cells[col] = "".join(t.text or "" for t in is_el.iter(NS + "t"))
					else:
						print("  [诊断] 跳过单元格:", c.get("r"), "t=", c.get("t"))
					continue
				cells[col] = shared[int(v.text)] if c.get("t") == "s" else v.text
			rows.append(cells)
		sheets[sh.get("name")] = rows
	return sheets

# ---------- 数值解析（支持"万"） ----------
def num(s):
	s = s.strip()
	mult = 10000 if s.endswith("万") else 1
	if mult == 1:
		s = s
	else:
		s = s[:-1]
	return int(float(s) * mult)

# ---------- 门客名→id ----------
HEROES = {"李白":"li_bai","小柒":"xiao_qi","王昭君":"wang_zhaojun","花木兰":"hua_mulan",
"杨戬":"yang_jian","小舞":"xiao_wu","小八":"xiao_ba","葫芦仙人":"hu_lu_xianren",
"兰飞鸿":"lan_feihong","张起灵":"zhang_qiling","白月初":"bai_yuechu","刘昴星":"liu_maoxing",
"董小宛":"dong_xiaowan","小鱼儿":"xiao_yuer","梅长苏":"mei_changsu","昊天上帝":"haotian_shangdi",
"东皇太一":"donghuang_taiyi","蚩尤":"chiyou","后羿":"houyi","大禹":"dayu",
"寇白门":"kou_baimen","马湘兰":"ma_xianglan","卞玉京":"bian_yujing","李香君":"li_xiangjun"}
# 名字长的不放上面字典也行，单独查
LONGEST_FIRST = sorted(HEROES.keys(), key=len, reverse=True)

# 品质: 0无双 1传奇 2卓越 3优秀 4普通
QCOLS = ["A", "B", "C", "D", "E"]
QBASE = {0:50, 1:40, 2:30, 3:20, 4:10}
GENERIC_NAME = {2:"卓越藏品", 3:"优秀藏品", 4:"普通藏品"}

BASE_RE = re.compile(r"^(?:基础效果)?[:：]?\s*(.+?)(资质|赚钱|才华|友好|店员数量)每级\+([0-9.万]+)[，,]\s*每星\+([0-9.万]+)")
SP_RE = re.compile(r"(.+?)(资质|赚钱)每星\+([0-9.]+)\s*(%?)")

def parse_base(text, warns, name):
	"""基础效果 → 结构化；识别不出的降级为仅展示"""
	m = BASE_RE.match(text.strip())
	if not m:
		warns.append("[基础] %s: %s" % (name, text))
		return {"desc": text, "wired": False}
	target, stat, pl, ps = m.group(1).strip(), m.group(2), num(m.group(3)), num(m.group(4))
	base = {"desc": "%s%s每级+%s，每星+%s" % (target, stat, m.group(3), m.group(4)),
		"stat": "apt" if stat == "资质" else ("income" if stat == "赚钱" else stat),
		"per_level": pl, "per_star": ps, "wired": False}
	if stat in ("资质", "赚钱"):
		if target in HEROES:
			base["target"] = "hero"; base["hero"] = HEROES[target]; base["wired"] = True
		elif target == "五艳凤魁":
			base["target"] = "wuyan"; base["wired"] = True
		elif target == "自选门客":
			base["target"] = "pick"; base["wired"] = True
		elif target == "无双及以上门客":
			base["target"] = "quality_min"; base["min"] = 2; base["wired"] = True
		else:
			m2 = re.match(r"^([士农工商侠])类门客$", target)
			if m2 and stat == "赚钱":
				base["target"] = "category"; base["category"] = m2.group(1); base["wired"] = True
	return base

def parse_special(text, warns, name):
	"""特殊效果 → 结构化；仅接入门客资质/赚钱类，其余仅展示"""
	s = {"desc": text}
	if not text:
		return s
	# 写法一：xxx资质/赚钱每星+N（+%?）
	m = SP_RE.search(text)
	if m:
		target = re.sub(r"^(特殊效果|基础效果)?[:：]?\s*", "", m.group(1)).strip()
		stat, val, is_pct = m.group(2), float(m.group(3)), m.group(4) == "%"
		if stat == "资质" and not is_pct and target in HEROES:
			s.update({"kind": "hero_apt", "hero": HEROES[target], "per_star": int(val)}); return s
		if stat == "资质" and not is_pct and target == "五艳凤魁":
			s.update({"kind": "group_apt", "per_star": int(val)}); return s
		if stat == "资质" and not is_pct:
			m2 = re.match(r"^([士农工商侠])类门客$", target)
			if m2:
				s.update({"kind": "category_apt", "category": m2.group(1), "per_star": int(val)}); 				return s
		if is_pct and stat == "赚钱":
			if target in HEROES:
				s.update({"kind": "hero_pct", "hero": HEROES[target], "per_star": val}); return s
			if target == "五艳凤魁":
				s.update({"kind": "group_pct", "per_star": val}); return s
			if target == "自选门客":
				s.update({"kind": "pick_pct", "per_star": val}); return s
			m2 = re.match(r"^([士农工商侠])类门客$", target)
			if m2:
				s.update({"kind": "category_pct", "category": m2.group(1), "per_star": val}); return s
			if target == "无双及以上门客":
				s.update({"kind": "quality_min_pct", "min": 2, "per_star": val}); return s
		return s  # 未识别目标→仅展示
	# 写法二：xxx每星+N%（省略"赚钱"二字，如 李白每星+10% / 五艳凤魁每星+10% / 自选门客每星+10%）
	m2 = re.match(r"^(.+?)每星\+([0-9.]+)%$", text)
	if m2:
		target, val = m2.group(1).strip(), float(m2.group(2))
		if target in HEROES:
			s.update({"kind": "hero_pct", "hero": HEROES[target], "per_star": val})
		elif target == "五艳凤魁":
			s.update({"kind": "group_pct", "per_star": val})
		elif target == "自选门客":
			s.update({"kind": "pick_pct", "per_star": val})
	return s

def parse_cell(text, warns):
	"""单元格: 名字：基础效果...；特殊效果..."""
	text = text.strip().replace(":", "：")
	name, _, rest = text.partition("：")
	parts = re.split(r"[。.;；]\s*特殊效果[:：]?", rest)
	base_text = re.sub(r"^基础效果[:：]?", "", parts[0]).strip("。;； ")
	special_text = parts[1].strip("。;； ") if len(parts) > 1 else ""
	return name.strip(), parse_base(base_text, warns, name), parse_special(special_text, warns, name)

def col_letter(idx):
	# 0→A
	return chr(ord("A") + idx)

def main():
	src = sys.argv[1] if len(sys.argv) > 1 else "藏品.xlsx"
	dst = sys.argv[2] if len(sys.argv) > 2 else "data/collection.json"
	sheets = read_xlsx(src)
	warns = []
	collections = {}
	name2id = {}
	idx = 0
	# ---- Sheet1 藏品 ----
	for q in range(5):
		for row in sheets["Sheet1"]:
			cell = row.get(col_letter(q), "").strip()
			if not cell or cell == ["无双", "传奇", "卓越", "优秀", "普通"][q] or cell.startswith("说明"):
				continue
			name, base, special = parse_cell(cell, warns)
			cid = "c%03d" % idx; idx += 1
			collections[cid] = {"name": name, "quality": q, "order": idx, "base": base, "special": special}
			if name in name2id:
				warns.append("[重名] %s 出现在 %s 和 %s" % (name, name2id[name], cid))
			name2id[name] = cid
	# ---- Sheet2 套装 ----
	suits = {}
	for row in sheets["Sheet2"]:
		name = (row.get("A") or "").strip()
		if not name or name == "套装":
			continue
		members = [m.strip() for m in re.split(r"[，,]", row.get("B", "")) if m.strip()]
		members = [{"幽客": "幽谷", "青纱禅衣": "素纱禅衣", "细雨清尘": "细雨轻尘"}.get(m, m) for m in members]
		effect = (row.get("C") or "").strip()
		head = effect.split("星时")[0]
		tiers = [int(x) for x in re.findall(r"\d+", head)]
		if len(tiers) >= 2 and tiers[-1] < tiers[-2]:
			tiers[-1] = tiers[-2] + (tiers[-2] - tiers[-3] if len(tiers) > 2 else 1)  # 修 19/10→20 笔误
		suit = {"name": name, "members": members, "tiers": tiers, "effect": effect, "kind": "display", "per_tier": 1}
		m = re.search(r"五艳门客赚钱\+([0-9.]+)%", effect)
		if m:
			suit.update({"kind": "wuyan_pct", "per_tier": float(m.group(1))})
		else:
			m = re.search(r"白月初赚钱\+([0-9.]+)%", effect)
			if m:
				suit.update({"kind": "hero_pct", "hero": "bai_yuechu", "per_tier": float(m.group(1))})
			else:
				m = re.search(r"\+([0-9.]+)%", effect)
				if m:
					suit["per_tier"] = float(m.group(1))
		for m in members:
			if m not in name2id:
				warns.append("[套装成员无匹配] %s(%s)" % (name, m))
		# 【修复】成员名→藏品id（系统按id存档和匹配）
		suit["members"] = [name2id[m] if m in name2id else m for m in members]
		suits["s_" + name] = suit
	# ---- Sheet3 淘宝奖池 ----
	LIGHTS = {"萤虫光": "ying_chong_guang", "烛火光": "zhu_huo_guang", "星曜光": "xing_yao_guang",
		"月华光": "yue_hua_guang", "日轮光": "ri_lun_guang"}
	lottery = []
	for row in sheets["Sheet3"]:
		for i in range(3):
			nm = (row.get(col_letter(i * 2)) or "").strip()
			pr = (row.get(col_letter(i * 2 + 1)) or "").strip()
			if not nm or not pr or nm == "物品名称":
				continue
			weight = int(round(float(pr) * 10000))
			m = re.match(r"(.+?)碎片[＊*](\d+)$", nm)
			if m:
				cname, count = m.group(1), int(m.group(2))
				if cname == "世纪":
					cname = "史记"  # 用户确认:世纪=史记笔误
				if cname in GENERIC_NAME.values():
					lottery.append({"type": "gfrag", "quality": [k for k, v in GENERIC_NAME.items() if v == cname][0],
						"count": count, "weight": weight, "label": cname + "碎片*%d" % count})
				elif cname in name2id:
					lottery.append({"type": "frag", "collection": name2id[cname],
						"count": count, "weight": weight, "label": cname + "碎片*%d" % count})
				else:
					warns.append("[奖池无匹配] %s" % nm)
			elif nm in LIGHTS:
				lottery.append({"type": "item", "item": LIGHTS[nm], "count": 0,
					"weight": weight, "label": nm})  # count=0 → 用 settings.light_counts
			else:
				warns.append("[奖池未识别] %s" % nm)
	out = {
		"settings": {
			"max_level": 500, "max_star": 20,
			"quality_base": {str(k): v for k, v in QBASE.items()},
			"upgrade_items": ["ying_chong_guang", "zhu_huo_guang", "xing_yao_guang", "yue_hua_guang", "ri_lun_guang"],
			"synthesize_frag": 100,
			"lottery_ticket": "tao_bao_quan",
			"generic_frag_items": {"2": "frag_zhuoyue", "3": "frag_youxiu", "4": "frag_putong"},
			"wuyan_heroes": ["ma_xianglan", "li_xiangjun", "dong_xiaowan", "kou_baimen", "bian_yujing"],
			"light_counts": {"ying_chong_guang": 20, "zhu_huo_guang": 10, "xing_yao_guang": 5,
				"yue_hua_guang": 3, "ri_lun_guang": 1}
		},
		"collections": collections,
		"suits": suits,
		"lottery": lottery
	}
	with open(dst, "w", encoding="utf-8") as f:
		json.dump(out, f, ensure_ascii=False, indent=1)
	print("生成完成: %s  藏品%d件 套装%d套 奖池%d项" % (dst, len(collections), len(suits), len(lottery)))
	wired = sum(1 for c in collections.values() if c["base"].get("wired")) + \
		sum(1 for c in collections.values() if c["special"].get("kind", "display") != "display")
	print("已接入HeroData的效果条目: %d（其余为仅展示，效果后续接入）" % wired)
		# 【新增】套装锦盒：每个套装一个自选锦盒道具，打印段落粘贴进 items.json
	print("---- 套装锦盒 items.json 段落（粘进 items.json 的 \"config\" 内）----")
	for sid, suit in suits.items():
		box_id = "suitbox_" + sid[2:]
		member_names = [collections[m]["name"] if m in collections else m for m in suit["members"]]
		entry = {"name": "%s自选锦盒" % suit["name"],
			"desc": "使用后任选以下藏品碎片×1：%s" % "、".join(member_names),
			"use": {"type": "suit_frag_box", "btn": "使用", "title": "选择碎片"}}
		print('\t"%s": %s,' % (box_id, json.dumps(entry, ensure_ascii=False)))
	if warns:
		print("---- ⚠ 解析警告（对应条目已降级为仅展示，请贴给Kimi）----")
		for w in warns:
			print(w)

if __name__ == "__main__":
	main()
