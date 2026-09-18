# ============================================================
# 妙音坊玩法系统（2026-09-18 第一批：数据/收益罐/加速卡/勋章/赚速挂点）
# 设计口径：妙音坊设计方案 v1.0 §0~§3、§8~§12；批次②才接建筑/满意度 UI，批次③新秀，批次④选秀。
# 资源三轨：应援币=全部已解锁建筑等级×10/分；应援物=Σceil(居住建筑等级/10)/分（妙音坊内部道具，不进背包）；
#           缘分物=Σ功能建筑等级/分，五种花均分（走背包 items 轨）。
# 收益罐：三轨先累积进 jar（last 时间戳 lazy settlement，在线/离线同口径），点击一次性领取；上限见 settings.jar_cap_hours。
# 勋章：15 级，繁荣度=应援币总产出/分；全部商铺赚速 +100%×级，读取式挂 shop_system 百分比层（同酒坊勋章）。
# 高等级防卡顿：应援物按概率期望直写 jar（长期等价于逐项 roll，避免每秒钟大循环）。
# ============================================================
class_name MiaoyinSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有，随 get_save_data 落盘） ----------
var medal_lv: int = 1                 # 勋章等级 1~15（初始 1 级）
var yyb: float = 0.0                  # 已领取应援币（罐外即时部分）
var yyw: Dictionary = {}              # 已领取应援物 {support_item_id: 数量}（妙音坊内部，不进背包）
var jar: Dictionary = {}              # 收益罐 {last, yyb, yyw{}, yyf{}}；fraction 保留在罐内，领取时取整
var buildings: Dictionary = {}        # building_id: [设施等级...]（批次②才开放升级，本期先落存档结构）
var rookies: Dictionary = {}          # friend_id: {lv, exp, prof, good, house}（批次③使用，本期只保留字段）
var opinions: Dictionary = {"day": "", "list": []}   # 满意度意见簿（批次②使用）
var audition: Dictionary = {"stage": 1}              # 选秀关卡（批次④使用）

# 六配置分表缓存：buildings 由 GameData SYSTEM_LIST 直挂 _miaoyin_configs，其余五张懒加载缓存
var _extra_cfg: Dictionary = {}

const EXTRA_CFG_PATHS := {
	"professions": "res://data/miaoyin_professions.json",
	"support_table": "res://data/miaoyin_support_table.json",
	"medal": "res://data/miaoyin_medal.json",
	"audition": "res://data/miaoyin_audition.json",
	"satisfaction": "res://data/miaoyin_satisfaction.json",
}

func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {"miaoyin": {
		"medal": medal_lv, "yyb": yyb, "yyw": yyw, "jar": jar,
		"buildings": buildings, "rookies": rookies, "opinions": opinions, "audition": audition,
	}}

# 从扁平存档表认领本系统字段（旧档缺 miaoyin 段则按初始形状建档）
func load_save_data(s: Dictionary):
	if not s.has("miaoyin") or not (s.miaoyin is Dictionary):
		jar = _new_jar()
		_init_state()
		return
	var d: Dictionary = s.miaoyin
	medal_lv = clampi(int(d.get("medal", 1)), 1, get_medal_count())
	yyb = maxf(0.0, float(d.get("yyb", 0.0)))
	yyw = d.get("yyw", {})
	if not (yyw is Dictionary):
		yyw = {}
	jar = d.get("jar", {})
	if not (jar is Dictionary):
		jar = _new_jar()
	buildings = d.get("buildings", {})
	if not (buildings is Dictionary):
		buildings = {}
	rookies = d.get("rookies", {})
	if not (rookies is Dictionary):
		rookies = {}
	opinions = d.get("opinions", {"day": "", "list": []})
	if not (opinions is Dictionary):
		opinions = {"day": "", "list": []}
	audition = d.get("audition", {"stage": 1})
	if not (audition is Dictionary):
		audition = {"stage": 1}
	_init_state()
	settle_jar()   # 上线即补离线收益（只进罐，不自动入背包/已领池）

