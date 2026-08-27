# ============================================================
# 宅院系统（庄园子玩法：技艺卷轴升级）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 配置外置 res://data/courtyard.json（由 GameData._load_all_configs 加载进 g._courtyard_configs）
# ============================================================
class_name CourtyardSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 提供宅院卷轴等级（由 GameData.save_game 合并进扁平存档表）
func get_save_data() -> Dictionary:
	return {
		"courtyard_levels": g.courtyard_levels,   # {技艺id: {project1/project2: {vol1/vol2: 等级}}}
	}

# 从扁平存档表认领宅院字段（老存档缺字段则保持初始值，自动兼容）
func load_save_data(s: Dictionary):
	if s.has("courtyard_levels"):
		g.courtyard_levels = s["courtyard_levels"].duplicate(true)
	# 清理存档中已不存在的技艺，防止配置删除后残留
	for tech_id in g.courtyard_levels.keys():
		if get_technique_cfg(tech_id).is_empty():
			g.courtyard_levels.erase(tech_id)

# ============ 配置读取 ============
# 宅院全局参数（courtyard.json 的 settings 段）
func get_settings() -> Dictionary:
	return g._courtyard_configs.get("settings", {})

# 技艺列表（32个技艺，每个技艺固定两个项目）
func get_technique_list() -> Array:
	return g._courtyard_configs.get("techniques", [])

# 按 id 查技艺配置；找不到返回空字典
func get_technique_cfg(tech_id: String) -> Dictionary:
	for cfg in get_technique_list():
		if cfg.get("id", "") == tech_id:
			return cfg
	return {}

# ============ 卷轴状态 ============
# 取某技艺某项目的卷轴状态，首次访问自动初始化为 卷一Lv0 / 卷二Lv0
func _get_project_state(tech_id: String, project_key: String) -> Dictionary:
	if not g.courtyard_levels.has(tech_id):
		g.courtyard_levels[tech_id] = {
			"project1": {"vol1": 0, "vol2": 0},
			"project2": {"vol1": 0, "vol2": 0},
		}
	var tech_state: Dictionary = g.courtyard_levels[tech_id]
	if not tech_state.has(project_key):
		tech_state[project_key] = {"vol1": 0, "vol2": 0}
	var project_state: Dictionary = tech_state[project_key]
	if not project_state.has("vol1"): project_state["vol1"] = 0
	if not project_state.has("vol2"): project_state["vol2"] = 0
	return project_state

# 取某卷当前等级（volume = "vol1" / "vol2"）
func get_scroll_level(tech_id: String, project_key: String, volume: String) -> int:
	return int(_get_project_state(tech_id, project_key).get(volume, 0))


# 【改】升级消耗公式重构：单级消耗 = a + b × 当前等级^p（最低1个产物）
# 参数按 项目类型×卷 配置在 courtyard.json 的 settings.cost_formulas 里，拟合自目标消耗表
func get_scroll_cost(tech_id: String, project_key: String, volume: String) -> int:
	var cfg = get_technique_cfg(tech_id)
	var project_type = String(cfg.get(project_key, {}).get("type", "shop"))
	var formula: Dictionary = get_settings().get("cost_formulas", {}).get(project_type, {}).get(volume, {})
	var level = get_scroll_level(tech_id, project_key, volume)
	var cost = float(formula.get("a", 0)) + float(formula.get("b", 1)) * pow(level, float(formula.get("p", 1)))
	return maxi(1, int(cost))

# ============ 升级 ============
# 升级指定项目的卷一/卷二；消耗该技艺对应的庄园仓库产物
func upgrade_scroll(tech_id: String, project_key: String, volume: String) -> Dictionary:
	var cfg = get_technique_cfg(tech_id)
	if cfg.is_empty():
		return {"ok": false, "reason": "技艺不存在"}
	if not cfg.has(project_key):
		return {"ok": false, "reason": "项目不存在"}
	if volume != "vol1" and volume != "vol2":
		return {"ok": false, "reason": "卷轴类型错误"}

	var state = _get_project_state(tech_id, project_key)
	var level = int(state.get(volume, 0))
	# 【改】卷二不再要求卷一100级解锁，两卷都可从0级直接升级

	var product = String(cfg.get("product", ""))
	var cost = get_scroll_cost(tech_id, project_key, volume)
	var owned = int(g.manor_goods.get(product, 0))
	if owned < cost:
		return {"ok": false, "reason": "%s不足（需要%d个）" % [product, cost]}

	# 庄园仓库数量是浮点累计值，这里按整数扣减本次消耗
	g.manor_goods[product] = float(g.manor_goods.get(product, 0.0)) - cost
	if float(g.manor_goods[product]) <= 0.0:
		g.manor_goods.erase(product)

	state[volume] = level + 1

	# 挚友卷直接提升已拥有挚友的属性；未拥有挚友在解锁时补发累计加成
	var project: Dictionary = cfg[project_key]
	if project.get("type", "") == "friend":
		_apply_friend_scroll_effect(project, volume)

	return {"ok": true, "level": level + 1, "cost": cost}

