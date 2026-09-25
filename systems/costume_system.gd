# ============================================================
# 服装系统（门客服装 + 挚友服装 + 系列服装光环）
# 纯逻辑模块：不碰场景节点；g = GameData 数据中枢
# 状态存放：门客服装状态存 heroes[id]["costumes"]、挚友服装状态存 friends[id]["costumes"]，
# 随门客/挚友系统存档，本系统无独立存档（get_save_data 返回空）
# 配置：res://data/costumes.json → g.costume_configs（由 GameData._load_all_configs 加载）
# ============================================================
class_name CostumeSystem
extends RefCounted

var g  # GameData 数据中枢引用

# 由 GameData._ready 创建本系统时注入引用
func _init(p_g):
	g = p_g

# ============ 存档（状态随门客/挚友字典，本系统无独立数据） ============
func get_save_data() -> Dictionary:
	return {"cos_pending": _cos_pending}   # 【改】2026-09-24 待领池落盘（原空字典占位）

func load_save_data(d: Dictionary):
	var p: Dictionary = d.get("cos_pending", {})
	if p == null: p = {}
	_cos_pending = p
	# 【新增】2026-09-25 服装版之道技能回灌：老档已解锁华服/锦衣的门客补发技能+重算上限（幂等）
	for hid0 in g.heroes.keys():
		refresh_cos_way_skill(hid0, "华服")
		refresh_cos_way_skill(hid0, "锦衣")

# ============ 配置访问 ============
# 服装总配置
func _cfgs() -> Dictionary:
	return g.costume_configs

# 数值设置
func _settings() -> Dictionary:
	return _cfgs().get("settings", {})

# 指定门客的服装配置表（无服装的门客返回空数组）
func get_hero_costume_cfgs(hero_id: String) -> Array:
	return _cfgs().get("hero_costumes", {}).get(hero_id, [])

# 指定挚友的服装配置表
func get_friend_costume_cfgs(friend_id: String) -> Array:
	return _cfgs().get("friend_costumes", {}).get(friend_id, [])

# 查门客服装配置条目
func _get_hero_cos_cfg(hero_id: String, cos_id: String) -> Dictionary:
	for cfg in get_hero_costume_cfgs(hero_id):
		if cfg.get("id", "") == cos_id: return cfg
	return {}

# 查挚友服装配置条目
func _get_friend_cos_cfg(friend_id: String, cos_id: String) -> Dictionary:
	for cfg in get_friend_costume_cfgs(friend_id):
		if cfg.get("id", "") == cos_id: return cfg
	return {}

