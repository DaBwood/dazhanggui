# ============================================================
# 守护灵系统
# 职责：无双门客的守护灵培养（注灵升级/阶段解锁/技能升级/幻化形象）
# 数据存 g.guardian_spirits[hero_id]，旧档自动补初始化
# ============================================================
class_name GuardianSystem
extends RefCounted

var g  # GameData中枢

# 阶段配置（从guardian.json加载，保留代码默认值兜底）
var PHASES: Array = []
var AVATARS: Array = []

func _init(p_g):
	g = p_g
	_load_config()

# 【新增】加载守护灵配置
func _load_config():
	var d = g._load_json("res://data/guardian.json")
	PHASES = d.get("phases", PHASES)
	AVATARS = d.get("avatars", AVATARS)

# 【新增】初始化门客守护灵（仅无双门客，防重复）
func init_guardian(hero_id: String):
	if not g.heroes.has(hero_id): return
	if g.heroes[hero_id].get("quality", 0) != 2: return
	if g.guardian_spirits.has(hero_id): return
	var skills = []
	for phase in PHASES:
		skills.append({
			"name": phase.skill_name,
			"level": 0,
			"max_level": 400,
			"aptitude_per_level": phase.skill_apt
		})
	g.guardian_spirits[hero_id] = {
		"level": 0,
		"skills": skills,
		"avatar": "mingling",
		"avatars": {"mingling": true},
		"total_yulin_cost": 0   # 【新增】累计消耗蕴灵珏（每消耗1个+1资质）
	}

# 【新增】获取守护灵数据（空字典兜底）
func get_guardian(hero_id: String) -> Dictionary:
	return g.guardian_spirits.get(hero_id, {})

# ============ 注灵升级 ============

# 【新增】计算升级消耗：初始1级1个，每1000级+1
func get_level_up_cost(level: int) -> int:
	var s = g._guardian_configs.get("settings", {})
	var base = int(s.get("base_cost", 1))
	var inc_lv = int(s.get("cost_increment_level", 1000))
	var inc_amt = int(s.get("cost_increment_amount", 1))
	return base + int((level - 1) / float(inc_lv)) * inc_amt

# 【新增】根据等级反推累计消耗（旧档兼容用）
func _calc_total_yulin_cost(level: int) -> int:
	var total = 0
	for i in range(1, level):
		total += get_level_up_cost(i)
	return total

# 【新增】检查当前等级是否被阶段解锁条件锁住
func _is_level_blocked(hero_id: String) -> bool:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return true
	for i in range(PHASES.size() - 1):
		var phase = PHASES[i]
		var next_idx = i + 1
		# 当前等级 >= 该阶段full_level 且 < 下一阶段full_level
		if gs.level >= phase.full_level and gs.level < PHASES[next_idx].full_level:
			# 需要下一阶段解锁才能继续升
			if not is_phase_unlocked(hero_id, next_idx):
				return true
	return false

# 【新增】获取当前等级上限（被阶段解锁条件限制）
func get_level_cap(hero_id: String) -> int:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return 0
	for i in range(PHASES.size() - 1):
		var phase = PHASES[i]
		var next_idx = i + 1
		# 当前等级在该阶段范围内（含full_level边界）
		if gs.level >= phase.unlock_level and gs.level < PHASES[next_idx].full_level:
			# 如果下一阶段未解锁，上限=当前阶段full_level
			if not is_phase_unlocked(hero_id, next_idx):
				return phase.full_level
	return 6000

# 【改】判断是否可升级：加入阶段解锁条件检查
func can_level_up(hero_id: String) -> bool:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return false
	if gs.level >= 6000: return false
	# 【新增】阶段解锁条件检查
	if _is_level_blocked(hero_id): return false
	var cost = get_level_up_cost(gs.level)
	return g.items.get("yulin_jue", 0) >= cost

# 【改】升级守护灵（batch=true时十连，返回实际升级次数）
func level_up(hero_id: String, batch: bool = false) -> int:
	if not can_level_up(hero_id): return 0
	var gs = get_guardian(hero_id)
	var upgraded = 0
	var max_lv = 6000
	if batch:
		for i in range(10):
			if gs.level >= max_lv: break
			# 【新增】每级都检阶段锁（十连中途可能触顶）
			if _is_level_blocked(hero_id): break
			var cost = get_level_up_cost(gs.level)
			if g.items.get("yulin_jue", 0) < cost: break
			g.items["yulin_jue"] = int(g.items["yulin_jue"]) - cost
			gs.total_yulin_cost = int(gs.get("total_yulin_cost", 0)) + cost   # 【新增】累加消耗
			gs.level += 1
			upgraded += 1
	else:
		var cost = get_level_up_cost(gs.level)
		g.items["yulin_jue"] = int(g.items["yulin_jue"]) - cost
		gs.total_yulin_cost = int(gs.get("total_yulin_cost", 0)) + cost   # 【新增】累加消耗
		gs.level += 1
		upgraded = 1
	return upgraded

# ============ 阶段判断 ============

# 【新增】阶段是否完全注灵（等级达到该阶段full_level）
func is_phase_full(hero_id: String, phase_idx: int) -> bool:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return false
	if phase_idx < 0 or phase_idx >= PHASES.size(): return false
	return gs.level >= PHASES[phase_idx].full_level

