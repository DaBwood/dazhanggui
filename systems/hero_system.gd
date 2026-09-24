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
				if int(g.heroes[hid].get("quality", 0)) >= int(sp_cfg.get("target_quality", 2)):
					_grant_simple_promotion_skills(g.heroes[hid], sp_cfg)
			# 【新增】赋诗晋升（2026-09-24）：promotion 块解锁时拷贝，旧档缺键回灌（王昭君落雁等；
			# level 从 0 开始，已达阈值档位品质由 quality 存量迁移保障，幂等）
			if g._hero_configs.get(hid, {}).has("promotion") and not g.heroes[hid].has("promotion"):
				g.heroes[hid]["promotion"] = g._hero_configs[hid]["promotion"]
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

# ============ 服装一键晋升（解鲁/四郎，2026-09-24 用户拍板） ============
# 轻量晋升：升级钮上方"晋升"按钮，集齐任一已解锁服装→亮红点，点击直接升目标品质+送技能，晋升后按钮消失
# 配置 = heroes.json "simple_promotion"：{name, target_quality, costume_need, skills:[{name, aptitude_per_level, max_level}]}
# 数据驱动：后续小舞/小柒/小八（传奇→无双）照搬配置改 target_quality 即可；与赋诗道具晋升（promotion 块）互斥不共存
func get_simple_promotion_cfg(hero_id: String) -> Dictionary:
	return g._hero_configs.get(hero_id, {}).get("simple_promotion", {})

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
	if int(g.heroes[hero_id].get("quality", 0)) >= int(sp.get("target_quality", 2)): return false
	return get_unlocked_costume_count(hero_id) >= int(sp.get("costume_need", 1))

func do_simple_promote(hero_id: String) -> Dictionary:
	if not can_simple_promote(hero_id):
		return {"ok": false, "reason": "晋升条件未满足"}
	var sp = get_simple_promotion_cfg(hero_id)
	var h = g.heroes[hero_id]
	h.quality = int(sp.get("target_quality", 2))
	_grant_simple_promotion_skills(h, sp)
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
