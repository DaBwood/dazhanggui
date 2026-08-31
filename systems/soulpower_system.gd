# ============================================================
# 魂力培养系统（2026-08-31 新增：珍兽魂体 + 魂骨装配）
# 纯逻辑模块：魂骨仓库统一存 GameData 中枢（g.soul_bones），魂体数据存珍兽实例 instance["hunli"]
# 配置外置 res://data/soulpower.json（g._soulpower_configs）
# 规则要点（数值表：魂骨.xlsx，2026-08-31 与用户逐条确认）：
#   魂体6槽位（头/左臂/右臂/躯干/左腿/右腿），初始解锁1个，其余免费无损解锁、不可回锁；
#   每槽装1块对应部位魂骨；魂骨5品级：百年/千年/万年/十万年/百万年
#   魂骨资质=阶×品级资质（5/10/30/80/200），升阶上限20阶，每阶吃对应晶核（13/5/4/2/1）；
#   百万年魂骨额外：赚钱每阶+10%
#   魂骨技能按品级固定（部位只是槽位区分）：赚钱技能加固定赚速、资质技能加资质；
#     技能上限50级，升级吃淬骨精尘（赚钱技能 星数×3/级，资质技能 星数×10/级）
#   魂体升级：每级60龙芝草、+6资质，上限200级
#   魂骨共鸣：按已装备魂骨数（1~6）给基础资质50~100，再乘印记倍率
#     （印记=装备魂骨品级对应数之和：百年1/千年4/万年5/十万年6/百万年7；≥4枚起每多1枚+0.1，不足4枚不惩罚×1.0）
#   回收：仓库魂骨按品级返还 对应晶核×1 + 淬骨精尘（120/540/1760/4220/8640）
#   全部加成只作用于该珍兽装备的门客（经 HeroData 三处接入，与兽魂同一接法）
# ============================================================
class_name SoulpowerSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免循环引用）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {
		"soul_bones": g.soul_bones,         # 魂骨仓库 {uid: {uid, slot, quality, tier, skills:{技能id:等级}}}
		"soul_bone_seq": g.soul_bone_seq,   # 魂骨uid自增序号
	}

# 从存档认领（老存档缺字段保持初始值；魂体在 beasts 实例 instance["hunli"] 里由 beast_system 存档天然覆盖）
func load_save_data(s: Dictionary):
	if s.has("soul_bones"): g.soul_bones = s.soul_bones.duplicate(true)
	if s.has("soul_bone_seq"): g.soul_bone_seq = int(s.soul_bone_seq)

# ============ 配置读取 ============
func _settings() -> Dictionary:
	return g._soulpower_configs.get("settings", {})

# 6个槽位id（顺序即配置顺序，显示用；解锁不分顺序）
func get_slots() -> Array:
	return _settings().get("slots", ["tou", "zuo_bi", "you_bi", "qu_gan", "zuo_tui", "you_tui"])

# 槽位显示名
func get_slot_name(slot: String) -> String:
	return _settings().get("slot_names", {}).get(slot, slot)

# 品级配置
func _quality_cfg(quality: String) -> Dictionary:
	return g._soulpower_configs.get("qualities", {}).get(quality, {})

# 技能配置
func _skill_cfg(skill_id: String) -> Dictionary:
	return g._soulpower_configs.get("skills", {}).get(skill_id, {})

# ============ 魂骨生成（魂骨盒子自选部位+品级） ============
# 生成一块魂骨入仓库：1阶、全部技能0级（技能吃淬骨精尘手动升级）
func gen_bone(slot: String, quality: String) -> Dictionary:
	if not get_slots().has(slot):
		return {}
	var qcfg = _quality_cfg(quality)
	if qcfg.is_empty():
		return {}
	var skills = {}
	for entry in qcfg.get("skills", []):
		skills[entry.get("id", "")] = 0   # 技能初始0级
	g.soul_bone_seq += 1
	var uid = "sb%d" % g.soul_bone_seq
	g.soul_bones[uid] = {"uid": uid, "slot": slot, "quality": quality, "tier": 1, "skills": skills}
	return g.soul_bones[uid]