# 【新增】阶段是否解锁（可显示/可激活）
# 胎元默认解锁；其余需：等级达标 + 前一阶段完全注灵 + 指定数量其他守护灵前一阶段完全注灵
func is_phase_unlocked(hero_id: String, phase_idx: int) -> bool:
	if phase_idx == 0: return true
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return false
	var phase = PHASES[phase_idx]
	# 等级条件
	if gs.level < phase.unlock_level: return false
	# 前一阶段完全注灵
	if gs.level < PHASES[phase_idx - 1].full_level: return false
	# 其他守护灵前一阶段完全注灵数量
	if phase.need_prev_count > 0:
		var count = _count_full_phase(phase_idx - 1)
		if count < phase.need_prev_count: return false
	return true

# 【新增】统计所有无双门客守护灵中，指定阶段完全注灵的数量
func _count_full_phase(phase_idx: int) -> int:
	var count = 0
	for hero_id in g.guardian_spirits.keys():
		if is_phase_full(hero_id, phase_idx):
			count += 1
	return count

# 【新增】获取所有完全注灵阶段的赚钱加成总和
func get_total_income_pct(hero_id: String) -> float:
	var total = 0.0
	for i in range(PHASES.size()):
		if is_phase_full(hero_id, i):
			total += PHASES[i].income_pct
	return total

# ============ 技能 ============

# 【改】守护灵技能总资质 = 基础资质(累计消耗蕴灵珏) + 技能资质
func get_total_aptitude(hero_id: String) -> int:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return 0
	var total = int(gs.get("total_yulin_cost", 0))   # 【新增】基础资质：每消耗1个蕴灵珏+1
	for skill in gs.skills:
		total += int(skill.level) * int(skill.aptitude_per_level)
	return total

# 【新增】升级守护灵技能（消耗资质丹，规则与门客资质技能完全一致）
func upgrade_skill(hero_id: String, skill_idx: int, batch: bool = false) -> int:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return 0
	if skill_idx < 0 or skill_idx >= gs.skills.size(): return 0
	# 阶段未解锁不能升级
	if not is_phase_unlocked(hero_id, skill_idx): return 0
	var skill = gs.skills[skill_idx]
	if int(skill.level) >= int(skill.max_level): return 0
	var cost_per = int(skill.aptitude_per_level)
	var pill = g.items.get("aptitude_pill", 0)
	if pill < cost_per: return 0
	var levels = 1
	if batch:
		var remaining = int(skill.max_level) - int(skill.level)
		levels = min(pill / cost_per, remaining)
	if levels > 0:
		g.items.aptitude_pill = int(g.items.aptitude_pill) - levels * cost_per
		skill.level = int(skill.level) + levels
	return levels

# ============ 幻化 ============

# 【新增】获取当前幻化加成（资质/赚钱%/同类光环%）
func get_avatar_bonus(hero_id: String) -> Dictionary:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return {"aptitude": 0, "income_pct": 0.0, "career_pct": 0.0}
	var avatar_id = gs.get("avatar", "mingling")
	for av in AVATARS:
		if av.id == avatar_id:
			return {
				"aptitude": int(av.get("aptitude", 0)),
				"income_pct": float(av.get("income_pct", 0.0)),
				"career_pct": float(av.get("career_pct", 0.0))
			}
	return {"aptitude": 0, "income_pct": 0.0, "career_pct": 0.0}

# 【新增】解锁幻化形象（消耗专属道具）
func unlock_avatar(hero_id: String, avatar_id: String) -> bool:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return false
	for av in AVATARS:
		if av.id == avatar_id:
			if av.get("is_default", false): return true
			var item_id = av.get("unlock_item", "")
			if item_id == "": return false
			if g.items.get(item_id, 0) <= 100: return false
			g.items[item_id] = int(g.items[item_id]) - 100
			gs.avatars[avatar_id] = true
			return true
	return false

# 【新增】切换当前幻化形象
func set_avatar(hero_id: String, avatar_id: String) -> bool:
	var gs = get_guardian(hero_id)
	if gs.is_empty(): return false
	if not gs.avatars.get(avatar_id, false): return false
	gs.avatar = avatar_id
	return true

# 【新增】同类门客光环：统计其他装备了非默认幻化的无双门客，给目标门客加career_pct
# （目标门客与幻化门客同category时才生效）
func get_career_bonus_for_hero(target_hero_id: String) -> float:
	if not g.heroes.has(target_hero_id): return 0.0
	var hero = g.heroes[target_hero_id]
	var category = hero.get("category", "")
	var total = 0.0
	for hid in g.guardian_spirits.keys():
		if hid == target_hero_id: continue  # 不算自己
		var gs = g.guardian_spirits[hid]
		var avatar_id = gs.get("avatar", "mingling")
		for av in AVATARS:
			if av.id == avatar_id and not av.get("is_default", false):
				if g.heroes.has(hid):
					var other = g.heroes[hid]
					if other.get("category", "") == category:
						total += float(av.get("career_pct", 0.0))
				break
	return total

# ============ 存档 ============

func get_save_data() -> Dictionary:
	return {"guardian_spirits": g.guardian_spirits}

func load_save_data(data: Dictionary):
	if data.has("guardian_spirits") and data.guardian_spirits is Dictionary:
		g.guardian_spirits = data.guardian_spirits
	# 【新增】旧档兼容：补 total_yulin_cost（根据等级反推累计消耗）
	for hero_id in g.guardian_spirits.keys():
		var gs = g.guardian_spirits[hero_id]
		if not gs.has("total_yulin_cost"):
			gs.total_yulin_cost = _calc_total_yulin_cost(gs.level)
	# 旧档兼容：为所有无双门客补初始化（已存在的不覆盖）
	for hero_id in g.heroes.keys():
		if g.heroes[hero_id].get("quality", 0) == 2:
			if not g.guardian_spirits.has(hero_id):
				init_guardian(hero_id)
