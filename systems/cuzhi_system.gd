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
	var cfg = _cfg.get("worm_book", {}).get("qualities", {}).get(str(skill.star), {})
	var base = cfg.get("bonus", [0])[0]
	return base * skill.level

# 【查】某技能下次升级消耗
func get_worm_skill_upgrade_cost(hero_id: String, skill_idx: int) -> int:
	var master = g.cuzhi_worm_masters.get(hero_id)
	if master == null: return 0
	var skills = master.skills
	if skill_idx >= skills.size(): return 0
	var skill = skills[skill_idx]
	var cfg = _cfg.get("worm_book", {}).get("qualities", {}).get(str(skill.star), {})
	var costs = cfg.get("cost", [])
	if costs.is_empty(): return 0
	var cost_idx = skill.level % costs.size()
	return costs[cost_idx]

# 【查】能否升级某技能
func can_upgrade_worm_skill(hero_id: String, skill_idx: int) -> bool:
	var cost = get_worm_skill_upgrade_cost(hero_id, skill_idx)
	if cost <= 0: return false
	var master = g.cuzhi_worm_masters.get(hero_id)
	if master == null: return false
	var skill = master.skills[skill_idx]
	var item_id = "cuzhi_exp_high" if skill.star >= 5 else "cuzhi_exp_low"
	return g.items.get(item_id, 0) >= cost

# 【升】升级某技能
func upgrade_worm_skill(hero_id: String, skill_idx: int) -> bool:
	if not can_upgrade_worm_skill(hero_id, skill_idx): return false
	var cost = get_worm_skill_upgrade_cost(hero_id, skill_idx)
	var master = g.cuzhi_worm_masters[hero_id]
	var skill = master.skills[skill_idx]
	var item_id = "cuzhi_exp_high" if skill.star >= 5 else "cuzhi_exp_low"
	g.items[item_id] = g.items.get(item_id, 0) - cost
	skill.level += 1
	return true

# 【内】同步某门客的技能列表（把新获得的同职业促织加进来）
func _sync_worm_skills(hero_id: String):
	var hero = g.heroes.get(hero_id)
	if hero == null: return
	var career_map = {"士": "shi", "农": "nong", "工": "gong", "商": "shang", "侠": "xia"}
	var hero_career = career_map.get(hero.get("category", ""), "")
	
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
		var star = _cfg.get("worm_book", {}).get("qualities", {}).get(str(q), {}).get("star", 1)
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

func get_career_name(c: String) -> String:
	return _cfg.career_names.get(c, c)

func get_quality_color(q: int) -> String:
	return _cfg.quality_colors.get(str(q), "#ffffff")

func get_total_crickets() -> int:
	return _cfg.crickets.size()

func get_caught_count() -> int:
	return g.cuzhi_caught.size()
