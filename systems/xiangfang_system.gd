# ============================================================
# 厢房玩法系统（批次① 2026-09-20：家具/升级/套装/舒适度/风水推导/工坊直购/回收/勋章）
# 设计口径：厢房设计方案 v1.0 §1~§5、§7；配置 data/xiangfang.json（296 家具/20 套装/勋章 15 级/风水概率）
# 家具模型：{lv, cnt}——lv=当前等级(0=未解锁)，cnt=持有件数；升级 n→n+1 消耗 cost(n) 件同名家具并返风水符；
#           首件获得自动 0→1 解锁（无双"初始未解锁、首个同名件解锁"口径对全品质统一，玩家零成本理解）。
# 舒适度=Σ等级×每级舒适度（推导值，唯一消耗口=勋章门槛）；风水=Σ无双家具等级×100（唯一来源=无双家具）。
# 套装等级=手动解锁/升级（用户 2026-09-20 拍板）：存档存 set_lv，解锁/升级无消耗；
#           前提=套内家具最低件等级≥目标级（0→1 需全套≥1 级，1→2 需全套≥2 级，依此类推，上限 50）；
#           条件未达点击弹提示"需要全套家具达到XX级"；效果=配置表值×套装等级（表值同 xlsx）。
# 勋章：15 级×舒适度门槛手动升级；效果①全部商铺赚速+100%/级=读取式挂 shop bonus 链（批次② view+挂点）；
#       效果②初始技能等级上限挂起未接（同酒坊/妙音坊，配置已带 skill_cap 字段）。
# 货币：家具币=普通道具 items 轨（id "jiajibi"，道具表原有占位道具，用户 2026-09-20 拍板接入——
#       不开独立货币 var，珍兽果双轨坑铁律）；风水符=普通道具 fengshui_fu 同轨。回收主来源，批次②接 UI。
# ============================================================
class_name XiangfangSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有，随 get_save_data 落盘） ----------
var furniture: Dictionary = {}   # {fid: {lv, cnt}}
var set_levels: Dictionary = {}  # {sid: 套装等级}（手动解锁/升级制，用户 2026-09-20 拍板；上限=套内最低件等级）
var medal_lv: int = 1            # 勋章等级 1~15

# 家具币道具 id（道具表 items.json 原有占位道具，直接复用不开存档字段）
const JIAJIBI_ITEM := "jiajibi"

func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {"xiangfang": {
		"furniture": furniture, "set_levels": set_levels, "medal": medal_lv,
	}}

# 从扁平存档表认领本系统字段（旧档缺 xiangfang 段则按初始形状建档）
func load_save_data(s: Dictionary):
	if not s.has("xiangfang") or not (s.xiangfang is Dictionary):
		_init_state()
		return
	var d: Dictionary = s.xiangfang
	furniture = d.get("furniture", {})
	if not (furniture is Dictionary):
		furniture = {}
	# 旧版内置 jiajibi 字段迁移：一次性折算进道具轨（防早期测试档丢币）
	if d.has("jiajibi") and int(d.get("jiajibi", 0)) > 0:
		_grant_jiajibi(int(d.get("jiajibi", 0)))
	medal_lv = clampi(int(d.get("medal", 1)), 1, get_medal_count())
	_init_state()

# 存档形状兜底：逐件钳等级/件数（空容器也是 Dictionary，读档即自愈，防"空表死锁"同类坑）
func _init_state() -> void:
	medal_lv = clampi(medal_lv, 1, get_medal_count())
	for fid in furniture.keys():
		var entry = furniture[fid]
		if not (entry is Dictionary):
			furniture.erase(fid)
			continue
		entry["lv"] = clampi(int(entry.get("lv", 0)), 0, get_max_lv())
		entry["cnt"] = maxi(0, int(entry.get("cnt", 0)))

# ============ 配置读取（静态匹配读配置不读存档快照——加成范式铁律） ============
func _cfg() -> Dictionary:
	return g._xiangfang_configs

