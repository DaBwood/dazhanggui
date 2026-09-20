# ============================================================
# 命盘系统（批次① 2026-09-20：存档结构 + 盘/槽配置 + 解锁判定 + 进度曲线骨架）
# 设计口径：厢房设计方案 v1.0 §6；配置 data/mingpan.json（5 五行盘×10 槽/10 品质档/数值 ladder/进度曲线）
# 结构：5 盘（庚金/甲木/壬水/丙火/戊土），每盘外圈 6 槽（阳干+六地支·资质命格）+ 内圈 4 槽（神兽/方位/色/季·赚钱%四象）。
# 存档：plate_lv 命盘等级 / plate_exp 当前进度 / plates{p_id:{slots:{idx:{q,lv,heroes:{hid:val}}}}} / unlocked 已解锁盘。
# 解锁：初始 p1；其余 4 盘=命盘等级+门客数双门槛（settings.plate_unlocks，配置可调）。
# 进度：每卦+1，满 need(n)=step*n+base 则命盘等级+1（锚 19→20=440）；产出等级区间整体上移。
# 卜卦全流程（roll/对比/替换/自动卜卦）批次③已实装；命格数值接 HeroData 批次④（挂点=get_hero_aptitude/get_hero_pct/get_hero_totals）。
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
		var norm_slots: Dictionary = {}
		for idx in slots.keys():
			var sd = slots[idx]
			if not (sd is Dictionary):
				continue
			sd["q"] = str(sd.get("q", ""))
			sd["lv"] = maxi(1, int(sd.get("lv", 1)))
			var heroes: Dictionary = sd.get("heroes", {})
			if not (heroes is Dictionary):
				heroes = {}
			sd["heroes"] = heroes
			norm_slots[str(int(idx))] = sd
		pd["slots"] = norm_slots
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

# ============ 卜卦（批次③ 2026-09-20；设计口径 §6.2/6.3/6.4/6.5/6.6） ============
# 流程：消耗 1 风水符 → 品质=风水等级 10 档权重（走 xiangfang_system.roll_quality_key，风水唯一效果）
#       → 槽位=全部已解锁盘随机一盘随机 1/10 槽（五盘同步养成，用户拍板）
#       → 等级=命盘等级 L 的 L~L+5 六档倾斜分布 → 绑定 3 个随机已拥有门客（不足 3 个则全绑），各独立 0.9~1.1 随机
# 对比/替换：外圈=资质、内圈=赚钱%，同槽同量纲比总值；胜者装槽败者消失；无论取舍进度+1。
func get_talisman_item() -> String:
	return str(_cfg().get("settings", {}).get("talisman_item", "fengshui_fu"))

func get_talisman_count() -> int:
	return int(g.items.get(get_talisman_item(), 0))

func get_divine_cost() -> int:
	return int(_cfg().get("settings", {}).get("talisman_cost", 1))

func can_divine() -> bool:
	return get_talisman_count() >= get_divine_cost()

# 消耗风水符（成功 true）
func _spend_talisman() -> bool:
	if not can_divine():
		return false
	g.items[get_talisman_item()] = get_talisman_count() - get_divine_cost()
	return true

# 等级偏移 k（0~5 → 命格等级 L+k）六档权重：w_k=max(0, base_k+tilt*(L-anchor)*(k-2.5))，归一化累积 roll
func roll_level_offset() -> int:
	var dist: Dictionary = _cfg().get("level_dist", {})
	var base: Array = dist.get("base", [1.0])
	var tilt: float = float(dist.get("tilt", 0.0))
	var anchor_l: float = float(dist.get("anchor", 19))
	var weights: Array = []
	var sum: float = 0.0
	for k in range(base.size()):
		var w: float = maxf(0.0, float(base[k]) + tilt * (plate_lv - anchor_l) * (k - 2.5))
		weights.append(w)
		sum += w
	if sum <= 0.0:
		return 0
	var roll: float = randf() * sum
	var acc: float = 0.0
	for k in range(weights.size()):
		acc += float(weights[k])
		if roll <= acc:
			return k
	return weights.size() - 1