# ============ 门客服装状态 ============
# 读取门客某件服装的养成状态 {base=资质丹等级(1-200), extra=服装额外等级, halo=光环等级}
# 未解锁返回空字典
func get_hero_cos_state(hero_id: String, cos_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {}
	return g.heroes[hero_id].get("costumes", {}).get(cos_id, {})

# 门客是否已解锁某件服装（有base字段才算解锁，仅有stock不算）
func is_hero_cos_unlocked(hero_id: String, cos_id: String) -> bool:
	return get_hero_cos_state(hero_id, cos_id).has("base")

# 服装技能总等级 = 资质丹等级 + 服装额外等级（额外等级在200满级之上）
# 未解锁（含只有stock无base）返回0
func get_cos_skill_level(hero_id: String, cos_id: String) -> int:
	var st = get_hero_cos_state(hero_id, cos_id)
	if not st.has("base"): return 0
	return int(st.get("base", 1)) + int(st.get("extra", 0))

# 服装技能资质 = 总等级 × 每级资质（素装2/华服2/锦衣3）
func get_cos_skill_aptitude(hero_id: String, cos_id: String) -> int:
	var cfg = _get_hero_cos_cfg(hero_id, cos_id)
	if cfg.is_empty(): return 0
	var per = int(_settings().get("apt_per_level", {}).get(cfg.get("quality", "素装"), 2))
	return get_cos_skill_level(hero_id, cos_id) * per

# ============ 门客服装兑换 ============
# 【改】兑换后只加库存(stock)，不自动解锁/升级，由玩家在门客面板手动操作
# 返回 {ok, msg}
func exchange_hero_costume(hero_id: String, cos_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {"ok": false, "msg": "尚未拥有该门客"}
	var cfg = _get_hero_cos_cfg(hero_id, cos_id)
	if cfg.is_empty(): return {"ok": false, "msg": "服装不存在"}
	var series_name = cfg.get("series", "")
	if series_name == "": return {"ok": false, "msg": "该服装暂未开放获取"}
	var series = _get_series_cfg(series_name)
	if series.is_empty(): return {"ok": false, "msg": "系列配置缺失"}
	var item_id = series.get("cost_item", "")
	var cost = int(_settings().get("exchange_cost", 100))
	if int(g.items.get(item_id, 0)) < cost:
		return {"ok": false, "msg": "%s不足（%d/%d）" % [series.get("item_name", item_id), int(g.items.get(item_id, 0)), cost]}
	g.items[item_id] = int(g.items.get(item_id, 0)) - cost
	# 初始化服装容器
	if not g.heroes[hero_id].has("costumes"):
		g.heroes[hero_id]["costumes"] = {}
	var cos_dict = g.heroes[hero_id]["costumes"]
	if not cos_dict.has(cos_id):
		cos_dict[cos_id] = {}
	var st = cos_dict[cos_id]
	st["stock"] = int(st.get("stock", 0)) + 1
	return {"ok": true, "msg": "获得【%s】×1，请在门客面板解锁" % cfg.get("name", cos_id)}

# 【新增】手动解锁服装：消耗1库存，创建 {base:1, extra:bonus, halo:0}
# 返回 {ok, msg}
func unlock_hero_cos(hero_id: String, cos_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {"ok": false, "msg": "尚未拥有该门客"}
	var st = get_hero_cos_state(hero_id, cos_id)
	if st.is_empty(): return {"ok": false, "msg": "尚未获得该服装"}
	if st.has("base"): return {"ok": false, "msg": "已解锁"}
	var stock = int(st.get("stock", 0))
	if stock < 1: return {"ok": false, "msg": "库存不足"}
	var cfg = _get_hero_cos_cfg(hero_id, cos_id)
	var bonus = int(_settings().get("unlock_bonus", {}).get(cfg.get("quality", "素装"), 10))
	st["stock"] = stock - 1
	st["base"] = 1
	st["extra"] = bonus
	st["halo"] = 0
	# 【新增】2026-09-25 服装版之道技能：华服/锦衣首件解锁时新增（refresh 内部按名查重+上限重算，幂等）
	refresh_cos_way_skill(hero_id, str(cfg.get("quality", "")))
	return {"ok": true, "msg": "解锁服装【%s】，额外等级+%d，获得同名光环技能" % [cfg.get("name", cos_id), bonus]}

# 【新增】手动升级服装（消耗库存加额外等级）：消耗1库存，extra+15
# 返回 {ok, msg}
func upgrade_hero_cos_extra(hero_id: String, cos_id: String) -> Dictionary:
	if not g.heroes.has(hero_id): return {"ok": false, "msg": "尚未拥有该门客"}
	var st = get_hero_cos_state(hero_id, cos_id)
	if not st.has("base"): return {"ok": false, "msg": "服装未解锁"}
	var stock = int(st.get("stock", 0))
	if stock < 1: return {"ok": false, "msg": "库存不足"}
	var bonus = int(_settings().get("dup_bonus", 15))
	st["stock"] = stock - 1
	st["extra"] = int(st.get("extra", 0)) + bonus
	# 【新增】2026-09-25 服装版之道技能：华服/锦衣升级加上限（公式重算，幂等）
	refresh_cos_way_skill(hero_id, str(_get_hero_cos_cfg(hero_id, cos_id).get("quality", "")))
	return {"ok": true, "msg": "【%s】额外等级+%d" % [_get_hero_cos_cfg(hero_id, cos_id).get("name", cos_id), bonus]}

# 【服装盒子】加库存（不自动解锁；解锁走 unlock_hero_cos 消耗1库存）。与 exchange 落库逻辑一致
func gain_hero_cos_stock(hero_id: String, cos_id: String, n: int = 1) -> Dictionary:
	var cos_cfg = _get_hero_cos_cfg(hero_id, cos_id)
	if cos_cfg.is_empty(): return {"ok": false, "msg": "服装不存在"}
	# 【改】2026-09-24 服装盒子不要求先拥有门客：未拥有时进待领池，招募时 merge_pending_cos 合并
	if not g.heroes.has(hero_id):
		if not _cos_pending.has(hero_id): _cos_pending[hero_id] = {}
		var pd: Dictionary = _cos_pending[hero_id]
		pd[cos_id] = int(pd.get(cos_id, 0)) + n
		return {"ok": true, "stock": pd[cos_id], "pending": true}
	# 与 exchange_hero_costume 落库一致：状态存在 g.heroes[hero_id]["costumes"][cos_id]
	if not g.heroes[hero_id].has("costumes"):
		g.heroes[hero_id]["costumes"] = {}
	var cos_dict = g.heroes[hero_id]["costumes"]
	if not cos_dict.has(cos_id):
		cos_dict[cos_id] = {}
	var st = cos_dict[cos_id]
	st["stock"] = int(st.get("stock", 0)) + n
	return {"ok": true, "stock": st["stock"]}

# ============ 服装盒子待领池（2026-09-24） ============
# 服装盒子不要求先拥有门客：未拥有时库存进待领池，hero_system.unlock_hero 招募时合并
# 存档字段 cos_pending = {hero_id: {cos_id: 库存}}
var _cos_pending: Dictionary = {}

# 已解锁服装按品质计数（杨戬晋升无双条件：4素装+1华服）
func get_unlocked_cos_count_by_q(hero_id: String, cos_quality: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var cos_dict: Dictionary = g.heroes[hero_id].get("costumes", {})
	var n := 0
	for cos_id in cos_dict.keys():
		var st = cos_dict[cos_id]
		if st is Dictionary and st.has("base"):
			var cfg = _get_hero_cos_cfg(hero_id, cos_id)
			if str(cfg.get("quality", "")) == cos_quality:
				n += 1
	return n

# 招募合并待领库存（跨系统入口：服装状态住本系统域，hero_system 招募时调用）
func merge_pending_cos(hero_id: String) -> void:
	if not g.heroes.has(hero_id): return
	if not _cos_pending.has(hero_id): return
	if not g.heroes[hero_id].has("costumes"):
		g.heroes[hero_id]["costumes"] = {}
	var cos_dict = g.heroes[hero_id]["costumes"]
	for cos_id in _cos_pending[hero_id].keys():
		if not cos_dict.has(cos_id): cos_dict[cos_id] = {}
		cos_dict[cos_id]["stock"] = int(cos_dict[cos_id].get("stock", 0)) + int(_cos_pending[hero_id][cos_id])
	_cos_pending.erase(hero_id)


# 【服装盒子】全服服装清单（含所属门客，供盒子选择弹窗用）
func get_all_cos_entries() -> Array:
	var out: Array = []
	for hero_id in _cfgs().get("hero_costumes", {}):
				# 【修】2026-09-24 名字查配置全量表（g.heroes 仅含已招募门客，未招募会兜底成 ID）
		var hero_name: String = g._hero_configs.get(hero_id, {}).get("name", hero_id)
		for cfg in _cfgs()["hero_costumes"][hero_id]:
			out.append({"hero_id": hero_id, "hero_name": hero_name,
				"cos_id": cfg.get("id", ""), "name": cfg.get("name", ""), "quality": cfg.get("quality", "")})
	return out

# ============ 服装技能升级（资质丹，升基础等级，上限=200+额外等级【第35节·模型B】） ============
#  【改】升下一级所需资质丹：固定消耗=该品质每级资质增量（素装2/华服2/锦衣3），不再随等级增长
func get_cos_skill_cost(quality: String = "素装") -> int:
	return int(_settings().get("apt_per_level", {}).get(quality, 2))

# 升级服装技能（base 部分）；mode: single=1级 / bulk=升级10次（资源/上限不够升剩余）
# 【第35节·改】base 上限固定200（模型B作废：extra 分离到服装页纯展示，不再扩展上限）
# use_baiye=true 时从百业经验个人池抵扣（每级=300×每级丹数）
# 返回 {ok, levels, msg}
func upgrade_cos_skill(hero_id: String, cos_id: String, mode: String = "single", use_baiye: bool = false) -> Dictionary:
	var st = get_hero_cos_state(hero_id, cos_id)
	if not st.has("base"): return {"ok": false, "msg": "服装未解锁"}
	var max_lv = int(_settings().get("skill_max_level", 200))
	var base = int(st.get("base", 1))
	if base >= max_lv: return {"ok": false, "msg": "已满级"}
	# 品质决定固定消耗（素装2/华服2/锦衣3），每级相同，提出循环只算一次
	var quality = _get_hero_cos_cfg(hero_id, cos_id).get("quality", "素装")
	var cost = get_cos_skill_cost(quality)
	var limit: int = 1 if mode == "single" else 10   # 【第35节】bulk=升级10次
	var levels = 0
	if use_baiye:
		# 百业经验抵扣：池够升多少升多少（bulk 封顶10级）
		var per_level: int = cost * g.hero_system.get_baiye_per_pill()
		var affordable: int = floori(g.hero_system.get_baiye(hero_id) / float(per_level))
		levels = min(mini(affordable, max_lv - base), limit)
		if levels <= 0: return {"ok": false, "msg": "百业经验不足"}
		if not g.hero_system.spend_baiye_for_pills(hero_id, levels * cost):
			return {"ok": false, "msg": "百业经验不足"}
		st["base"] = base + levels
		return {"ok": true, "levels": levels}
	var pills = int(g.items.get("aptitude_pill", 0))
	while base < max_lv and levels < limit:
		if pills < cost: break
		pills -= cost
		base += 1
		levels += 1
		if mode == "single": break
	if levels <= 0: return {"ok": false, "msg": "资质丹不足"}
	# 写回资质丹余量（pills 已在循环内逐级扣除）
	g.items["aptitude_pill"] = pills
	st["base"] = base
	return {"ok": true, "levels": levels}

# ============ 门客光环技能（玉璜升级） ============
# 光环等级上限 = min(100, 服装总等级×10)；未解锁返回0
func get_halo_cap(hero_id: String, cos_id: String) -> int:
	var st = get_hero_cos_state(hero_id, cos_id)
	if not st.has("base"): return 0
	var per = int(_settings().get("halo_cap_per_costume_level", 10))
	return min(int(_settings().get("halo_max_level", 100)), get_cos_skill_level(hero_id, cos_id) * per)

# 【修】整数除法警告：/10 → /10.0，结果再转 int，逻辑不变
func get_halo_cost(target_level: int) -> int:
	return int(_settings().get("halo_cost_base", 10)) + int(_settings().get("halo_cost_step", 5)) * int((target_level - 1) / 10.0)

# 升级光环；mode: single=1级 / bulk=升级10次（玉璜不够升剩余）
# 返回 {ok, levels, msg}
func upgrade_halo(hero_id: String, cos_id: String, mode: String = "single") -> Dictionary:
	var st = get_hero_cos_state(hero_id, cos_id)
	if not st.has("base"): return {"ok": false, "msg": "服装未解锁"}
	var cap = get_halo_cap(hero_id, cos_id)
	var lv = int(st.get("halo", 0))
	if lv >= cap:
		var max_lv = int(_settings().get("halo_max_level", 100))
		return {"ok": false, "msg": "已满级" if cap >= max_lv else "受服装等级限制（上限=服装等级×10）"}
	var stones = int(g.items.get("yu_huang", 0))
	if stones <= 0: return {"ok": false, "msg": "玉璜不足"}
	var levels = 0
	var limit: int = 1 if mode == "single" else 10   # 【第35节】bulk=升级10次
	while lv < cap and levels < limit:
		var cost = get_halo_cost(lv + 1)
		if stones < cost: break
		stones -= cost
		lv += 1
		levels += 1
		if mode == "single": break
	if levels <= 0: return {"ok": false, "msg": "玉璜不足"}
	g.items["yu_huang"] = stones
	st["halo"] = lv
	return {"ok": true, "levels": levels}

# ============ 资质/赚速加成汇总（HeroData 经 GameData 转发调用） ============
# 服装总资质 = 自身全部服装技能资质 + 同category所有门客的光环等级合计（含自身）
func get_hero_costume_aptitude(hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var total = 0
	# 自身服装技能资质（山河五岳系列除外：该系列集中到凤魁晋升页签，资质计入凤魁本人，2026-09-25）
	for cfg in get_hero_costume_cfgs(hero_id):
		if str(cfg.get("series", "")) == "山河五岳": continue
		total += get_cos_skill_aptitude(hero_id, cfg.get("id", ""))
	# 光环资质：同category门客的已解锁光环，每级+1（含自身）
	# 【改】跳过只有stock没有base的未解锁服装
	var my_cat = g.heroes[hero_id].get("category", "")
	var per = int(_settings().get("halo_apt_per_level", 1))
	for hid in g.heroes.keys():
		if g.heroes[hid].get("category", "") != my_cat: continue
		var cos_dict = g.heroes[hid].get("costumes", {})
		for cos_id in cos_dict.keys():
			if not cos_dict[cos_id].has("base"): continue   # 跳过未解锁的
			total += int(cos_dict[cos_id].get("halo", 0)) * per
	return total

# 服装系列百分比 = 每个已解锁系列（拥有≥1件即视为该系列成员）：
#   光环1 群体+3%×关联系列已解锁件数；光环2 自身+3%×该系列自己已解锁件数
func get_hero_costume_series_pct(hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	var group_pct = float(_settings().get("series_group_pct", 0.03))
	var self_pct = float(_settings().get("series_self_pct", 0.03))
	var total = 0.0
	for series in _cfgs().get("series", []):
		if series.get("owner_type", "hero") != "hero": continue
		var my_owned = _count_series_owned_by_hero(series, hero_id)
		if my_owned <= 0: continue
		# 光环1：群体加成（计数含关联系列，秦淮五艳系含挚友的山河五岳）
		var group_count = 0
		for sname in series.get("group_count_series", []):
			group_count += count_series_unlocked(sname)
		total += group_pct * group_count
		# 光环2：自身加成，每件+3%
		total += self_pct * my_owned
	return total

# 该门客在某系列中已解锁的服装件数
func _count_series_owned_by_hero(series: Dictionary, hero_id: String) -> int:
	var n = 0
	for m in series.get("members", []):
		if m.get("owner", "") != hero_id: continue
		var cfg = _find_cos_cfg_by_name(hero_id, m.get("costume", ""), false)
		if not cfg.is_empty() and is_hero_cos_unlocked(hero_id, cfg.get("id", "")):
			n += 1
	return n

# 某系列已解锁件数（门客系列数门客，挚友系列数挚友；用于光环1跨系列计数）
func count_series_unlocked(series_name: String) -> int:
	var series = _get_series_cfg(series_name)
	if series.is_empty(): return 0
	var n = 0
	var is_friend = series.get("owner_type", "hero") == "friend"
	for m in series.get("members", []):
		var cfg = _find_cos_cfg_by_name(m.get("owner", ""), m.get("costume", ""), is_friend)
		if cfg.is_empty(): continue
		if is_friend:
			if int(g.friends.get(m.get("owner", ""), {}).get("costumes", {}).get(cfg.get("id", ""), 0)) > 0:
				n += 1
		elif is_hero_cos_unlocked(m.get("owner", ""), cfg.get("id", "")):
			n += 1
	return n

# 按服装名反查配置条目（系列成员表按名字记录）
func _find_cos_cfg_by_name(owner_id: String, cos_name: String, is_friend: bool) -> Dictionary:
	var pool = get_friend_costume_cfgs(owner_id) if is_friend else get_hero_costume_cfgs(owner_id)
	for cfg in pool:
		if cfg.get("name", "") == cos_name: return cfg
	return {}

# 系列配置
func _get_series_cfg(series_name: String) -> Dictionary:
	for series in _cfgs().get("series", []):
		if series.get("name", "") == series_name: return series
	return {}

# ============ 挚友服装（只加友好/才华，无技能无光环） ============
# 挚友某服装已兑换件数
func get_friend_cos_copies(friend_id: String, cos_id: String) -> int:
	if not g.friends.has(friend_id): return 0
	return int(g.friends[friend_id].get("costumes", {}).get(cos_id, 0))

# 兑换挚友服装：消耗100个系列专属道具；首次按 unlock 档、重复按 dup 档直接加友好/才华
# 返回 {ok, msg}
func exchange_friend_costume(friend_id: String, cos_id: String) -> Dictionary:
	if not g.friends.has(friend_id): return {"ok": false, "msg": "尚未拥有该挚友"}
	var cfg = _get_friend_cos_cfg(friend_id, cos_id)
	if cfg.is_empty(): return {"ok": false, "msg": "服装不存在"}
	var series_name = cfg.get("series", "")
	if series_name == "": return {"ok": false, "msg": "该服装暂未开放获取"}
	var series = _get_series_cfg(series_name)
	if series.is_empty(): return {"ok": false, "msg": "系列配置缺失"}
	var item_id = series.get("cost_item", "")
	var cost = int(_settings().get("exchange_cost", 100))
	if int(g.items.get(item_id, 0)) < cost:
		return {"ok": false, "msg": "%s不足（%d/%d）" % [series.get("item_name", item_id), int(g.items.get(item_id, 0)), cost]}
	g.items[item_id] = int(g.items.get(item_id, 0)) - cost
	if not g.friends[friend_id].has("costumes"):
		g.friends[friend_id]["costumes"] = {}
	var copies = get_friend_cos_copies(friend_id, cos_id)
	# 首次用 unlock 档，重复用 dup 档（[友好, 才华]）
	var table = _settings().get("friend_unlock" if copies == 0 else "friend_dup", {})
	var gain = table.get(cfg.get("quality", "素装"), [300, 300])
	g.friends[friend_id].friendly += int(gain[0])
	g.friends[friend_id].talent += int(gain[1])
	g.friends[friend_id]["costumes"][cos_id] = copies + 1
	if copies == 0:
		return {"ok": true, "msg": "解锁服装【%s】，友好+%d 才华+%d" % [cfg.get("name", cos_id), int(gain[0]), int(gain[1])]}
	return {"ok": true, "msg": "【%s】友好+%d 才华+%d" % [cfg.get("name", cos_id), int(gain[0]), int(gain[1])]}

# ============ 服装版之道技能（2026-09-25 用户拍板：华服→XX之道（华服）、锦衣→极·XX之道（锦衣）） ============
# 与自带版同名共存的额外资质技能（方案B后缀命名），进【技能】页签；数值同自带版：华服版 1★（+1资质/级）吃职业道书100/级，锦衣版 3★（+3资质/级）吃书300/级
# 技能字典带 cost_item/cost_num 走 hero_page 通用书消耗/own 显示分支；上限公式=服装技能同款数值：新解锁+unlock_bonus（华服20/锦衣30）、每次升级+dup_bonus（15），无封顶
# 发放点：unlock_hero_cos 首件解锁/upgrade_hero_cos_extra 升级（refresh 幂等）；load_save_data 回灌老档

# 某品质服装的解锁件数与升级次数（升级次数=(extra-unlock_bonus)/dup_bonus，extra 由升级函数唯一写入）
func _cos_way_stats(hero_id: String, quality: String) -> Dictionary:
	var unlocked := 0
	var ups := 0
	var ub: int = int(_settings().get("unlock_bonus", {}).get(quality, 0))
	var db: int = int(_settings().get("dup_bonus", 15))
	for cos_id in g.heroes.get(hero_id, {}).get("costumes", {}):
		var cfg := _get_hero_cos_cfg(hero_id, cos_id)
		if cfg.is_empty() or str(cfg.get("quality", "")) != quality: continue
		if not is_hero_cos_unlocked(hero_id, cos_id): continue
		unlocked += 1
		ups += floori(float(maxi(int(get_hero_cos_state(hero_id, cos_id).get("extra", 0)) - ub, 0)) / float(db))
	return {"unlocked": unlocked, "ups": ups}

# 服装版之道技能当前上限（公式值；0=无对应已解锁服装，技能不应存在）
func get_cos_way_cap(hero_id: String, quality: String) -> int:
	var s: Dictionary = _cos_way_stats(hero_id, quality)
	return int(_settings().get("unlock_bonus", {}).get(quality, 0)) * int(s.get("unlocked", 0)) + int(_settings().get("dup_bonus", 15)) * int(s.get("ups", 0))

# 服装版技能模板（quality=华服/锦衣；按职业书派生名字，与自带版同名共存靠（华服）/（锦衣）后缀区分）
func _cos_way_skill_base(hero_id: String, quality: String) -> Dictionary:
	var hero: Dictionary = g.heroes.get(hero_id, {})
	var book_id: String = g.side_skill_system.get_career_book(str(hero.get("category", "")))
	if book_id == "": return {}
	var book_name: String = str(g.ITEM_CONFIG.get(book_id, {}).get("name", book_id))
	var is_ji: bool = quality == "锦衣"
	return {
		"name": ("极·" if is_ji else "") + book_name + ("（锦衣）" if is_ji else "（华服）"),
		"level": 0,
		"max_level": 0,
		"aptitude_per_level": 3 if is_ji else 1,
		"cost_item": book_id,
		"cost_num": 300 if is_ji else 100,
		"cos_way": quality
	}

# 刷新服装版之道技能：上限重算为公式值；首件解锁时新增技能（按名查重，幂等）；公式值≤0 时不创建
func refresh_cos_way_skill(hero_id: String, quality: String) -> void:
	if quality != "华服" and quality != "锦衣": return
	if not g.heroes.has(hero_id): return
	var base := _cos_way_skill_base(hero_id, quality)
	if base.is_empty(): return
	var cap := get_cos_way_cap(hero_id, quality)
	var hero: Dictionary = g.heroes[hero_id]
	var found: Dictionary = {}
	for sk in hero.aptitude_skills:
		if str(sk.get("name", "")) == base["name"]:
			found = sk
			break
	if found.is_empty():
		if cap <= 0: return
		base["max_level"] = cap
		hero.aptitude_skills.append(base)
	else:
		found["max_level"] = cap