func get_max_lv() -> int:
	return int(_cfg().get("settings", {}).get("max_lv", 50))

func get_quality_cfg(quality: String) -> Dictionary:
	return _cfg().get("qualities", {}).get(quality, {})

func get_furniture_cfg(fid: String) -> Dictionary:
	return _cfg().get("furniture", {}).get(fid, {})

func get_set_cfg(sid: String) -> Dictionary:
	for s in _cfg().get("sets", []):
		if str(s.get("id", "")) == sid:
			return s
	return {}

func get_set_list() -> Array:
	return _cfg().get("sets", [])

# 某套装的家具配置列表（按配置件序）
func get_set_furniture(sid: String) -> Array:
	var out: Array = []
	var s: Dictionary = get_set_cfg(sid)
	for fid in s.get("items", []):
		var fc: Dictionary = get_furniture_cfg(str(fid))
		if not fc.is_empty():
			out.append(fc)
	return out

# ============ 家具状态 ============
func get_furniture_state(fid: String) -> Dictionary:
	var e = furniture.get(fid, {})
	if e is Dictionary:
		return {"lv": int(e.get("lv", 0)), "cnt": int(e.get("cnt", 0))}
	return {"lv": 0, "cnt": 0}

func is_unlocked(fid: String) -> bool:
	return get_furniture_state(fid)["lv"] > 0

# 发放家具：cnt 增加；首件自动 0→1 解锁（无双口径，全品质统一）
func gain_furniture(fid: String, n: int) -> void:
	if n <= 0 or get_furniture_cfg(fid).is_empty():
		return
	var e: Dictionary = furniture.get(fid, {"lv": 0, "cnt": 0})
	e["cnt"] = int(e.get("cnt", 0)) + n
	if int(e.get("lv", 0)) == 0:
		e["lv"] = 1
	furniture[fid] = e

# 升级消耗：n→n+1 需同名件数；无双固定 1，其余 1+floor((n-1)/step)
func get_upgrade_cost(fid: String, n: int) -> int:
	var q: Dictionary = get_quality_cfg(get_furniture_cfg(fid).get("quality", ""))
	if q.is_empty():
		return 0
	if str(q.get("cost_mode", "step")) == "fixed":
		return int(q.get("cost_fixed", 1))
	var step: int = maxi(1, int(q.get("cost_step", 1)))
	return 1 + int(floor((n - 1) / float(step)))

# 可升级判定：未满级 且 富余件数(cnt-(lv-1)) ≥ 消耗
func can_upgrade(fid: String) -> Dictionary:
	var st: Dictionary = get_furniture_state(fid)
	if st["lv"] <= 0:
		return {"ok": false, "reason": "尚未拥有"}
	if st["lv"] >= get_max_lv():
		return {"ok": false, "reason": "已满级"}
	var cost: int = get_upgrade_cost(fid, st["lv"])
	if st["cnt"] - (st["lv"] - 1) < cost:
		return {"ok": false, "reason": "同名家具不足（需%d件）" % cost, "cost": cost}
	return {"ok": true, "cost": cost}

# 升级一次：扣件、升级、按消耗件数返风水符（每消耗1件返 quality.talisman 个）
func upgrade_furniture(fid: String) -> Dictionary:
	var chk: Dictionary = can_upgrade(fid)
	if not chk.get("ok", false):
		return chk
	var cost: int = int(chk.get("cost", 1))
	var e: Dictionary = furniture[fid]
	e["cnt"] = int(e.get("cnt", 0)) - cost
	e["lv"] = int(e.get("lv", 0)) + 1
	_grant_talisman(get_quality_cfg(get_furniture_cfg(fid).get("quality", "")).get("talisman", 0) * cost)
	return {"ok": true, "lv": e["lv"], "cost": cost}