# 缺项补初始形状；不覆盖已有值（老档兼容）
func _init_state() -> void:
	medal_lv = clampi(medal_lv, 1, get_medal_count())
	if not jar.has("last"):
		jar["last"] = int(Time.get_unix_time_from_system())
	jar["last"] = int(jar.get("last", 0))
	jar["yyb"] = maxf(0.0, float(jar.get("yyb", 0.0)))
	if not jar.has("yyw") or not (jar["yyw"] is Dictionary):
		jar["yyw"] = {}
	if not jar.has("yyf") or not (jar["yyf"] is Dictionary):
		jar["yyf"] = {}
	for sid in get_support_ids():
		yyw[sid] = maxi(0, int(yyw.get(sid, 0)))
		jar["yyw"][sid] = maxf(0.0, float(jar["yyw"].get(sid, 0.0)))
		# 缘分物走背包 items 轨；这里只做键存在性兜底，不发数量
		var fid: String = get_flower_by_support(sid)
		if fid != "":
			g.items[fid] = int(g.items.get(fid, 0))
			jar["yyf"][fid] = maxf(0.0, float(jar["yyf"].get(fid, 0.0)))
	for b in get_building_list():
		var bid: String = str(b.get("id", ""))
		if bid == "":
			continue
		var facs: Array = b.get("facilities", [])
		if not buildings.has(bid) or not (buildings[bid] is Array) or (buildings[bid] as Array).size() != facs.size():
			var arr: Array = []
			for i in range(facs.size()):
				arr.append(0)
			buildings[bid] = arr
		else:
			var arr2: Array = buildings[bid]
			for i in range(arr2.size()):
				arr2[i] = clampi(int(arr2[i]), 0, get_facility_max_lv())

func _new_jar() -> Dictionary:
	return {"last": int(Time.get_unix_time_from_system()), "yyb": 0.0, "yyw": {}, "yyf": {}}

# ============ 配置快捷读 ============
func _cfg() -> Dictionary:
	return g._miaoyin_configs

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

func get_building_list() -> Array:
	return _cfg().get("buildings", [])

func get_profession_list() -> Array:
	return _extra("professions").get("professions", [])

func get_support_ids() -> Array:
	var ids: Array = []
	for p in get_profession_list():
		for it in p.get("support_items", []):
			var sid: String = str(it.get("id", ""))
			if sid != "":
				ids.append(sid)
	return ids

func get_flower_ids() -> Array:
	var ids: Array = []
	for p in get_profession_list():
		var fid: String = str(p.get("flower", ""))
		if fid != "":
			ids.append(fid)
	return ids

func get_flower_by_support(support_id: String) -> String:
	for p in get_profession_list():
		for it in p.get("support_items", []):
			if str(it.get("id", "")) == support_id:
				return str(p.get("flower", ""))
	return ""

func get_support_name_map() -> Dictionary:
	var m: Dictionary = {}
	for p in get_profession_list():
		for it in p.get("support_items", []):
			var sid: String = str(it.get("id", ""))
			if sid != "":
				m[sid] = str(it.get("name", sid))
	return m

# ============ 建筑/产出（批次②开放升级；本期已可结算 0 级建筑） ============
func get_settings() -> Dictionary:
	return _cfg().get("settings", {})

func get_jar_cap_hours() -> int:
	return int(get_settings().get("jar_cap_hours", 120))

func get_facility_max_lv() -> int:
	return int(get_settings().get("facility_max_lv", 999999))

func is_building_unlocked(building_cfg: Dictionary) -> bool:
	return medal_lv >= int(building_cfg.get("unlock_medal", 1))

func get_building_level(bid: String) -> int:
	if not buildings.has(bid) or not (buildings[bid] is Array):
		return 0
	var total: int = 0
	for lv in buildings[bid]:
		total += maxi(0, int(lv))
	return total

func get_unlocked_building_level_total() -> int:
	var total: int = 0
	for b in get_building_list():
		if is_building_unlocked(b):
			total += get_building_level(str(b.get("id", "")))
	return total

