class_name CollectionSystem
extends RefCounted

# ============================================================
# 藏品系统：藏宝阁（合成/升级/晋升）+ 套装（手动激活）+ 淘宝（抽奖）
# 存档字段（经 GameData systems 数组合并/认领）：
#   collections_owned {藏品id:{"level":n,"star":n}}
#   collection_frags  {藏品id:碎片数}          （无双/传奇=专属碎片计数）
#   collection_suits  {套装id:已激活档数}
#   collection_picks  {藏品id:自选门客hero_id}
# 加成经 HeroData 三件套接入（资质/固定赚速/百分比）
# ============================================================

var g   # GameData 中枢（不标类型避免循环引用）

# 存档数据（类级声明+加载类型防御，三管齐下惯例）
var _owned: Dictionary = {}
var _frags: Dictionary = {}
var _suits: Dictionary = {}
var _picks: Dictionary = {}

const QUALITY_NAMES: Array = ["无双", "传奇", "卓越", "优秀", "普通"]
# 必须映射后写入——直接写中文会造出无人读取的孤儿键（2026-09-08 实测踩坑：发放成功但面板不跳变）
const FRIEND_STAT_KEYS := {"友好": "friendly", "才华": "talent"}


func _init(p_g):
	g = p_g

# ---------- 配置 ----------
func _cfg() -> Dictionary:
	return g._collection_configs

func _settings() -> Dictionary:
	return _cfg().get("settings", {})

func get_collection(coll_id: String) -> Dictionary:
	return _cfg().get("collections", {}).get(coll_id, {})

func get_all_collections() -> Dictionary:
	return _cfg().get("collections", {})

func get_suits() -> Dictionary:
	return _cfg().get("suits", {})

func get_lottery_pool() -> Array:
	return _cfg().get("lottery", [])

# ---------- 存档 ----------
func get_save_data() -> Dictionary:
	return {"collections_owned": _owned, "collection_frags": _frags,
		"collection_suits": _suits, "collection_picks": _picks}

func load_save_data(d) -> void:
	if d.has("collections_owned") and d.collections_owned is Dictionary: _owned = d.collections_owned
	if d.has("collection_frags") and d.collection_frags is Dictionary: _frags = d.collection_frags
	if d.has("collection_suits") and d.collection_suits is Dictionary: _suits = d.collection_suits
	if d.has("collection_picks") and d.collection_picks is Dictionary: _picks = d.collection_picks

# ---------- 基础查询 ----------
func is_owned(coll_id: String) -> bool:
	return _owned.has(coll_id)

func get_level(coll_id: String) -> int:
	return int(_owned.get(coll_id, {}).get("level", 1))

func get_star(coll_id: String) -> int:
	return int(_owned.get(coll_id, {}).get("star", 1))

func get_frag_count(coll_id: String) -> int:
	return int(_frags.get(coll_id, 0))

func get_quality_name(q: int) -> String:
	return QUALITY_NAMES[q] if q >= 0 and q < QUALITY_NAMES.size() else ""

# ---------- 碎片 ----------
# 品质0/1用专属碎片计数；品质2/3/4用通用碎片道具
func add_frags(coll_id: String, n: int) -> void:
	_frags[coll_id] = get_frag_count(coll_id) + n

func _consume_frag(quality: int, coll_id: String, n: int) -> void:
	if quality <= 1:
		_frags[coll_id] = get_frag_count(coll_id) - n
	else:
		var item: String = _settings().get("generic_frag_items", {}).get(str(quality), "")
		if item != "":
			g.items[item] = int(g.items.get(item, 0)) - n

# 当前碎片来源的拥有量
func get_frag_have(quality: int, coll_id: String) -> int:
	if quality <= 1:
		return get_frag_count(coll_id)
	var item: String = _settings().get("generic_frag_items", {}).get(str(quality), "")
	return int(g.items.get(item, 0)) if item != "" else 0

# ---------- 合成（100碎片→1星1级） ----------
func get_synthesize_info(coll_id: String) -> Dictionary:
	var q = int(get_collection(coll_id).get("quality", 4))
	var need = int(_settings().get("synthesize_frag", 100))
	var have = get_frag_have(q, coll_id)
	return {"need": need, "have": have, "ok": have >= need}