# ============ 魂体（数据存珍兽实例 instance["hunli"]） ============
# 取魂体数据（首次访问自动初始化：level=魂体等级 / unlocked=已解锁槽位数组 / bones={槽位:魂骨uid}）
func _get_body(beast_id: String, instance_index: int = 0) -> Dictionary:
	var inst = g.beast_system.get_beast_instance(beast_id, instance_index)
	if inst == null:
		return {}
	if not inst.has("hunli") or not (inst["hunli"] is Dictionary):
		inst["hunli"] = {"level": 1, "unlocked": [get_slots()[0]], "bones": {}}
	var body: Dictionary = inst["hunli"]
	if not body.has("level"): body["level"] = 1
	if not body.has("unlocked") or not (body["unlocked"] is Array) or body["unlocked"].is_empty():
		body["unlocked"] = [get_slots()[0]]
	if not body.has("bones"): body["bones"] = {}
	return body

# 魂体等级
func get_body_level(beast_id: String, instance_index: int = 0) -> int:
	return int(_get_body(beast_id, instance_index).get("level", 1))

# 魂体升级：每级60龙芝草、+6资质，上限200级；times=连升次数，材料不足即停
func upgrade_body(beast_id: String, instance_index: int, times: int = 1) -> Dictionary:
	var body = _get_body(beast_id, instance_index)
	if body.is_empty():
		return {"ok": false, "reason": "珍兽不存在"}
	var max_lv = int(_settings().get("body_max_level", 200))
	var item: String = _settings().get("body_cost_item", "long_zhi_cao")
	var cost = int(_settings().get("body_level_cost", 60))
	var lv = int(body.get("level", 1))
	if lv >= max_lv:
		return {"ok": false, "reason": "魂体已满级"}
	var up = 0
	for _i in range(times):
		if lv >= max_lv:
			break
		if int(g.items.get(item, 0)) < cost:
			break
		g.items[item] = int(g.items.get(item, 0)) - cost
		lv += 1
		up += 1
	body["level"] = lv
	if up <= 0:
		return {"ok": false, "reason": "龙芝草不足（每级%d）" % cost}
	return {"ok": true, "up": up}

# 解锁槽位：免费无损，但不可回锁（填满有共鸣加成，全解开会让填满变难——已二次确认）
func unlock_slot(beast_id: String, instance_index: int, slot: String) -> Dictionary:
	if not get_slots().has(slot):
		return {"ok": false, "reason": "槽位无效"}
	var body = _get_body(beast_id, instance_index)
	var unlocked: Array = body.get("unlocked", [])
	if unlocked.has(slot):
		return {"ok": false, "reason": "该槽位已解锁"}
	unlocked.append(slot)
	return {"ok": true}

# ============ 装备 / 卸下 ============
# 魂骨是否已装在某只珍兽魂体上（扫全部珍兽实例）
func is_equipped(uid: String) -> bool:
	for bid in g.beasts.keys():
		var d = g.beasts[bid]
		var instances = d if d is Array else [d]
		for inst in instances:
			var body = inst.get("hunli", {})
			if body is Dictionary and body.get("bones", {}).values().has(uid):
				return true
	return false

# 装备魂骨到魂体：槽位须已解锁；该槽已有魂骨时自动无损换下（旧骨回仓库）
func equip_bone(beast_id: String, instance_index: int, uid: String) -> Dictionary:
	var bone = g.soul_bones.get(uid, {})
	if bone.is_empty():
		return {"ok": false, "reason": "魂骨不存在"}
	if is_equipped(uid):
		return {"ok": false, "reason": "该魂骨已装备在魂体上"}
	var body = _get_body(beast_id, instance_index)
	if body.is_empty():
		return {"ok": false, "reason": "珍兽不存在"}
	var slot: String = bone.get("slot", "")
	if not body.get("unlocked", []).has(slot):
		return {"ok": false, "reason": "该槽位未解锁"}
	body.get("bones", {})[slot] = uid   # 直接覆盖=旧骨自动换下回仓库（无损）
	return {"ok": true}

# 卸下魂骨（无损，魂骨回仓库）
func unequip_bone(beast_id: String, instance_index: int, slot: String) -> Dictionary:
	_get_body(beast_id, instance_index).get("bones", {}).erase(slot)
	return {"ok": true}