# 随机 3 个已拥有门客（不足 3 个全绑）
func _roll_hero_ids() -> Array:
	var ids: Array = g.heroes.keys()
	ids.shuffle()
	var n: int = mini(int(_cfg().get("settings", {}).get("bind_heroes", 3)), ids.size())
	return ids.slice(0, n)

# 单门客数值：外圈=round(资质系数×命格等级×rand)；内圈=赚钱%系数×命格等级×rand
func _roll_value(qkey: String, luck_lv: int, is_outer: bool) -> float:
	var q: Dictionary = get_quality_cfg(qkey)
	var coef: float = float(q.get("apt_coef" if is_outer else "pct_coef", 0.0))
	var r: float = randf_range(
		float(_cfg().get("settings", {}).get("rand_min", 0.9)),
		float(_cfg().get("settings", {}).get("rand_max", 1.1)))
	if is_outer:
		return float(int(round(coef * luck_lv * r)))
	return snappedf(coef * luck_lv * r, 0.0001)

# 产出一个命格（不消耗不算进度；divine/auto_divine 用）
func roll_luck() -> Dictionary:
	var pool: Array = unlocked.duplicate()
	var pid: String = str(pool[randi() % pool.size()])
	var outer_n: int = int(_cfg().get("settings", {}).get("outer_slots", 6))
	var slot: int = randi() % (outer_n + int(_cfg().get("settings", {}).get("inner_slots", 4)))
	var qkey: String = g.xiangfang_system.roll_quality_key(g.xiangfang_system.get_fengshui_level())
	var luck_lv: int = plate_lv + roll_level_offset()
	var is_outer: bool = slot < outer_n
	var heroes: Dictionary = {}
	for hid in _roll_hero_ids():
		heroes[str(hid)] = _roll_value(qkey, luck_lv, is_outer)
	return {"plate": pid, "slot": slot, "q": qkey, "lv": luck_lv, "outer": is_outer, "heroes": heroes}

# 命格原始数值和（展示用：外圈=资质和，内圈=赚钱%和；对比请用 luck_money_impact）
func luck_value(luck: Dictionary) -> float:
	var total: float = 0.0
	for v in luck.get("heroes", {}).values():
		total += float(v)
	return total

# 命格真实赚速增量（对比/自动替换基准，用户拍板：面上数值不可比，门客有强弱）。
# 口径=真实重算：临时装上新命格 → 逐门客读 HeroData.get_income（全链含截断/跨门客权重）→ 还原旧命格。
# 返回"装上此命格后总赚速变化量"（替换判据：>0 才更好；空槽必为正）。
func luck_money_impact(luck: Dictionary) -> float:
	var pid: String = str(luck.get("plate", ""))
	var slot: int = int(luck.get("slot", 0))
	var old: Dictionary = get_slot_luck(pid, slot)
	var touched: Array = (luck.get("heroes", {}) as Dictionary).keys().duplicate()
	for hid in (old.get("heroes", {}) as Dictionary).keys():
		var hs: String = str(hid)
		if not touched.has(hs):
			touched.append(hs)
	if touched.is_empty():
		return 0.0
	var before: Dictionary = {}
	for hid in touched:
		before[str(hid)] = HeroData.get_income(g, str(hid))
	install_luck(luck)
	var total: float = 0.0
	for hid in touched:
		total += HeroData.get_income(g, str(hid)) - float(before[str(hid)])
	# 还原旧命格（临时换装只用于测算，不落状态）
	if old.is_empty():
		if plates.has(pid) and plates[pid] is Dictionary:
			(plates[pid]["slots"] as Dictionary).erase(str(slot))
	else:
		if not plates.has(pid) or not (plates[pid] is Dictionary):
			plates[pid] = {"slots": {}}
		plates[pid]["slots"][str(slot)] = old.duplicate(true)
	return total