func synthesize(coll_id: String) -> Dictionary:
	if is_owned(coll_id):
		return {"ok": false, "msg": "已获得"}
	if get_collection(coll_id).is_empty():
		return {"ok": false, "msg": "配置缺失"}
	var info = get_synthesize_info(coll_id)
	if not info.ok:
		return {"ok": false, "msg": "碎片不足"}
	_consume_frag(int(get_collection(coll_id).quality), coll_id, info.need)
	_owned[coll_id] = {"level": 1, "star": 1}
	# 【新增】二批：合成即发1星1级对应的友好/才华加成
	apply_friend_bonus_delta(coll_id, 0, 0)
	# 【新增】三批：合成即发绑定店铺的初始店员（1级1星）
	apply_shop_staff_delta(coll_id, 0, 0)
	return {"ok": true, "msg": "合成成功"}

# ---------- 升级（消耗五种光，每100级换道具重新计算） ----------
# 消耗=品质基数×(1+段内每10级+1)；例：无双1级→50萤虫光、23级→150萤虫光、100级→50烛火光
func get_upgrade_item(coll_id: String) -> String:
	var lv = get_level(coll_id)
	var seg = int((lv - 1) / 100.0)   # 0~4 段
	var items: Array = _settings().get("upgrade_items", [])
	return items[mini(seg, items.size() - 1)] if items.size() > 0 else ""

func get_upgrade_cost(coll_id: String) -> int:
	var lv = get_level(coll_id)
	var q = int(get_collection(coll_id).get("quality", 4))
	var base = int(_settings().get("quality_base", {}).get(str(q), 10))
	return base * (1 + int((lv - 1) % 100 / 10.0))

func can_upgrade(coll_id: String) -> bool:
	if not is_owned(coll_id):
		return false
	if get_level(coll_id) >= int(_settings().get("max_level", 500)):
		return false
	var item = get_upgrade_item(coll_id)
	return item != "" and int(g.items.get(item, 0)) >= get_upgrade_cost(coll_id)

func upgrade(coll_id: String, batch: bool = false) -> Dictionary:
	if not is_owned(coll_id):
		return {"ok": false, "msg": "未获得"}
	var old_lv = get_level(coll_id)   # 【新增】二批：记录升级前等级，用于差值发放
	var times = 10 if batch else 1
	var upgraded = 0
	while times > 0 and can_upgrade(coll_id):
		var item = get_upgrade_item(coll_id)
		g.items[item] = int(g.items.get(item, 0)) - get_upgrade_cost(coll_id)
		_owned[coll_id].level = get_level(coll_id) + 1
		upgraded += 1
		times -= 1
	if upgraded == 0:
		return {"ok": false, "msg": "道具不足或已满级"}
	# 【新增】二批：升级后把新增等级对应的友好/才华差值发给匹配挚友
	apply_friend_bonus_delta(coll_id, old_lv, get_star(coll_id))
	# 【新增】三批：升级差值店员写入绑定店铺
	apply_shop_staff_delta(coll_id, old_lv, get_star(coll_id))
	return {"ok": true, "msg": "升级 %d 级" % upgraded}

# ---------- 晋升（升星，消耗碎片） ----------
# 无双=固定100；传奇=100×(1+(星-1)/10取整)；卓越=100×(1+(星-1)/3)；优秀=100×(1+(星-1)/2)；普通=100×星
func get_star_up_cost(coll_id: String) -> int:
	var q = int(get_collection(coll_id).get("quality", 4))
	var s = get_star(coll_id)
	match q:
		0: return int(_settings().get("synthesize_frag", 100))
		1: return 100 * (1 + int((s - 1) / 10.0))
		2: return 100 * (1 + int((s - 1) / 3.0))
		3: return 100 * (1 + int((s - 1) / 2.0))
		_: return 100 * s

func can_star_up(coll_id: String) -> bool:
	if not is_owned(coll_id):
		return false
	if get_star(coll_id) >= int(_settings().get("max_star", 20)):
		return false
	return get_frag_have(int(get_collection(coll_id).get("quality", 4)), coll_id) >= get_star_up_cost(coll_id)

