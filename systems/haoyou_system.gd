# ============================================================
# 好友系统（2026-10-05 真人版：好友管理/搜索添加/拜访快照/点赞，人机+真人≤50）
# 纯逻辑模块：状态内部持有随 get_save_data 落盘；本类通过 g.xxx 访问中枢
# 口径（用户拍板 2026-10-05）：
#   体力丹每位好友固定 1 颗；每日限领 claim_cap_base(20) 名；藏品幽恒(c191)每星额外+3 名
#   点赞每位好友每天 1 次（真人走服务器唯一约束防刷，人机本地记账）；奖励=家具币5+风水符1
#   添加单向直加、删除单向删自己列表；真人功能走云存档 Worker，未登录=单机人机版全功能
# ============================================================
class_name HaoyouSystem
extends RefCounted

var g

func _init(p_g):
	g = p_g

# ============ 存档 ============
# friends 元素：{name, kind("ai"/"real"), user(真人账号,人机=""), friendly, sent_day, claimed_day, liked_day}
var friends: Array = []
var day_key: String = ""
var claimed_count: int = 0   # 今日已领回礼好友数（名额口径：基础20名+幽恒每星3名）

func get_save_data() -> Dictionary:
	return {"hy_friends": friends, "hy_day": day_key, "hy_claimed": claimed_count}

func load_save_data(s: Dictionary):
	if s.has("hy_friends") and s.hy_friends is Array:
		friends = s.hy_friends
		_migrate()   # 旧档（2026-10-04 版无 kind/user/liked_day）就地补键，全按人机处理
	if s.has("hy_day"):
		day_key = str(s.hy_day)
	if s.has("hy_claimed"):
		claimed_count = int(s.hy_claimed)

func _migrate():
	for f in friends:
		if not f.has("kind"):
			f.kind = "ai"
		if not f.has("user"):
			f.user = ""
		if not f.has("liked_day"):
			f.liked_day = ""
		if not f.has("friendly"):
			f.friendly = 0

# 本地日期键：get_date_string_from_unix_time 按 UTC 解析，需手动 +8 小时对齐每日 0 点
func _today() -> String:
	var now := int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(now + 8 * 3600)

func _check_day():
	var t := _today()
	if day_key == t:
		return
	day_key = t
	claimed_count = 0
	for f in friends:
		f.sent_day = ""
		f.claimed_day = ""
		f.liked_day = ""

func _settings() -> Dictionary:
	return g._haoyou_configs.get("settings", {})

func get_today() -> String:
	_check_day()
	return day_key

func friend_cap() -> int:
	return int(_settings().get("friend_cap", 50))

func is_full() -> bool:
	_check_day()
	return friends.size() >= friend_cap()

# 首次进入按名库随机填充初始人机（真人靠搜索添加，用户拍板）
func ensure_friends():
	_check_day()
	if not friends.is_empty():
		return
	for n in _unused_names(int(_settings().get("initial_ai", 8))):
		friends.append(_mk_ai(n))

func _mk_ai(p_name: String) -> Dictionary:
	return {"name": p_name, "kind": "ai", "user": "", "friendly": 0, "sent_day": "", "claimed_day": "", "liked_day": ""}

# 名库中未被占用的名字，随机取 n 个
func _unused_names(n: int) -> Array:
	var used := {}
	for f in friends:
		used[f.name] = true
	var pool: Array = []
	for nm in g._haoyou_configs.get("names", []):
		if not used.has(nm):
			pool.append(nm)
	pool.shuffle()
	return pool.slice(0, mini(n, pool.size()))

func get_friends() -> Array:
	ensure_friends()
	return friends

func find_index_by_user(user: String) -> int:
	for i in friends.size():
		if str(friends[i].get("user", "")) == user:
			return i
	return -1

