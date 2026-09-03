class_name CuzhiSystem extends RefCounted
# 【促织系统】促织园核心逻辑：捕捉、军衔、促织庙、保底自选、虫师

var g  # GameData 中枢引用

var _cfg: Dictionary
var _crickets_by_id: Dictionary
var _crickets_by_quality: Dictionary

func _init(game_data):
	g = game_data
	_cfg = g._load_json("res://data/cuzhi.json")
	_build_lookup()

func _build_lookup():
	_crickets_by_id.clear()
	_crickets_by_quality.clear()
	for q in range(1, 7):
		_crickets_by_quality[q] = []
	for c in _cfg.crickets:
		_crickets_by_id[c.id] = c
		var q = int(c.quality)
		_crickets_by_quality[q].append(c)

# ========== 存档接口 ==========
func get_save_data() -> Dictionary:
	return {
		"caught": g.cuzhi_caught,
		"fate": g.cuzhi_fate,
		"temple": g.cuzhi_temple,
		"spent": g.cuzhi_spent,
		"worm_masters": g.cuzhi_worm_masters,
		"jars": g.cuzhi_jars,
		"unlocked_jars": g.cuzhi_unlocked_jars,
		"equipped": g.cuzhi_equipped,       # 【新增】装备映射
		"equip_levels": g.cuzhi_equip_levels, # 【新增】装备等级
	}


func load_save_data(d: Dictionary):
	if d.has("caught"):
		g.cuzhi_caught = d.caught
	if d.has("fate"):
		g.cuzhi_fate = d.fate
	if d.has("temple"):
		g.cuzhi_temple = d.temple
	if d.has("spent"):
		g.cuzhi_spent = d.spent
	if d.has("worm_masters"):
		g.cuzhi_worm_masters = d.worm_masters
	if d.has("jars"):
		g.cuzhi_jars = d.jars
	else:
		# 初始化空罐（4个）
		g.cuzhi_jars = []
	while g.cuzhi_jars.size() < 4:
		g.cuzhi_jars.append({"cid": "", "part": "", "start_time": 0, "duration_sec": 0})
	if d.has("unlocked_jars"):
		g.cuzhi_unlocked_jars = d.unlocked_jars
	else:
		g.cuzhi_unlocked_jars = 2
	if d.has("equipped"):                   # 【新增】加载装备映射
		g.cuzhi_equipped = d.equipped
	if d.has("equip_levels"):               # 【新增】加载装备等级
		g.cuzhi_equip_levels = d.equip_levels
	# 旧档兼容
	for cid in g.cuzhi_caught.keys():
		_ensure_cricket_dev(cid)

# ========== 军衔系统 ==========
func get_cricket_max_level(quality: int) -> int:
	var info = _cfg.rank_init.get(str(quality), {"rank": 0, "max_rank": 11})
	return int(info.max_rank) * 9 + 8

func get_cricket_init_level(quality: int) -> int:
	var info = _cfg.rank_init.get(str(quality), {"rank": 0, "max_rank": 11})
	return int(info.rank) * 9


func get_levelup_cost(level: int, quality: int) -> int:
	var init_lv = get_cricket_init_level(quality)
	var offset = level - init_lv
	match quality:
		5, 6: return 1
		4: return 1 + floori(offset / 9.0)
		3: return 1 + floori(offset / 5.0)
		2: return 1 + floori(offset / 3.0)
		1: return 1 + floori(offset / 2.0)
		_: return 1


func get_cricket_rank_info(level: int) -> Dictionary:
	var ranks = _cfg.get("ranks", [])
	var idx = floori(level / 9.0)
	var pin = (level % 9) + 1
	var name = ranks[idx] if idx < ranks.size() else "未知"
	return {"rank_name": name, "pin": pin, "full_name": "%s%d品" % [name, pin]}