# 一键升级：连升直到材料尽（十连语义统一：资源不足升剩余可升数）
func upgrade_all(fid: String) -> Dictionary:
	var times: int = 0
	while true:
		var r: Dictionary = upgrade_furniture(fid)
		if not r.get("ok", false):
			return {"ok": times > 0, "times": times, "reason": r.get("reason", "")}
		times += 1
	return {"ok": true, "times": times}

# 风水符发放（普通道具 items 轨；item_system 配置补0兜底，这里再 get 防御）
func _grant_talisman(n: int) -> void:
	if n <= 0:
		return
	var item_id: String = str(_cfg().get("settings", {}).get("talisman_item", "fengshui_fu"))
	g.items[item_id] = int(g.items.get(item_id, 0)) + n

func get_talisman_count() -> int:
	return int(g.items.get(str(_cfg().get("settings", {}).get("talisman_item", "fengshui_fu")), 0))

# ============ 家具币（道具 items 轨，不内置存档字段；用户 2026-09-20 拍板接入道具表 jiajibi） ============
func get_jiajibi() -> int:
	return int(g.items.get(JIAJIBI_ITEM, 0))

func _grant_jiajibi(n: int) -> void:
	if n <= 0:
		return
	g.items[JIAJIBI_ITEM] = get_jiajibi() + n

func _spend_jiajibi(n: int) -> bool:
	if get_jiajibi() < n:
		return false
	g.items[JIAJIBI_ITEM] = get_jiajibi() - n
	return true

# ============ 推导值：舒适度 / 风水 ============
# 舒适度=Σ 等级×每级舒适度（未解锁 lv=0 自然不计）
func get_total_comfort() -> int:
	var total: int = 0
	var fcfg: Dictionary = _cfg().get("furniture", {})
	for fid in furniture.keys():
		var st: Dictionary = get_furniture_state(str(fid))
		if st["lv"] <= 0:
			continue
		var q: Dictionary = get_quality_cfg(fcfg.get(str(fid), {}).get("quality", ""))
		total += st["lv"] * int(q.get("comfort", 0))
	return total

# 风水=Σ 无双家具等级×100（唯一来源；风水等级=floor(风水/100)+1，每级固定100点）
func get_fengshui() -> int:
	var total: int = 0
	var fcfg: Dictionary = _cfg().get("furniture", {})
	var per: int = int(_cfg().get("fengshui", {}).get("per_wushuang_lv", 100))
	for fid in furniture.keys():
		var st: Dictionary = get_furniture_state(str(fid))
		if st["lv"] <= 0:
			continue
		if fcfg.get(str(fid), {}).get("quality", "") == "wushuang":
			total += st["lv"] * per
	return total

func get_fengshui_level() -> int:
	var div: int = maxi(1, int(_cfg().get("fengshui", {}).get("level_div", 100)))
	return int(floor(get_fengshui() / float(div))) + 1

# 距下一级风水还差多少点（每级固定 div 点）
func get_fengshui_to_next() -> int:
	var div: int = maxi(1, int(_cfg().get("fengshui", {}).get("level_div", 100)))
	return div - get_fengshui() % div

# 风水等级 L 的 10 档品质权重（w=max(0,min(a+b(L-1), a+b(P-1)-b(L-P)))，峰值P后对称回落）
func get_fengshui_weights(fengshui_level: int) -> Array:
	var out: Array = []
	var weights: Array = _cfg().get("fengshui", {}).get("weights", [])
	var sum: float = 0.0
	for w in weights:
		var a: float = float(w.get("a", 0.0))
		var b: float = float(w.get("b", 0.0))
		var p: float = float(w.get("P", 1))
		var rise: float = a + b * (fengshui_level - 1)
		var fall: float = a + b * (p - 1) - b * (fengshui_level - p)
		var val: float = maxf(0.0, minf(rise, fall))
		out.append(val)
		sum += val
	if sum <= 0.0:
		return out
	for i in range(out.size()):
		out[i] = float(out[i]) / sum
	return out

