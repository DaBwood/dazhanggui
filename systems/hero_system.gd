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
# 百业经验个人池 {hero_id: 数量}（2026-09-19 从 bank_system 归位：门客域资源，钱庄/酒肆/酒坊产出统一 add_baiye 入账）
var baiye: Dictionary = {}

# ============ 百业经验（门客域，2026-09-19 归位自 bank_system） ============
func get_baiye(hero_id: String) -> int:
	return int(baiye.get(hero_id, 0))

func add_baiye(hero_id: String, n: int):
	baiye[hero_id] = get_baiye(hero_id) + n

func get_baiye_total() -> int:
	var total := 0
	for k in baiye.keys():
		total += int(baiye[k])
	return total

# 兑换价配置暂留 bank.json settings（百业经验由钱庄 tick 产出，产出速率与兑换价同文件）；门客域读取
func get_baiye_per_pill() -> int:
	return int(g._bank_configs.get("settings", {}).get("baiye_per_pill", 300))

# 用百业经验抵扣 pills 颗资质丹（baiye_per_pill×pills 经验），成功扣池返回 true
func spend_baiye_for_pills(hero_id: String, pills: int) -> bool:
	var need := pills * get_baiye_per_pill()
	if get_baiye(hero_id) < need: return false
	baiye[hero_id] = get_baiye(hero_id) - need
	return true