# ============ 魂骨养成 ============
# 升阶消耗查询（已满阶返回空表）
func get_tier_upgrade_cost(uid: String) -> Dictionary:
	var bone = g.soul_bones.get(uid, {})
	if bone.is_empty():
		return {}
	var max_tier = int(_settings().get("bone_max_tier", 20))
	if int(bone.get("tier", 1)) >= max_tier:
		return {}
	var qcfg = _quality_cfg(bone.get("quality", ""))
	return {"item": qcfg.get("core_item", ""), "cost": int(qcfg.get("core_cost", 1))}

# 魂骨升阶：每阶吃对应品级晶核（百年13/千年5/万年4/十万年2/百万年1），上限20阶
func upgrade_bone_tier(uid: String) -> Dictionary:
	var bone = g.soul_bones.get(uid, {})
	if bone.is_empty():
		return {"ok": false, "reason": "魂骨不存在"}
	var max_tier = int(_settings().get("bone_max_tier", 20))
	var tier = int(bone.get("tier", 1))
	if tier >= max_tier:
		return {"ok": false, "reason": "魂骨已满阶"}
	var cost_info = get_tier_upgrade_cost(uid)
	var item: String = cost_info.get("item", "")
	var cost = int(cost_info.get("cost", 1))
	if int(g.items.get(item, 0)) < cost:
		return {"ok": false, "reason": "%s不足（需要%d）" % [g.ITEM_CONFIG.get(item, {}).get("name", item), cost]}
	g.items[item] = int(g.items.get(item, 0)) - cost
	bone["tier"] = tier + 1
	return {"ok": true, "tier": tier + 1}

# 技能升级消耗（淬骨精尘：赚钱技能 星数×3/级，资质技能 星数×10/级；满级或无效返回0）
func get_skill_upgrade_cost(uid: String, skill_id: String) -> int:
	var bone = g.soul_bones.get(uid, {})
	if bone.is_empty():
		return 0
	var max_lv = int(_settings().get("skill_max_level", 50))
	if int(bone.get("skills", {}).get(skill_id, 0)) >= max_lv:
		return 0
	var star = 1
	for entry in _quality_cfg(bone.get("quality", "")).get("skills", []):
		if entry.get("id", "") == skill_id:
			star = int(entry.get("star", 1))
	return star * int(_skill_cfg(skill_id).get("cost_per_star", 3))

# 魂骨技能升级：上限50级
func upgrade_bone_skill(uid: String, skill_id: String) -> Dictionary:
	var bone = g.soul_bones.get(uid, {})
	if bone.is_empty():
		return {"ok": false, "reason": "魂骨不存在"}
	if not bone.get("skills", {}).has(skill_id):
		return {"ok": false, "reason": "该魂骨没有这个技能"}
	var cost = get_skill_upgrade_cost(uid, skill_id)
	if cost <= 0:
		return {"ok": false, "reason": "技能已满级"}
	var item: String = _settings().get("skill_cost_item", "cui_gu_jing_chen")
	if int(g.items.get(item, 0)) < cost:
		return {"ok": false, "reason": "淬骨精尘不足（需要%d）" % cost}
	g.items[item] = int(g.items.get(item, 0)) - cost
	bone["skills"][skill_id] = int(bone["skills"].get(skill_id, 0)) + 1
	return {"ok": true, "level": bone["skills"][skill_id]}

# 技能每级效果数值（entry 可带 value_per_level 覆盖 星数×per_star——百万年幻影突袭按表写死22500）
func get_skill_per_level_value(quality: String, skill_id: String) -> float:
	for entry in _quality_cfg(quality).get("skills", []):
		if entry.get("id", "") == skill_id:
			if entry.has("value_per_level"):
				return float(entry.get("value_per_level", 0))
			return int(entry.get("star", 1)) * float(_skill_cfg(skill_id).get("per_star", 0))
	return 0.0