# ========== 统一获得促织（所有渠道走这里）==========
func _on_cricket_acquired(cid: String) -> Dictionary:
	var cdata = _crickets_by_id.get(cid)
	if cdata == null:
		return {"ok": false}
	var q = int(cdata.quality)
	var is_new = not g.cuzhi_caught.has(cid)
	if is_new:
		var init_lv = get_cricket_init_level(q)
		var max_lv = get_cricket_max_level(q)
		g.cuzhi_caught[cid] = {"level": init_lv, "exp": 0, "max_level": max_lv}
	else:
		_add_exp(cid, _cfg.levelup.exp_per_dup)

	# 给缘分（无双及以上）
	if q >= 5:
		var career = cdata.career
		if not g.cuzhi_fate.has(career):
			g.cuzhi_fate[career] = 0
		g.cuzhi_fate[career] += _cfg.fate_per_catch

	# 【新增】给心得（所有品质）
	var exp_reward = _cfg.get("catch_exp_reward", {}).get(str(q), 0)
	if q >= 5:
		g.items["cuzhi_exp_high"] = g.items.get("cuzhi_exp_high", 0) + exp_reward
	else:
		g.items["cuzhi_exp_low"] = g.items.get("cuzhi_exp_low", 0) + exp_reward
	return {"ok": true, "is_new": is_new, "cricket": cdata, "quality": q}

# ========== 虫师系统（门客级别，多技能）==========

# 【查】某门客当前所有虫师技能
func get_hero_worm_skills(hero_id: String) -> Array:
	var master = g.cuzhi_worm_masters.get(hero_id, {})
	return master.get("skills", [])

# 【查】某技能当前加成
func get_worm_skill_bonus(hero_id: String, skill_idx: int):
	var master = g.cuzhi_worm_masters.get(hero_id)
	if master == null: return 0
	var skills = master.skills
	if skill_idx >= skills.size(): return 0
	var skill = skills[skill_idx]
	if skill.level <= 0: return 0
	var cfg = _cfg.get("worm_book", {}).get("qualities", {}).get(str(int(skill.star)), {})
	var bonuses = cfg.get("bonus", [0])
	if bonuses.is_empty(): return 0
	var total = 0
	for i in range(int(skill.level)):
		var idx = i % bonuses.size()
		total += bonuses[idx]
	return total

# 【查】某技能下次升级消耗
func get_worm_skill_upgrade_cost(hero_id: String, skill_idx: int) -> int:
	var master = g.cuzhi_worm_masters.get(hero_id)
	if master == null: return 0
	var skills = master.skills
	if skill_idx >= skills.size(): return 0
	var skill = skills[skill_idx]
	var cfg = _cfg.get("worm_book", {}).get("qualities", {}).get(str(int(skill.star)), {})
	var costs = cfg.get("cost", [])
	if costs.is_empty(): return 0
	var cost_idx = int(skill.level) % costs.size()
	return costs[cost_idx]

# 【查】某技能升级所需的促织军衔阶别索引
# 规则：每升10级需要一个更高阶别
# Lv.1~10 需小卒(0), Lv.11~20 需副尉(1), Lv.21~30 需校尉(2)...
func get_worm_skill_required_rank(skill_level: int) -> int:
	# 目标等级 = 当前等级 + 1
	var target_level = skill_level + 1
	# 所需阶别索引 = floor((目标等级 - 1) / 10)
	return floori((target_level - 1) / 10.0)

# 【查】促织某品质的初始军衔阶别索引
func get_cricket_init_rank(quality: int) -> int:
	var info = _cfg.rank_init.get(str(quality), {"rank": 0, "max_rank": 11})
	return int(info.rank)

# 【查】某促织当前的军衔阶别索引
func get_cricket_rank_index(level: int) -> int:
	return floori(level / 9.0)

# 【查】能否升级某技能（增加军衔阶别检查，考虑初始阶别差异）
func can_upgrade_worm_skill(hero_id: String, skill_idx: int) -> bool:
	var cost = get_worm_skill_upgrade_cost(hero_id, skill_idx)
	if cost <= 0: return false
	var master = g.cuzhi_worm_masters.get(hero_id)
	if master == null: return false
	var skill = master.skills[skill_idx]
	
	# 【新增】检查促织军衔阶别是否满足下一级要求（考虑不同品质初始阶别差异）
	var cid = skill.cricket_id
	var cdata = _crickets_by_id.get(cid)
	if cdata == null: return false
	var q = int(cdata.quality)
	var init_rank = get_cricket_init_rank(q)           # 该促织的初始阶别
	var cricket_level = get_cricket_level(cid)         # 促织当前等级
	var current_rank = get_cricket_rank_index(cricket_level)  # 促织当前绝对阶别
	var required_offset = get_worm_skill_required_rank(int(skill.level))  # 技能需要的相对提升阶数
	var required_absolute = init_rank + required_offset  # 技能需要的绝对阶别
	if current_rank < required_absolute:
		return false
	
	# 【修复】int(skill.star) 防御 float 问题
	var item_id = "cuzhi_exp_high" if int(skill.star) >= 5 else "cuzhi_exp_low"
	return g.items.get(item_id, 0) >= cost

