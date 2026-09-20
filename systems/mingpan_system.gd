# ============================================================
# 命盘系统（批次① 2026-09-20：存档结构 + 盘/槽配置 + 解锁判定 + 进度曲线骨架）
# 设计口径：厢房设计方案 v1.0 §6；配置 data/mingpan.json（5 五行盘×10 槽/10 品质档/数值 ladder/进度曲线）
# 结构：5 盘（庚金/甲木/壬水/丙火/戊土），每盘外圈 6 槽（阳干+六地支·资质命格）+ 内圈 4 槽（神兽/方位/色/季·赚钱%四象）。
# 存档：plate_lv 命盘等级 / plate_exp 当前进度 / plates{p_id:{slots:{idx:{q,lv,heroes:{hid:val}}}}} / unlocked 已解锁盘。
# 解锁：初始 p1；其余 4 盘=命盘等级+门客数双门槛（settings.plate_unlocks，配置可调）。
# 进度：每卦+1，满 need(n)=step*n+base 则命盘等级+1（锚 19→20=440）；产出等级区间整体上移。
# 卜卦全流程（roll/对比/替换/自动卜卦）批次③实装；命格数值接 HeroData 批次④（本文件已留 get_hero_aptitude/get_hero_pct 挂点函数）。
# ============================================================
class_name MingpanSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有，随 get_save_data 落盘） ----------
var plate_lv: int = 1              # 命盘等级（产出命格等级区间 L~L+5 整体上移）
var plate_exp: int = 0             # 当前进度（每卦+1，满 need 升级）
var plates: Dictionary = {}        # {p_id: {"slots": {slot_idx: {"q","lv","heroes"{hid:val}}}}}
var unlocked: Array = ["p1"]       # 已解锁盘 id 列表

func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {"mingpan": {
		"plate_lv": plate_lv, "plate_exp": plate_exp, "plates": plates, "unlocked": unlocked,
	}}

# 从扁平存档表认领本系统字段（旧档缺 mingpan 段则按初始形状建档）
func load_save_data(s: Dictionary):
	if not s.has("mingpan") or not (s.mingpan is Dictionary):
		_init_state()
		return
	var d: Dictionary = s.mingpan
	plate_lv = maxi(1, int(d.get("plate_lv", 1)))
	plate_exp = maxi(0, int(d.get("plate_exp", 0)))
	plates = d.get("plates", {})
	if not (plates is Dictionary):
		plates = {}
	unlocked = d.get("unlocked", ["p1"])
	if not (unlocked is Array):
		unlocked = ["p1"]
	_init_state()

# 存档形状兜底 + 解锁状态按当前命盘等级/门客数重算（解锁是实例实时状态，读取式，读档即对齐）
func _init_state() -> void:
	plate_lv = maxi(1, plate_lv)
	plate_exp = maxi(0, plate_exp)
	for pid in plates.keys():
		var pd = plates[pid]
		if not (pd is Dictionary):
			plates.erase(pid)
			continue
		var slots: Dictionary = pd.get("slots", {})
		if not (slots is Dictionary):
			slots = {}
		for idx in slots.keys():
			var sd = slots[idx]
			if not (sd is Dictionary):
				slots.erase(idx)
				continue
			sd["q"] = str(sd.get("q", ""))
			sd["lv"] = maxi(1, int(sd.get("lv", 1)))
			var heroes: Dictionary = sd.get("heroes", {})
			if not (heroes is Dictionary):
				heroes = {}
			sd["heroes"] = heroes
		pd["slots"] = slots
	_refresh_unlocks()

# 按配置重算解锁盘列表（p1 恒解锁；其余=命盘等级+门客数双门槛，实时状态读取式）
func _refresh_unlocks() -> void:
	var out: Array = ["p1"]
	var unlocks: Dictionary = _cfg().get("settings", {}).get("plate_unlocks", {})
	for pid in get_plate_list():
		if str(pid) == "p1":
			continue
		var cond: Dictionary = unlocks.get(str(pid), {})
		if cond.is_empty():
			continue
		if plate_lv >= int(cond.get("plate_lv", 0)) and get_hero_count() >= int(cond.get("hero_count", 0)):
			out.append(str(pid))
	unlocked = out