func star_up(coll_id: String) -> Dictionary:
	if not can_star_up(coll_id):
		return {"ok": false, "msg": "碎片不足或已满星"}
	var q = int(get_collection(coll_id).get("quality", 4))
	_consume_frag(q, coll_id, get_star_up_cost(coll_id))
	var old_star = get_star(coll_id)   # 【新增】二批：记录升星前星数
	_owned[coll_id].star = get_star(coll_id) + 1
	# 【新增】二批：升星后把新增星数对应的友好/才华差值发给匹配挚友
	apply_friend_bonus_delta(coll_id, get_level(coll_id), old_star)
	# 【新增】三批：升星差值店员写入绑定店铺
	apply_shop_staff_delta(coll_id, get_level(coll_id), old_star)
	return {"ok": true, "msg": "晋升成功"}

# ---------- 自选门客 ----------
func set_pick(coll_id: String, hero_id: String) -> void:
	_picks[coll_id] = hero_id

func get_pick(coll_id: String) -> String:
	return _picks.get(coll_id, "")

# ---------- 挚友友好/才华（二批·写入式 2026-09-08） ----------
# 仿宅院挚友卷：升级/升星/合成时把差值直接写进挚友存档字段；挚友解锁时补发累计值。
# 存档字段映射：挚友存档键是英文 friendly/talent（friend_system 结构），藏品 stat 是中文显示名，
# 必须映射后写入——直接写中文会造出无人读取的孤儿键（2026-09-08 实测踩坑：发放成功但面板不跳变）
# 友好/才华类藏品目标匹配：friend=指定挚友 / friend_category=指定职业挚友（职业读 friends.json 的 category 字段）
# 目标匹配：friend=指定挚友 / friend_category=指定职业挚友（职业读全量配置，不读解锁时刻的存档快照）
func _friend_target_match(base: Dictionary, friend_id: String) -> bool:
	if not g.friends.has(friend_id):
		return false
	match base.get("target", ""):
		"friend":
			return friend_id == base.get("friend", "")
		"friend_category":
			return str(g._friend_configs.get(friend_id, {}).get("category", "")) == base.get("category", "")
	return false

# 差值发放：藏品等级/星数变化后，把该藏品本次新增部分发给所有匹配挚友（只加不减，追加即正确）
func apply_friend_bonus_delta(coll_id: String, old_lv: int, old_star: int) -> void:
	var coll = get_collection(coll_id)
	if coll.is_empty():
		return
	var base: Dictionary = coll.get("base", {})
	if not base.get("wired", false):
		return
	var key: String = FRIEND_STAT_KEYS.get(str(base.get("stat", "")), "")
	if key == "":
		return
	var delta = int(base.get("per_level", 0)) * (get_level(coll_id) - old_lv) + int(base.get("per_star", 0)) * (get_star(coll_id) - old_star)
	if delta <= 0:
		return
	for friend_id in g.friends.keys():
		if _friend_target_match(base, friend_id):
			var f = g.friends[friend_id]
			f[key] = int(f.get(key, 0)) + delta

# 挚友解锁补发：一次性加上当前所有已养成藏品累计应得值（新挚友即时享受）
func apply_friend_unlock_bonus(friend_id: String) -> void:
	if not g.friends.has(friend_id):
		return
	for cid in _owned.keys():
		var coll = get_collection(cid)
		if coll.is_empty():
			continue
		var base: Dictionary = coll.get("base", {})
		if not base.get("wired", false) or not _friend_target_match(base, friend_id):
			continue
		var key: String = FRIEND_STAT_KEYS.get(str(base.get("stat", "")), "")
		if key == "":
			continue
		var f = g.friends[friend_id]
		f[key] = int(f.get(key, 0)) + int(base.get("per_level", 0)) * get_level(cid) + int(base.get("per_star", 0)) * get_star(cid)