func get_unlocked_function_level_total() -> int:
	var total: int = 0
	for b in get_building_list():
		if str(b.get("type", "")) == "function" and is_building_unlocked(b):
			total += get_building_level(str(b.get("id", "")))
	return total

func get_yyb_per_min() -> float:
	return float(get_unlocked_building_level_total()) * float(get_settings().get("yyb_per_building_level", 10))

func get_yyw_per_min() -> float:
	var div: float = float(get_settings().get("residence_support_divisor", 10))
	var total: float = 0.0
	for b in get_building_list():
		if str(b.get("type", "")) == "residence" and is_building_unlocked(b):
			total += ceil(float(get_building_level(str(b.get("id", "")))) / div)
	return total

func get_yyf_per_min() -> float:
	return float(get_unlocked_function_level_total()) * float(get_settings().get("yyf_per_function_level", 1))

# ============ 建筑/设施升级（批次②；消耗应援币 yyb，费用=基础费用×增长系数^当前等级） ============
func get_building_cfg(bid: String) -> Dictionary:
	for b in get_building_list():
		if str(b.get("id", "")) == bid:
			return b
	return {}

func get_building_type(bid: String) -> String:
	return str(get_building_cfg(bid).get("type", ""))

func get_building_unlock_medal(bid: String) -> int:
	return int(get_building_cfg(bid).get("unlock_medal", 1))

func is_building_unlocked_by_id(bid: String) -> bool:
	return is_building_unlocked(get_building_cfg(bid))

func get_facility_count(bid: String) -> int:
	return get_building_cfg(bid).get("facilities", []).size()

func get_facility_cfg(bid: String, fac_idx: int) -> Dictionary:
	var facs: Array = get_building_cfg(bid).get("facilities", [])
	if fac_idx < 0 or fac_idx >= facs.size():
		return {}
	return facs[fac_idx]

func get_facility_level(bid: String, fac_idx: int) -> int:
	if not buildings.has(bid) or not (buildings[bid] is Array):
		return 0
	var arr: Array = buildings[bid]
	if fac_idx < 0 or fac_idx >= arr.size():
		return 0
	return maxi(0, int(arr[fac_idx]))

func get_facility_max_lv_pub() -> int:
	return get_facility_max_lv()

# L→L+1 消耗 = 基础费用（按该建筑设施数量分档）× growth^L；count 级求和（十连用）
func get_facility_upgrade_cost(bid: String, fac_idx: int, count: int = 1) -> int:
	var bcfg: Dictionary = get_building_cfg(bid)
	var fac_count: int = maxi(1, bcfg.get("facilities", []).size())
	var base_map: Dictionary = get_settings().get("cost_base_by_fac_count", {})
	var base: float = float(base_map.get(str(fac_count), 200))
	var growth: float = float(get_settings().get("cost_growth", 1.35))
	var lv: int = get_facility_level(bid, fac_idx)
	var total: float = 0.0
	for i in range(maxi(1, count)):
		total += base * pow(growth, float(lv + i))
	return int(min(total, 999999999999.0))

# 建筑“下一级费用”= 该建筑内最低单设施 +1 费用；建筑页升序/推荐口径
func get_building_next_cost(bid: String) -> int:
	if not is_building_unlocked_by_id(bid):
		return 2147483647
	var best: int = 2147483647
	for i in range(get_facility_count(bid)):
		best = mini(best, get_facility_upgrade_cost(bid, i, 1))
	return best

func can_upgrade_facility(bid: String, fac_idx: int, count: int = 1) -> Dictionary:
	if get_building_cfg(bid).is_empty():
		return {"ok": false, "msg": "建筑不存在"}
	if not is_building_unlocked_by_id(bid):
		return {"ok": false, "msg": "建筑未解锁"}
	if get_facility_level(bid, fac_idx) + count > get_facility_max_lv_pub():
		return {"ok": false, "msg": "设施已满级"}
	if yyb < float(get_facility_upgrade_cost(bid, fac_idx, count)):
		return {"ok": false, "msg": "应援币不足"}
	return {"ok": true}