# 卷轴十连升级：逐次结算，产物不足即停（卷一卷二通用，均无上限）
# 【改】十连卷一卷二通用，新增 volume 参数指定升哪卷
func upgrade_scroll_batch(tech_id: String, project_key: String, volume: String = "vol1", times: int = 10) -> Dictionary:
	var done = 0
	var last_reason = ""
	for i in range(times):
		var result = upgrade_scroll(tech_id, project_key, volume)   # 【改】原为固定 "vol1"
		if not result.ok:
			last_reason = result.get("reason", "升级失败")
			break
		done += 1
	if done == 0:
		return {"ok": false, "done": 0, "reason": last_reason}
	return {"ok": true, "done": done}

# 挚友卷升级时，给该卷已拥有的挚友立即加友好/才华
func _apply_friend_scroll_effect(project: Dictionary, volume: String):
	var amount = int(get_settings().get("friend_friendly_per_level", 1)) if volume == "vol1" else int(get_settings().get("friend_talent_per_level", 1))
	for friend_id in project.get("friends", []):
		if not g.friends.has(friend_id): continue
		if volume == "vol1":
			g.friends[friend_id].friendly += amount
		else:
			g.friends[friend_id].talent += amount

# 挚友解锁时补发该挚友所在卷轴已累计的友好/才华加成
func apply_friend_unlock_bonus(friend_id: String):
	if not g.friends.has(friend_id): return
	var bonus = get_friend_stat_bonus(friend_id)
	g.friends[friend_id].friendly += int(bonus.get("friendly", 0))
	g.friends[friend_id].talent += int(bonus.get("talent", 0))

# ============ 分配反查与加成 ============
# 反查门客/挚友所在的卷轴项目；找不到返回空字典
func _find_role_project(role_id: String, role_type: String) -> Dictionary:
	var list_key = "heroes" if role_type == "hero" else "friends"
	for tech in get_technique_list():
		for project_key in ["project1", "project2"]:
			var project: Dictionary = tech.get(project_key, {})
			if project.get("type", "") != role_type: continue
			if role_id in project.get(list_key, []):
				return {"tech_id": tech.get("id", ""), "project_key": project_key}
	return {}

# 反查店铺所在的商铺卷项目；找不到返回空字典
func _find_shop_project(shop_id: String) -> Dictionary:
	for tech in get_technique_list():
		for project_key in ["project1", "project2"]:
			var project: Dictionary = tech.get(project_key, {})
			if project.get("type", "") == "shop" and project.get("target", "") == shop_id:
				return {"tech_id": tech.get("id", ""), "project_key": project_key}
	return {}

# 门客卷给单个门客的固定赚速加成：卷一每级+5000
func get_hero_income_bonus(hero_id: String) -> int:
	var found = _find_role_project(hero_id, "hero")
	if found.is_empty(): return 0
	var level = get_scroll_level(found.tech_id, found.project_key, "vol1")
	return level * int(get_settings().get("hero_income_per_level", 5000))

# 门客卷给单个门客的资质加成：卷二每级+1
func get_hero_aptitude_bonus(hero_id: String) -> int:
	var found = _find_role_project(hero_id, "hero")
	if found.is_empty(): return 0
	var level = get_scroll_level(found.tech_id, found.project_key, "vol2")
	return level * int(get_settings().get("hero_aptitude_per_level", 1))

# 商铺卷给单个店员的赚速加成：卷一每级+0.1
func get_shop_staff_income_bonus(shop_id: String) -> float:
	var found = _find_shop_project(shop_id)
	if found.is_empty(): return 0.0
	var level = get_scroll_level(found.tech_id, found.project_key, "vol1")
	return level * float(get_settings().get("shop_staff_income_per_level", 0.1))

# 商铺卷给店铺总赚速的百分比加成：卷二每级+25%
func get_shop_percent_bonus(shop_id: String) -> float:
	var found = _find_shop_project(shop_id)
	if found.is_empty(): return 0.0
	var level = get_scroll_level(found.tech_id, found.project_key, "vol2")
	return level * float(get_settings().get("shop_percent_per_level", 0.25))

# 挚友卷给单个挚友的友好/才华加成（卷一友好，卷二才华，每级各+1）
func get_friend_stat_bonus(friend_id: String) -> Dictionary:
	var found = _find_role_project(friend_id, "friend")
	if found.is_empty():
		return {"friendly": 0, "talent": 0}
	var friendly_lv = get_scroll_level(found.tech_id, found.project_key, "vol1")
	var talent_lv = get_scroll_level(found.tech_id, found.project_key, "vol2")
	return {
		"friendly": friendly_lv * int(get_settings().get("friend_friendly_per_level", 1)),
		"talent": talent_lv * int(get_settings().get("friend_talent_per_level", 1)),
	}