# 加人机好友：名库自动取名（删除后名字回池可复用）
func add_ai_friend() -> Dictionary:
	_check_day()
	ensure_friends()
	if is_full():
		return {"ok": false, "msg": "好友已满（上限%d）" % friend_cap()}
	var names := _unused_names(1)
	if names.is_empty():
		return {"ok": false, "msg": "名库已用尽"}
	var f := _mk_ai(names[0])
	friends.append(f)
	return {"ok": true, "msg": "已添加人机好友【%s】" % f.name, "name": f.name}

# 加真人好友：单向直加（对方列表不受影响，用户拍板）；显示名=角色名
func add_real_friend(user: String, p_name: String) -> Dictionary:
	_check_day()
	ensure_friends()
	if user == "" or p_name == "":
		return {"ok": false, "msg": "玩家信息无效"}
	if find_index_by_user(user) >= 0:
		return {"ok": false, "msg": "对方已在好友列表"}
	if is_full():
		return {"ok": false, "msg": "好友已满（上限%d）" % friend_cap()}
	friends.append({"name": p_name, "kind": "real", "user": user, "friendly": 0, "sent_day": "", "claimed_day": "", "liked_day": ""})
	return {"ok": true, "msg": "已添加好友【%s】" % p_name}

# 单向删自己列表（对方列表不受影响）
func remove_friend(i: int) -> Dictionary:
	_check_day()
	if i < 0 or i >= friends.size():
		return {"ok": false, "msg": "好友不存在"}
	var nm: String = friends[i].name
	friends.remove_at(i)
	return {"ok": true, "msg": "已删除好友【%s】" % nm}

# ---- 赠礼（不耗资源，友好+1，每日每好友1次；friendly 暂纯展示进度）----
func can_send(i: int) -> bool:
	_check_day()
	return i >= 0 and i < friends.size() and str(friends[i].get("sent_day", "")) != day_key

func send_gift(i: int) -> Dictionary:
	_check_day()
	if not can_send(i):
		return {"ok": false, "msg": "今日已赠过礼"}
	friends[i].sent_day = day_key
	var gain := int(_settings().get("send_friendly", 1))
	friends[i].friendly = int(friends[i].get("friendly", 0)) + gain
	return {"ok": true, "msg": "已向【%s】赠礼，友好+%d" % [friends[i].name, gain]}

func send_all() -> Dictionary:
	_check_day()
	var n := 0
	for i in friends.size():
		if can_send(i):
			send_gift(i)
			n += 1
	return {"ok": true, "count": n}

func get_sendable_count() -> int:
	ensure_friends()
	var n := 0
	for i in friends.size():
		if can_send(i):
			n += 1
	return n

# ---- 领回礼（体力丹：每位固定1颗；每日名额=基础20名+幽恒每星3名，用户拍板 2026-10-05）----
func claim_cap() -> int:
	return int(_settings().get("claim_cap_base", 20)) + 3 * g.collection_system.get_haoyou_star_count()

func get_claimed_count() -> int:
	_check_day()
	return claimed_count

func can_claim(i: int) -> bool:
	_check_day()
	return i >= 0 and i < friends.size() and str(friends[i].get("claimed_day", "")) != day_key and claimed_count < claim_cap()

func claim_gift(i: int) -> Dictionary:
	_check_day()
	if i < 0 or i >= friends.size():
		return {"ok": false, "msg": "好友不存在"}
	if str(friends[i].get("claimed_day", "")) == day_key:
		return {"ok": false, "msg": "今日已领过礼"}
	if claimed_count >= claim_cap():
		return {"ok": false, "msg": "今日领取名额已满（%d名）" % claim_cap()}
	friends[i].claimed_day = day_key
	claimed_count += 1
	var pills := int(_settings().get("pill_per_friend", 1))
	g.items["stamina_pill"] = int(g.items.get("stamina_pill", 0)) + pills
	return {"ok": true, "msg": "领取【%s】的回礼：体力丹×%d" % [friends[i].name, pills], "pills": pills}

