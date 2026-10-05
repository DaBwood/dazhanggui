# ============================================================
# 好友系统（2026-10-04：游历页好友玩法，人机填充本地版）
# 纯逻辑模块：状态内部持有随 get_save_data 落盘；本类通过 g.xxx 访问中枢
# 口径：好友=游历页社交对象（与"挚友"完全是两套）；每日 0 点（UTC+8）重置赠/领标记
# ============================================================
class_name HaoyouSystem
extends RefCounted

var g

func _init(p_g):
	g = p_g

# ============ 存档 ============
# friends 元素：{name, friendly, sent_day, claimed_day}——day 字段=当日日期键，跨天清空即重置
var friends: Array = []
var day_key: String = ""

func get_save_data() -> Dictionary:
	return {"hy_friends": friends, "hy_day": day_key}

func load_save_data(s: Dictionary):
	if s.has("hy_friends") and s.hy_friends is Array:
		friends = s.hy_friends
	if s.has("hy_day"):
		day_key = str(s.hy_day)

# 本地日期键：get_date_string_from_unix_time 按 UTC 解析，需手动 +8 小时对齐每日 0 点
func _today() -> String:
	var now := int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(now + 8 * 3600)

func _check_day():
	var t := _today()
	if day_key == t:
		return
	day_key = t
	for f in friends:
		f.sent_day = ""
		f.claimed_day = ""

func _settings() -> Dictionary:
	return g._haoyou_configs.get("settings", {})

# 首次进入按名库随机填充固定好友（人机填充：真人同步未排期，参考招商 ai_names 先例）
func ensure_friends():
	_check_day()
	if not friends.is_empty():
		return
	var count := int(_settings().get("friend_count", 8))
	var pool: Array = g._haoyou_configs.get("names", []).duplicate()
	pool.shuffle()
	for i in mini(count, pool.size()):
		friends.append({"name": pool[i], "friendly": 0, "sent_day": "", "claimed_day": ""})

func get_friends() -> Array:
	ensure_friends()
	return friends

func can_send(i: int) -> bool:
	_check_day()
	return i >= 0 and i < friends.size() and str(friends[i].get("sent_day", "")) != day_key

func can_claim(i: int) -> bool:
	_check_day()
	return i >= 0 and i < friends.size() and str(friends[i].get("claimed_day", "")) != day_key

# 赠礼：不耗资源（轻社交日常），好友友好+1，每日每好友 1 次
func send_gift(i: int) -> Dictionary:
	_check_day()
	if not can_send(i):
		return {"ok": false, "msg": "今日已赠过礼"}
	friends[i].sent_day = day_key
	var gain := int(_settings().get("send_friendly", 1))
	friends[i].friendly = int(friends[i].get("friendly", 0)) + gain
	return {"ok": true, "msg": "已向【%s】赠礼，友好+%d" % [friends[i].name, gain]}

# 领礼回礼体力丹：基础 1 颗 + 藏品幽恒（c191）每星+1
func claim_pill_count() -> int:
	return int(_settings().get("claim_pill_base", 1)) + g.collection_system.get_haoyou_pill_bonus()

func claim_gift(i: int) -> Dictionary:
	_check_day()
	if not can_claim(i):
		return {"ok": false, "msg": "今日已领过礼"}
	friends[i].claimed_day = day_key
	var pills := claim_pill_count()
	g.items["stamina_pill"] = int(g.items.get("stamina_pill", 0)) + pills
	return {"ok": true, "msg": "领取【%s】的回礼：体力丹×%d" % [friends[i].name, pills], "pills": pills}

func send_all() -> Dictionary:
	_check_day()
	var n := 0
	for i in friends.size():
		if can_send(i):
			send_gift(i)
			n += 1
	return {"ok": true, "count": n}

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

func get_sendable_count() -> int:
	ensure_friends()
	var n := 0
	for i in friends.size():
		if can_send(i):
			n += 1
	return n