# 按风水等级 roll 一档品质 key（累积权重 roll，权重制惯例）
func roll_quality_key(fengshui_level: int) -> String:
	var weights: Array = get_fengshui_weights(fengshui_level)
	var names: Array = _cfg().get("fengshui", {}).get("weights", [])
	var total: float = 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in range(mini(weights.size(), names.size())):
		acc += float(weights[i])
		if roll <= acc:
			return str(names[i].get("key", ""))
	return str(names[names.size() - 1].get("key", ""))

# ============ 套装（手动解锁/升级制，用户 2026-09-20 拍板） ============
# 套装等级=存档 set_levels[sid]（初始 0=未解锁无效果）；解锁/升级前提=套内最低件等级≥目标级
func get_set_level(sid: String) -> int:
	return clampi(int(set_levels.get(sid, 0)), 0, get_max_lv())

# 套装等级上限=套内最低件等级（未拥有件计 0）
func get_set_max_level(sid: String) -> int:
	var s: Dictionary = get_set_cfg(sid)
	var lv_min: int = get_max_lv()
	var any: bool = false
	for fid in s.get("items", []):
		var st: Dictionary = get_furniture_state(str(fid))
		lv_min = mini(lv_min, st["lv"])
		any = true
	if not any:
		return 0
	return lv_min

# 解锁/升级判定：set_lv+1 ≤ 套内最低件等级
func can_advance_set(sid: String) -> Dictionary:
	var cur: int = get_set_level(sid)
	if cur >= get_max_lv():
		return {"ok": false, "reason": "套装已满级"}
	var need_lv: int = cur + 1
	if get_set_max_level(sid) < need_lv:
		return {"ok": false, "reason": "需要全套家具达到%d级" % need_lv, "need_lv": need_lv}
	return {"ok": true, "need_lv": need_lv}

# 解锁/升级（无消耗）：set_lv+1
func advance_set(sid: String) -> Dictionary:
	var chk: Dictionary = can_advance_set(sid)
	if not chk.get("ok", false):
		return chk
	set_levels[sid] = get_set_level(sid) + 1
	return {"ok": true, "lv": set_levels[sid]}

# 套装效果描述（效果=表值×套装等级；等级 0 时显示基础表值供预览）
func get_set_effect_desc(sid: String) -> String:
	var s: Dictionary = get_set_cfg(sid)
	if s.is_empty():
		return ""
	var slv: int = get_set_level(sid)
	if str(s.get("effect", "")) == "aptitude_all":
		return "所有门客资质 +%d（=1×套装等级%d）" % [int(s.get("aptitude", 0)) * slv, slv] if slv > 0 else "所有门客资质 +1/套装等级"
	return "%s类门客赚钱 +%s%%（=%s%%×套装等级%d）" % [s.get("career", ""), _fmt_pct(float(s.get("pct", 0.0)) * slv), _fmt_pct(float(s.get("pct", 0.0))), slv] if slv > 0 else "%s类门客赚钱 +%s%%/套装等级" % [s.get("career", ""), _fmt_pct(float(s.get("pct", 0.0)))]

func _fmt_pct(v: float) -> String:
	var s: String = "%.2f" % v
	s = s.rstrip("0").rstrip(".")
	return s

# 套内拥有件数/总件数
func get_set_owned(sid: String) -> Dictionary:
	var s: Dictionary = get_set_cfg(sid)
	var owned: int = 0
	for fid in s.get("items", []):
		if get_furniture_state(str(fid))["cnt"] > 0:
			owned += 1
	return {"owned": owned, "total": (s.get("items", []) as Array).size()}

# ============ 工坊（直购不刷新；范围=settings.workshop_sets 前 5 套） ============
func get_workshop_price(quality: String) -> int:
	return int(_cfg().get("workshop_price", {}).get(quality, 0))