# 【升】升级某技能
func upgrade_worm_skill(hero_id: String, skill_idx: int) -> bool:
	if not can_upgrade_worm_skill(hero_id, skill_idx): return false
	var cost = get_worm_skill_upgrade_cost(hero_id, skill_idx)
	var master = g.cuzhi_worm_masters[hero_id]
	var skill = master.skills[skill_idx]
	var item_id = "cuzhi_exp_high" if int(skill.star) >= 5 else "cuzhi_exp_low"
	g.items[item_id] = g.items.get(item_id, 0) - cost
	skill.level = int(skill.level) + 1
	return true
# ========== 虫师系统（门客级别，多技能）==========
# 【内】同步某门客的技能列表（把新获得的同职业促织加进来）
func _sync_worm_skills(hero_id: String):
	var hero = g.heroes.get(hero_id)
	if hero == null: return
	var hero_career = hero.get("category", "")
	
	if not g.cuzhi_worm_masters.has(hero_id):
		g.cuzhi_worm_masters[hero_id] = {"skills": []}
	
	var master = g.cuzhi_worm_masters[hero_id]
	var existing_ids = []
	for s in master.skills:
		existing_ids.append(s.cricket_id)
	
	for cid in g.cuzhi_caught.keys():
		var cdata = _crickets_by_id.get(cid)
		if cdata == null: continue
		if cdata.career != hero_career: continue
		if cid in existing_ids: continue
		var q = int(cdata.quality)
		var star = int(_cfg.get("worm_book", {}).get("qualities", {}).get(str(q), {}).get("star", 1))
		master.skills.append({"cricket_id": cid, "level": 0, "star": star})

func _add_exp(cid: String, amount: int):
	var caught = g.cuzhi_caught[cid]
	var cdata = _crickets_by_id.get(cid)
	if cdata == null:
		return
	var q = int(cdata.quality)
	if not caught.has("max_level"):
		caught.max_level = get_cricket_max_level(q)

	caught.exp += amount
	var needed = get_levelup_cost(caught.level, q)
	while caught.level < caught.max_level and caught.exp >= needed:
		caught.exp -= needed
		caught.level += 1
		needed = get_levelup_cost(caught.level, q)

# ========== 捕捉 ==========
func can_catch() -> bool:
	return g.items.get("cuzhi_cage", 0) > 0

func catch_one() -> Dictionary:
	g.items["cuzhi_cage"] = g.items.get("cuzhi_cage", 0) - 1
	g.cuzhi_spent += 1
	var q = _roll_quality()
	var pool = _crickets_by_quality[q]
	var c = pool[randi() % pool.size()]
	var result = _on_cricket_acquired(c.id)
	return {
		"cricket": result.cricket,
		"is_new": result.is_new,
		"quality": result.quality,
		"guarantee_ready": g.cuzhi_spent >= _cfg.guarantee.count,
	}

func _roll_quality() -> int:
	var total = 0
	for q in _cfg.catch_weights.keys():
		total += int(_cfg.catch_weights[q])
	var roll = randi() % total
	var cum = 0
	for q in _cfg.catch_weights.keys():
		cum += int(_cfg.catch_weights[q])
		if roll < cum:
			return int(q)
	return 1

func get_cricket_level(cid: String) -> int:
	if not g.cuzhi_caught.has(cid):
		return 0
	return g.cuzhi_caught[cid].level

func get_cricket_exp(cid: String) -> int:
	if not g.cuzhi_caught.has(cid):
		return 0
	return g.cuzhi_caught[cid].exp

