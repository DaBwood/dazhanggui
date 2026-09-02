class_name CuzhiSystem extends RefCounted
# 【促织系统】促织园核心逻辑：捕捉、升级、促织庙、保底自选

var g  # GameData 中枢引用

var _cfg: Dictionary
var _crickets_by_id: Dictionary
var _crickets_by_quality: Dictionary

func _init(game_data):
	g = game_data
	_cfg = g._load_json("res://data/cuzhi.json")
	_build_lookup()

func _build_lookup():
	# 【构建】id映射表 + 按品质分组
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

# ========== 捕捉 ==========
func can_catch() -> bool:
	# 【查】是否有促织笼道具
	return g.get_item_count("cuzhi_cage") > 0

func catch_one() -> Dictionary:
	# 【捕捉】消耗1个促织笼，roll品质，随机选促织，给缘分，检查保底
	g.consume_item("cuzhi_cage", 1)
	g.cuzhi_spent += 1

	var q = _roll_quality()
	var pool = _crickets_by_quality[q]
	var c = pool[randi() % pool.size()]
	var cid = c.id

	var is_new = not g.cuzhi_caught.has(cid)
	if is_new:
		g.cuzhi_caught[cid] = {"level": 1, "exp": 0}
	else:
		_add_exp(cid, _cfg.levelup.exp_per_dup)

	# 给职业缘分
	var career = c.career
	if not g.cuzhi_fate.has(career):
		g.cuzhi_fate[career] = 0
	g.cuzhi_fate[career] += _cfg.fate_per_catch

	return {
		"cricket": c,
		"is_new": is_new,
		"quality": q,
		"guarantee_ready": g.cuzhi_spent >= _cfg.guarantee.count,
	}

func _roll_quality() -> int:
	# 【内】按权重roll品质，只出1~5（极.无双不在捕捉池）
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

func _add_exp(cid: String, amount: int):
	# 【内】给同名促织加经验，自动升级
	var data = g.cuzhi_caught[cid]
	data.exp += amount
	var needed = get_levelup_exp(data.level)
	while data.level < _cfg.levelup.max_level and data.exp >= needed:
		data.exp -= needed
		data.level += 1
		needed = get_levelup_exp(data.level)

func get_levelup_exp(level: int) -> int:
	# 【查】从level升到level+1所需经验
	var idx = level - 1
	var table = _cfg.levelup.exp_table
	if idx < 0 or idx >= table.size():
		return 999999
	return table[idx]

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
	# 【查】下次升级消耗 = 50 + 已升级次数 × 50
	var lv = get_temple_level(hero_id)
	return _cfg.temple.base_cost + lv * _cfg.temple.cost_increment

func get_temple_bonus(hero_id: String) -> float:
	# 【查】当前促织庙加成百分比
	var lv = get_temple_level(hero_id)
	return lv * _cfg.temple.bonus_per_level

func can_upgrade_temple(hero_id: String, career: String) -> bool:
	# 【查】能否升级：等级未达上限 + 缘分足够
	var lv = get_temple_level(hero_id)
	if lv >= _cfg.temple.max_level:
		return false
	var cost = get_temple_cost(hero_id)
	return g.cuzhi_fate.get(career, 0) >= cost

func upgrade_temple(hero_id: String, career: String) -> bool:
	# 【升】消耗缘分，提升指定门客促织庙等级
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
	# 【兑】消耗100次进度，自选一只无双及以下促织
	if g.cuzhi_spent < _cfg.guarantee.count:
		return false
	var c = _crickets_by_id.get(cid)
	if c == null or c.quality > _cfg.guarantee.pool_quality_max:
		return false
	g.cuzhi_spent -= _cfg.guarantee.count
	if not g.cuzhi_caught.has(cid):
		g.cuzhi_caught[cid] = {"level": 1, "exp": 0}
	else:
		_add_exp(cid, _cfg.levelup.exp_per_dup)
	return true

# ========== 查询接口 ==========
func get_caught_list() -> Array:
	# 【查】已捉促织列表（含等级），按品质降序
	var result = []
	for cid in g.cuzhi_caught.keys():
		var c = _crickets_by_id.get(cid)
		if c:
			result.append({
				"id": cid,
				"data": c,
				"level": g.cuzhi_caught[cid].level,
				"exp": g.cuzhi_caught[cid].exp,
			})
	result.sort_custom(func(a, b): return b.data.quality < a.data.quality)
	return result

func get_career_fate(career: String) -> int:
	return g.cuzhi_fate.get(career, 0)

func get_all_crickets() -> Array:
	return _cfg.crickets.duplicate()

func get_catchable_crickets() -> Array:
	# 【查】可捕捉促织列表（无双及以下）
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
	# 【查】促织总种类数（含极.无双）
	return _cfg.crickets.size()

func get_caught_count() -> int:
	# 【查】已收集种类数
	return g.cuzhi_caught.size()