func upgrade_facility(bid: String, fac_idx: int, count: int = 1) -> Dictionary:
	var chk: Dictionary = can_upgrade_facility(bid, fac_idx, count)
	if not chk.get("ok", false):
		return chk
	var cost: int = get_facility_upgrade_cost(bid, fac_idx, count)
	yyb = maxf(0.0, yyb - float(cost))
	var arr: Array = buildings[bid]
	arr[fac_idx] = int(arr[fac_idx]) + count
	refresh_opinion_resolutions()
	return {"ok": true, "count": count, "cost": cost}

func can_upgrade_building_sync(bid: String, count: int = 1) -> Dictionary:
	if get_building_cfg(bid).is_empty():
		return {"ok": false, "msg": "建筑不存在"}
	if not is_building_unlocked_by_id(bid):
		return {"ok": false, "msg": "建筑未解锁"}
	for i in range(get_facility_count(bid)):
		if can_upgrade_facility(bid, i, count).get("ok", false):
			return {"ok": true}
	return {"ok": false, "msg": "应援币不足或设施已满级"}

# 同步升级：该建筑全部设施各升 count 级；单个设施不满足整段费用则跳过（不半扣）
func upgrade_building_sync(bid: String, count: int = 1) -> Dictionary:
	var up: int = 0
	var spend: int = 0
	for i in range(get_facility_count(bid)):
		var r: Dictionary = upgrade_facility(bid, i, count)
		if r.get("ok", false):
			up += 1
			spend += int(r.get("cost", 0))
	if up <= 0:
		return {"ok": false, "msg": "应援币不足或设施已满级"}
	return {"ok": true, "count": up, "cost": spend}

func has_any_upgradeable_building() -> bool:
	for b in get_building_list():
		var bid: String = str(b.get("id", ""))
		if is_building_unlocked(b) and can_upgrade_building_sync(bid, 1).get("ok", false):
			return true
	return false

# 建筑页卡片数据：已解锁按 next_cost 升序；未解锁按勋章门槛升序排尾部；recommended=全场最低下一级费用
func get_building_card_list() -> Array:
	var unlocked: Array = []
	var locked: Array = []
	for b in get_building_list():
		var bid: String = str(b.get("id", ""))
		var entry: Dictionary = {
			"bid": bid,
			"name": str(b.get("name", bid)),
			"type": str(b.get("type", "")),
			"unlock_medal": int(b.get("unlock_medal", 1)),
			"unlocked": is_building_unlocked(b),
			"level": get_building_level(bid),
			"next_cost": get_building_next_cost(bid),
			"upgradeable": is_building_unlocked(b) and can_upgrade_building_sync(bid, 1).get("ok", false),
		}
		if entry["unlocked"]:
			unlocked.append(entry)
		else:
			locked.append(entry)
	unlocked.sort_custom(func(a, b): return int(a.get("next_cost", 0)) < int(b.get("next_cost", 0)))
	locked.sort_custom(func(a, b):
		if int(a.get("unlock_medal", 1)) == int(b.get("unlock_medal", 1)):
			return str(a.get("name", "")) < str(b.get("name", ""))
		return int(a.get("unlock_medal", 1)) < int(b.get("unlock_medal", 1)))
	var cards: Array = unlocked + locked
	var rec_bid: String = ""
	var rec_cost: int = 2147483647
	for e in cards:
		if e.get("unlocked", false) and int(e.get("next_cost", 0)) < rec_cost:
			rec_cost = int(e.get("next_cost", 0))
			rec_bid = str(e.get("bid", ""))
	for e in cards:
		e["recommended"] = str(e.get("bid", "")) == rec_bid and rec_bid != ""
	return cards

# ---------- 焕新纯表现：设施名变色 + 200级后每150级一颗红星（无属性） ----------
func get_facility_threshold_index(lv: int) -> int:
	var th: Array = get_settings().get("refresh_color_lvs", [10, 25, 50, 100, 200])
	var idx: int = 0
	for v in th:
		if lv >= int(v):
			idx += 1
	return idx