# ========== 促织庙 ==========
func get_temple_level(hero_id: String) -> int:
	if not g.cuzhi_temple.has(hero_id):
		return 0
	return g.cuzhi_temple[hero_id]

func get_temple_cost(hero_id: String) -> int:
	var lv = get_temple_level(hero_id)
	return _cfg.temple.base_cost + lv * _cfg.temple.cost_increment

func get_temple_bonus(hero_id: String) -> float:
	var lv = get_temple_level(hero_id)
	return lv * _cfg.temple.bonus_per_level

func can_upgrade_temple(hero_id: String, career: String) -> bool:
	var lv = get_temple_level(hero_id)
	if lv >= _cfg.temple.max_level:
		return false
	var cost = get_temple_cost(hero_id)
	return g.cuzhi_fate.get(career, 0) >= cost

func upgrade_temple(hero_id: String, career: String) -> bool:
	if not can_upgrade_temple(hero_id, career):
		return false
	var cost = get_temple_cost(hero_id)
	g.cuzhi_fate[career] -= cost
	if not g.cuzhi_temple.has(hero_id):
		g.cuzhi_temple[hero_id] = 0
	g.cuzhi_temple[hero_id] += 1
	return true

# ========== 保底自选 ==========
func get_guarantee_progress() -> int:
	return g.cuzhi_spent

func get_guarantee_target() -> int:
	return _cfg.guarantee.count

func claim_guarantee(cid: String) -> bool:
	if g.cuzhi_spent < _cfg.guarantee.count:
		return false
	var cdata = _crickets_by_id.get(cid)
	if cdata == null or int(cdata.quality) > _cfg.guarantee.pool_quality_max:
		return false
	g.cuzhi_spent -= _cfg.guarantee.count
	var result = _on_cricket_acquired(cid)
	return result.ok



# ========== 查询接口 ==========
func get_caught_list() -> Array:
	var result = []
	for cid in g.cuzhi_caught.keys():
		var c = _crickets_by_id.get(cid)
		if c:
			result.append({
				"id": cid,
				"data": c,
				"level": g.cuzhi_caught[cid].level,
				"exp": g.cuzhi_caught[cid].exp,
				"max_level": g.cuzhi_caught[cid].get("max_level", get_cricket_max_level(int(c.quality))),
			})
	result.sort_custom(func(a, b): return b.data.quality < a.data.quality)
	return result

func get_career_fate(career: String) -> int:
	return g.cuzhi_fate.get(career, 0)

func get_all_crickets() -> Array:
	return _cfg.crickets.duplicate()

func get_catchable_crickets() -> Array:
	var result = []
	for c in _cfg.crickets:
		if c.quality <= 5:
			result.append(c)
	return result

func get_quality_name(q: int) -> String:
	return _cfg.quality_names.get(str(q), "未知")

func get_quality_color(q: int) -> String:
	return _cfg.quality_colors.get(str(q), "#ffffff")

func get_total_crickets() -> int:
	return _cfg.crickets.size()

func get_caught_count() -> int:
	return g.cuzhi_caught.size()

# ============================================================
# 【促织培育 + 蜕壳 + 促织罐】
# ============================================================

# ---------- 系列查询 ----------
func get_cricket_series(cid: String) -> String:
	var cdata = _crickets_by_id.get(cid)
	if cdata == null:
		return ""
	var cname = cdata.get("name", "")
	var series_map = _cfg.get("series", {})
	for s_name in series_map.keys():
		if cname in series_map[s_name]:
			return s_name
	return ""

# ---------- 培育解锁检查 ----------
func is_peiyu_unlocked() -> bool:
	# 需要任意促织达到八品·上尉（rank_index >= 3，即 level >= 27）
	for cid in g.cuzhi_caught.keys():
		if get_cricket_rank_index(g.cuzhi_caught[cid].level) >= 3:
			return true
	return false

func can_peiyu(cid: String) -> bool:
	if not g.cuzhi_caught.has(cid):
		return false
	var cdata = _crickets_by_id.get(cid)
	if cdata == null:
		return false
	if int(cdata.quality) != 6:
		return false
	if not is_peiyu_unlocked():
		return false
	# 【新增】只有属于系列的促织才能培育（五行/三国/江湖/山海/五灵）
	if get_cricket_series(cid) == "":
		return false
	return true