func get_save_data() -> Dictionary:
	return {
		"heroes": g.heroes,   # 门客数据
		"hero_baiye": baiye,
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("heroes"):
		# 只覆盖存档里有的门客（保留老进度）；存档没有的新门客保持初始值
		g.heroes = s.heroes.duplicate(true)
		# 【新增】品质四档改造·旧档迁移（2026-09-21 拍板）：旧档 quality 语义 0=卓越/1=传奇/2=无双，
		# 新档 0=优秀/1=卓越/2=传奇/3=无双——旧档已写的 quality 整体+1（李白/白月初旧值0→新值1 卓越）；
		# 未写 quality 的（绝大多数门客）按 heroes.json 配置 born 值补齐（含上古神话6人=3 连带解锁守护灵）。
		# 迁移一次性：由中枢 quality_four_tiers 标记判定，迁移后置真，新档不再重复+1。
		if not g.quality_four_tiers:
			for hid in g.heroes.keys():
				var hh = g.heroes[hid]
				if hh.has("quality"):
					hh.quality = int(hh.quality) + 1
				# 晋升档位 quality 同步+1：旧档 promotion.tiers 存的是旧三档值（1传奇/2无双），
				# 不迁的话下次晋升升级会按旧值回写 hero.quality（传奇被写回成卓越）
				if hh.has("promotion") and hh.promotion.get("tiers", []) is Array:
					for tier in hh.promotion.tiers:
						if tier.has("quality"):
							tier.quality = int(tier.quality) + 1
			g.quality_four_tiers = true
		for hid in g.heroes.keys():
			if not g.heroes[hid].has("quality"):
				g.heroes[hid].quality = int(g._hero_configs.get(hid, {}).get("quality", 0))
			# 【新增】服装一键晋升（2026-09-24）：simple_promotion 解锁时拷贝，旧档缺键回灌；
			# 已达目标品质但缺赠送技能的老档补发（幂等，防配置调整或异常中断漏发）
			if g._hero_configs.get(hid, {}).has("simple_promotion"):
				if not g.heroes[hid].has("simple_promotion"):
					g.heroes[hid]["simple_promotion"] = g._hero_configs[hid]["simple_promotion"]
				var sp_cfg: Dictionary = g.heroes[hid]["simple_promotion"]
				# 【改】2026-09-24 stages 道具分档：按已达档位补发各档技能（按名查重幂等）
				if sp_cfg.get("stages", []).is_empty():
					if int(g.heroes[hid].get("quality", 0)) >= int(sp_cfg.get("target_quality", 2)):
						_grant_simple_promotion_skills(g.heroes[hid], sp_cfg)
				else:
					var cur_q: int = int(g.heroes[hid].get("quality", 0))
					for st in sp_cfg["stages"]:
						if cur_q >= int(st.get("quality", 2)):
							_grant_simple_promotion_skills(g.heroes[hid], st)
			# 【新增】赋诗晋升（2026-09-24）：promotion 块解锁时拷贝，旧档缺键回灌（王昭君落雁等；
			# level 从 0 开始，已达阈值档位品质由 quality 存量迁移保障，幂等）
			if g._hero_configs.get(hid, {}).has("promotion") and not g.heroes[hid].has("promotion"):
				g.heroes[hid]["promotion"] = g._hero_configs[hid]["promotion"]
			# 【新增】2026-09-25 极·XX之道回灌：品质≥3 门客（天生无双/老档已无双）自动补发（幂等，按名查重）
			ensure_ji_zhidao(hid)
			# 【新增】2026-09-25 自带极·XX之道上限 200→300 迁移（锦衣版带（锦衣）后缀，天然排除）
			for sk0 in g.heroes[hid].get("aptitude_skills", []):
				if str(sk0.get("name", "")).begins_with("极·") and not str(sk0.get("name", "")).ends_with("（锦衣）"):
					sk0["max_level"] = 300
		# 【新增】2026-09-24 读档回灌：为已拥有门客补发缺失的绑定珍兽（魅影兔：发放+形态技能同步，幂等）
		g.beast_system.sync_all_bound_beasts()
	# 【新增】存档迁移：旧档门客的 base_income 字段改名为 extra_income
	# （该字段实为"额外赚速池"，与基础赚速公式无关；旧档已攒数值原样保留，含旧版升级攒入的部分）
	for hero in g.heroes.values():
		if hero.has("base_income"):
			hero["extra_income"] = hero.get("extra_income", 0) + int(hero["base_income"])
			hero.erase("base_income")
	# 【新增】百业经验池：新键 hero_baiye；旧档从钱庄段 bank_baiye 收养（2026-09-19 域归位迁移）
	if s.has("hero_baiye") and s.hero_baiye is Dictionary:
		baiye = s.hero_baiye.duplicate(true)
	elif s.has("bank_baiye") and s.bank_baiye is Dictionary:
		baiye = s.bank_baiye.duplicate(true)

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
	# 【新增】2026-09-24 合并服装盒子待领库存（整份覆盖会清掉未拥有期间攒的库存）
	g.costume_system.merge_pending_cos(hero_id)
	ensure_ji_zhidao(hero_id)   # 【新增】2026-09-25 极·XX之道：天生无双门客新获时发放（幂等）
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
		var cost = int(ceil(900 * pow(1.0158, lv)))
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
		# 【第35节】升级10次：最多10级，算盘不够升剩余
		var remaining = mini(skill.max_level - skill.level, 10)
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
		# 【新增】2026-09-24 晋升跨形态阈值（30/80）时同步绑定珍兽形态与技能（幂等）
		g.beast_system.sync_bound_beast(hero_id)
	
	return upgraded

func _check_promotion(hero: Dictionary):
	if not hero.has("promotion"): return
	var promo = hero.promotion
	var lv = promo.level
	
	for tier in promo.tiers:
		if lv >= tier.threshold:
			if tier.has("quality"):
				hero.quality = tier.quality
			# 【删】2026-09-24 初始资质改由品质表决定（hero_data.get_initial_aptitude），tier 不再写
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
	# 【新增】2026-09-25 极·XX之道：晋升升档（含 80 级升无双）自动发放（幂等）
	_grant_ji_zhidao(hero)

# ============ 服装一键晋升（解鲁/四郎，2026-09-24 用户拍板） ============
# 轻量晋升：升级钮上方"晋升"按钮，集齐任一已解锁服装→亮红点，点击直接升目标品质+送技能，晋升后按钮消失
# 配置 = heroes.json "simple_promotion"：{name, target_quality, costume_need, skills:[{name, aptitude_per_level, max_level}]}
# 数据驱动：后续小舞/小柒/小八（传奇→无双）照搬配置改 target_quality 即可；与赋诗道具晋升（promotion 块）互斥不共存
func get_simple_promotion_cfg(hero_id: String) -> Dictionary:
	return g._hero_configs.get(hero_id, {}).get("simple_promotion", {})

# 当前应晋档位：stages 形式（兰飞鸿道具分档）取第一个品质高于当前品质的阶段；legacy 服装形式返回整档
func get_simple_promote_stage(hero_id: String) -> Dictionary:
	var sp: Dictionary = get_simple_promotion_cfg(hero_id)
	var stages: Array = sp.get("stages", [])
	if stages.is_empty(): return sp
	var q: int = int(g.heroes.get(hero_id, {}).get("quality", 0))
	for st in stages:
		if q < int(st.get("quality", 2)):
			return st
	return {}

# 档位条件是否满足：cost_item=道具消耗；condition.type=costume_any 任意已解锁服装数 / costume_mix 素装+华服组合（杨戬）
func simple_stage_met(hero_id: String, stage: Dictionary) -> bool:
	if stage.has("cost_item"):
		return int(g.items.get(stage.get("cost_item", ""), 0)) >= int(stage.get("cost_amount", 0))
	var cond: Dictionary = stage.get("condition", {})
	match str(cond.get("type", "")):
		"costume_any":
			return get_unlocked_costume_count(hero_id) >= int(cond.get("count", 1))
		"costume_mix":
			return g.costume_system.get_unlocked_cos_count_by_q(hero_id, "素装") >= int(cond.get("suzhuang", 0)) \
				and g.costume_system.get_unlocked_cos_count_by_q(hero_id, "华服") >= int(cond.get("huafu", 0))
	return false

# 已解锁服装数（与 costume_system.is_hero_cos_unlocked 同口径：任一件有 base 字段即算解锁；来源不限）
func get_unlocked_costume_count(hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var cos_dict: Dictionary = g.heroes[hero_id].get("costumes", {})
	var n := 0
	for cos_id in cos_dict.keys():
		var st = cos_dict[cos_id]
		if st is Dictionary and st.has("base"):
			n += 1
	return n

func can_simple_promote(hero_id: String) -> bool:
	var sp = get_simple_promotion_cfg(hero_id)
	if sp.is_empty() or not g.heroes.has(hero_id): return false
	# 【改】2026-09-24 stages 分档（道具/服装条件混合，杨戬：任意1件服装→4素装+1华服）；legacy 服装形式走原判断
	if not sp.get("stages", []).is_empty():
		var stage: Dictionary = get_simple_promote_stage(hero_id)
		return not stage.is_empty() and simple_stage_met(hero_id, stage)
	if int(g.heroes[hero_id].get("quality", 0)) >= int(sp.get("target_quality", 2)): return false
	return get_unlocked_costume_count(hero_id) >= int(sp.get("costume_need", 1))

func do_simple_promote(hero_id: String) -> Dictionary:
	if not can_simple_promote(hero_id):
		return {"ok": false, "reason": "晋升条件未满足"}
	var sp = get_simple_promotion_cfg(hero_id)
	var h = g.heroes[hero_id]
	# 【改】2026-09-24 道具分档：扣当前档消耗后升品质（无赠送技能，"没有其他花里胡哨"）
	if not sp.get("stages", []).is_empty():
		var stage: Dictionary = get_simple_promote_stage(hero_id)
		# 道具条件才扣消耗；服装类条件（杨戬）只校验不消耗
		if stage.has("cost_item"):
			var item_id: String = stage.get("cost_item", "")
			g.items[item_id] = int(g.items.get(item_id, 0)) - int(stage.get("cost_amount", 0))
		h.quality = int(stage.get("quality", 2))
		_grant_simple_promotion_skills(h, stage)   # 【新增】2026-09-24 该档解锁技能（按名查重幂等）
		ensure_ji_zhidao(hero_id)                  # 【新增】2026-09-25 极·XX之道：分档晋升升档自动发放（幂等）
		return {"ok": true, "quality": h.quality}
	h.quality = int(sp.get("target_quality", 2))
	_grant_simple_promotion_skills(h, sp)
	ensure_ji_zhidao(hero_id)   # 【新增】2026-09-25 极·XX之道：服装晋升升档自动发放（幂等）
	return {"ok": true, "quality": h.quality}

# 赠送技能按名查重幂等发放（晋升时刻与读档补发共用，防重复领取）
func _grant_simple_promotion_skills(h: Dictionary, sp: Dictionary):
	for sk in sp.get("skills", []):
		var has_it := false
		for old in h.aptitude_skills:
			if old.name == str(sk.get("name", "")):
				has_it = true
				break
		if not has_it:
			h.aptitude_skills.append({
				"name": sk.get("name", ""),
				"level": 0,
				"max_level": int(sk.get("max_level", 200)),
				"aptitude_per_level": int(sk.get("aptitude_per_level", 3)),
			})

# ============ 师徒光环（小八专属，2026-09-24 用户拍板） ============
# 光环配置在 hero_talents 对应门客条目的 "master_auras"；等级存英雄字典 "master_aura_levels"（初始1级，读档回灌默认）
# 拜师：master_hero_id 存英雄字典，限已拥有门客、可更换；广结良缘按师傅职业实时切换

func get_master_hero_id(hero_id: String) -> String:
	return str(g.heroes.get(hero_id, {}).get("master_hero_id", ""))

# 设定/更换师傅（限已拥有、不能拜自己；传空串=解除）
func set_master_hero_id(hero_id: String, master_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {"ok": false, "msg": "门客不存在"}
	if master_id == "":
		g.heroes[hero_id]["master_hero_id"] = ""
		return {"ok": true, "master": ""}
	if master_id == hero_id: return {"ok": false, "msg": "不能拜自己为师"}
	if not g.heroes.has(master_id): return {"ok": false, "msg": "师傅必须选择已拥有的门客"}
	# 【新增】2026-09-25 拜师池限定（小柒 master_pool="wuyan"）：只能拜师秦淮五艳
	if str(g.talent_system.get_hero_talent_cfg(hero_id).get("master_pool", "")) == "wuyan" and not is_wuyan(master_id):
		return {"ok": false, "msg": "只能拜师秦淮五艳门客"}
	g.heroes[hero_id]["master_hero_id"] = master_id
	return {"ok": true, "master": master_id}

func get_master_aura_cfgs(hero_id: String) -> Array:
	return g.talent_system.get_hero_talent_cfg(hero_id).get("master_auras", [])

func _get_master_aura_cfg(hero_id: String, aura_id: String) -> Dictionary:
	for a in get_master_aura_cfgs(hero_id):
		if a.get("id", "") == aura_id: return a
	return {}

# 光环等级表（读档自适应回灌，默认全 1 级）
func _get_master_aura_levels(hero_id: String) -> Dictionary:
	if not g.heroes[hero_id].has("master_aura_levels"):
		var d := {}
		for a in get_master_aura_cfgs(hero_id):
			d[a.get("id", "")] = 1
		g.heroes[hero_id]["master_aura_levels"] = d
	return g.heroes[hero_id]["master_aura_levels"]

func get_master_aura_level(hero_id: String, aura_id: String) -> int:
	return int(_get_master_aura_levels(hero_id).get(aura_id, 1))

# 等级上限：cap_by_promo=财商通达（晋升技能）每10级可升1级，初始1级 → 上限=技能等级÷10+1；道具消耗型不设数值上限
func get_master_aura_cap(hero_id: String, aura_cfg: Dictionary) -> int:
	if aura_cfg.get("cap_by_promo", false):
		var promo_lv := 0
		if g.heroes[hero_id].has("promotion"):
			promo_lv = int(g.heroes[hero_id]["promotion"].get("level", 0))
		return int(promo_lv / 10.0) + 1
	return 9999

# 下级消耗（道具型）：cost_base + floor((当前级-1)/step_every) × cost_step
# 【改】2026-09-25 支持 cost_step_every（师徒同心=每2级消耗+1）；缺省 every=1 即原线性公式，小八行为不变
func get_master_aura_cost(hero_id: String, aura_cfg: Dictionary) -> int:
	var lv := get_master_aura_level(hero_id, aura_cfg.get("id", ""))
	var every := maxi(int(aura_cfg.get("cost_step_every", 1)), 1)
	return int(aura_cfg.get("cost_base", 0)) + int(floor(float(lv - 1) / float(every))) * int(aura_cfg.get("cost_step", 0))

# 升级光环 times 级：校验上限与道具，消耗按级递增逐段累加
func upgrade_master_aura(hero_id: String, aura_id: String, times: int = 1) -> Dictionary:
	var aura := _get_master_aura_cfg(hero_id, aura_id)
	if aura.is_empty(): return {"ok": false, "msg": "光环不存在"}
	var lv := get_master_aura_level(hero_id, aura_id)
	var cap := get_master_aura_cap(hero_id, aura)
	if lv >= cap: return {"ok": false, "msg": "已达等级上限"}
	times = mini(times, cap - lv)
	var total_cost := 0
	var every_u := maxi(int(aura.get("cost_step_every", 1)), 1)
	for i in range(times):
		total_cost += int(aura.get("cost_base", 0)) + int(floor(float(lv + i - 1) / float(every_u))) * int(aura.get("cost_step", 0))
	if aura.has("cost_item"):
		var item_id := str(aura.get("cost_item", ""))
		if int(g.items.get(item_id, 0)) < total_cost:
			return {"ok": false, "msg": "道具不足"}
		g.items[item_id] = int(g.items.get(item_id, 0)) - total_cost
	_get_master_aura_levels(hero_id)[aura_id] = lv + times
	return {"ok": true, "level": lv + times}

# 师徒光环·资质加成：配置驱动遍历（童叟无欺/师徒同心——光环持有者本人与师傅各吃一份，HeroData.get_total_aptitude 追加）
# 【改】2026-09-25 去硬编码 aura id，按 type/target 走配置（小柒师徒同心同款生效，小八数值口径不变）
func get_master_aura_aptitude(hero_id: String) -> int:
	var total := 0
	for hid in g.heroes.keys():
		for aura in get_master_aura_cfgs(hid):
			if str(aura.get("type", "")) != "aptitude": continue
			if str(aura.get("target", "self_master")) != "self_master": continue
			if hid == hero_id or get_master_hero_id(hid) == hero_id:
				total += int(aura.get("per", 0)) * get_master_aura_level(hid, aura.get("id", ""))
	return total

# 师徒光环·赚钱%（get_percent_bonus 追加）：target=self_master（自身与师傅）/ master_career（师傅同职业门客）/ self（自身）
# 【改】2026-09-25 去硬编码 aura id，按 target 走配置（师从五艳同款生效，小八数值口径不变）
func get_master_aura_income_pct(hero_id: String) -> float:
	var total := 0.0
	var hero_cat := str(g.heroes.get(hero_id, {}).get("category", ""))
	for hid in g.heroes.keys():
		var master_id := get_master_hero_id(hid)
		for aura in get_master_aura_cfgs(hid):
			if str(aura.get("type", "")) != "income_pct": continue
			var n: float = float(aura.get("per", 0)) * get_master_aura_level(hid, aura.get("id", "")) / 100.0
			match str(aura.get("target", "")):
				"self_master":
					if hid == hero_id or master_id == hero_id:
						total += n
				"master_career":
					if master_id != "" and g.heroes.has(master_id) and hero_cat != "" \
						and hero_cat == str(g.heroes[master_id].get("category", "")):
						total += n
				"self":
					if hid == hero_id:
						total += n
	return total

# ============ 自带光环（小柒专属，2026-09-25 用户拍板；配置结构同师徒光环） ============
# 配置在 hero_talents 条目 "self_auras"；等级存英雄字典 "self_aura_levels"（初始1级，读档懒初始化）
# 无道具消耗：升级闸门 = 秦淮五艳对应系列光环总等级（玉蝶轻舞←勾栏美人 / 花影翩跹←绝代风华 / 云裳羽衣←群芳荟萃）
# gate 需求公式：mul/sub 型 = 当前级×mul−sub（玉蝶轻舞 ×2−2，1级首升需求0）；add 型 = 当前级+add（花影/云裳 +1）
# target：self=自身赚钱% / career=同职业门客赚钱%（含本人，同 career_pct 口径） / self_wuyan=小柒与秦淮五艳资质

func get_self_aura_cfgs(hero_id: String) -> Array:
	return g.talent_system.get_hero_talent_cfg(hero_id).get("self_auras", [])

func _get_self_aura_cfg(hero_id: String, aura_id: String) -> Dictionary:
	for a in get_self_aura_cfgs(hero_id):
		if a.get("id", "") == aura_id: return a
	return {}

# 光环等级表（读档自适应回灌，默认全 1 级）
func _get_self_aura_levels(hero_id: String) -> Dictionary:
	if not g.heroes[hero_id].has("self_aura_levels"):
		var d := {}
		for a in get_self_aura_cfgs(hero_id):
			d[a.get("id", "")] = 1
		g.heroes[hero_id]["self_aura_levels"] = d
	return g.heroes[hero_id]["self_aura_levels"]

func get_self_aura_level(hero_id: String, aura_id: String) -> int:
	return int(_get_self_aura_levels(hero_id).get(aura_id, 1))

# 五艳某光环总等级（闸门实际值）：遍历秦淮五艳按光环名累加系列光环等级（未拥有/无该技能跳过）
func get_self_aura_gate_total(aura_name: String) -> int:
	var total := 0
	for hid in get_wuyan_heroes():
		if not g.heroes.has(hid): continue
		for sk in g.talent_system.get_hero_aura_cfg(hid).get("skills", []):
			if str(sk.get("name", "")) == aura_name:
				total += g.talent_system.get_aura_level(hid, sk)
	return total

# 升级需求（当前级 k → 升 k+1 需五艳总等级 ≥ f(k)）
func get_self_aura_need(level: int, gate: Dictionary) -> int:
	if gate.has("mul"):
		return level * int(gate.get("mul", 1)) - int(gate.get("sub", 0))
	return level + int(gate.get("add", 1))

# 闸门状态：{"ok"/"total"/"need"}（光环页签卡片显示进度用）
func get_self_aura_gate(hero_id: String, aura: Dictionary) -> Dictionary:
	var lv := get_self_aura_level(hero_id, aura.get("id", ""))
	var gate: Dictionary = aura.get("gate", {})
	var need := get_self_aura_need(lv, gate)
	var total := get_self_aura_gate_total(str(gate.get("aura", "")))
	return {"ok": total >= need, "total": total, "need": need}

# 升级（无道具消耗，闸门即成本）
func upgrade_self_aura(hero_id: String, aura_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {"ok": false, "msg": "门客不存在"}
	var aura := _get_self_aura_cfg(hero_id, aura_id)
	if aura.is_empty(): return {"ok": false, "msg": "光环不存在"}
	var st := get_self_aura_gate(hero_id, aura)
	if not st.get("ok", false):
		return {"ok": false, "msg": "需五艳【%s】总等级≥%d（当前%d）" % [str(aura.get("gate", {}).get("aura", "")), int(st.get("need", 0)), int(st.get("total", 0))]}
	var lv := get_self_aura_level(hero_id, aura_id)
	_get_self_aura_levels(hero_id)[aura_id] = lv + 1
	return {"ok": true, "level": lv + 1}

# 自带光环·资质加成（云裳羽衣）：光环持有者（小柒）与秦淮五艳各吃一份（HeroData.get_total_aptitude 追加）
func get_self_aura_aptitude(hero_id: String) -> int:
	var total := 0
	for hid in g.heroes.keys():
		for aura in get_self_aura_cfgs(hid):
			if str(aura.get("type", "")) != "aptitude": continue
			if str(aura.get("target", "")) != "self_wuyan": continue
			var n: int = int(aura.get("per", 0)) * get_self_aura_level(hid, aura.get("id", ""))
			if hid == hero_id or is_wuyan(hero_id):
				total += n
	return total

# 自带光环·赚钱%（玉蝶轻舞=自身 / 花影翩跹=同职业含本人；get_percent_bonus 追加）
func get_self_aura_income_pct(hero_id: String) -> float:
	var total := 0.0
	var hero_cat := str(g.heroes.get(hero_id, {}).get("category", ""))
	for hid in g.heroes.keys():
		for aura in get_self_aura_cfgs(hid):
			if str(aura.get("type", "")) != "income_pct": continue
			var n: float = float(aura.get("per", 0)) * get_self_aura_level(hid, aura.get("id", "")) / 100.0
			match str(aura.get("target", "")):
				"self":
					if hid == hero_id:
						total += n
				"career":
					if hero_cat != "" and hero_cat == str(g.heroes[hid].get("category", "")):
						total += n
	return total

# ============ 极·XX之道（2026-09-25 用户拍板：全门客晋升无双自动发放） ============
# 品质≥3 自动获得资质技能【极·职业之道】：3★（3资质/级）、上限300、升级只吃对应职业之道书×300/级（不吃资质丹）
# 职业→书：side_skill.json career_books（士→仕途之道 … 侠→侠义之道），技能名="极·"+书道具名；88 门客全自动派生，无手写配置
# 发放点（幂等，按名查重）：load 回灌（天生无双/老档）/_check_promotion/do_simple_promote/凤临乐宴满级/凤魁转移/unlock_hero

# 核心发放（持英雄字典；品质≥3 且技能未拥有才发，返回是否新发放）
func _grant_ji_zhidao(hero: Dictionary) -> bool:
	if int(hero.get("quality", 0)) < 3: return false
	var book_id: String = g.side_skill_system.get_career_book(str(hero.get("category", "")))
	if book_id == "": return false
	var book_name: String = str(g.ITEM_CONFIG.get(book_id, {}).get("name", book_id))
	var skill_name: String = "极·" + book_name
	for sk in hero.get("aptitude_skills", []):
		if str(sk.get("name", "")) == skill_name: return false
	hero.aptitude_skills.append({
		"name": skill_name,
		"level": 0,
		"max_level": 300,
		"aptitude_per_level": 3,
		"cost_item": book_id,
		"cost_num": 300
	})
	return true

# 按 id 发放包装（发放点统一走这里，持字典场景直接调 _grant_ji_zhidao）
func ensure_ji_zhidao(hero_id: String) -> bool:
	if not g.heroes.has(hero_id): return false
	return _grant_ji_zhidao(g.heroes[hero_id])

# ============ 金兰（花木兰专属，2026-09-24 用户拍板） ============
# 花木兰晋升无双后可选一名已拥有门客（非自身，可重复选/随时解除更换）为金兰门客；
# 金兰门客获得花木兰 100% 风姿属性 = 风姿等级资质 + 技能栏风姿技能资质 + 风姿赚钱%
# 三个金兰光环：巾帼英风（自身赚钱+2%/级）/ 金兰义（双方资质+10/级）/ 同袍同泽（双方赚钱+2%/级）
# 光环上限 = floor(红妆缭乱风姿等级 / fengzi_per_level)，手动升级无道具消耗（风姿等级即成本）
# 配置 = heroes.json "jinlan"；存档 = 英雄字典 "jinlan" {"partner": id, "levels": {技能名: 级}}（懒初始化）
func get_jinlan_cfg(hero_id: String) -> Dictionary:
	return g._hero_configs.get(hero_id, {}).get("jinlan", {})

# 金兰存档状态（懒初始化，旧档无感）
func get_jinlan_state(hero_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {}
	var h = g.heroes[hero_id]
	if not h.has("jinlan"):
		h["jinlan"] = {"partner": "", "levels": {}}
		for sk in get_jinlan_cfg(hero_id).get("skills", []):
			h["jinlan"]["levels"][sk.get("name", "")] = 0
	return h["jinlan"]

# 光环等级上限 = floor(风姿等级 / fengzi_per_level)
func get_jinlan_cap(hero_id: String) -> int:
	var cfg = get_jinlan_cfg(hero_id)
	if cfg.is_empty() or not g.heroes.has(hero_id): return 0
	# 【修】风姿等级存 g.hero_fengzi[hero_id].level（fengzi_system 私有），必须走其 getter
	var lv = g.fengzi_system.get_level(hero_id)
	return int(lv / max(1, int(cfg.get("fengzi_per_level", 4))))

func is_jinlan_unlocked(hero_id: String) -> bool:
	return not get_jinlan_cfg(hero_id).is_empty() and int(g.heroes.get(hero_id, {}).get("quality", 0)) >= 3

func set_jinlan_partner(hero_id: String, partner_id: String) -> Dictionary:
	if not is_jinlan_unlocked(hero_id):
		return {"ok": false, "reason": "晋升无双后解锁"}
	if partner_id == "" or partner_id == hero_id or not g.heroes.has(partner_id):
		return {"ok": false, "reason": "不能选择自身或未拥有门客"}
	get_jinlan_state(hero_id)["partner"] = partner_id
	return {"ok": true}

func clear_jinlan_partner(hero_id: String):
	if g.heroes.has(hero_id) and g.heroes[hero_id].has("jinlan"):
		g.heroes[hero_id]["jinlan"]["partner"] = ""

func upgrade_jinlan_skill(hero_id: String, skill_name: String) -> Dictionary:
	if not is_jinlan_unlocked(hero_id):
		return {"ok": false, "reason": "晋升无双后解锁"}
	var st = get_jinlan_state(hero_id)
	if not st.get("levels", {}).has(skill_name):
		return {"ok": false, "reason": "技能不存在"}
	if int(st["levels"][skill_name]) >= get_jinlan_cap(hero_id):
		return {"ok": false, "reason": "已达当前上限（提升风姿等级可解锁更高级）"}
	st["levels"][skill_name] = int(st["levels"][skill_name]) + 1
	return {"ok": true}

# 花木兰风姿属性合计（金兰 100% 传递用）：风姿等级资质 + 技能栏风姿技能资质 + 风姿赚钱%
func get_fengzi_attr(hero_id: String) -> Dictionary:
	var apt: int = g.fengzi_system.get_aptitude(hero_id)
	var fz_names: Array = g.fengzi_system.get_fengzi_cfg(hero_id).get("skills", [])
	for sk in g.heroes.get(hero_id, {}).get("aptitude_skills", []):
		if fz_names.has(str(sk.get("name", ""))):
			apt += int(sk.get("level", 0)) * int(sk.get("aptitude_per_level", 0))
	return {"aptitude": apt, "income_pct": g.fengzi_system.get_income_pct(hero_id)}

# 谁把我设为金兰伙伴（反向查找；全游戏仅花木兰有金兰，循环极短）
func get_jinlan_owner(partner_id: String) -> String:
	for hid in g.heroes.keys():
		if hid == partner_id: continue
		if not is_jinlan_unlocked(hid): continue
		if str(g.heroes[hid].get("jinlan", {}).get("partner", "")) == partner_id:
			return hid
	return ""

# ── 加成挂钩（hero_data 赚钱%/总资质汇总调用，源点读取式）──
# 自身侧赚钱%：巾帼英风 + 同袍同泽
func get_jinlan_self_income_pct(hero_id: String) -> float:
	var cfg = get_jinlan_cfg(hero_id)
	if cfg.is_empty() or not is_jinlan_unlocked(hero_id): return 0.0
	var st = get_jinlan_state(hero_id)
	var pct := 0.0
	for sk in cfg.get("skills", []):
		var lv = int(st.get("levels", {}).get(sk.get("name", ""), 0))
		pct += lv * float(sk.get("self_income_pct", 0)) / 100.0
		pct += lv * float(sk.get("both_income_pct", 0)) / 100.0
	return pct

# 自身侧资质：金兰义
func get_jinlan_self_aptitude(hero_id: String) -> int:
	var cfg = get_jinlan_cfg(hero_id)
	if cfg.is_empty() or not is_jinlan_unlocked(hero_id): return 0
	var st = get_jinlan_state(hero_id)
	var apt := 0
	for sk in cfg.get("skills", []):
		apt += int(st.get("levels", {}).get(sk.get("name", ""), 0)) * int(sk.get("both_aptitude", 0))
	return apt

# 伙伴侧赚钱%：花木兰风姿赚钱 100% + 同袍同泽
func get_jinlan_partner_income_pct(partner_id: String) -> float:
	var owner = get_jinlan_owner(partner_id)
	if owner == "": return 0.0
	# 【修】percent_bonus 全口径为小数（0.02=2%，风姿 income_pct 本身就是小数）——光环配置值（2=2%）须 /100
	var pct := float(get_fengzi_attr(owner).get("income_pct", 0.0))
	var st = get_jinlan_state(owner)
	for sk in get_jinlan_cfg(owner).get("skills", []):
		pct += int(st.get("levels", {}).get(sk.get("name", ""), 0)) * float(sk.get("both_income_pct", 0)) / 100.0
	return pct

# 伙伴侧资质：花木兰风姿资质 100% + 金兰义
func get_jinlan_partner_aptitude(partner_id: String) -> int:
	var owner = get_jinlan_owner(partner_id)
	if owner == "": return 0
	var apt := int(get_fengzi_attr(owner).get("aptitude", 0))
	var st = get_jinlan_state(owner)
	for sk in get_jinlan_cfg(owner).get("skills", []):
		apt += int(st.get("levels", {}).get(sk.get("name", ""), 0)) * int(sk.get("both_aptitude", 0))
	return apt

# ============ 亲和（沉香专属，2026-09-25 用户拍板） ============
# 沉香晋升无双（历练80级）后解锁：选一名已拥有门客（非自身，可更换/解除）为亲和门客；
# 光环①动物亲和：只定义转化比例（初始40%、每级+40%，第k级=40k%），对沉香自身无独立效果；
# 光环②珍兽亲和：亲和门客获得"沉香装备珍兽提升的赚钱"×转化比例
#   （珍兽贡献=有兽总赚钱−无兽总赚钱，含珍兽资质/百分比、魂力、兽魂全部贡献，计算在 hero_data）；
# 光环升级：无道具消耗手动升；等级上限 = 1 + floor((开山斧决等级-80)/10)（斧决500满级→43级=1720%）
# 配置 = heroes.json "qinhe"；存档 = 英雄字典 "qinhe" {"partner": id, "aura_level": 级}（懒初始化，旧档无感）

func get_qinhe_cfg(hero_id: String) -> Dictionary:
	return g._hero_configs.get(hero_id, {}).get("qinhe", {})

# 亲和存档状态（懒初始化：解锁即 1 级=初始转化比例 40%）
func get_qinhe_state(hero_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {}
	var h = g.heroes[hero_id]
	if not h.has("qinhe"):
		h["qinhe"] = {"partner": "", "aura_level": 1}
	return h["qinhe"]

func is_qinhe_unlocked(hero_id: String) -> bool:
	return not get_qinhe_cfg(hero_id).is_empty() and int(g.heroes.get(hero_id, {}).get("quality", 0)) >= 3

# 光环等级上限 = 1 + floor((开山斧决等级-80)/10)；斧决未到 80 时上限 1（解锁即 1 级）
func get_qinhe_aura_cap(hero_id: String) -> int:
	var promo_lv := 0
	if g.heroes.has(hero_id):
		promo_lv = int(g.heroes[hero_id].get("promotion", {}).get("level", 0))
	@warning_ignore("integer_division")
	return maxi(1, 1 + int(maxi(0, promo_lv - 80) / 10))

# 转化比例（小数口径）：第k级 = ratio_base × k（配置 0.4=40%）
func get_qinhe_ratio(hero_id: String) -> float:
	var cfg = get_qinhe_cfg(hero_id)
	if cfg.is_empty(): return 0.0
	return float(cfg.get("ratio_base", 0.4)) * float(get_qinhe_state(hero_id).get("aura_level", 1))

func upgrade_qinhe_aura(hero_id: String) -> Dictionary:
	if not is_qinhe_unlocked(hero_id):
		return {"ok": false, "reason": "晋升无双后解锁"}
	var st = get_qinhe_state(hero_id)
	if int(st.get("aura_level", 1)) >= get_qinhe_aura_cap(hero_id):
		return {"ok": false, "reason": "已达当前上限（提升开山斧决等级可解锁更高级）"}
	st["aura_level"] = int(st.get("aura_level", 1)) + 1
	return {"ok": true}

func set_qinhe_partner(hero_id: String, partner_id: String) -> Dictionary:
	if not is_qinhe_unlocked(hero_id):
		return {"ok": false, "reason": "晋升无双后解锁"}
	if partner_id == "" or partner_id == hero_id or not g.heroes.has(partner_id):
		return {"ok": false, "reason": "不能选择自身或未拥有门客"}
	get_qinhe_state(hero_id)["partner"] = partner_id
	return {"ok": true}

func clear_qinhe_partner(hero_id: String):
	if g.heroes.has(hero_id) and g.heroes[hero_id].has("qinhe"):
		g.heroes[hero_id]["qinhe"]["partner"] = ""

# 谁把我设为亲和门客（反向查找；全游戏仅沉香有亲和，循环极短）
func get_qinhe_owner(partner_id: String) -> String:
	for hid in g.heroes.keys():
		if hid == partner_id: continue
		if not is_qinhe_unlocked(hid): continue
		if str(g.heroes[hid].get("qinhe", {}).get("partner", "")) == partner_id:
			return hid
	return ""

# 伙伴侧固定赚钱：沉香装备珍兽提升的赚钱 × 转化比例（读取式，hero_data.get_extra_income 调用）
func get_qinhe_income_bonus(partner_id: String) -> int:
	var owner = get_qinhe_owner(partner_id)
	if owner == "": return 0
	return int(HeroData.get_beast_income_contribution(g, owner) * get_qinhe_ratio(owner) + 0.5)

# ============ 双人光环（小舞专属，2026-09-24 用户拍板） ============
# 落日起誓（赚钱+5%/级，圣魂草 20+10×(k-1)）/ 三五组合（资质+10/级，圣魂草 10+(k-1)）：
# 配置 = hero_talents.json 该门客条目 "pair_auras"：{id, name, type, per, partner, cost_item, cost_base, cost_step}
# 等级存配置主（小舞）英雄字典 "pair_aura_levels"（懒初始化全 1 级，旧档读档即回灌，无需迁移）；
# 效果对配置主与 partner（杨戬）双方都生效；激活条件=拥有小舞；无等级上限；杨戬面板不显示光环卡（只进数值）

func get_pair_aura_cfgs(hero_id: String) -> Array:
	return g.talent_system.get_hero_talent_cfg(hero_id).get("pair_auras", [])

func _get_pair_aura_cfg(hero_id: String, aura_id: String) -> Dictionary:
	for a in get_pair_aura_cfgs(hero_id):
		if a.get("id", "") == aura_id: return a
	return {}

# 光环等级表（读档自适应回灌，默认全 1 级 = 初始一级）
func _get_pair_aura_levels(hero_id: String) -> Dictionary:
	if not g.heroes[hero_id].has("pair_aura_levels"):
		var d := {}
		for a in get_pair_aura_cfgs(hero_id):
			d[a.get("id", "")] = 1
		g.heroes[hero_id]["pair_aura_levels"] = d
	return g.heroes[hero_id]["pair_aura_levels"]

func get_pair_aura_level(hero_id: String, aura_id: String) -> int:
	return int(_get_pair_aura_levels(hero_id).get(aura_id, 1))

# 下级消耗：cost_base + (当前级-1) × cost_step
func get_pair_aura_cost(hero_id: String, aura_id: String) -> int:
	var aura := _get_pair_aura_cfg(hero_id, aura_id)
	return int(aura.get("cost_base", 0)) + (get_pair_aura_level(hero_id, aura_id) - 1) * int(aura.get("cost_step", 0))

# 升级光环 times 级（无上限）：逐级扣道具，不足升剩余（十连语义统一）；一级都升不动才报错
func upgrade_pair_aura(hero_id: String, aura_id: String, times: int = 1) -> Dictionary:
	var aura := _get_pair_aura_cfg(hero_id, aura_id)
	if aura.is_empty(): return {"ok": false, "msg": "光环不存在"}
	var lv := get_pair_aura_level(hero_id, aura_id)
	var item_id := str(aura.get("cost_item", ""))
	var upgraded := 0
	for i in range(maxi(1, times)):
		var cost: int = int(aura.get("cost_base", 0)) + (lv + upgraded - 1) * int(aura.get("cost_step", 0))
		if item_id != "" and int(g.items.get(item_id, 0)) < cost: break
		if item_id != "":
			g.items[item_id] = int(g.items.get(item_id, 0)) - cost
		upgraded += 1
	if upgraded <= 0:
		return {"ok": false, "msg": "道具不足"}
	_get_pair_aura_levels(hero_id)[aura_id] = lv + upgraded
	return {"ok": true, "level": lv + upgraded}

# 双人光环·资质：三五组合 per=10/级 → 配置主与 partner 各吃一份（HeroData.get_total_aptitude 追加）
func get_pair_aura_aptitude(hero_id: String) -> int:
	var total := 0
	for hid in g.heroes.keys():
		for a in get_pair_aura_cfgs(hid):
			if a.get("type", "") != "aptitude": continue
			var n: int = int(a.get("per", 0)) * get_pair_aura_level(hid, a.get("id", ""))
			if hid == hero_id or str(a.get("partner", "")) == hero_id:
				total += n
	return total

# 双人光环·赚钱%：落日起誓 per=5%/级（配置百分数口径，/100 转小数，percent_bonus 小数口径）
func get_pair_aura_income_pct(hero_id: String) -> float:
	var total := 0.0
	for hid in g.heroes.keys():
		for a in get_pair_aura_cfgs(hid):
			if a.get("type", "") != "income_pct": continue
			var n: float = float(a.get("per", 0)) * get_pair_aura_level(hid, a.get("id", "")) / 100.0
			if hid == hero_id or str(a.get("partner", "")) == hero_id:
				total += n
	return total

# ============ 凤魁（秦淮五艳晋升，2026-09-25） ============
# 机制：五艳全传奇时各自面板出"凤魁"按钮，确认选定后该门客成为凤魁——
#   获得金凤玲珑信物（tokens.json fengkui_only，存算分离自动发放）+ 凤魁晋升（凤临乐宴
#   6资质/级、凤游宴图600/级、上限80，30/50/80 解锁才貌双全3★/拈韵吟诗3★/度曲画兰4★，
#   80级 quality→3 升无双）；其余四人"凤魁"按钮消失、保持传奇。
# 状态：heroes.json 五人各有一份 fengkui 配置块（load 回灌进存档），选定只翻 chosen 开关，
#   技能等级存 fengkui.skills——配置跟人走，凤魁转移时整块搬迁即可（见 transfer_fengkui 留口）。

func get_wuyan_heroes() -> Array:
	return g.collection_system.get_wuyan_heroes()

func is_wuyan(hero_id: String) -> bool:
	return get_wuyan_heroes().has(hero_id)

# 当前凤魁门客 id（扫描五人的 fengkui.chosen），未选返回 ""
func get_fengkui_id() -> String:
	for hid in get_wuyan_heroes():
		if g.heroes.has(hid) and g.heroes[hid].get("fengkui", {}).get("chosen", false):
			return hid
	return ""

func can_choose_fengkui(hero_id: String) -> bool:
	if not is_wuyan(hero_id): return false
	if not g.heroes.has(hero_id): return false
	if int(g.heroes[hero_id].get("quality", 0)) != 2: return false
	return get_fengkui_id() == ""

# 凤魁配置块（heroes.json 五人各一份；load 回灌后存档自带，旧档缺键时从配置取兜底）
func _fengkui_cfg(hero_id: String) -> Dictionary:
	return g._hero_configs.get(hero_id, {}).get("fengkui", {})

# 选定凤魁：翻 chosen 开关 + 初始化技能等级表（信物由 has_token 存算分离即刻生效）
func choose_fengkui(hero_id: String) -> Dictionary:
	if not can_choose_fengkui(hero_id):
		return {"ok": false, "msg": "当前无法选定凤魁"}
	var hero = g.heroes[hero_id]
	if not hero.has("fengkui"):
		hero["fengkui"] = _fengkui_cfg(hero_id).duplicate(true)
	hero["fengkui"]["chosen"] = true
	if not hero["fengkui"].has("skills"):
		hero["fengkui"]["skills"] = {}
	_check_fengkui(hero)
	return {"ok": true}

# 凤魁晋升（凤临乐宴）升级：batch=false 升1级 / true 升10级（照 promotion 模板）
func upgrade_fengkui(hero_id: String, batch: bool = false) -> int:
	if hero_id != get_fengkui_id(): return 0
	var hero = g.heroes[hero_id]
	var promo = hero.get("fengkui", {})
	if promo.is_empty(): return 0
	if int(promo.get("level", 0)) >= int(promo.get("max_level", 80)): return 0
	var cost = int(promo.get("cost_amount", 600))
	var max_times = 1
	if batch:
		max_times = min(10, int(promo["max_level"]) - int(promo["level"]), int(g.items.get(promo.get("cost_item", ""), 0) / cost))
	else:
		if g.items.get(promo.get("cost_item", ""), 0) < cost: return 0
	if max_times <= 0: return 0
	var upgraded = 0
	for i in range(max_times):
		if int(promo["level"]) >= int(promo["max_level"]): break
		if g.items.get(promo.get("cost_item", ""), 0) < cost: break
		g.items[promo["cost_item"]] -= cost
		promo["level"] = int(promo["level"]) + 1
		upgraded += 1
		_check_fengkui(hero)
	return upgraded

# 阈值校验：30/50/80 登记解锁技能（等级0起），80 级升无双（quality=3）
func _check_fengkui(hero: Dictionary):
	if not hero.has("fengkui"): return
	var promo = hero["fengkui"]
	var lv = int(promo.get("level", 0))
	if not promo.has("skills"):
		promo["skills"] = {}
	for sk in promo.get("unlock_skills", []):
		if lv >= int(sk.get("threshold", 0)) and not promo["skills"].has(sk.get("name", "")):
			promo["skills"][sk["name"]] = 0
	if lv >= int(promo.get("max_level", 80)):
		hero.quality = 3   # 凤临乐宴满级晋升无双（初始资质由品质表决定自动涨）
		_grant_ji_zhidao(hero)   # 【新增】2026-09-25 极·XX之道：凤临乐宴满级升无双自动发放（幂等）

func get_fengkui_level(hero_id: String) -> int:
	return int(g.heroes.get(hero_id, {}).get("fengkui", {}).get("level", 0))

func _fengkui_skill_cfg(hero_id: String, skill_name: String) -> Dictionary:
	for sk in g.heroes.get(hero_id, {}).get("fengkui", {}).get("unlock_skills", []):
		if sk.get("name", "") == skill_name: return sk
	return {}

func get_fengkui_skill_level(hero_id: String, skill_name: String) -> int:
	return int(g.heroes.get(hero_id, {}).get("fengkui", {}).get("skills", {}).get(skill_name, -1))

# 凤魁技能升级：每级消耗=星级数颗资质丹，或百业经验抵扣（300/颗，use_baiye 互斥）；
# 上限200；需凤临乐宴已达对应解锁阈值。mode: single=1级 / bulk=10级（照服装技能模板）
func upgrade_fengkui_skill(hero_id: String, skill_name: String, mode: String = "single", use_baiye: bool = false) -> Dictionary:
	if hero_id != get_fengkui_id(): return {"ok": false, "msg": "仅凤魁可升级"}
	var promo = g.heroes[hero_id].get("fengkui", {})
	var sk = _fengkui_skill_cfg(hero_id, skill_name)
	if sk.is_empty(): return {"ok": false, "msg": "技能不存在"}
	if not promo.get("skills", {}).has(skill_name):
		return {"ok": false, "msg": "凤临乐宴 %d 级解锁" % int(sk.get("threshold", 0))}
	var cost = int(sk.get("stars", 1))
	var max_lv = int(sk.get("max_level", 200))
	var base = int(promo["skills"][skill_name])
	if base >= max_lv: return {"ok": false, "msg": "已满级"}
	var limit: int = 1 if mode == "single" else 10
	var levels = 0
	if use_baiye:
		var per_level: int = cost * get_baiye_per_pill()
		var affordable: int = floori(get_baiye(hero_id) / float(per_level))
		levels = min(mini(affordable, max_lv - base), limit)
		if levels <= 0: return {"ok": false, "msg": "百业经验不足"}
		if not spend_baiye_for_pills(hero_id, levels * cost):
			return {"ok": false, "msg": "百业经验不足"}
		promo["skills"][skill_name] = base + levels
		return {"ok": true, "levels": levels}
	var pills = int(g.items.get("aptitude_pill", 0))
	while base < max_lv and levels < limit:
		if pills < cost: break
		pills -= cost
		base += 1
		levels += 1
		if mode == "single": break
	if levels <= 0: return {"ok": false, "msg": "资质丹不足"}
	g.items["aptitude_pill"] = pills
	promo["skills"][skill_name] = base
	return {"ok": true, "levels": levels}

# 凤临乐宴本体资质（等级×每级资质，仅凤魁计入，hero_data 挂钩）
func get_fengkui_promo_aptitude(hero_id: String) -> int:
	if hero_id != get_fengkui_id(): return 0
	var promo = g.heroes[hero_id].get("fengkui", {})
	return int(promo.get("level", 0)) * int(promo.get("aptitude_per_level", 6))

# 凤魁技能资质合计（才貌双全/拈韵吟诗/度曲画兰 等级×星级；仅凤魁计入，hero_data 挂钩）
func get_fengkui_skill_aptitude(hero_id: String) -> int:
	if hero_id != get_fengkui_id(): return 0
	var total = 0
	for sk in g.heroes[hero_id]["fengkui"].get("unlock_skills", []):
		var lv = int(g.heroes[hero_id]["fengkui"].get("skills", {}).get(sk.get("name", ""), 0))
		total += lv * int(sk.get("stars", 0))
	return total

# 山河五岳页签数据：五件门客服装（cos03，属主各一），含解锁/兑换/升级所需状态
# 返回 [{owner, owner_name, cos_id, name, quality, unlocked, base, stock, pill_cost}]
func get_wuyue_cos_items() -> Array:
	var list = []
	for hid in get_wuyan_heroes():
		if not g.heroes.has(hid): continue
		var cos_id = "%s_cos03" % hid
		var cfg = g.costume_system._get_hero_cos_cfg(hid, cos_id)
		if cfg.is_empty(): continue
		var st = g.costume_system.get_hero_cos_state(hid, cos_id)
		list.append({
			"owner": hid,
			"owner_name": g.heroes[hid].get("name", ""),
			"cos_id": cos_id,
			"name": cfg.get("name", ""),
			"quality": cfg.get("quality", ""),
			"unlocked": st.has("base"),
			"base": int(st.get("base", 0)),
			"stock": int(g.heroes[hid].get("costumes", {}).get(cos_id, {}).get("stock", 0)),   # 库存存 hero.costumes[cos_id].stock
			"pill_cost": g.costume_system.get_cos_skill_cost(cfg.get("quality", "")),
		})
	return list

# 山河五岳服装技能资质合计（五件求和，仅凤魁计入，hero_data 挂钩；光环仍归各属主）
func get_wuyue_aptitude(hero_id: String) -> int:
	if hero_id != get_fengkui_id(): return 0
	var total = 0
	for item in get_wuyue_cos_items():
		total += g.costume_system.get_cos_skill_aptitude(item["owner"], item["cos_id"])
	return total

# 凤魁转移：fengkui 块（凤临乐宴等级/解锁技能等级/chosen）+ 金凤玲珑信物状态
# （g.hero_tokens 含信物等级/绑定门客/信物技能）整体搬迁至目标五艳门客；
# 品质跟随凤临乐宴等级（满80=无双3，否则传奇2），原门客退回传奇2——原门客不再显示凤魁钮，
# 信物由 has_token 的 fengkui_only 判定自动消失；山河五岳服装状态留在各属门客不动（资质自动跟随新凤魁）。
func transfer_fengkui(to_id: String) -> Dictionary:
	var from_id = get_fengkui_id()
	if from_id == "": return {"ok": false, "msg": "当前没有凤魁"}
	if not is_wuyan(to_id) or to_id == from_id: return {"ok": false, "msg": "只能转移给秦淮五艳门客"}
	if not g.heroes.has(to_id): return {"ok": false, "msg": "门客不存在"}
	var fk: Dictionary = g.heroes[from_id].get("fengkui", {})
	if fk.is_empty() or not fk.get("chosen", false): return {"ok": false, "msg": "凤魁状态缺失"}
	var lv: int = int(fk.get("level", 0))
	# ① fengkui 块整体搬迁（配置+进度跟人走）
	g.heroes[to_id]["fengkui"] = fk.duplicate(true)
	g.heroes[to_id]["fengkui"]["chosen"] = true
	g.heroes[from_id].erase("fengkui")
	# ② 品质跟随等级定档，原门客退回传奇
	g.heroes[to_id].quality = 3 if lv >= 80 else 2
	g.heroes[from_id].quality = 2
	ensure_ji_zhidao(to_id)   # 【新增】2026-09-25 极·XX之道：新凤魁定档无双自动发放（幂等）；from_id 降回传奇，已发技能保留不回收
	# ③ 金凤玲珑信物状态搬迁（等级/绑定/信物技能整体搬；五人只有这一件信物）
	if g.hero_tokens.has(from_id):
		g.hero_tokens[to_id] = g.hero_tokens[from_id]
		g.hero_tokens.erase(from_id)
	return {"ok": true, "from": from_id, "to": to_id}