func get_facility_color(lv: int) -> Color:
	var idx: int = get_facility_threshold_index(lv)
	var colors: Array = get_settings().get("refresh_colors", ["#2ecc71", "#3498db", "#9b59b6", "#e67e22", "#e74c3c"])
	if idx <= 0:
		return Color("#ffffff")
	return Color(str(colors[mini(idx - 1, colors.size() - 1)]))

func get_facility_star_count(lv: int) -> int:
	if lv < 200:
		return 0
	return 1 + int(floor(float(lv - 200) / 150.0))

func get_facility_display_name(base_name: String, lv: int) -> String:
	var stars: int = get_facility_star_count(lv)
	if stars <= 0:
		return base_name
	return base_name + " " + "★".repeat(stars)

# ============ 满意度意见簿（批次②页面/规则；意见来源=已入住挚友，批次③接入前允许为空） ============
func get_satisfaction_settings() -> Dictionary:
	return _extra("satisfaction").get("settings", {})

func get_opinion_day() -> String:
	# 设计口径为每日 12:00 刷新；这里按本地日期归并，跨天首次访问刷新，避免存档写入过于频繁
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(dt.get("year", 1970)), int(dt.get("month", 1)), int(dt.get("day", 1))]

func _housed_rookie_entries() -> Array:
	var out: Array = []
	for fid in rookies.keys():
		var r: Dictionary = rookies.get(fid, {})
		var house: String = str(r.get("house", ""))
		if house == "" or not buildings.has(house):
			continue
		var bcfg: Dictionary = get_building_cfg(house)
		if bcfg.is_empty() or str(bcfg.get("type", "")) != "residence":
			continue
		out.append({"friend_id": str(fid), "friend_name": str(g.get_friend_config(str(fid)).get("name", fid)), "bid": house})
	return out

func refresh_opinions(force: bool = false) -> void:
	_init_state()
	var day: String = get_opinion_day()
	if not force and str(opinions.get("day", "")) == day:
		refresh_opinion_resolutions()
		return
	opinions["day"] = day
	opinions["list"] = []
	var housed: Array = _housed_rookie_entries()
	if housed.is_empty():
		return
	var st: Dictionary = get_satisfaction_settings()
	var total_n: int = maxi(0, int(st.get("opinion_count", 10)))
	var bad_min: int = int(st.get("bad_min", 4))
	var bad_max: int = int(st.get("bad_max", 6))
	var bad_n: int = clampi(randi_range(mini(bad_min, bad_max), maxi(bad_min, bad_max)), 0, total_n)
	var list: Array = []
	for i in range(total_n):
		var h: Dictionary = housed[randi() % housed.size()]
		var bcfg: Dictionary = get_building_cfg(str(h.get("bid", "")))
		var fac_count: int = maxi(1, bcfg.get("facilities", []).size())
		var fac_idx: int = randi() % fac_count
		var fac: Dictionary = get_facility_cfg(str(h.get("bid", "")), fac_idx)
		var is_bad: bool = i < bad_n
		list.append({
			"friend_id": str(h.get("friend_id", "")),
			"friend_name": str(h.get("friend_name", "")),
			"bid": str(h.get("bid", "")),
			"building_name": str(bcfg.get("name", "")),
			"fac_idx": fac_idx,
			"facility_name": str(fac.get("name", "")),
			"bad": is_bad,
			"resolved": false,
			"base_lv": get_facility_level(str(h.get("bid", "")), fac_idx),
		})
	opinions["list"] = list

func get_opinion_list() -> Array:
	refresh_opinions(false)
	return opinions.get("list", [])

func get_bad_unresolved_count() -> int:
	refresh_opinions(false)
	var n: int = 0
	for op in opinions.get("list", []):
		if op.get("bad", false) and not op.get("resolved", false):
			n += 1
	return n