# ---------- 促织数据扩展（旧档兼容） ----------
func _ensure_cricket_dev(cid: String):
	var caught = g.cuzhi_caught[cid]
	if not caught.has("phase"):
		caught.phase = 0
	if not caught.has("parts"):
		caught.parts = {"head": 0, "jaw": 0, "wing": 0}

# ---------- 阶段与部位查询 ----------
func get_phase_cfg(phase_idx: int) -> Dictionary:
	var phases = _cfg.get("phases", [])
	if phase_idx >= 0 and phase_idx < phases.size():
		return phases[phase_idx]
	return {}

func get_phase_name(phase_idx: int) -> String:
	var cfg = get_phase_cfg(phase_idx)
	return cfg.get("name", "未知")

func get_current_phase(cid: String) -> int:
	_ensure_cricket_dev(cid)
	return g.cuzhi_caught[cid].get("phase", 0)

func get_part_level(cid: String, part: String) -> int:
	_ensure_cricket_dev(cid)
	return g.cuzhi_caught[cid].parts.get(part, 0)

func get_part_max_level(cid: String) -> int:
	var phase = get_current_phase(cid)
	var cfg = get_phase_cfg(phase)
	return cfg.get("max_level", 0)

func get_total_part_levels(cid: String) -> int:
	_ensure_cricket_dev(cid)
	var parts = g.cuzhi_caught[cid].parts
	return parts.get("head", 0) + parts.get("jaw", 0) + parts.get("wing", 0)

# ---------- 促织罐管理 ----------
func get_jar_count() -> int:
	return g.cuzhi_unlocked_jars

func get_max_jar_count() -> int:
	return _cfg.get("jar_unlock", {}).get("max", 4)

func get_used_jars() -> Array:
	var used = []
	for jar in g.cuzhi_jars:
		if jar.get("cid", "") != "":
			used.append(jar)
	return used

func get_free_jar_count() -> int:
	return get_jar_count() - get_used_jars().size()

func is_any_jar_free() -> bool:
	return get_free_jar_count() > 0

func is_cricket_busy(cid: String) -> bool:
	for jar in g.cuzhi_jars:
		if jar.get("cid", "") == cid:
			return true
	return false

func get_jar_by_cid_part(cid: String, part: String) -> Dictionary:
	for jar in g.cuzhi_jars:
		if jar.get("cid", "") == cid and jar.get("part", "") == part:
			return jar
	return {}

func _check_jar_unlock():
	var total_lv = 0
	for cid in g.cuzhi_caught.keys():
		var cdata = _crickets_by_id.get(cid)
		if cdata == null:
			continue
		if int(cdata.quality) != 6:
			continue
		total_lv += get_total_part_levels(cid)
	var per = _cfg.get("jar_unlock", {}).get("per_levels", 45)
	var initial = _cfg.get("jar_unlock", {}).get("initial", 2)
	var max_jars = _cfg.get("jar_unlock", {}).get("max", 4)
	var unlocked = initial + floori(total_lv / float(per))
	if unlocked > max_jars:
		unlocked = max_jars
	if unlocked > g.cuzhi_unlocked_jars:
		g.cuzhi_unlocked_jars = unlocked

# ---------- 培育倒计时 ----------
func get_remaining_seconds(jar: Dictionary) -> int:
	if jar.get("cid", "") == "":
		return 0
	var elapsed = Time.get_unix_time_from_system() - jar.get("start_time", 0)
	var remain = int(jar.get("duration_sec", 0) - elapsed)
	return maxi(remain, 0)

func is_jar_finished(jar: Dictionary) -> bool:
	return get_remaining_seconds(jar) <= 0

func _finish_jar(jar: Dictionary) -> bool:
	var cid = jar.get("cid", "")
	var part = jar.get("part", "")
	if cid == "" or part == "":
		return false
	if not g.cuzhi_caught.has(cid):
		return false
	_ensure_cricket_dev(cid)
	var caught = g.cuzhi_caught[cid]
	caught.parts[part] = caught.parts.get(part, 0) + 1
	jar.cid = ""
	jar.part = ""
	jar.start_time = 0
	jar.duration_sec = 0
	_check_jar_unlock()
	return true