func claim_all() -> Dictionary:
	_check_day()
	var n := 0
	var pills := 0
	for i in friends.size():
		if can_claim(i):
			var r := claim_gift(i)
			n += 1
			pills += int(r.get("pills", 0))
	return {"ok": true, "count": n, "pills": pills}

func get_claimable_count() -> int:
	ensure_friends()
	var n := 0
	for i in friends.size():
		if can_claim(i):
			n += 1
	return n

# ---- 点赞（每位好友每天1次；真人防双刷以服务器唯一约束为准，回执冲突本地回滚）----
func can_like(i: int) -> bool:
	_check_day()
	return i >= 0 and i < friends.size() and str(friends[i].get("liked_day", "")) != day_key

func _grant_like_reward():
	var rw: Dictionary = _settings().get("like_reward", {})
	for item_id in rw.keys():
		g.items[item_id] = int(g.items.get(item_id, 0)) + int(rw[item_id])

func _revoke_like_reward():
	var rw: Dictionary = _settings().get("like_reward", {})
	for item_id in rw.keys():
		g.items[item_id] = maxi(0, int(g.items.get(item_id, 0)) - int(rw[item_id]))

func like_friend(i: int) -> Dictionary:
	_check_day()
	if not can_like(i):
		return {"ok": false, "msg": "今日已赞过"}
	friends[i].liked_day = day_key
	_grant_like_reward()
	return {"ok": true, "msg": "已赞【%s】" % friends[i].name, "user": str(friends[i].get("user", "")), "kind": str(friends[i].get("kind", "ai"))}

func like_all() -> Dictionary:
	_check_day()
	var n := 0
	var real_users: Array = []
	for i in friends.size():
		if can_like(i):
			var r := like_friend(i)
			n += 1
			if str(r.get("kind", "")) == "real":
				real_users.append(r.get("user", ""))
	return {"ok": true, "count": n, "real_users": real_users}

func get_likeable_count() -> int:
	ensure_friends()
	var n := 0
	for i in friends.size():
		if can_like(i):
			n += 1
	return n

# 服务器判重回执：撤奖励+清标记（真人点赞服务器为准）
func rollback_like_user(user: String):
	_check_day()
	var i := find_index_by_user(user)
	if i < 0:
		return
	if str(friends[i].get("liked_day", "")) != day_key:
		return
	friends[i].liked_day = ""
	_revoke_like_reward()

# 服务器"我今日已赞"清单：本地标记对齐（多设备场景，服务器为准）
func mark_liked_by_server(liked_users: Array):
	_check_day()
	for u in liked_users:
		var i := find_index_by_user(str(u))
		if i >= 0:
			friends[i].liked_day = day_key

# ---- 拜访档案：真人=读对方上传快照；人机=本地生成假档案（与真人口同构，randi 现场 roll 不落存档）----
func build_visit_profile() -> Dictionary:
	var heroes: Array = []
	for hid in g.heroes.keys():
		var h: Dictionary = g.heroes[hid]
		heroes.append({
			"name": str(h.get("name", hid)),
			"category": str(h.get("category", "")),
			"level": int(h.get("level", 1)),
			"income": int(g.get_hero_income(hid)),
			"beast": _hero_beast_name(h),
			"fish": _hero_fish_name(hid),
			"cuzhi": _hero_cuzhi_name(hid),
			"auras": _hero_aura_names(hid),
		})
	var zhiyou: Array = []
	for fid in g.friends.keys():
		zhiyou.append({
			"name": str(g.get_friend_config(fid).get("name", fid)),
			"friendly": int(g.friends[fid].get("friendly", 0)),
			"affection": int(g.friend_affection.get(fid, 0)),
		})
	var shops: Array = []
	for sid in g.shops.keys():
		var s: Dictionary = g.shops[sid]
		shops.append({
			"name": str(s.get("name", sid)),
			"level": int(s.get("level", 1)),
			"income": int(g.shop_system.get_shop_auto_income(sid)),
		})
	return {"v": 1, "name": str(g.player_name), "total_income": int(g.get_heroes_total_income()), "heroes": heroes, "zhiyou": zhiyou, "shops": shops}

