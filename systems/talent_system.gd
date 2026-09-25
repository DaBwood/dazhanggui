# ============================================================
# 天赋系统：所有门客通用【技能】页——鬼斧神工（星级制，一星~七星）
# 精进：消耗门客帖(hero_token)提升星级，需满足 门客等级 / N个门客达到M星(含本人) 条件
# 加成：固定赚钱/百分比赚钱为【替换制】——只取当前星级配置值，不累加
# 技能：每星级解锁一个技能（追加进 aptitude_skills：初始0级/上限200/每级资质=资质丹消耗）
# 独有天赋页：hero_talents.json（品质天赋三档，2026-09-21 定稿实装；批次⑤：效果数值随精进星级成长）
# 系列光环：hero_auras.json（7系列47门客，等级存 hero_aura_levels；人数档/flat/.极 实时计算不落盘）
# 两张分表由本系统成组自加载（仿 miaoyin 先例；孤儿扫描走 game_data.CONFIG_SPECIAL_LOADERS 登记）
# 纯逻辑模块：状态经 g 共享中枢；talent.json 由 SYSTEM_LIST 直挂 _talent_configs
# ============================================================
class_name TalentSystem
extends RefCounted

var g   # GameData 中枢引用（不标类型避免循环引用）

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 分表懒加载（hero_talents/hero_auras，仿 miaoyin 成组自加载先例） ============
const EXTRA_CFG_PATHS := {
	"hero_talents": "res://data/hero_talents.json",
	"hero_auras": "res://data/hero_auras.json",
}
var _extra_cfg: Dictionary = {}

func _extra(section: String) -> Dictionary:
	if not _extra_cfg.has(section):
		_extra_cfg[section] = _read_json(str(EXTRA_CFG_PATHS.get(section, "")))
	return _extra_cfg[section]

func _read_json(path: String) -> Dictionary:
	if path == "":
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var j = JSON.new()
	if j.parse(txt) != OK:
		return {}
	var d = j.get_data()
	if d is Dictionary:
		return d
	return {}

# ============ 存档：本系统拥有的字段 ============
# 天赋存档：{hero_id: {"star": 星级}}
func get_save_data() -> Dictionary:
	# 【新增】hero_aura_levels：系列光环 item 模式等级（人数档/flat/.极 实时计算不落盘）
	return {"hero_talents": g.hero_talents, "hero_aura_levels": g.hero_aura_levels}

func load_save_data(s: Dictionary):
	# 类型防御：旧档/异常档缺字段或为 null 时保持初始空表
	if s.has("hero_talents") and s.hero_talents is Dictionary:
		g.hero_talents = s.hero_talents.duplicate(true)
	# 【新增】系列光环等级（旧档缺字段保持空表，get_aura_level 读取式默认 0）
	if s.has("hero_aura_levels") and s.hero_aura_levels is Dictionary:
		g.hero_aura_levels = s.hero_aura_levels.duplicate(true)
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
	# 【新增】药铺勋章精进上限：追加时按 基础上限+勋章加成 写入（升级判定/UI 显示读 sk.max_level 自动生效）
	var max_lv = int(g._talent_configs.get("settings", {}).get("skill_max_level", 200)) + g.drugshop_system.get_refine_cap_bonus()
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

# 【新增】药铺勋章升级时调用：把天赋解锁技能的等级上限按差值整体提高（写入式，只加不减）
# 按技能名匹配（其他系统追加的同名词条不受影响——命中即天赋解锁技能）
func apply_skill_cap_delta(delta: int):
	if delta <= 0:
		return
	# 收集天赋解锁技能名集合（1~7星配置）
	var names := {}
	for s in range(1, get_max_star() + 1):
		var sname: String = get_star_cfg(s).get("skill_name", "")
		if sname != "":
			names[sname] = true
	for hero_id in g.heroes.keys():
		for sk in g.heroes[hero_id].aptitude_skills:
			if names.has(sk.name):
				sk.max_level = int(sk.max_level) + delta