func tick_jars():
	for jar in g.cuzhi_jars:
		if jar.get("cid", "") != "" and is_jar_finished(jar):
			_finish_jar(jar)

# ---------- 开始培育 ----------
func can_start_peiyu(cid: String, part: String) -> bool:
	if not can_peiyu(cid):
		return false
	var max_lv = get_part_max_level(cid)
	var cur_lv = get_part_level(cid, part)
	if cur_lv >= max_lv:
		return false
	if not is_any_jar_free():
		return false
	if is_cricket_busy(cid):
		return false
	return true

func start_peiyu(cid: String, part: String) -> bool:
	if not can_start_peiyu(cid, part):
		return false
	var phase = get_current_phase(cid)
	var cfg = get_phase_cfg(phase)
	var hours = cfg.get("time_hours", 24)
	var duration_sec = int(hours * 3600)
	for jar in g.cuzhi_jars:
		if jar.get("cid", "") == "":
			jar.cid = cid
			jar.part = part
			jar.start_time = Time.get_unix_time_from_system()
			jar.duration_sec = duration_sec
			return true
	return false

# ---------- 加速培育 ----------
func can_speedup(jar: Dictionary, count: int) -> bool:
	if jar.get("cid", "") == "":
		return false
	return g.items.get("cuzhi_migao", 0) >= count

func speedup(jar: Dictionary, count: int) -> bool:
	if not can_speedup(jar, count):
		return false
	g.items["cuzhi_migao"] = g.items.get("cuzhi_migao", 0) - count
	jar.duration_sec = maxi(jar.get("duration_sec", 0) - count * 600, 0)
	if is_jar_finished(jar):
		_finish_jar(jar)
	return true

# ---------- 蜕壳 ----------
func can_molt(cid: String) -> bool:
	if not can_peiyu(cid):
		return false
	var phase = get_current_phase(cid)
	var phases = _cfg.get("phases", [])
	if phase >= phases.size() - 1:
		return false
	var max_lv = get_part_max_level(cid)
	for part in ["head", "jaw", "wing"]:
		if get_part_level(cid, part) < max_lv:
			return false
	var series = get_cricket_series(cid)
	if series == "":
		return false
	var item_id = _cfg.get("molt_items", {}).get(series, "")
	return g.items.get(item_id, 0) > 0

func do_molt(cid: String) -> bool:
	if not can_molt(cid):
		return false
	var series = get_cricket_series(cid)
	var item_id = _cfg.get("molt_items", {}).get(series, "")
	g.items[item_id] = g.items.get(item_id, 0) - 1
	var caught = g.cuzhi_caught[cid]
	caught.phase = caught.get("phase", 0) + 1
	return true

# ---------- 加成计算（供 HeroData 调用） ----------
func get_career_peiyu_percent(career: String) -> float:
	var total = 0.0
	for cid in g.cuzhi_caught.keys():
		var cdata = _crickets_by_id.get(cid)
		if cdata == null:
			continue
		if cdata.career != career:
			continue
		if int(cdata.quality) != 6:
			continue
		_ensure_cricket_dev(cid)
		var phase = get_current_phase(cid)
		var cfg = get_phase_cfg(phase)
		total += cfg.get("stage_pct", 0.0)
	return total

func get_career_peiyu_flat_income(career: String) -> int:
	var total = 0
	for cid in g.cuzhi_caught.keys():
		var cdata = _crickets_by_id.get(cid)
		if cdata == null:
			continue
		if cdata.career != career:
			continue
		if int(cdata.quality) != 6:
			continue
		_ensure_cricket_dev(cid)
		var phase = get_current_phase(cid)
		var cfg = get_phase_cfg(phase)
		var income_per_lv = cfg.get("income_per_level", 0)
		var parts = g.cuzhi_caught[cid].parts
		total += (parts.get("head", 0) + parts.get("jaw", 0) + parts.get("wing", 0)) * income_per_lv
	return total


