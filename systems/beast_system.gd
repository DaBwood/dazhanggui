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
				if not inst.has("aura2_lv"): inst["aura2_lv"] = 1   # 【新增】旧档兼容：光环二初始1级
				if not inst.has("aura3_lv"): inst["aura3_lv"] = 1   # 【新增】旧档兼容：光环三初始1级
	if s.has("beast_fruit"):
		g.items["beast_fruit"] = int(g.items.get("beast_fruit", 0)) + int(s.beast_fruit)
	if s.has("aroma_fruit"):
		g.items["aroma_fruit"] = int(g.items.get("aroma_fruit", 0)) + int(s.aroma_fruit)
	

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
	return total * get_star_skill_multiplier()   # 【改】星神圣兽光环二：全珍兽技能加成×倍率（无星神兽时倍率1.0）

# 【改】光环总加成=光环一（系列数量自动）+光环二（每级5%）；光环三加等级上限不加%；星神光环二走全局倍率不在此计
func get_beast_aura_bonus(beast_id: String, instance_index: int = 0) -> float:
	return get_aura1_bonus(beast_id) + get_aura2_bonus(beast_id, instance_index)


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
	var init_data = {"level": 1, "equipped_hero": "", "skills": _init_beast_skills(cfg.get("skill_count", 0)), "aura2_lv": 1, "aura3_lv": 1}   # 【改】新增光环二/三等级，初始1级
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
	if instance.level >= get_beast_max_level(beast_id, instance_index): return false   # 【改】上限=200+光环三等级（原写死200）
	if int(g.items.get("beast_fruit", 0)) < 80: return false   # 【改】珍兽果改走道具
	g.items["beast_fruit"] -= 80   # 【改】
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
		if int(g.items.get("aroma_fruit", 0)) < 1: return false   # 【改】奇香果改走道具
		g.items["aroma_fruit"] -= 1   # 【改】
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

# ============ 光环养成（2026-08-30 重构） ============
# 光环一（auras[0]系列光环）：10%+(特殊系列兽数量-1)×10%，随数量自动涨，不可升级
# 光环二（auras[1]）：初始1级、每级+5%，集齐同系列珍兽解锁升级，满级20，消耗该兽兑换道具 当前等级×10 个
#   特例·星神圣兽光环二：不加%，效果=全珍兽技能加成×(2.0+0.1×(等级-1))，多只星神兽取最高级
# 光环三（auras[2]）：初始1级、每级+1珍兽等级上限，光环二满20级解锁升级，消耗同上；星神系列无光环三
# 等级存珍兽实例 aura2_lv/aura3_lv（初始1级，旧档自动补1）

# 【新增】光环一加成（系列光环，随已拥有特殊系列兽数量自动涨，不可升级）
func get_aura1_bonus(beast_id: String) -> float:
	var cfg = get_beast_config(beast_id)
	if cfg.get("auras", []).is_empty(): return 0.0   # 无光环兽（驺虞）不加
	var special_count = _get_special_beast_count()
	if special_count <= 0: return 0.0
	return 0.10 + (special_count - 1) * 0.10

# 【新增】光环二/三当前等级（初始1级，旧档缺省补1）
func get_aura2_lv(beast_id: String, instance_index: int = 0) -> int:
	var inst = get_beast_instance(beast_id, instance_index)
	if inst == null: return 1
	return int(inst.get("aura2_lv", 1))

func get_aura3_lv(beast_id: String, instance_index: int = 0) -> int:
	var inst = get_beast_instance(beast_id, instance_index)
	if inst == null: return 1
	return int(inst.get("aura3_lv", 1))

# 【新增】是否星神圣兽系列（光环二效果特殊：全局技能倍率）
func is_star_series(beast_id: String) -> bool:
	return get_beast_config(beast_id).get("quality", "") == "星神圣兽"

# 【新增】光环二加成：每级+5%；星神系列走全局倍率此处计0
func get_aura2_bonus(beast_id: String, instance_index: int = 0) -> float:
	if is_star_series(beast_id): return 0.0
	return 0.05 * get_aura2_lv(beast_id, instance_index)

