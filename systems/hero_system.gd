# ============================================================
# 门客系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name HeroSystem
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
		"heroes": g.heroes,   # 门客数据
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("heroes"):
		# 只覆盖存档里有的门客（保留老进度）；存档没有的新门客保持初始值
		g.heroes = s.heroes.duplicate(true)
	# 【新增】存档迁移：旧档门客的 base_income 字段改名为 extra_income
	# （该字段实为"额外赚速池"，与基础赚速公式无关；旧档已攒数值原样保留，含旧版升级攒入的部分）
	for hero in g.heroes.values():
		if hero.has("base_income"):
			hero["extra_income"] = hero.get("extra_income", 0) + int(hero["base_income"])
			hero.erase("base_income")

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 系列兑换（可附带同名挚友）
func exchange_series_hero(hero_id: String, item_id: String, cost: int, friend_id: String = "") -> Dictionary:
	if g.heroes.has(hero_id):
		return {"ok": false, "reason": "已拥有该门客"}
	if g.items.get(item_id, 0) < cost:
		return {"ok": false, "reason": "兑换道具不足"}
	if not unlock_hero(hero_id):
		return {"ok": false, "reason": "兑换失败"}
	g.items[item_id] -= cost
	if friend_id != "":
		g.unlock_friend(friend_id)
	return {"ok": true}

# ========== 角色解锁（所有获得途径统一走这里） ==========
func unlock_hero(hero_id: String) -> bool:
	if g.heroes.has(hero_id): return false
	var cfg = g.get_hero_config(hero_id)
	if cfg.is_empty(): return false
	g.heroes[hero_id] = cfg
	return true

#门客升级
func upgrade_hero_level(hero_id: String, batch: bool = false) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	var max_level = 50 + hero.breakthrough_count * 50
	if hero.level >= max_level:
		return 0
	
	var exp_count = g.items.get("experience", 0)
	if exp_count <= 0: return 0
	
	var target = hero.level + (10 if batch else 1)
	target = min(target, max_level)  # 不能超过上限
	
	var total_cost = 0
	var levels = 0
	for lv in range(hero.level, target):
		var cost = int(ceil(100 * pow(1.05, lv)))
		if exp_count < total_cost + cost:
			break
		total_cost += cost
		levels += 1
	
	if levels > 0:
		g.items.experience -= total_cost
		hero.level += levels
		return levels
	return 0

#门客突破
func breakthrough_hero(hero_id: String) -> bool:
	if not g.heroes.has(hero_id): return false
	var hero = g.heroes[hero_id]
	var max_level = 50 + hero.breakthrough_count * 50
	if hero.level < max_level:
		return false  # 还没到突破节点
	
	var cost = hero.breakthrough_count * 10
	if not g.items.has("fengyasong") or g.items.fengyasong < cost:
		return false
	
	g.items.fengyasong -= cost
	hero.breakthrough_count += 1
	return true

#门客资质技能升级
func upgrade_hero_aptitude_skill(hero_id: String, skill_index: int) -> bool:
	if not g.heroes.has(hero_id): return false
	var skills = g.heroes[hero_id].aptitude_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	var skill = skills[skill_index]
	if skill.level >= skill.max_level: return false
	skill.level += 1
	return true

#门客店铺技能升级
func upgrade_hero_shop_skill(hero_id: String, skill_index: int, mode: String = "single") -> bool:
	if not g.heroes.has(hero_id): return false
	var skills = g.heroes[hero_id].shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	var skill = skills[skill_index]
	if skill.level >= skill.max_level: return false
	
	var abacus_count = g.items.get("abacus", 0)
	if abacus_count <= 0: return false
	
	if mode == "single":
		var cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		if abacus_count < cost: return false
		g.items.abacus -= cost
		skill.level += 1
		return true
	else:
		# 一键升满：能升多少升多少
		var remaining = skill.max_level - skill.level
		var upgraded = 0
		while upgraded < remaining:
			var cost = max(1, int(ceil(pow(1.05, skill.level + upgraded - 1))))
			if g.items.abacus < cost: break
			g.items.abacus -= cost
			upgraded += 1
		if upgraded > 0:
			skill.level += upgraded
			return true
		return false

# 门客晋升升级（通用，不绑定任何具体门客）
func upgrade_promotion(hero_id: String, batch: bool = false) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	if not hero.has("promotion"): return 0
	var promo = hero.promotion
	if promo.level >= promo.max_level: return 0
	
	var cost = promo.cost_amount
	var max_item = g.items.get(promo.cost_item, 0)
	
	var max_times = 1
	if batch:
		max_times = min(10, promo.max_level - promo.level, int(max_item / cost))
	else:
		if max_item < cost: return 0
	
	if max_times <= 0: return 0
	
	var upgraded = 0
	for i in range(max_times):
		if promo.level >= promo.max_level: break
		if g.items.get(promo.cost_item, 0) < cost: break
		g.items[promo.cost_item] -= cost
		promo.level += 1
		upgraded += 1
		_check_promotion(hero)
	
	return upgraded

func _check_promotion(hero: Dictionary):
	if not hero.has("promotion"): return
	var promo = hero.promotion
	var lv = promo.level
	
	for tier in promo.tiers:
		if lv >= tier.threshold:
			if tier.has("quality"):
				hero.quality = tier.quality
			if tier.has("initial_aptitude"):
				hero.initial_aptitude = tier.initial_aptitude
			if tier.has("new_skills"):
				for new_skill in tier.new_skills:
					var has_it = false
					for sk in hero.aptitude_skills:
						if sk.name == new_skill.name:
							has_it = true
							break
					if not has_it:
						hero.aptitude_skills.append({
							"name": new_skill.name,
							"level": 0,
							"max_level": 200,
							"aptitude_per_level": new_skill.aptitude_per_level
						})