# ---------- 套装（手动逐档激活，免费） ----------
# 进度=成员最低星数达到的档位数；激活不自动，亮红点提示
func get_suit_info(suit_id: String) -> Dictionary:
	var suit: Dictionary = get_suits().get(suit_id, {})
	var tiers: Array = suit.get("tiers", [])
	var min_star = 99
	for m in suit.get("members", []):
		if is_owned(m):
			min_star = mini(min_star, get_star(m))
		else:
			min_star = 0
	var reached = 0
	for t in tiers:
		if min_star >= int(t):
			reached += 1
	var activated = int(_suits.get(suit_id, 0))
	return {"reached": reached, "activated": activated,
		"total": tiers.size(), "can_activate": activated < reached, "min_star": min_star}

func has_activatable_suit() -> bool:
	for sid in get_suits().keys():
		if get_suit_info(sid).can_activate:
			return true
	return false

func activate_suit(suit_id: String) -> Dictionary:
	var info = get_suit_info(suit_id)
	if not info.can_activate:
		return {"ok": false, "msg": "暂无可激活档位"}
	_suits[suit_id] = int(_suits.get(suit_id, 0)) + 1
	return {"ok": true, "msg": "激活成功"}

# ---------- 淘宝（权重制 roll，单抽1券/十连10券） ----------
func get_ticket_item() -> String:
	return _settings().get("lottery_ticket", "tao_bao_quan")

func get_ticket_count() -> int:
	return int(g.items.get(get_ticket_item(), 0))

func can_lottery(n: int) -> bool:
	return get_ticket_count() >= n

func roll(count: int) -> Dictionary:
	if not can_lottery(count):
		return {"ok": false, "msg": "淘宝券不足", "results": []}
	g.items[get_ticket_item()] = get_ticket_count() - count
	var results = []
	for i in count:
		results.append(_roll_one())
	return {"ok": true, "results": results}

func _roll_one() -> Dictionary:
	var pool = get_lottery_pool()
	var total = 0
	for e in pool:
		total += int(e.get("weight", 0))
	var r = randi() % maxi(total, 1)
	for e in pool:
		r -= int(e.get("weight", 0))
		if r < 0:
			return _apply_lottery(e)
	return _apply_lottery(pool.back())

# 应用奖池项：frag=专属碎片 / gfrag=通用碎片道具 / item=普通道具（数量取settings.light_counts）
func _apply_lottery(e: Dictionary) -> Dictionary:
	match e.get("type", ""):
		"frag":
			add_frags(e.get("collection", ""), int(e.get("count", 0)))
		"gfrag":
			var item: String = _settings().get("generic_frag_items", {}).get(str(int(e.get("quality", 4))), "")
			if item != "":
				g.items[item] = int(g.items.get(item, 0)) + int(e.get("count", 0))
		"item":
			var item_id: String = e.get("item", "")
			var n = int(e.get("count", 0))
			if n <= 0:
				n = int(_settings().get("light_counts", {}).get(item_id, 10))
			g.items[item_id] = int(g.items.get(item_id, 0)) + n
			e = e.duplicate()
			e["count"] = n
	return e

# ============ HeroData 三件套接入 ============

# 当前门客是否五艳（配置 settings.wuyan_heroes）
func _is_wuyan(hero_id: String) -> bool:
	return hero_id in _settings().get("wuyan_heroes", [])

# 基础效果目标匹配：hero/wuyan/pick/quality_min/category
func _target_match(base: Dictionary, hero_id: String) -> bool:
	if not g.heroes.has(hero_id):
		return false
	var hero = g.heroes[hero_id]
	match base.get("target", ""):
		"hero": return hero_id == base.get("hero", "")
		"wuyan": return _is_wuyan(hero_id)
		"quality_min": return int(hero.get("quality", 0)) >= int(base.get("min", 2))
		"category": return hero.get("category", "") == base.get("category", "")
	return false

# 特殊效果目标匹配（hero_pct/hero_apt 用）
func _special_match(sp: Dictionary, hero_id: String) -> bool:
	match sp.get("kind", ""):
		"hero_pct", "hero_apt":
			return hero_id == sp.get("hero", "")
		"group_pct", "group_apt":
			return _is_wuyan(hero_id)
		"pick_pct":
			return hero_id == get_pick("")
		"category_pct":
			return g.heroes.has(hero_id) and g.heroes[hero_id].get("category", "") == sp.get("category", "")
		"quality_min_pct":
			return g.heroes.has(hero_id) and int(g.heroes[hero_id].get("quality", 0)) >= int(sp.get("min", 2))
		"category_pct", "category_apt":
			return g.heroes.has(hero_id) and g.heroes[hero_id].get("category", "") == sp.get("category", "")
	return false

