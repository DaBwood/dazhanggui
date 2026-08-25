# ============================================================
# 珍兽系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name BeastSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 提供本系统的存档字段（由 GameData.save_game 合并进扁平存档表，格式与旧版完全一致）
func get_save_data() -> Dictionary:
	return {
		"beasts": g.beasts,   # 珍兽数据
		"beast_fruit": g.beast_fruit,   # 珍兽果
		"aroma_fruit": g.aroma_fruit,   # 奇香果
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("beasts"):
		g.beasts = s.beasts
		# 兼容旧存档：给没有 refresh_count 的珍兽技能补上
		for bid in g.beasts.keys():
			var d = g.beasts[bid]
			var instances = d if d is Array else [d]
			for inst in instances:
				for sk in inst.get("skills", []):
					if not sk.has("refresh_count"):
						sk.refresh_count = 0
	if s.has("beast_fruit"): g.beast_fruit = s.beast_fruit
	if s.has("aroma_fruit"): g.aroma_fruit = s.aroma_fruit

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

func get_beast_config(beast_id: String) -> Dictionary:
	return g._beast_configs.get(beast_id, {}).duplicate(true)

func get_all_beast_ids() -> Array:
	return g._beast_configs.keys()

func get_beast_instance(beast_id: String, index: int = 0):
	if not g.beasts.has(beast_id): return null
	var d = g.beasts[beast_id]
	if d is Array:
		if index >= 0 and index < d.size(): return d[index]
		return null
	return d

func get_beast_instance_count(beast_id: String) -> int:
	if not g.beasts.has(beast_id): return 0
	var d = g.beasts[beast_id]
	if d is Array: return d.size()
	return 1

func get_beast_aptitude(beast_id: String, instance_index: int = 0) -> int:
	var cfg = get_beast_config(beast_id)
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return 0
	var base = cfg.get("aptitude", 0)
	var lv = instance.get("level", 1)
	return base + (lv - 1) * 8

func get_beast_skill_bonus(beast_id: String, instance_index: int = 0) -> float:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return 0.0
	var skills = instance.get("skills", [])
	var total = 0.0
	for sk in skills:
		total += sk.get("percent", 0.0)
	return total

func get_beast_aura_bonus(beast_id: String, _instance_index: int = 0) -> float:
	var cfg = get_beast_config(beast_id)
	var auras = cfg.get("auras", [])
	if auras.is_empty(): return 0.0
	var special_count = _get_special_beast_count()
	var bonus = 0.10 + (special_count - 1) * 0.10
	bonus += 0.05
	return bonus

func _get_special_beast_count() -> int:
	var count = 0
	for bid in g.beasts.keys():
		if get_beast_config(bid).get("max_count", 1) == 1:
			count += 1
	return count

func get_hero_beast_bonus(hero_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {"aptitude": 0, "percent": 0.0}
	var h = g.heroes[hero_id]
	var beast_id = h.get("equipped_beast", "")
	if beast_id == "": return {"aptitude": 0, "percent": 0.0}
	var idx = h.get("equipped_beast_index", 0)
	return {
		"aptitude": get_beast_aptitude(beast_id, idx),
		"percent": get_beast_skill_bonus(beast_id, idx) + get_beast_aura_bonus(beast_id, idx)
	}

func _init_beast_skills(count: int) -> Array:
	var skills = []
	for i in range(count):
		skills.append({"percent": 0.01, "refresh_count": 0})
	return skills

func add_beast(beast_id: String) -> bool:
	var cfg = get_beast_config(beast_id)
	if cfg.is_empty(): return false
	var max_count = cfg.get("max_count", 1)
	var init_data = {"level": 1, "equipped_hero": "", "skills": _init_beast_skills(cfg.get("skill_count", 0))}
	if max_count == 1:
		if g.beasts.has(beast_id): return false
		g.beasts[beast_id] = init_data
	else:
		if not g.beasts.has(beast_id): g.beasts[beast_id] = []
		g.beasts[beast_id].append(init_data)
	return true

func upgrade_beast(beast_id: String, instance_index: int = 0) -> bool:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return false
	if instance.level >= 200: return false
	if g.beast_fruit < 80: return false
	g.beast_fruit -= 80
	instance.level += 1
	return true

func refresh_beast_skill(beast_id: String, instance_index: int, skill_index: int, use_aroma: bool = false) -> bool:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return false
	var skills = instance.get("skills", [])
	if skill_index < 0 or skill_index >= skills.size(): return false
	
	var skill = skills[skill_index]
	if skill.percent >= 0.249:  # 满级 25%，留一点浮点余量
		skill.percent = 0.25
		return false
	
	if use_aroma:
		# 奇香果刷新：固定消耗1个，15%-25%
		if g.aroma_fruit < 1: return false
		g.aroma_fruit -= 1
		skill.refresh_count += 1
		var new_val = randf_range(0.15, 0.251)
		if new_val > 0.25: new_val = 0.25
		skill.percent = max(skill.percent, new_val)
	else:
		# 铜钱刷新：指数增长费用
		var cost = 100 * int(pow(2, skill.refresh_count))
		if g.money < cost: return false
		g.money -= cost
		skill.refresh_count += 1
		
		var roll = randf()
		var new_val: float
		if roll < 0.9:
			new_val = randf_range(0.01, 0.149)
		else:
			new_val = randf_range(0.15, 0.251)
		
		if new_val > 0.25: new_val = 0.25
		skill.percent = max(skill.percent, new_val)
	
	# 接近满级直接封顶
	if skill.percent >= 0.245:
		skill.percent = 0.25
	
	return true

func equip_beast(hero_id: String, beast_id: String, instance_index: int) -> bool:
	if not g.heroes.has(hero_id): return false
	if not g.beasts.has(beast_id): return false
	
	# 【新增】先卸下当前门客的旧珍兽，并清空 beasts 中的标记
	var old_beast_id = g.heroes[hero_id].get("equipped_beast", "")
	var old_idx = g.heroes[hero_id].get("equipped_beast_index", 0)
	if old_beast_id != "":
		var old_inst = get_beast_instance(old_beast_id, old_idx)
		if old_inst != null:
			old_inst.equipped_hero = ""
	
	# 把新珍兽从其他门客身上卸下
	for hid in g.heroes.keys():
		if g.heroes[hid].get("equipped_beast", "") == beast_id and g.heroes[hid].get("equipped_beast_index", 0) == instance_index:
			g.heroes[hid].equipped_beast = ""
			g.heroes[hid].equipped_beast_index = 0
	
	# 【新增】设置 beasts 中新实例的 equipped_hero
	var new_inst = get_beast_instance(beast_id, instance_index)
	if new_inst != null:
		new_inst.equipped_hero = hero_id
	
	g.heroes[hero_id].equipped_beast = beast_id
	g.heroes[hero_id].equipped_beast_index = instance_index
	return true

func unequip_beast(hero_id: String) -> bool:
	if not g.heroes.has(hero_id): return false
	# 【新增】同步清空 beasts 中旧实例的 equipped_hero
	var old_beast_id = g.heroes[hero_id].get("equipped_beast", "")
	var old_idx = g.heroes[hero_id].get("equipped_beast_index", 0)
	if old_beast_id != "":
		var old_inst = get_beast_instance(old_beast_id, old_idx)
		if old_inst != null:
			old_inst.equipped_hero = ""
	g.heroes[hero_id].equipped_beast = ""
	g.heroes[hero_id].equipped_beast_index = 0
	return true