# 差评转好评：生成差评后，该设施净升 resolve_upgrade_levels 级即视为解决（十连跨过也算）
func refresh_opinion_resolutions() -> int:
	var need: int = int(get_satisfaction_settings().get("resolve_upgrade_levels", 10))
	var fixed: int = 0
	for op in opinions.get("list", []):
		if not op.get("bad", false) or op.get("resolved", false):
			continue
		var bid: String = str(op.get("bid", ""))
		var idx: int = int(op.get("fac_idx", -1))
		if bid == "" or idx < 0:
			continue
		if get_facility_level(bid, idx) >= int(op.get("base_lv", 0)) + need:
			op["resolved"] = true
			op["bad"] = false
			fixed += 1
	return fixed

func get_satisfaction_rate() -> float:
	refresh_opinions(false)
	var list: Array = opinions.get("list", [])
	if list.is_empty():
		return 1.0
	var good: int = 0
	for op in list:
		if not op.get("bad", false):
			good += 1
	return float(good) / float(list.size())

func get_collection_satisfaction_pct() -> float:
	# c234「曲高和寡」= 妙音坊店员数量藏品：设计方案指定满意度+5%；其 special 槽已挂徒弟赚速，故此处读取式直连
	if g.collection_system.is_owned("c234"):
		return float(get_satisfaction_settings().get("collection_c234_bonus", 0.05))
	return 0.0

func get_satisfaction_score() -> float:
	return clampf(get_satisfaction_rate() + get_collection_satisfaction_pct(), 0.0, 1.0)

func get_satisfaction_bonus_pct() -> float:
	var score: float = get_satisfaction_score()
	var thresholds: Array = get_satisfaction_settings().get("bonus_thresholds", [])
	thresholds.sort_custom(func(a, b): return float(a.get("gt", 0.0)) > float(b.get("gt", 0.0)))
	for t in thresholds:
		if score > float(t.get("gt", 0.0)):
			return float(t.get("pct", 0.0))
	return 0.0

func get_satisfaction_mult() -> float:
	return 1.0 + get_satisfaction_bonus_pct()

# 输出乘区：批次②满意度（好评率+满意度阈值加成）；满意度加成即三轨产出乘区
func get_output_mult() -> float:
	return get_satisfaction_mult()

func has_any_output() -> bool:
	return get_yyb_per_min() > 0.0 or get_yyw_per_min() > 0.0 or get_yyf_per_min() > 0.0

# ============ 收益罐（lazy settlement；上限截断，领取取整，fraction 留罐） ============
func settle_jar() -> void:
	_init_state()
	var now: int = int(Time.get_unix_time_from_system())
	var last: int = int(jar.get("last", 0))
	if last <= 0:
		jar["last"] = now
		return
	var elapsed_min: float = maxf(0.0, (float(now) - float(last)) / 60.0)
	var cap_min: float = float(get_jar_cap_hours() * 60)
	var settle_min: float = minf(elapsed_min, cap_min)
	if settle_min > 0.0:
		_produce_minutes(settle_min, false)
	jar["last"] = now

func has_pending() -> bool:
	settle_jar()
	if int(floor(float(jar.get("yyb", 0.0)))) > 0:
		return true
	for sid in get_support_ids():
		if int(floor(float(jar["yyw"].get(sid, 0.0)))) > 0:
			return true
	for fid in get_flower_ids():
		if int(floor(float(jar["yyf"].get(fid, 0.0)))) > 0:
			return true
	return false

func get_pending_total() -> int:
	settle_jar()
	var total: int = int(floor(float(jar.get("yyb", 0.0))))
	for sid in get_support_ids():
		total += int(floor(float(jar["yyw"].get(sid, 0.0))))
	for fid in get_flower_ids():
		total += int(floor(float(jar["yyf"].get(fid, 0.0))))
	return total