# 【新增】无双促织盒子兑换：扣盒子，直接获得指定促织（quality>=5）
func do_wushuang_box_claim(cid: String) -> bool:
	if g.items.get("wushuang_cuzhi_box", 0) <= 0:
		return false
	var cdata = _crickets_by_id.get(cid)
	if cdata == null or int(cdata.quality) < 5:
		return false
	g.items["wushuang_cuzhi_box"] -= 1
	var result = _on_cricket_acquired(cid)
	return result.ok


# 【查】某门客虫师技能总固定赚速加成（star 1~4 累加）
func get_hero_worm_flat_bonus(hero_id: String) -> int:
	var total = 0
	var skills = get_hero_worm_skills(hero_id)
	for i in range(skills.size()):
		var skill = skills[i]
		if int(skill.star) >= 5: continue
		if skill.level <= 0: continue
		total += int(get_worm_skill_bonus(hero_id, i))
	return total

# 【查】某门客虫师技能总百分比赚速加成（star 5~6 累加）
func get_hero_worm_percent_bonus(hero_id: String) -> float:
	var total = 0.0
	var skills = get_hero_worm_skills(hero_id)
	for i in range(skills.size()):
		var skill = skills[i]
		if int(skill.star) < 5: continue
		if skill.level <= 0: continue
		total += get_worm_skill_bonus(hero_id, i)
	return total


# ========== 促织装备系统 ==========

func _get_equip_cfg() -> Dictionary:
	return _cfg.get("equip", {})

func get_cricket_data(cid: String) -> Dictionary:
	# 【查】获取促织配置数据（public接口，供外部查询）
	return _crickets_by_id.get(cid, {}).duplicate()

func get_cricket_rank(cid: String) -> int:
	# 【查】促织当前军衔rank值（培育/蜕壳系统写入的rank字段）
	if not g.cuzhi_caught.has(cid): return 0
	return get_cricket_rank_index(g.cuzhi_caught[cid].level)

func get_cricket_initial_rank(cid: String) -> int:
	# 【查】促织初始军衔（按品质查配置）
	var cdata = _crickets_by_id.get(cid)
	if cdata == null: return 0
	var q = int(cdata.quality)
	var cfg = _get_equip_cfg()
	return cfg.get("initial_rank_by_quality", {}).get(str(q), 4)

func get_rank_tier_changes(cid: String) -> int:
	# 【查】促织从初始军衔到现在，经历了多少次大段变化（称号变化次数）
	var current = get_cricket_rank(cid)
	var initial = get_cricket_initial_rank(cid)
	return max(0, current - initial)

func get_equip_max_level(cid: String) -> int:
	# 【查】促织装备等级上限 = 初始上限 + 军衔大段变化次数 × 每段增量
	var cfg = _get_equip_cfg()
	var base = cfg.get("initial_max_level", 100)
	var per_tier = cfg.get("level_cap_per_rank_tier", 50)
	var tiers = get_rank_tier_changes(cid)
	return base + tiers * per_tier

func get_equip_level(cid: String) -> int:
	# 【查】促织当前装备等级（默认1级）
	return g.cuzhi_equip_levels.get(cid, 1)

func get_equip_aptitude_per_level(cid: String) -> int:
	# 【查】促织每级提供的资质（无双6/极无双7）
	var cdata = _crickets_by_id.get(cid)
	if cdata == null: return 0
	var q = int(cdata.quality)
	var cfg = _get_equip_cfg()
	return cfg.get("aptitude_per_level", {}).get(str(q), 6)

func get_equip_cost_beast_fruit(cid: String) -> int:
	# 【查】升级消耗珍兽果数量
	var cdata = _crickets_by_id.get(cid)
	if cdata == null: return 0
	var q = int(cdata.quality)
	var cfg = _get_equip_cfg()
	return cfg.get("cost_beast_fruit", {}).get(str(q), 180)

func get_equip_cost_jinghua(cid: String) -> int:
	# 【查】升级消耗促织精华数量
	var cdata = _crickets_by_id.get(cid)
	if cdata == null: return 0
	var q = int(cdata.quality)
	var cfg = _get_equip_cfg()
	return cfg.get("cost_jinghua", {}).get(str(q), 60)

func can_upgrade_equip(cid: String) -> bool:
	# 【查】能否升级装备：等级未达上限
	var level = get_equip_level(cid)
	var max_level = get_equip_max_level(cid)
	return level < max_level