# ============ 系列光环：升级链路（批次②） ============
# 解锁链判定：前置技能（unlock 字段同名技能）须满级；无前置=true
func is_aura_unlocked(hero_id: String, skill: Dictionary) -> bool:
	var unlock = str(skill.get("unlock", ""))
	if unlock == "": return true
	for sk in get_hero_aura_cfg(hero_id).get("skills", []):
		if str(sk.get("name", "")) == unlock:
			return get_aura_level(hero_id, sk) >= int(sk.get("max_level", 1))
	return false

# 升级条件检查（不扣道具）：返回 {ok, reasons[], cost, item_id}
# cost(k)=base+step*floor((k-1)/step_every)，k=目标等级（当前 lv→lv+1 即 k=lv+1 → floor(lv/step_every)）
func get_aura_upgrade_check(hero_id: String, skill: Dictionary) -> Dictionary:
	if str(skill.get("mode", "item")) != "item":
		return {"ok": false, "reasons": ["该档位不可手动升级"]}
	var lv = get_aura_level(hero_id, skill)
	if lv >= int(skill.get("max_level", 1)):
		return {"ok": false, "reasons": ["已满级"]}
	var reasons = []
	var acfg = get_hero_aura_cfg(hero_id)
	var unlock = str(skill.get("unlock", ""))
	if not is_aura_unlocked(hero_id, skill):
		reasons.append("需【%s】满级" % unlock)
	var cost_cfg: Dictionary = skill.get("cost", {})
	var step_every = maxi(int(cost_cfg.get("step_every", 1)), 1)
	var cost = int(cost_cfg.get("base", 0)) + int(cost_cfg.get("step", 0)) * floori(float(lv) / float(step_every))
	var item_id = str(acfg.get("item_id", ""))
	if int(g.items.get(item_id, 0)) < cost:
		var iname = str(g.ITEM_CONFIG.get(item_id, {}).get("name", item_id))
		reasons.append("%s不足 %d/%d" % [iname, int(g.items.get(item_id, 0)), cost])
	return {"ok": reasons.is_empty(), "reasons": reasons, "cost": cost, "item_id": item_id}

