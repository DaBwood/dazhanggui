# ============================================================
# 天赋系统：所有门客通用【技能】页——鬼斧神工（星级制，一星~七星）
# 精进：消耗门客帖(hero_token)提升星级，需满足 门客等级 / N个门客达到M星(含本人) 条件
# 加成：固定赚钱/百分比赚钱为【替换制】——只取当前星级配置值，不累加
# 技能：每星级解锁一个技能（追加进 aptitude_skills：初始0级/上限200/每级资质=资质丹消耗）
# 独有天赋页：配置表未做好，本轮留空占位
# 纯逻辑模块：状态经 g 共享中枢；配置在 res://data/talent.json
# ============================================================
class_name TalentSystem
extends RefCounted

var g   # GameData 中枢引用（不标类型避免循环引用）

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 天赋存档：{hero_id: {"star": 星级}}
func get_save_data() -> Dictionary:
	return {"hero_talents": g.hero_talents}

func load_save_data(s: Dictionary):
	# 类型防御：旧档/异常档缺字段或为 null 时保持初始空表
	if s.has("hero_talents") and s.hero_talents is Dictionary:
		g.hero_talents = s.hero_talents.duplicate(true)
	# 【新增】读档后按星级幂等同步一遍解锁技能
	# （防中间态：星级已精进、技能没同步上；重复调用安全）
	for hero_id in g.hero_talents.keys():
		if g.heroes.has(hero_id):
			sync_skills(hero_id)

# ============ 配置查询 ============
# 某星级的配置（无则空字典；talent.json "stars" 段按星级字符串索引）
func get_star_cfg(star: int) -> Dictionary:
	return g._talent_configs.get("stars", {}).get(str(star), {})

# 星级上限（默认7星）
func get_max_star() -> int:
	return int(g._talent_configs.get("settings", {}).get("max_star", 7))

# 精进消耗道具（门客帖）
func get_cost_item() -> String:
	return g._talent_configs.get("settings", {}).get("cost_item", "hero_token")

# ============ 状态 ============
# 取天赋状态（星级），无记录则惰性初始化（仅在精进时实质写入存档）
func _get_state(hero_id: String) -> Dictionary:
	if not g.hero_talents.has(hero_id):
		g.hero_talents[hero_id] = {"star": 0}
	return g.hero_talents[hero_id]

# 当前星级（0=未精进；只读不写，避免面板刷新给全门客造空档）
func get_star(hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	if not g.hero_talents.has(hero_id): return 0
	return int(g.hero_talents[hero_id].get("star", 0))

# 达到≥star星的门客数量（含本人；四星起的精进条件用）
func get_heroes_at_least_star(star: int) -> int:
	var count = 0
	for hero_id in g.heroes.keys():
		if get_star(hero_id) >= star:
			count += 1
	return count

# ============ 加成计算（HeroData 聚合唯一入口调用，替换制不累加） ============
# 固定赚钱 = 当前星级配置的 flat_income（0星=0）
func get_flat_income(hero_id: String) -> int:
	var star = get_star(hero_id)
	if star <= 0: return 0
	return int(get_star_cfg(star).get("flat_income", 0))

# 百分比赚钱 = 当前星级配置的 income_pct（0星=0）
func get_income_pct(hero_id: String) -> float:
	var star = get_star(hero_id)
	if star <= 0: return 0.0
	return float(get_star_cfg(star).get("income_pct", 0.0))

# ============ 精进 ============
# 精进条件检查（不扣道具）：返回 {ok, reasons[]}，reasons=未满足项文案（UI红字提示用）
func get_refine_check(hero_id: String) -> Dictionary:
	var star = get_star(hero_id)
	var next = star + 1
	if next > get_max_star():
		return {"ok": false, "reasons": ["已达满星"]}
	var cfg = get_star_cfg(next)
	var reasons = []
	# 条件1：门客等级
	var h = g.heroes[hero_id]
	if int(h.level) < int(cfg.get("require_level", 0)):
		reasons.append("门客等级不足 Lv.%d/%d" % [int(h.level), int(cfg.get("require_level", 0))])
	# 条件2：N个门客达到M星（含本人；一星~三星配置为0，无此条件）
	var need_star = int(cfg.get("require_heroes_star", 0))
	var need_count = int(cfg.get("require_heroes_count", 0))
	if need_count > 0:
		var have = get_heroes_at_least_star(need_star)
		if have < need_count:
			reasons.append("%d个门客达到%d星（当前%d）" % [need_count, need_star, have])
	# 条件3：门客帖消耗
	var cost = int(cfg.get("cost", 0))
	if int(g.items.get(get_cost_item(), 0)) < cost:
		reasons.append("门客帖不足 %d/%d" % [int(g.items.get(get_cost_item(), 0)), cost])
	return {"ok": reasons.is_empty(), "reasons": reasons}

# 精进一星：条件全过→扣门客帖、星级+1、幂等同步解锁技能
func refine(hero_id: String) -> Dictionary:
	var check = get_refine_check(hero_id)
	if not check.ok:
		return {"ok": false, "reasons": check.reasons}
	var star = get_star(hero_id) + 1
	var cfg = get_star_cfg(star)
	g.items[get_cost_item()] = int(g.items.get(get_cost_item(), 0)) - int(cfg.get("cost", 0))
	_get_state(hero_id).star = star
	sync_skills(hero_id)
	return {"ok": true, "star": star}

# ============ 技能同步（幂等） ============
# 把≤当前星级的解锁技能按顺序追加进门客 aptitude_skills（按名字查重，不重复追加）：
# 初始0级 / 上限 settings.skill_max_level / 每级资质=资质丹固定消耗数
func sync_skills(hero_id: String):
	var star = get_star(hero_id)
	if star <= 0 or not g.heroes.has(hero_id): return
	var h = g.heroes[hero_id]
	var max_lv = int(g._talent_configs.get("settings", {}).get("skill_max_level", 200))
	for s in range(1, star + 1):
		var scfg = get_star_cfg(s)
		var sname: String = scfg.get("skill_name", "")
		if sname == "": continue
		var has_it = false
		for sk in h.aptitude_skills:
			if sk.name == sname:
				has_it = true
				break
		if not has_it:
			h.aptitude_skills.append({
				"name": sname,
				"level": 0,
				"max_level": max_lv,
				"aptitude_per_level": int(scfg.get("skill_aptitude_per_level", 1))
			})

# ============ 星级文本（门客面板标题用） ============
# 0星返回空串；>0 返回 ★×N（例：三星="★★★"）
func get_star_text(hero_id: String) -> String:
	var star = get_star(hero_id)
	var txt = ""
	for i in range(star):
		txt += "★"
	return txt