# 【改】星神光环二全局倍率：每只已拥有星神兽贡献 100%+10%×(等级-1)，多只【累加】；无星神兽返回1.0
func get_star_skill_multiplier() -> float:
	var bonus = 0.0
	for bid in g.beasts.keys():
		if get_beast_config(bid).get("quality", "") != "星神圣兽": continue
		var inst = get_beast_instance(bid, 0)
		if inst == null: continue
		bonus += 1.0 + 0.1 * float(int(inst.get("aura2_lv", 1)) - 1)   # 每只独立贡献，累加
	return 1.0 + bonus

# 【改】珍兽等级上限=200 + 所有已拥有特殊珍兽的光环三等级之和（光环三全局生效、多只累加；无光环三的兽自身也享受）
func get_beast_max_level(_beast_id: String, _instance_index: int = 0) -> int:
	var extra = 0
	for bid in g.beasts.keys():
		if get_beast_config(bid).get("auras", []).size() < 3: continue   # 只统计有光环三的特殊珍兽
		var d = g.beasts[bid]
		var instances = d if d is Array else [d]   # 兼容多实例存储结构（特殊兽实际都是单实例）
		for inst in instances:
			extra += int(inst.get("aura3_lv", 1))
	return 200 + extra

# 【新增】系列是否集齐（同品质珍兽全部拥有）→ 光环二升级解锁条件
func is_series_complete(beast_id: String) -> bool:
	var quality = get_beast_config(beast_id).get("quality", "")
	if quality == "": return false
	for bid in g._beast_configs.keys():
		if g._beast_configs[bid].get("quality", "") == quality:
			if not g.beasts.has(bid): return false
	return true

# 【新增】光环二/三升级解锁状态
func can_upgrade_aura2(beast_id: String) -> bool:
	return is_series_complete(beast_id)

func can_upgrade_aura3(beast_id: String, instance_index: int = 0) -> bool:
	return get_aura2_lv(beast_id, instance_index) >= 20   # 光环二满级解锁光环三

# 【新增】光环升级消耗：当前等级×10 个该兽兑换道具（1→2花10、2→3花20……19→20花190）
func get_aura_upgrade_cost(beast_id: String, instance_index: int, which: int) -> int:
	var lv = get_aura2_lv(beast_id, instance_index) if which == 2 else get_aura3_lv(beast_id, instance_index)
	return lv * 10

# 【新增】光环升级：校验光环位/满级20/解锁条件/兑换道具消耗，成功等级+1
func upgrade_aura(beast_id: String, instance_index: int, which: int) -> Dictionary:
	var cfg = get_beast_config(beast_id)
	var auras = cfg.get("auras", [])
	if which == 2 and auras.size() < 2: return {"ok": false, "reason": "无光环二"}
	if which == 3 and auras.size() < 3: return {"ok": false, "reason": "无光环三"}
	var inst = get_beast_instance(beast_id, instance_index)
	if inst == null: return {"ok": false, "reason": "珍兽不存在"}
	var lv = get_aura2_lv(beast_id, instance_index) if which == 2 else get_aura3_lv(beast_id, instance_index)
	if lv >= 20: return {"ok": false, "reason": "已满级"}
	if which == 2 and not can_upgrade_aura2(beast_id):
		return {"ok": false, "reason": "集齐【%s】系列珍兽后解锁升级" % cfg.get("quality", "")}
	if which == 3 and not can_upgrade_aura3(beast_id, instance_index):
		return {"ok": false, "reason": "光环二满级后解锁升级"}
	var item = cfg.get("exchange_item", "")
	if item == "": return {"ok": false, "reason": "该珍兽无兑换道具"}
	var cost = lv * 10
	if int(g.items.get(item, 0)) < cost:
		return {"ok": false, "reason": "【%s】不足（需要%d个）" % [g.ITEM_CONFIG.get(item, {}).get("name", item), cost]}
	g.items[item] = int(g.items.get(item, 0)) - cost
	if which == 2: inst["aura2_lv"] = lv + 1
	else: inst["aura3_lv"] = lv + 1
	return {"ok": true, "lv": lv + 1}
