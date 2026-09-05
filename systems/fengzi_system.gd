# ============================================================
# 风姿系统：门客晋升无双（quality≥unlock_quality）时解锁专属风姿（李白→醉墨挥毫）
# 风姿升级：每级固定消耗专属道具，给门客 +aptitude_per_level 资质（无上限）
# 风姿技能：每 skill_unlock_every 级按顺序解锁一个（追加进技能栏 aptitude_skills，
#           初始0级 / 上限 skill_max_level / 每级 skill_aptitude_per_level 资质，吃资质丹，
#           固定消耗=每级资质数，走门客面板技能页现有升级逻辑）
#           每解锁一个 +income_pct_per_unlock 赚钱（全部解锁后封顶）
# 全部解锁后（等级=skills数×skill_unlock_every）：每 cap_bonus_every 级按顺序给一个技能
#           上限 +cap_bonus_amount（只加上限，升级仍需技能栏消耗资质丹，不再加赚钱）
# 纯逻辑模块：状态经 g 共享中枢；配置在 res://data/fengzi.json（按 hero_id 索引）
# ============================================================
class_name FengziSystem
extends RefCounted

var g   # GameData 中枢引用（不标类型避免循环引用）

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 风姿存档：{hero_id: {"level": 风姿等级}}
func get_save_data() -> Dictionary:
	return {"hero_fengzi": g.hero_fengzi}

func load_save_data(s: Dictionary):
	# 类型防御：旧档/异常档缺字段或为 null 时保持初始空表
	if s.has("hero_fengzi") and s.hero_fengzi is Dictionary:
		g.hero_fengzi = s.hero_fengzi.duplicate(true)
	# 【新增】读档后按等级幂等同步一遍风姿技能
	# （防中间态：等级已升、技能没同步上；重复调用安全）
	for hero_id in g.hero_fengzi.keys():
		if g.heroes.has(hero_id):
			sync_skills(hero_id)

# ============ 配置查询 ============
# 某门客的风姿配置（无则空字典；fengzi.json 顶层 "fengzi" 段按 hero_id 索引）
func get_fengzi_cfg(hero_id: String) -> Dictionary:
	return g._fengzi_configs.get("fengzi", {}).get(hero_id, {})

# ============ 解锁判定 ============
# 是否已解锁风姿：配置了风姿 且 门客品质达到 unlock_quality（2=无双）
func has_fengzi(hero_id: String) -> bool:
	var cfg = get_fengzi_cfg(hero_id)
	if cfg.is_empty() or not g.heroes.has(hero_id): return false
	return int(g.heroes[hero_id].get("quality", 0)) >= int(cfg.get("unlock_quality", 2))

# ============ 状态 ============
# 取风姿状态（等级），无记录则惰性初始化
func _get_state(hero_id: String) -> Dictionary:
	if not g.hero_fengzi.has(hero_id):
		g.hero_fengzi[hero_id] = {"level": 0}
	return g.hero_fengzi[hero_id]

# 风姿当前等级（无上限）
func get_level(hero_id: String) -> int:
	return int(_get_state(hero_id).get("level", 0))

# ============ 升级 ============
# 升级风姿：每级固定消耗 cost_per_level 个专属道具，无上限
# batch=true 十连；道具不足按实际可升级数结算；升级后幂等同步风姿技能
func upgrade(hero_id: String, batch: bool = false) -> int:
	var cfg = get_fengzi_cfg(hero_id)
	if cfg.is_empty(): return 0
	var cost_per = int(cfg.get("cost_per_level", 600))
	var item_id: String = cfg.get("cost_item", "")
	var times = 10 if batch else 1
	var have = g.items.get(item_id, 0)
	var can = min(times, int(have / cost_per))   # 无上限，能升多少升多少
	if can <= 0: return 0
	g.items[item_id] = have - can * cost_per
	var state = _get_state(hero_id)
	state.level = int(state.get("level", 0)) + can
	sync_skills(hero_id)   # 【新增】升级后同步技能解锁/上限（跳级/十连一次结算到位）
	return can