# 资质加成 = Σ(基础效果资质类 每级×级+每星×星) + Σ(特殊效果 hero_apt/group_apt 每星×星)
func get_aptitude_bonus(hero_id: String) -> int:
	if not g.heroes.has(hero_id):
		return 0
	var total = 0
	for cid in _owned.keys():
		var coll = get_collection(cid)
		if coll.is_empty():
			continue
		var lv = get_level(cid)
		var st = get_star(cid)
		var base: Dictionary = coll.get("base", {})
		# 自选门客的基础效果目标匹配需要藏品id，单独处理
		if base.get("wired", false) and base.get("stat", "") == "apt":
			if base.get("target", "") == "pick":
				if hero_id == get_pick(cid):
					total += int(base.get("per_level", 0)) * lv + int(base.get("per_star", 0)) * st
			elif _target_match(base, hero_id):
				total += int(base.get("per_level", 0)) * lv + int(base.get("per_star", 0)) * st
		var sp: Dictionary = coll.get("special", {})
		if sp.get("kind", "") in ["hero_apt", "group_apt", "category_apt"]:
			if _special_match(sp, hero_id):
				total += int(sp.get("per_star", 0)) * st
	return total

# 固定赚速 = Σ(基础效果赚钱类 每级×级+每星×星)
func get_flat_income_bonus(hero_id: String) -> int:
	if not g.heroes.has(hero_id):
		return 0
	var total = 0
	for cid in _owned.keys():
		var coll = get_collection(cid)
		if coll.is_empty():
			continue
		var base: Dictionary = coll.get("base", {})
		if not base.get("wired", false) or base.get("stat", "") != "income":
			continue
		var val = int(base.get("per_level", 0)) * get_level(cid) + int(base.get("per_star", 0)) * get_star(cid)
		if base.get("target", "") == "pick":
			if hero_id == get_pick(cid):
				total += val
		elif _target_match(base, hero_id):
			total += val
	return total

# 百分比 = Σ(特殊效果每星×星%) + 套装(五艳门客%/指定门客%)
func get_percent_bonus(hero_id: String) -> float:
	if not g.heroes.has(hero_id):
		return 0.0
	var bonus = 0.0
	for cid in _owned.keys():
		var coll = get_collection(cid)
		if coll.is_empty():
			continue
		var sp: Dictionary = coll.get("special", {})
		if sp.get("kind", "").ends_with("_pct") or sp.get("kind", "") == "pick_pct":
			# pick_pct 需要藏品id判断
			if sp.get("kind", "") == "pick_pct":
				if hero_id == get_pick(cid):
					bonus += float(sp.get("per_star", 0)) * get_star(cid) / 100.0
			elif _special_match(sp, hero_id):
				bonus += float(sp.get("per_star", 0)) * get_star(cid) / 100.0
	bonus += _suit_percent(hero_id)
	return bonus

# 套装百分比,已接入：wuyan_pct / hero_pct / quality_min_pct；其余展示不接入"。
func _suit_percent(hero_id: String) -> float:
	var pct = 0.0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		var act = int(_suits.get(sid, 0))
		if act <= 0:
			continue
		var per = float(suit.get("per_tier", 0))
		match suit.get("kind", "display"):
			"wuyan_pct":
				if _is_wuyan(hero_id):
					pct += per * act / 100.0
			"hero_pct":
				if hero_id == suit.get("hero", ""):
					pct += per * act / 100.0
			# 【新增】无双及以上门客赚钱+per_tier%/档（min 默认2=无双；-1优秀/0卓越/1传奇不吃）
			"quality_min_pct":
				if int(g.heroes[hero_id].get("quality", 0)) >= int(suit.get("min", 2)):
					pct += per * act / 100.0
	return pct

# ---------- 套装效果·一批接入（2026-09-08） ----------

# 通用：指定 kind 套装 已激活档数×每档值 之和（上限类用，返回整数）
func get_suit_limit_bonus(kind: String) -> int:
	var total = 0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		if suit.get("kind", "") != kind:
			continue
		total += int(suit.get("per_tier", 0)) * int(_suits.get(sid, 0))
	return total