func _hero_beast_name(h: Dictionary) -> String:
	var bid := str(h.get("equipped_beast", ""))
	if bid == "":
		return ""
	return str(g._beast_configs.get(bid, {}).get("name", bid))

func _hero_fish_name(hid: String) -> String:
	var fid := str(g.fishing_system.get_hero_fish(hid))
	if fid == "":
		return ""
	return "%s %d阶" % [g.fishing_system.get_fish_name(fid), g.fishing_system.get_fish_tier(fid)]

func _hero_cuzhi_name(hid: String) -> String:
	var cid := str(g.cuzhi_system.get_equipped_cricket(hid))
	if cid == "":
		return ""
	return "%s Lv.%d" % [g.cuzhi_system.get_cricket_data(cid).name, g.cuzhi_system.get_equip_level(cid)]

# 光环名+等级：hero_talents 配置懒加载（talent_system 成组自加载的私有配置不跨系统摸，本类自读一份）
var _talent_heroes_cfg: Dictionary = {}

func _hero_talent_heroes() -> Dictionary:
	if _talent_heroes_cfg.is_empty():
		var f := FileAccess.open("res://data/hero_talents.json", FileAccess.READ)
		if f != null:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK and j.get_data() is Dictionary:
				_talent_heroes_cfg = j.get_data().get("heroes", {})
			f.close()
	return _talent_heroes_cfg

func _hero_aura_names(hid: String) -> Array:
	var out: Array = []
	var hc: Dictionary = _hero_talent_heroes().get(hid, {})
	var hd: Dictionary = g.heroes.get(hid, {})
	for grp in [["master_auras", "master_aura_levels"], ["self_auras", "self_aura_levels"], ["pair_auras", "pair_aura_levels"]]:
		var lv_dict: Dictionary = hd.get(grp[1], {})
		for a in hc.get(grp[0], []):
			var aid := str(a.get("id", ""))
			if aid == "":
				continue
			out.append("%s Lv.%d" % [a.get("name", aid), int(lv_dict.get(aid, 1))])
	return out

# 人机拜访假档案：名字做种子同日稳定，数值按自己养成 0.3~1.2 倍缩放
func make_ai_profile(friend_name: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(friend_name + day_key)
	var scale := 0.3 + rng.randf() * 0.9
	var heroes: Array = []
	var hero_pool: Array = g._hero_configs.keys()
	hero_pool.shuffle()
	for hid in hero_pool.slice(0, mini(8, hero_pool.size())):
		var hc: Dictionary = g._hero_configs[hid]
		var income := int((100 + rng.randi_range(0, 90000)) * scale)
		heroes.append({
			"name": str(hc.get("name", hid)),
			"category": str(hc.get("category", "")),
			"level": rng.randi_range(1, 200),
			"income": income,
			"beast": "",
			"fish": "",
			"cuzhi": "",
			"auras": [],
		})
	var total_income := 0
	for h in heroes:
		total_income += int(h.income)
	var zhiyou: Array = []
	var zy_pool: Array = g._friend_configs.keys()
	zy_pool.shuffle()
	for fid in zy_pool.slice(0, mini(6, zy_pool.size())):
		zhiyou.append({"name": str(g._friend_configs[fid].get("name", fid)), "friendly": rng.randi_range(0, 60), "affection": rng.randi_range(0, 5000)})
	var shops: Array = []
	var shop_pool: Array = g._shop_configs.keys()
	shop_pool.shuffle()
	for sid in shop_pool.slice(0, mini(6, shop_pool.size())):
		shops.append({"name": str(g._shop_configs[sid].get("name", sid)), "level": rng.randi_range(1, 100), "income": int(rng.randi_range(50, 5000) * scale)})
	return {"v": 1, "name": friend_name, "total_income": total_income, "heroes": heroes, "zhiyou": zhiyou, "shops": shops}