# 光环升级：mode=single 升1级 / bulk 十连升10次（不足升剩余，循环内逐级校验解锁链+消耗）
# 返回 {ok, msg, times, level}；times=0 时 msg=未满足原因（UI 红字提示）
func upgrade_aura(hero_id: String, skill_name: String, mode: String = "single") -> Dictionary:
	if not g.heroes.has(hero_id): return {"ok": false, "msg": "门客不存在"}
	var skill = null
	for sk in get_hero_aura_cfg(hero_id).get("skills", []):
		if str(sk.get("name", "")) == skill_name:
			skill = sk
			break
	if skill == null: return {"ok": false, "msg": "光环技能不存在"}
	var smode = str(skill.get("mode", ""))
	# .极档（手动升级）：门槛=同系列对应普通技能等级总和≥下级阈值；不满足返回提示文案（UI 红字）
	if smode == "series_total_level":
		if not is_aura_unlocked(hero_id, skill):
			return {"ok": false, "msg": "需【%s】满级" % str(skill.get("unlock", ""))}
		var p0 = get_aura_extreme_progress(hero_id, skill)
		if p0.next_need < 0:
			return {"ok": false, "msg": "已满级"}
		var max_times2 = 10 if mode == "bulk" else 1
		var times2 = 0
		if not g.hero_aura_levels.has(hero_id): g.hero_aura_levels[hero_id] = {}
		for i2 in range(max_times2):
			var lv2 = int(g.hero_aura_levels[hero_id].get(skill_name, 0))
			var p2 = get_aura_extreme_progress(hero_id, skill)
			if p2.total < p2.next_need: break
			g.hero_aura_levels[hero_id][skill_name] = lv2 + 1
			times2 += 1
		if times2 == 0:
			return {"ok": false, "msg": "同系列对应技能等级总和 %d/%d，未达下级需求" % [p0.total, p0.next_need]}
		return {"ok": true, "times": times2, "level": int(g.hero_aura_levels[hero_id].get(skill_name, 0))}
	if smode != "item": return {"ok": false, "msg": "该档位不可手动升级"}
	var max_times = 10 if mode == "bulk" else 1
	var times = 0
	if not g.hero_aura_levels.has(hero_id):
		g.hero_aura_levels[hero_id] = {}
	var lv_map: Dictionary = g.hero_aura_levels[hero_id]
	var item_id = str(get_hero_aura_cfg(hero_id).get("item_id", ""))
	var cost_cfg: Dictionary = skill.get("cost", {})
	var base = int(cost_cfg.get("base", 0))
	var step = int(cost_cfg.get("step", 0))
	var step_every = maxi(int(cost_cfg.get("step_every", 1)), 1)
	var max_lv = int(skill.get("max_level", 1))
	for i in range(max_times):
		var lv = int(lv_map.get(skill_name, 0))
		if lv >= max_lv: break
		if not is_aura_unlocked(hero_id, skill): break
		var cost = base + step * floori(float(lv) / float(step_every))
		if int(g.items.get(item_id, 0)) < cost: break
		g.items[item_id] = int(g.items.get(item_id, 0)) - cost
		lv_map[skill_name] = lv + 1
		times += 1
	if times == 0:
		var check = get_aura_upgrade_check(hero_id, skill)
		return {"ok": false, "msg": "；".join(check.get("reasons", ["无法升级"]))}
	return {"ok": true, "times": times, "level": int(lv_map.get(skill_name, 0))}

# ============ 星级文本（门客面板标题用） ============
# 0星返回空串；>0 返回 ★×N（例：三星="★★★"）
func get_star_text(hero_id: String) -> String:
	var star = get_star(hero_id)
	var txt = ""
	for i in range(star):
		txt += "★"
	return txt

# ============ 天赋/光环效果读取入口（批次③接线：读取式，乘在各系统源点） ============
# 生效天赋清单：只取当前品质档 tiers[当前档]，且该档不在 suspended_tiers（挂起档灰显不生效）
# 拍板（2026-09-21）：多档天赋非累积——当前品质体现对应档参数
func _active_talent_effects(hero_id: String) -> Array:
	var tcfg: Dictionary = get_hero_talent_cfg(hero_id)
	if tcfg.is_empty(): return []
	var tier: String = get_current_tier(hero_id)
	if tier == "": return []
	if tcfg.get("suspended_tiers", []).has(tier): return []
	return tcfg.get("tiers", {}).get(tier, [])