# 工坊在售清单（前 5 套全部家具）
func get_workshop_items() -> Array:
	var out: Array = []
	var fcfg: Dictionary = _cfg().get("furniture", {})
	for sid in _cfg().get("settings", {}).get("workshop_sets", []):
		var s: Dictionary = get_set_cfg(str(sid))
		for fid in s.get("items", []):
			var fc: Dictionary = fcfg.get(str(fid), {})
			if not fc.is_empty():
				out.append(fc)
	return out

# 工坊直购：扣家具币、发家具
func buy_furniture(fid: String, n: int) -> Dictionary:
	if n <= 0:
		return {"ok": false, "reason": "数量无效"}
	var fc: Dictionary = get_furniture_cfg(fid)
	if fc.is_empty():
		return {"ok": false, "reason": "家具不存在"}
	var price: int = get_workshop_price(str(fc.get("quality", "")))
	var total: int = price * n
	if not _spend_jiajibi(total):
		return {"ok": false, "reason": "家具币不足（需%d，有%d）" % [total, get_jiajibi()]}
	gain_furniture(fid, n)
	return {"ok": true, "cost": total}

# ============ 回收（满级富余件，品质工坊价×80%，批次②接 UI） ============
func get_recycle_price(quality: String) -> int:
	return int(round(get_workshop_price(quality) * float(_cfg().get("settings", {}).get("recycle_pct", 0.8))))

# 可回收件数：满级后富余件= cnt-(lv-1)（满级材料零需求，全部可回收，无需保底留一）
func get_recyclable_count(fid: String) -> int:
	var st: Dictionary = get_furniture_state(fid)
	if st["lv"] < get_max_lv():
		return 0
	return st["cnt"] - (st["lv"] - 1)

func recycle_furniture(fid: String, n: int) -> Dictionary:
	var avail: int = get_recyclable_count(fid)
	if n <= 0 or avail <= 0:
		return {"ok": false, "reason": "没有可回收的富余件"}
	n = mini(n, avail)
	var fc: Dictionary = get_furniture_cfg(fid)
	var gain: int = get_recycle_price(str(fc.get("quality", ""))) * n
	var e: Dictionary = furniture[fid]
	e["cnt"] = int(e.get("cnt", 0)) - n
	_grant_jiajibi(gain)
	return {"ok": true, "gain": gain, "n": n}

# ============ 勋章（15 级×舒适度门槛；效果①全部商铺赚速，读取式挂点见批次②） ============
func get_medal_list() -> Array:
	return _cfg().get("medal", [])

func get_medal_count() -> int:
	return (get_medal_list() as Array).size()

func get_medal_cfg(lv: int) -> Dictionary:
	for m in get_medal_list():
		if int(m.get("lv", 0)) == lv:
			return m
	return {}

func get_current_medal_cfg() -> Dictionary:
	return get_medal_cfg(medal_lv)

func get_next_medal_cfg() -> Dictionary:
	return get_medal_cfg(medal_lv + 1)

# 勋章升级判定：舒适度门槛（手动升级，进度=当前舒适度/门槛）
func can_upgrade_medal() -> Dictionary:
	var nxt: Dictionary = get_next_medal_cfg()
	if nxt.is_empty():
		return {"ok": false, "reason": "已达满级"}
	var need: int = int(nxt.get("need_comfort", 0))
	if get_total_comfort() < need:
		return {"ok": false, "reason": "舒适度不足（%d/%d）" % [get_total_comfort(), need], "need": need}
	return {"ok": true, "need": need}

func upgrade_medal() -> Dictionary:
	var chk: Dictionary = can_upgrade_medal()
	if not chk.get("ok", false):
		return chk
	medal_lv = mini(medal_lv + 1, get_medal_count())
	return {"ok": true, "lv": medal_lv}

# 全部商铺赚速加成（倍率，1.0=+100%；shop_system bonus 链读取式挂点，批次②接入）
func get_medal_shop_pct() -> float:
	return float(get_current_medal_cfg().get("shop_pct", 0.0))

func get_medal_name() -> String:
	return str(get_current_medal_cfg().get("name", "厢房勋章"))