# 目标槽原命格（无则空字典）。槽位键统一字符串：JSON 落盘后 int 键会变 string，兼容双查（丢档假象修复）
func get_slot_luck(pid: String, slot: int) -> Dictionary:
	var slots: Dictionary = get_plate_slots(pid)
	var sd = slots.get(slot, null)
	if sd == null:
		sd = slots.get(str(slot), {})
	return sd if sd is Dictionary else {}

# 卜卦一卦：扣符+roll+进度+1；返回新命格（不自动装槽，由玩家二选一）
func divine() -> Dictionary:
	if not _spend_talisman():
		return {"ok": false, "reason": "风水符不足（需%d）" % get_divine_cost()}
	var luck: Dictionary = roll_luck()
	var ups: int = add_progress(1)
	return {"ok": true, "luck": luck, "ups": ups}

# 装槽（胜者装、败者消失=不存任何仓库）
func install_luck(luck: Dictionary) -> void:
	var pid: String = str(luck.get("plate", ""))
	if not is_unlocked_plate(pid):
		return
	if not plates.has(pid) or not (plates[pid] is Dictionary):
		plates[pid] = {"slots": {}}
	plates[pid]["slots"][str(int(luck.get("slot", 0)))] = {   # 键用字符串，与 JSON 落盘形态一致
		"q": str(luck.get("q", "")), "lv": int(luck.get("lv", 1)),
		"heroes": (luck.get("heroes", {}) as Dictionary).duplicate(),
	}

# 自动卜卦：连抽直到符尽或达上限；新命格总值更高才自动替换。返回汇总
func auto_divine(max_rolls: int) -> Dictionary:
	var rolls: int = 0
	var replaced: int = 0
	var ups: int = 0
	while rolls < max_rolls and can_divine():
		var r: Dictionary = divine()
		if not r.get("ok", false):
			break
		rolls += 1
		ups += int(r.get("ups", 0))
		var luck: Dictionary = r.get("luck", {})
		if luck_money_impact(luck) > 0.0:   # 真实赚速增量为正才自动替换
			install_luck(luck)
			replaced += 1
	return {"rolls": rolls, "replaced": replaced, "ups": ups}

# ============ 展示辅助：等级分布表 / 加成总览 ============
# 命盘等级 L 的六档等级分布百分比（0~5 偏移）
func get_level_dist(lvl: int) -> Array:
	var dist: Dictionary = _cfg().get("level_dist", {})
	var base: Array = dist.get("base", [1.0])
	var tilt: float = float(dist.get("tilt", 0.0))
	var anchor_l: float = float(dist.get("anchor", 19))
	var weights: Array = []
	var sum: float = 0.0
	for k in range(base.size()):
		var w: float = maxf(0.0, float(base[k]) + tilt * (lvl - anchor_l) * (k - 2.5))
		weights.append(w)
		sum += w
	if sum <= 0.0:
		return weights
	for i in range(weights.size()):
		weights[i] = float(weights[i]) / sum
	return weights

# 加成总览：聚合全部已解锁盘槽位 → {hid: {apt, pct}}（批次③ 展示用；批次④ HeroData 读取式接同一数据源）
func get_hero_totals() -> Dictionary:
	var out: Dictionary = {}
	var outer_n: int = int(_cfg().get("settings", {}).get("outer_slots", 6))
	for pid in plates.keys():
		var slots: Dictionary = get_plate_slots(str(pid))
		for idx in slots.keys():
			var sd: Dictionary = slots[idx]
			if not (sd is Dictionary):
				continue
			var heroes: Dictionary = sd.get("heroes", {})
			if not (heroes is Dictionary):
				continue
			var key: String = "apt" if int(idx) < outer_n else "pct"
			for hid in heroes.keys():
				if not out.has(hid):
					out[hid] = {"apt": 0.0, "pct": 0.0}
				out[hid][key] = float(out[hid][key]) + float(heroes[hid])
	return out

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