# 门客赚钱百分比（hero_data get_percent_bonus 调用）：
# career_pct=同职业门客 / all_hero_pct=全体门客 / series_pct=指定系列（系列归属取 hero_auras.json）
func get_hero_talent_pct(hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	var cat: String = str(g.heroes[hero_id].get("category", ""))
	var total = 0.0
	for hid in g.heroes.keys():
		for e in _active_talent_effects(hid):
			match str(e.get("kind", "")):
				"career_pct":
					if str(g.heroes[hid].get("category", "")) == cat:
						total += get_effect_value(e, hid)
				"all_hero_pct":
					total += get_effect_value(e, hid)
				"series_pct":
					if str(get_hero_aura_cfg(hero_id).get("series", "")) == str(e.get("series", "")):
						total += get_effect_value(e, hid)
	return total

# 系列光环赚钱百分比（hero_data get_percent_bonus 调用）：
# self_pct=自身 / career_pct=全体同职业门客（持有者本人也算同职业）；per 为百分制（5=5%）
func get_aura_pct(hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	var cat: String = str(g.heroes[hero_id].get("category", ""))
	var total = 0.0
	for hid in g.heroes.keys():
		if str(g.heroes[hid].get("category", "")) != cat: continue
		for sk in get_hero_aura_cfg(hid).get("skills", []):
			var kind = str(sk.get("effect", {}).get("kind", ""))
			# 【修】2026-09-25：self_pct 只加光环持有者本人（原实现把同职业所有人的"自身"光环也加进来，
			#       沉香等非系列门客平白吃到+50%，构成面板抓出）；career_pct 同职业共享为设计口径，不动
			if kind == "self_pct" and hid != hero_id: continue
			if kind == "self_pct" or kind == "career_pct":
				total += float(sk.get("effect", {}).get("per", 0)) * get_aura_level(hid, sk)
	return total

# 系列光环资质（hero_data get_total_aptitude 调用）：自身 series_aptitude 技能 等级×每级资质
func get_series_aptitude_bonus(hero_id: String) -> int:
	var total = 0
	for sk in get_hero_aura_cfg(hero_id).get("skills", []):
		if str(sk.get("effect", {}).get("kind", "")) == "series_aptitude":
			total += int(sk.get("effect", {}).get("per", 0)) * get_aura_level(hero_id, sk)
	return total

# copy_max_level（hero_data get_base_income / get_global_contribution 调用）：
# 复制源=全门客最高等级门客；2026-09-22 用户补拍板：等级和突破次数都复制（有效值=max(自身, 复制值)，等级受档上限约束）
func get_copy_stats(hero_id: String) -> Dictionary:
	for e in _active_talent_effects(hero_id):
		if str(e.get("kind", "")) == "copy_max_level":
			var top_hid = ""
			var top_lv = 0
			for hid in g.heroes.keys():
				if int(g.heroes[hid].get("level", 1)) > top_lv:
					top_lv = int(g.heroes[hid].get("level", 1))
					top_hid = hid
			if top_hid == "":
				return {"level": 0, "bt": 0}
			return {"level": mini(top_lv, int(e.get("cap", 0))), "bt": int(g.heroes[top_hid].get("breakthrough_count", 1))}
	return {}

# 复制等级（hero_page 有效等级显示/升级区隐藏判定）：0=非复制档
func get_copy_level(hero_id: String) -> int:
	return int(get_copy_stats(hero_id).get("level", 0))

# 虫师技能等级上限加成（cuzhi get_side_max_level 调用）：同职业拥有门客的 cap 求和
func get_worm_skill_cap_bonus(hero_cat: String) -> int:
	var total = 0
	for hid in g.heroes.keys():
		if str(g.heroes[hid].get("category", "")) != hero_cat: continue
		for e in _active_talent_effects(hid):
			if str(e.get("kind", "")) == "worm_skill_cap":
				total += int(get_effect_value(e, hid))
	return total

# 珍兽等级上限加成（beast get_beast_max_level 调用）：全体拥有门客的 cap 求和
func get_beast_level_cap_bonus() -> int:
	var total = 0
	for hid in g.heroes.keys():
		for e in _active_talent_effects(hid):
			if str(e.get("kind", "")) == "beast_level_cap":
				total += int(get_effect_value(e, hid))
	return total

# 商铺等级上限加成（shop_system 调用）：全体拥有门客的 cap 求和（沈万三·招财进宝）
func get_shop_level_cap_bonus() -> int:
	var total = 0
	for hid in g.heroes.keys():
		for e in _active_talent_effects(hid):
			if str(e.get("kind", "")) == "shop_level_cap":
				total += int(get_effect_value(e, hid))
	return total

# 徒弟赚速百分比（apprentice 收入乘区）：全体拥有门客的 pct 求和（10=10%，调用方 /100）
func get_apprentice_income_pct() -> float:
	var total = 0.0
	for hid in g.heroes.keys():
		for e in _active_talent_effects(hid):
			if str(e.get("kind", "")) == "apprentice_income_pct":
				total += get_effect_value(e, hid)
	return total

# 培养见识（阅历）百分比（apprentice train 发放处乘区）：全体拥有门客的 pct 求和（10=10%）
func get_apprentice_learn_pct() -> float:
	var total = 0.0
	for hid in g.heroes.keys():
		for e in _active_talent_effects(hid):
			if str(e.get("kind", "")) == "apprentice_learn_pct":
				total += get_effect_value(e, hid)
	return total

# 谈心缘分百分比（friend chat 乘区）：谈心挚友职业与门客职业相同即 +%（无绑定，可叠；10=10%）
func get_friend_chat_bond_pct(friend_category: String) -> float:
	var total = 0.0
	for hid in g.heroes.keys():
		if str(g.heroes[hid].get("category", "")) != friend_category: continue
		for e in _active_talent_effects(hid):
			if str(e.get("kind", "")) == "friend_chat_bond_pct":
				total += get_effect_value(e, hid)
	return total

# 活动出战同职业加成（war 战力路径）：该门客带 career_activity_pct 且活动命中时返回 pct，否则 0（5=5%）
func get_career_activity_pct(hero_id: String, activity: String) -> float:
	for e in _active_talent_effects(hero_id):
		if str(e.get("kind", "")) == "career_activity_pct":
			if e.get("activities", []).has(activity):
				return get_effect_value(e, hero_id)
	return 0.0

# 商战积分加成（war settle 乘区）：该门客 war_points_pct（25=25%）
func get_war_points_pct(hero_id: String) -> float:
	for e in _active_talent_effects(hero_id):
		if str(e.get("kind", "")) == "war_points_pct":
			return get_effect_value(e, hero_id)
	return 0.0
# token_shared（hero_page 信物面板调用）：返回共享配对门客 id；无共享天赋返回 ""
func get_token_shared_partner(hero_id: String) -> String:
	for e in _active_talent_effects(hero_id):
		if str(e.get("kind", "")) == "token_shared":
			for p in e.get("pair", []):
				if str(p) != hero_id:
					return str(p)
	return ""

# 未实装效果类型清单（批次④收口）：活动向 8 种实装前，天赋页当前档灰显"后续版本开放"
const UNWIRED_TALENT_KINDS: Array = ["friend_activity_talent_pct", "hero_activity_income_pct",
	"apprentice_quality_prob_pct", "banquet_popularity_pct", "activity_stat_pct", "activity_stat_flat",
	"zhaoshang_extra", "escort_free"]

func is_unwired_talent_kind(kind: String) -> bool:
	return UNWIRED_TALENT_KINDS.has(kind)

# ============ 天赋精进成长（批次⑤，2026-09-24 拍板：设计口径=精进方案设计之初即存在） ============
# 精进等级 = 鬼斧神工当前星级（沿用已有精进入口/门客帖/等级门槛，星级上限 7 天然封顶）
# 实际值 = 基础值 + 增量 × 精进等级；0 星 = 基础值（旧档无感兼容，读取仅防御 clamp 0~7）
# 增量来源：A/B 组按 kind 统一表 settings.refine_growth；D 组定制增量写效果条目 inc 字段；
# copy_max_level / token_shared 不可精进（不入表、无 inc，始终取基础值）
# 效果数值字段名表（kind → 基础值所在字段；未收录 kind = 不可精进或无数值）
const _EFFECT_VALUE_FIELD := {
	"career_pct": "pct", "all_hero_pct": "pct", "series_pct": "pct", "war_points_pct": "pct",
	"friend_chat_bond_pct": "pct", "apprentice_income_pct": "pct", "apprentice_learn_pct": "pct",
	"beast_level_cap": "cap", "worm_skill_cap": "cap", "shop_level_cap": "cap",
	"career_activity_pct": "pct", "activity_stat_pct": "pct", "activity_stat_flat": "value",
	"hero_activity_income_pct": "pct", "friend_activity_talent_pct": "pct", "banquet_popularity_pct": "pct",
	"zhaoshang_extra": "count", "escort_free": "count", "apprentice_quality_prob_pct": "pct",
}

# 精进等级（读取仅防御 clamp 0~7，拍板：不做旧档兼容专项）
func get_refine_level(hero_id: String) -> int:
	return clampi(get_star(hero_id), 0, 7)

# 某 kind 的统一增量（A/B 组读 settings.refine_growth；无则 0）
func get_refine_growth(kind: String) -> float:
	return float(get_talent_settings().get("refine_growth", {}).get(kind, 0))

# 数字显示：整数值去小数点（JSON float 防 "15.0"，光环页等级 int 化同款教训）
func _fmt_growth_num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)

# 单个效果的当前实际数值（读取式源点：批次③已接线 getter 统一经此取值，预览/实发同口径）
# 增量 = 条目 inc 字段（D 组定制）优先，缺省回退 kind 统一表（A/B 组）；不可精进 kind 增量=0
func get_effect_value(effect: Dictionary, hero_id: String) -> float:
	var field: String = _EFFECT_VALUE_FIELD.get(str(effect.get("kind", "")), "")
	if field == "":
		return 0.0
	var base: float = float(effect.get(field, 0))
	var inc: float = float(effect.get("inc", get_refine_growth(str(effect.get("kind", "")))))
	return base + inc * float(get_refine_level(hero_id))

# 独有天赋显示文案：desc 为设计期基础值文案，显示时把基础数值渲染为当前实际值
# （拍板 2026-09-24：玩家只看当前实际数值；基础数值定位失败退回原文，防御不炸）
func get_effect_desc(effect: Dictionary, hero_id: String) -> String:
	var kind: String = str(effect.get("kind", ""))
	var desc: String = str(effect.get("desc", ""))
	var field: String = _EFFECT_VALUE_FIELD.get(kind, "")
	if field == "":
		return desc
	var base: float = float(effect.get(field, 0))
	var inc: float = float(effect.get("inc", get_refine_growth(kind)))
	if inc <= 0.0 or get_refine_level(hero_id) <= 0:
		return desc
	var base_str: String = _fmt_growth_num(base)
	var at: int = desc.find(base_str)
	if at < 0:
		return desc
	# 【修】Godot4 String.replace 无 count 参数，首处替换用 find+substr 拼接实现
	return desc.substr(0, at) + _fmt_growth_num(base + inc * float(get_refine_level(hero_id))) + desc.substr(at + base_str.length())

# ============ 独有天赋配置查询（hero_talents.json） ============
# 门客天赋配置（无天赋门客返回空字典）
func get_hero_talent_cfg(hero_id: String) -> Dictionary:
	return _extra("hero_talents").get("heroes", {}).get(hero_id, {})

func get_talent_settings() -> Dictionary:
	return _extra("hero_talents").get("settings", {})

# 当前生效品质档：门客 quality（1卓越/2传奇/3无双）→ tier 键；优秀(0)=无天赋档返回空串
func get_current_tier(hero_id: String) -> String:
	if not g.heroes.has(hero_id): return ""
	return {1: "epic", 2: "legend", 3: "wushuang"}.get(int(g.heroes[hero_id].get("quality", 0)), "")

# ============ 系列光环（hero_auras.json） ============
func get_hero_aura_cfg(hero_id: String) -> Dictionary:
	return _extra("hero_auras").get("hero_auras", {}).get(hero_id, {})

func get_aura_series_cfg(series_key: String) -> Dictionary:
	return _extra("hero_auras").get("series", {}).get(series_key, {})

# 已招募系列门客数（人数档等级实时来源；不按等级递归，只看是否拥有）
func get_series_recruited_count(series_key: String) -> int:
	var count = 0
	var hero_auras: Dictionary = _extra("hero_auras").get("hero_auras", {})
	for hid in g.heroes.keys():
		if str(hero_auras.get(hid, {}).get("series", "")) == series_key:
			count += 1
	return count

# 光环技能当前等级：四模式分派——
# series_count=已招募系列门客数（实时）；flat=固定满级；series_total_level(.极)=同系列他人普通技能总和查阈值（实时）；
# item=读存档 hero_aura_levels（升级链路批次②接入，默认 0）
func get_aura_level(hero_id: String, skill: Dictionary) -> int:
	match str(skill.get("mode", "item")):
		"series_count":
			return get_series_recruited_count(str(get_hero_aura_cfg(hero_id).get("series", "")))
		"flat":
			return int(skill.get("max_level", 1))
		"series_total_level":
			# 【改】.极档=手动升级（2026-09-22 拍板）：等级存 hero_aura_levels，门槛=同系列对应普通技能等级总和查阈值
			return int(g.hero_aura_levels.get(hero_id, {}).get(str(skill.get("name", "")), 0))
		_:
			return int(g.hero_aura_levels.get(hero_id, {}).get(str(skill.get("name", "")), 0))

# .极档进度：同系列其他门客"对应普通技能"（去.极同名 item 技能）等级明细+总和+下级需求（手动升级门槛）
# 无等级上限（2026-09-22 拍板）：需求=thresholds[min(当前等级, 表末位)]，升穿表后沿用最后一档，实际闸门=其他门客技能等级
func get_aura_extreme_progress(hero_id: String, skill: Dictionary) -> Dictionary:
	var thresholds: Array = skill.get("thresholds", [])
	# 【改】.极档无等级上限（2026-09-22 拍板）：能升多少纯看其他门客对应技能等级；
	# 需求=thresholds[min(当前等级, 表末位)]——升穿阈值表后沿用最后一档（其他门客技能各有自身上限，实际封顶）
	var base_name = str(skill.get("name", "")).trim_suffix(".极")
	var series_key = str(get_hero_aura_cfg(hero_id).get("series", ""))
	var siblings: Array = []
	var total = 0
	var hero_auras: Dictionary = _extra("hero_auras").get("hero_auras", {})
	for hid in g.heroes.keys():
		if hid == hero_id: continue
		if str(hero_auras.get(hid, {}).get("series", "")) != series_key: continue
		var lv_map: Dictionary = g.hero_aura_levels.get(hid, {})
		var lv = 0
		for sk in hero_auras[hid].get("skills", []):
			if sk.get("mode", "") == "item" and str(sk.get("name", "")) == base_name:
				lv = int(lv_map.get(base_name, 0))
				break
		siblings.append({"id": hid, "name": str(g._hero_configs.get(hid, {}).get("name", hid)), "level": lv})
		total += lv
	var stored = int(g.hero_aura_levels.get(hero_id, {}).get(str(skill.get("name", "")), 0))
	var next_need = -1
	if not thresholds.is_empty():
		next_need = int(thresholds[mini(stored, thresholds.size() - 1)])
	return {"total": total, "siblings": siblings, "next_need": next_need, "max_level": -1, "stored": stored}

# .极档"?"说明文本：各门客对应技能等级明细 + 总和/下级需求
func get_aura_extreme_detail(hero_id: String, skill_name: String) -> Array:
	for sk in get_hero_aura_cfg(hero_id).get("skills", []):
		if str(sk.get("name", "")) == skill_name:
			var p = get_aura_extreme_progress(hero_id, sk)
			var lines2: Array = ["【%s】各门客对应技能等级：" % skill_name, ""]
			for sb in p.siblings:
				lines2.append("%s：Lv.%d" % [sb.name, sb.level])
			lines2.append("")
			if p.next_need < 0:
				lines2.append("已升至满级 Lv.%d" % p.stored)
			else:
				var state: String = "可升级" if p.total >= p.next_need else "未达成"
				lines2.append("对应技能等级总和 %d / 下级需求 %d（%s）" % [p.total, p.next_need, state])
			return lines2
	return []