func get_hero_count() -> int:
	return g.heroes.size()

# ============ 配置读取 ============
func _cfg() -> Dictionary:
	return g._mingpan_configs

func get_plate_list() -> Array:
	var out: Array = []
	for p in _cfg().get("plates", []):
		out.append(str(p.get("id", "")))
	return out

func get_plate_cfg(pid: String) -> Dictionary:
	for p in _cfg().get("plates", []):
		if str(p.get("id", "")) == pid:
			return p
	return {}

func is_unlocked_plate(pid: String) -> bool:
	return unlocked.has(pid)

# 某盘解锁条件描述（未解锁时 UI 展示用）
func get_unlock_desc(pid: String) -> String:
	var cond: Dictionary = _cfg().get("settings", {}).get("plate_unlocks", {}).get(pid, {})
	if cond.is_empty():
		return ""
	return "命盘%d级且门客%d人解锁（当前命盘%d级/门客%d人）" % [int(cond.get("plate_lv", 0)), int(cond.get("hero_count", 0)), plate_lv, get_hero_count()]

func get_plate_slots(pid: String) -> Dictionary:
	var pd = plates.get(pid, {})
	if pd is Dictionary:
		var slots: Dictionary = pd.get("slots", {})
		if slots is Dictionary:
			return slots
	return {}

# ============ 品质档 / 数值 ladder ============
func get_quality_list() -> Array:
	return _cfg().get("qualities", [])

func get_quality_cfg(qkey: String) -> Dictionary:
	for q in get_quality_list():
		if str(q.get("key", "")) == qkey:
			return q
	return {}

func get_quality_color(qkey: String) -> String:
	return str(get_quality_cfg(qkey).get("color", "#ffffff"))

# ============ 进度曲线（need(n)=step*n+base；每卦+1，满则升级） ============
func get_need(n: int) -> int:
	var p: Dictionary = _cfg().get("progress", {})
	return int(p.get("step", 20)) * n + int(p.get("base", 60))

func get_current_need() -> int:
	return get_need(plate_lv)

# 进度+n（卜卦每卦+1；升级不清零溢出——进度=exp-need 结转，多卦连抽可跨级）
func add_progress(n: int) -> int:
	plate_exp += maxi(0, n)
	var ups: int = 0
	while plate_exp >= get_current_need():
		plate_exp -= get_current_need()
		plate_lv += 1
		ups += 1
	if ups > 0:
		_refresh_unlocks()
	return ups

# ============ 命格→门客加成挂点（批次④ HeroData 读取式接入；当前无槽位时恒 0） ============
# 某门客命格资质总和（外圈槽 heroes[hid] 求和）
func get_hero_aptitude(hero_id: String) -> int:
	var total: int = 0
	for pid in plates.keys():
		for idx in get_plate_slots(str(pid)).values():
			var heroes: Dictionary = (idx as Dictionary).get("heroes", {})
			if heroes is Dictionary:
				total += int(heroes.get(hero_id, 0))
	return total

# 某门客四象赚钱%总和（内圈槽 heroes[hid] 求和；槽位内外由槽位数序号区分：idx 0~5 外圈，6~9 内圈）
func get_hero_pct(hero_id: String) -> float:
	var total: float = 0.0
	var outer_n: int = int(_cfg().get("settings", {}).get("outer_slots", 6))
	for pid in plates.keys():
		var slots: Dictionary = get_plate_slots(str(pid))
		for idx in slots.keys():
			if int(idx) < outer_n:
				continue
			var heroes: Dictionary = (slots[idx] as Dictionary).get("heroes", {})
			if heroes is Dictionary:
				total += float(heroes.get(hero_id, 0.0))
	return total