func upgrade_equip(cid: String, use_jinghua: bool) -> Dictionary:
	# 【升】升级促织装备一次
	if not can_upgrade_equip(cid):
		return {"ok": false, "reason": "已达等级上限（需提升促织军衔解锁更高等级）"}
	
	var cost: int
	var item_id: String
	if use_jinghua:
		cost = get_equip_cost_jinghua(cid)
		item_id = "cuzhi_jinghua"
	else:
		cost = get_equip_cost_beast_fruit(cid)
		item_id = "beast_fruit"  # 珍兽果道具ID，若您本地不同请改此处
	
	if g.items.get(item_id, 0) < cost:
		var item_name = g.ITEM_CONFIG.get(item_id, {}).get("name", item_id)
		return {"ok": false, "reason": "%s不足" % item_name}
	
	# 扣道具、升级
	g.items[item_id] -= cost
	if not g.cuzhi_equip_levels.has(cid):
		g.cuzhi_equip_levels[cid] = 1
	g.cuzhi_equip_levels[cid] += 1
	
	return {"ok": true, "new_level": g.cuzhi_equip_levels[cid]}

func recycle_equip(cid: String) -> Dictionary:
	# 【回收】重置促织装备等级为1，返还全部促织精华（无论升级时用了什么材料）
	var level = get_equip_level(cid)
	if level <= 1:
		return {"ok": false, "reason": "等级为1，无需回收"}
	
	var total_upgrades = level - 1
	var jinghua_per_level = get_equip_cost_jinghua(cid)
	var return_jinghua = total_upgrades * jinghua_per_level
	
	# 重置等级
	g.cuzhi_equip_levels[cid] = 1
	
	# 返还促织精华
	if not g.items.has("cuzhi_jinghua"):
		g.items["cuzhi_jinghua"] = 0
	g.items["cuzhi_jinghua"] += return_jinghua
	
	return {"ok": true, "return_jinghua": return_jinghua}

func equip_cricket(hero_id: String, cid: String) -> bool:
	# 【装备】将促织装备给门客（仅无双/极无双可装备，每种促织只能被一个门客装备）
	if not g.cuzhi_caught.has(cid): return false
	var cdata = _crickets_by_id.get(cid)
	if cdata == null: return false
	var q = int(cdata.quality)
	if q < 5: return false
	
	# 检查是否已被其他门客装备
	for h_id in g.cuzhi_equipped.keys():
		if g.cuzhi_equipped[h_id] == cid and h_id != hero_id:
			return false
	
	# 如果该门客已有装备，先卸下
	if g.cuzhi_equipped.has(hero_id):
		unequip_cricket(hero_id)
	
	g.cuzhi_equipped[hero_id] = cid
	return true

func unequip_cricket(hero_id: String) -> bool:
	# 【卸下】门客卸下促织
	if not g.cuzhi_equipped.has(hero_id): return false
	g.cuzhi_equipped.erase(hero_id)
	return true

func get_equipped_cricket(hero_id: String) -> String:
	# 【查】获取门客装备的促织id
	return g.cuzhi_equipped.get(hero_id, "")

func get_hero_by_cricket(cid: String) -> String:
	# 【查】获取装备某促织的门客id
	for h_id in g.cuzhi_equipped.keys():
		if g.cuzhi_equipped[h_id] == cid:
			return h_id
	return ""

func get_equip_aptitude_bonus(hero_id: String) -> int:
	# 【查】门客装备促织提供的总资质加成（供 HeroData 调用）
	var cid = get_equipped_cricket(hero_id)
	if cid == "": return 0
	var level = get_equip_level(cid)
	var per_level = get_equip_aptitude_per_level(cid)
	return level * per_level

func get_equipable_crickets() -> Array:
	# 【查】获取可装备的无双/极无双促织列表（选择器用）
	var result = []
	for cid in g.cuzhi_caught.keys():
		var cdata = _crickets_by_id.get(cid)
		if cdata == null: continue
		var q = int(cdata.quality)
		if q >= 5:
			result.append({
				"id": cid,
				"data": cdata,
				"cricket_level": g.cuzhi_caught[cid].level,
				"equip_level": get_equip_level(cid),
			})
	return result