# 守护灵套装：返回守护灵赚钱的放大系数（1+Σ每档×档数/100），乘进阶段注满%
func get_guardian_suit_pct() -> float:
	var pct = 0.0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		if suit.get("kind", "") != "guardian_pct":
			continue
		pct += float(suit.get("per_tier", 0)) * int(_suits.get(sid, 0))
	return pct / 100.0

# 魂石套装：指定职业门客 每格激发魂石 +per_tier%/格（乘已激活档数×激发格数，返回小数）
func get_soul_suit_percent(category: String, inspired: int) -> float:
	var pct = 0.0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		if suit.get("kind", "") != "soul_cell_pct" or suit.get("category", "") != category:
			continue
		pct += float(suit.get("per_tier", 0)) * int(_suits.get(sid, 0)) / 100.0 * float(inspired)
	return pct

# ---------- 套装效果·三批接入（2026-09-09） ----------

# 虫师技能等级上限套装：全体（无category）+职业两类，返回放宽的军衔阶数（每档=required降1阶=同军衔多升1级）
func get_worm_cap_bonus(category: String) -> int:
	var total = 0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		if suit.get("kind", "") != "worm_cap":
			continue
		var suit_cat: String = str(suit.get("category", ""))
		# 无category=全体虫师；有category=仅该职业门客（职业读全量配置，不吃存档快照）
		if suit_cat != "" and suit_cat != category:
			continue
		total += int(suit.get("per_tier", 0)) * int(_suits.get(sid, 0))
	return total

# 徒弟套装（市贾/童忆）：培养阅历+徒弟赚速 共用放大系数（per_tier 为百分点，返回小数）
func get_apprentice_suit_pct() -> float:
	var pct = 0.0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		if suit.get("kind", "") != "apprentice_pct":
			continue
		pct += float(suit.get("per_tier", 0)) * int(_suits.get(sid, 0))
	return pct / 100.0

# 谈心缘分套装（凝冰）：返回小数放大系数（per_tier 为百分点）
func get_chat_bond_pct() -> float:
	var pct = 0.0
	for sid in get_suits().keys():
		var suit: Dictionary = get_suits()[sid]
		if suit.get("kind", "") != "chat_bond_pct":
			continue
		pct += float(suit.get("per_tier", 0)) * int(_suits.get(sid, 0))
	return pct / 100.0

# ---------- 店员数量15件（c220-c234，写入式，2026-09-09） ----------
# 映射表：藏品id → 店铺id（data/shops.json 的键，15店已逐一核对）
const SHOP_STAFF_COLLECTIONS := {
	"c220": "xiangliao_pu", "c221": "changle_fang", "c222": "yi_zhan", "c223": "dang_pu",
	"c224": "ke_zhan", "c225": "yao_pu", "c226": "shuoshu_tan", "c227": "jiu_fang",
	"c228": "jiu_si", "c229": "yi_guan", "c230": "chema_hang", "c231": "cha_si",
	"c232": "chengyi_pu", "c233": "suanming_tan", "c234": "miaoyin_fang",
}

# 查询：藏品绑定的店铺id（无绑定返回空串，视图显示用）
func get_shop_staff_shop(coll_id: String) -> String:
	return SHOP_STAFF_COLLECTIONS.get(coll_id, "")

# 店员数量差值发放：与 apply_friend_bonus_delta 同套路（只加不减），挂钩 upgrade/star_up/synthesize 三处
func apply_shop_staff_delta(coll_id: String, old_lv: int, old_star: int) -> void:
	var shop_id: String = SHOP_STAFF_COLLECTIONS.get(coll_id, "")
	if shop_id == "" or not g.shops.has(shop_id):
		return
	var base: Dictionary = get_collection(coll_id).get("base", {})
	var delta = int(base.get("per_level", 0)) * (get_level(coll_id) - old_lv) + int(base.get("per_star", 0)) * (get_star(coll_id) - old_star)
	if delta <= 0:
		return
	g.shops[shop_id].staff = int(g.shops[shop_id].get("staff", 0)) + delta