# 回收魂骨：仅仓库魂骨可回收，返还 对应晶核×1 + 淬骨精尘（120/540/1760/4220/8640）
func recycle_bone(uid: String) -> Dictionary:
	var bone = g.soul_bones.get(uid, {})
	if bone.is_empty():
		return {"ok": false, "reason": "魂骨不存在"}
	if is_equipped(uid):
		return {"ok": false, "reason": "请先卸下再回收"}
	var qcfg = _quality_cfg(bone.get("quality", ""))
	var core: String = qcfg.get("core_item", "")
	var dust = int(qcfg.get("recycle_dust", 0))
	g.soul_bones.erase(uid)
	if core != "":
		g.items[core] = int(g.items.get(core, 0)) + 1
	var dust_item: String = _settings().get("skill_cost_item", "cui_gu_jing_chen")
	g.items[dust_item] = int(g.items.get(dust_item, 0)) + dust
	return {"ok": true, "core": core, "dust": dust}

# ============ 加成计算（供 HeroData 聚合，经 GameData 转发） ============
# 魂骨共鸣：已装备魂骨数→基础资质50~100；印记≥4枚起倍率=1+0.1×(印记-4)，不足4枚×1.0不惩罚
func get_resonance(beast_id: String, instance_index: int = 0) -> Dictionary:
	var body = _get_body(beast_id, instance_index)
	var bones: Dictionary = body.get("bones", {})
	var filled = 0
	var marks = 0
	for slot in bones.keys():
		var bone = g.soul_bones.get(bones[slot], {})
		if bone.is_empty():
			continue
		filled += 1
		marks += int(_quality_cfg(bone.get("quality", "")).get("mark", 0))
	var base = int(_settings().get("resonance_base", {}).get(str(filled), 0))
	var mark_base = int(_settings().get("mark_base", 4))
	var step = float(_settings().get("mark_step", 0.1))
	var mult = (1.0 + (marks - mark_base) * step) if marks >= mark_base else 1.0
	return {"filled": filled, "base": base, "marks": marks, "mult": mult, "apt": int(round(base * mult))}

# 魂体总加成：魂体等级×6资质 + 各魂骨(阶×品级资质 / 百万年阶×10%赚钱 / 技能) + 共鸣资质
func get_body_bonus(beast_id: String, instance_index: int = 0) -> Dictionary:
	var res = {"apt": 0, "income": 0, "percent": 0.0}
	var body = _get_body(beast_id, instance_index)
	if body.is_empty():
		return res
	res.apt += int(body.get("level", 1)) * int(_settings().get("body_apt_per_level", 6))
	for slot in body.get("bones", {}).keys():
		var bone = g.soul_bones.get(body["bones"][slot], {})
		if bone.is_empty():
			continue
		var qcfg = _quality_cfg(bone.get("quality", ""))
		var tier = int(bone.get("tier", 1))
		res.apt += tier * int(qcfg.get("apt_per_tier", 0))
		res.percent += tier * float(qcfg.get("income_pct_per_tier", 0.0))
		for entry in qcfg.get("skills", []):
			var sid: String = entry.get("id", "")
			var slv = int(bone.get("skills", {}).get(sid, 0))
			if slv <= 0:
				continue
			var val = get_skill_per_level_value(bone.get("quality", ""), sid) * slv
			if _skill_cfg(sid).get("type", "") == "income":
				res.income += int(val)
			else:
				res.apt += int(val)
	var rz = get_resonance(beast_id, instance_index)
	res.apt += int(rz.get("apt", 0))
	return res

# ===== 门客维度聚合（找该门客装备的珍兽 → 其魂体；HeroData 三处调用） =====
# 魂力资质加成（HeroData.get_total_aptitude 调用）
func get_hero_hunli_aptitude(hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var h = g.heroes[hero_id]
	var bid: String = h.get("equipped_beast", "")
	if bid == "": return 0
	return int(get_body_bonus(bid, int(h.get("equipped_beast_index", 0))).apt)

# 魂力固定赚速加成（HeroData.get_extra_income 调用）
func get_hero_hunli_income(hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var h = g.heroes[hero_id]
	var bid: String = h.get("equipped_beast", "")
	if bid == "": return 0
	return int(get_body_bonus(bid, int(h.get("equipped_beast_index", 0))).income)

# 魂力赚钱百分比加成（百万年魂骨 阶×10%；HeroData.get_percent_bonus 调用）
func get_hero_hunli_percent(hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	var h = g.heroes[hero_id]
	var bid: String = h.get("equipped_beast", "")
	if bid == "": return 0.0
	return float(get_body_bonus(bid, int(h.get("equipped_beast_index", 0))).percent)