func claim_jar() -> Dictionary:
	settle_jar()
	var gains: Dictionary = {"yyb": 0, "yyw": {}, "yyf": {}}
	var yyb_gain: int = int(floor(float(jar.get("yyb", 0.0))))
	if yyb_gain > 0:
		jar["yyb"] = maxf(0.0, float(jar["yyb"]) - float(yyb_gain))
		yyb += float(yyb_gain)
		gains["yyb"] = yyb_gain
	var name_map: Dictionary = get_support_name_map()
	for sid in get_support_ids():
		var n: int = int(floor(float(jar["yyw"].get(sid, 0.0))))
		if n > 0:
			jar["yyw"][sid] = maxf(0.0, float(jar["yyw"][sid]) - float(n))
			yyw[sid] = int(yyw.get(sid, 0)) + n
			gains["yyw"][sid] = n
	for fid in get_flower_ids():
		var fn: int = int(floor(float(jar["yyf"].get(fid, 0.0))))
		if fn > 0:
			jar["yyf"][fid] = maxf(0.0, float(jar["yyf"][fid]) - float(fn))
			g.items[fid] = int(g.items.get(fid, 0)) + fn
			gains["yyf"][fid] = fn
	if int(gains["yyb"]) == 0 and (gains["yyw"] as Dictionary).is_empty() and (gains["yyf"] as Dictionary).is_empty():
		return {"ok": false, "msg": "收益罐还是空的"}
	return {"ok": true, "msg": "领取收益：" + _gains_text(gains, name_map), "gains": gains}

# 立即获得 minutes 分钟三轨产出（加速卡用）：直接入账，不进罐、不受罐上限限制
func use_accelerate_card(count: int) -> Dictionary:
	_init_state()
	if count <= 0:
		return {"ok": false, "msg": "数量错误"}
	if not has_any_output():
		return {"ok": false, "msg": "妙音坊暂无产出，请先升级建筑"}
	var gains: Dictionary = _produce_minutes(60.0 * float(count), true)
	return {"ok": true, "msg": "获得60分钟妙音坊收益：" + _gains_text(gains, get_support_name_map()), "gains": gains}

# direct=false：按期望 fractional 累积进 jar；direct=true：取整直接发放（加速卡）
func _produce_minutes(minutes: float, direct: bool) -> Dictionary:
	var gains: Dictionary = {"yyb": 0, "yyw": {}, "yyf": {}}
	if minutes <= 0.0:
		return gains
	var mult: float = get_output_mult()
	var yyb_rate: float = get_yyb_per_min() * mult
	if yyb_rate > 0.0:
		var yyb_amt: float = yyb_rate * minutes
		if direct:
			var yyb_n: int = int(floor(yyb_amt))
			if yyb_n > 0:
				yyb += float(yyb_n)
				gains["yyb"] = yyb_n
		else:
			jar["yyb"] = float(jar.get("yyb", 0.0)) + yyb_amt
	# 应援物：按居住建筑逐栋期望直写（profession 均分 1/5、档位按该建筑平均设施等级概率）
	var probs: Array = _support_probs(0.0)
	var div: float = float(get_settings().get("residence_support_divisor", 10))
	for b in get_building_list():
		if str(b.get("type", "")) != "residence" or not is_building_unlocked(b):
			continue
		var bid: String = str(b.get("id", ""))
		var lv: int = get_building_level(bid)
		if lv <= 0:
			continue
		var fac_count: int = maxi(1, (b.get("facilities", []) as Array).size())
		var avg_lv: float = float(lv) / float(fac_count)
		probs = _support_probs(avg_lv)
		var per_min: float = ceil(float(lv) / div) * mult
		var total_amt: float = per_min * minutes
		if total_amt <= 0.0:
			continue
		var plist: Array = get_profession_list()
		for pi in range(plist.size()):
			var items: Array = plist[pi].get("support_items", [])
			for gi in range(mini(items.size(), probs.size())):
				var sid: String = str(items[gi].get("id", ""))
				if sid == "":
					continue
				var amt: float = total_amt * float(probs[gi]) / 5.0
				if direct:
					var n: int = int(floor(amt))
					if n > 0:
						yyw[sid] = int(yyw.get(sid, 0)) + n
						gains["yyw"][sid] = int((gains["yyw"] as Dictionary).get(sid, 0)) + n
				else:
					jar["yyw"][sid] = float(jar["yyw"].get(sid, 0.0)) + amt
	# 缘分物：功能建筑等级均分五花
	var flower_total: float = get_yyf_per_min() * mult * minutes
	if flower_total > 0.0:
		var flowers: Array = get_flower_ids()
		if flowers.size() > 0:
			var per_flower: float = flower_total / float(flowers.size())
			for fid in flowers:
				if direct:
					var fn: int = int(floor(per_flower))
					if fn > 0:
						g.items[fid] = int(g.items.get(fid, 0)) + fn
						gains["yyf"][fid] = int((gains["yyf"] as Dictionary).get(fid, 0)) + fn
				else:
					jar["yyf"][fid] = float(jar["yyf"].get(fid, 0.0)) + per_flower
	return gains