# 升级按钮文本：单级/十连理论消耗（与实际扣费同口径）
func get_upgrade_btn_text(hero_id: String, batch: bool) -> String:
	var cost_per = int(get_fengzi_cfg(hero_id).get("cost_per_level", 600))
	if batch:
		return "十连\n%d" % (cost_per * 10)
	return "升级\n%d" % cost_per

# ============ 风姿技能同步（核心，幂等） ============
# 按风姿等级把风姿技能同步进门客 aptitude_skills：
# 1) 每 skill_unlock_every 级按顺序解锁一个（未追加才追加；初始0级/基础上限/配置每级资质）
# 2) 全部解锁（等级=skills数×skill_unlock_every）后，每 cap_bonus_every 级
#    按顺序给一个技能 上限+cap_bonus_amount（直接重算写入，重复调用/跳级安全）
func sync_skills(hero_id: String):
	var cfg = get_fengzi_cfg(hero_id)
	if cfg.is_empty() or not g.heroes.has(hero_id): return
	var h = g.heroes[hero_id]
	var skills: Array = cfg.get("skills", [])
	if skills.is_empty(): return
	var lv = get_level(hero_id)
	var every = int(cfg.get("skill_unlock_every", 5))
	var base_cap = int(cfg.get("skill_max_level", 200))
	var bonus = int(cfg.get("cap_bonus_amount", 10))
	var cap_every = int(cfg.get("cap_bonus_every", 5))
	var unlock_all = skills.size() * every   # 全部解锁等级（8技能×5级=40）
	# 1) 解锁：已达标而未追加的技能补进技能栏
	@warning_ignore("integer_division")
	var unlocked = min(int(lv / every), skills.size())
	for i in range(unlocked):
		var sname: String = skills[i]
		var has_it = false
		for sk in h.aptitude_skills:
			if sk.name == sname:
				has_it = true
				break
		if not has_it:
			h.aptitude_skills.append({
				"name": sname,
				"level": 0,
				"max_level": base_cap,
				"aptitude_per_level": int(cfg.get("skill_aptitude_per_level", 2))
			})
	# 2) 上限提升：等级超过 unlock_all 后，第 k 档（k从1数）提升技能 (k-1)%skills.size()
	#    例（8技能）：45级→技能1、50级→技能2……80级→技能8、85级→回到技能1，循环
	@warning_ignore("integer_division")
	var k_max = int((lv - unlock_all) / cap_every)   # 已触发的提升档数（≤0 表示尚未开始）
	if k_max > 0:
		for i in range(skills.size()):
			# 技能 i（0起）被命中的档数：第 i+1、i+1+size、i+1+2×size... 档 ≤ k_max
			var count = 0
			if k_max > i:
				@warning_ignore("integer_division")
				count = int((k_max - 1 - i) / skills.size()) + 1
			var sname: String = skills[i]
			for sk in h.aptitude_skills:
				if sk.name == sname:
					sk.max_level = base_cap + count * bonus
					break

# ============ 加成计算（HeroData 聚合唯一入口调用） ============
# 风姿资质 = 风姿等级 × 每级资质（无上限）
func get_aptitude(hero_id: String) -> int:
	if not has_fengzi(hero_id): return 0
	return get_level(hero_id) * int(get_fengzi_cfg(hero_id).get("aptitude_per_level", 6))

# 风姿赚钱加成 = 已解锁技能数 × income_pct_per_unlock（全部解锁后封顶，之后只加上限）
func get_income_pct(hero_id: String) -> float:
	if not has_fengzi(hero_id): return 0.0
	var cfg = get_fengzi_cfg(hero_id)
	var skills: Array = cfg.get("skills", [])
	var every = int(cfg.get("skill_unlock_every", 5))
	@warning_ignore("integer_division")
	var unlocked = min(int(get_level(hero_id) / every), skills.size())
	return unlocked * float(cfg.get("income_pct_per_unlock", 0.05))