func _support_probs(avg_lv: float) -> Array:
	var grades: Array = _extra("support_table").get("grades", [])
	if grades.is_empty():
		return [1.0]
	var raw: Array = []
	var sum: float = 0.0
	for gr in grades:
		var p: float = float(gr.get("initial_pct", 0.0)) + float(gr.get("slope_per_level", 0.0)) * maxf(0.0, avg_lv - 1.0)
		p = clampf(p, float(gr.get("min_pct", 0.0)), float(gr.get("max_pct", 100.0)))
		raw.append(p)
		sum += p
	if sum <= 0.0:
		return [1.0]
	var out: Array = []
	for p in raw:
		out.append(float(p) / sum)
	return out

func _gains_text(gains: Dictionary, name_map: Dictionary) -> String:
	var parts: Array = []
	if int(gains.get("yyb", 0)) > 0:
		parts.append("应援币×%s" % _fmt_num(int(gains["yyb"])))
	for sid in (gains.get("yyw", {}) as Dictionary).keys():
		var n: int = int(gains["yyw"][sid])
		if n > 0:
			parts.append("%s×%d" % [str(name_map.get(sid, sid)), n])
	for fid in (gains.get("yyf", {}) as Dictionary).keys():
		var fn: int = int(gains["yyf"][fid])
		if fn > 0:
			parts.append("%s×%d" % [str(g.ITEM_CONFIG.get(fid, {}).get("name", fid)), fn])
	if parts.is_empty():
		return "暂无收益"
	return "、".join(parts)

func _fmt_num(n: int) -> String:
	if n >= 100000000:
		return "%.2f亿" % (float(n) / 100000000.0)
	if n >= 10000:
		return "%.2f万" % (float(n) / 10000.0)
	return str(n)

# ============ 勋章（女团等级）：繁荣度=应援币总产出/分；赚速读取式挂 shop_system ============
func get_medal_count() -> int:
	return _extra("medal").get("medals", []).size()

func get_medal_lv() -> int:
	return medal_lv

func get_medal_cfg(lv: int) -> Dictionary:
	var arr: Array = _extra("medal").get("medals", [])
	if lv < 1 or lv > arr.size():
		return {}
	return arr[lv - 1]

func get_medal_name(lv: int = -1) -> String:
	if lv < 0:
		lv = medal_lv
	return str(get_medal_cfg(lv).get("name", "妙音坊勋章"))

# 繁荣度=全部已解锁建筑等级×10 = 应援币总产出/分（设计方案 §2，用户已确认）
func get_prosperity() -> int:
	return int(get_yyb_per_min())

func get_medal_shop_pct() -> float:
	return float(get_medal_cfg(medal_lv).get("shop_pct", 0.0))

func get_next_medal_need() -> int:
	var nxt: Dictionary = get_medal_cfg(medal_lv + 1)
	if nxt.is_empty():
		return -1
	return int(nxt.get("need_prosperity", 0))

func can_upgrade_medal() -> Dictionary:
	var need: int = get_next_medal_need()
	if need < 0:
		return {"ok": false, "msg": "已达满级"}
	if get_prosperity() < need:
		return {"ok": false, "msg": "繁荣度不足"}
	return {"ok": true}

func upgrade_medal() -> Dictionary:
	var chk: Dictionary = can_upgrade_medal()
	if not chk.get("ok", false):
		return chk
	medal_lv = clampi(medal_lv + 1, 1, get_medal_count())
	return {"ok": true}
