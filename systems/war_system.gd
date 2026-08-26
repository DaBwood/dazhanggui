# ============================================================
# 商战系统（第5批新增：税所 / 小队战斗 / 兑换商店）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 配置外置 res://data/war.json（由 GameData._load_all_configs 加载进 g._war_configs）
# ============================================================
class_name WarSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 提供本系统的存档字段（由 GameData.save_game 合并进扁平存档表）
func get_save_data() -> Dictionary:
	return {
		"war_tax_level": g.war_tax_level,     # 税所等级
		"war_tax_accum": g.war_tax_accum,     # 税所已累积秒数（封顶500分钟）
		"war_tax_last": g.war_tax_last,       # 上次累积结算时间戳
		"war_squads": g.war_squads,           # 小队编队（每队6格，空位""）
		"war_last_battle": g.war_last_battle, # 各小队最后出战日期
		"war_points": g.war_points,           # 商战积分
		"war_tax_yin": g.war_tax_yin,         # 商战税引
	}

# 从扁平存档表认领本系统字段（老存档缺字段则保持初始值，自动兼容）
func load_save_data(s: Dictionary):
	if s.has("war_tax_level"): g.war_tax_level = int(s.war_tax_level)
	if s.has("war_tax_accum"): g.war_tax_accum = float(s.war_tax_accum)
	if s.has("war_tax_last"): g.war_tax_last = int(s.war_tax_last)
	if s.has("war_squads"): g.war_squads = s.war_squads.duplicate(true)
	if s.has("war_last_battle"): g.war_last_battle = s.war_last_battle.duplicate(true)
	if s.has("war_points"): g.war_points = float(s.war_points)
	if s.has("war_tax_yin"): g.war_tax_yin = float(s.war_tax_yin)

# ============ 配置读取 ============
# 商战全局参数（war.json 的 settings 段）
func get_settings() -> Dictionary:
	return g._war_configs.get("settings", {})

# 兑换商店表
func get_exchange_list() -> Array:
	return g._war_configs.get("exchange", [])

# ============ 门客信息（战斗组队用） ============
# 已拥有门客 id 列表
func get_hero_list() -> Array:
	return g.heroes.keys()

# 门客显示名（查 heroes.json 配置，兜底返回 id）
func get_hero_name(hero_id: String) -> String:
	return g._hero_configs.get(hero_id, {}).get("name", hero_id)

# ============ 税所 ============
# 税所加成倍数 = 1 + 1.58 × ((等级-1)/98)^1.5（99级=2.58倍，200级≈5.56倍）
func get_tax_multiplier() -> float:
	var st = get_settings()
	var t = (g.war_tax_level - 1) / float(st.get("tax_mult_curve_levels", 98))
	return float(st.get("tax_mult_base", 1.0)) + float(st.get("tax_mult_span", 1.58)) * pow(maxf(t, 0.0), float(st.get("tax_mult_curve_exp", 1.5)))

# 税所累积上限（分钟）
func get_tax_cap_minutes() -> int:
	return int(get_settings().get("tax_cap_minutes", 500))

# 税所升级消耗（商战税引）= 10 × 当前等级²（99级=98010）
func get_tax_up_cost() -> int:
	return int(get_settings().get("tax_up_cost_base", 10)) * g.war_tax_level * g.war_tax_level

# 升级税所（耗商战税引，上限200级）
func upgrade_tax() -> Dictionary:
	var max_lv = int(get_settings().get("tax_max_level", 200))
	if g.war_tax_level >= max_lv:
		return {"ok": false, "reason": "税所已满级"}
	var cost = get_tax_up_cost()
	if g.war_tax_yin < cost:
		return {"ok": false, "reason": "商战税引不足（需要%d）" % cost}
	g.war_tax_yin -= cost
	g.war_tax_level += 1
	return {"ok": true}

# 把距上次结算的时间并入累积（封顶500分钟），并更新结算时间戳（内部方法）
func _settle_tax_accum():
	var now = int(Time.get_unix_time_from_system())
	if g.war_tax_last <= 0:
		g.war_tax_last = now   # 首次（新档/旧档升级）只初始化时间戳
		return
	var cap_sec = get_tax_cap_minutes() * 60
	g.war_tax_accum = minf(g.war_tax_accum + (now - g.war_tax_last), cap_sec)
	g.war_tax_last = now

# 已累积的挂机时间（分钟；先结算再返回）
func get_tax_accum_minutes() -> float:
	_settle_tax_accum()
	return g.war_tax_accum / 60.0

# 当前可领取金额 = 当前总赚速 × 税所加成 × 累积秒数
func get_tax_pending_income() -> float:
	_settle_tax_accum()
	return g.get_total_auto_income() * get_tax_multiplier() * g.war_tax_accum

# 领取税所收益（入账并清零累积）
func claim_tax() -> Dictionary:
	_settle_tax_accum()
	if g.war_tax_accum <= 0.0:
		return {"ok": false, "reason": "暂无累积收益"}
	var amount = int(g.get_total_auto_income() * get_tax_multiplier() * g.war_tax_accum)
	g.money += amount
	g.war_tax_accum = 0.0
	return {"ok": true, "amount": amount}

# ============ 小队 ============
# 小队数量上限 = 门客总数 ÷ 6（向下取整）
func get_max_squads() -> int:
	return int(g.heroes.size() / int(get_settings().get("squad_size", 6)))+1

# 取小队数据（6格，空位为""；首次访问自动补齐）
func get_squad(squad_index: int) -> Array:
	var size = int(get_settings().get("squad_size", 6))
	while g.war_squads.size() <= squad_index:
		var sq = []
		for i in range(size):
			sq.append("")
		g.war_squads.append(sq)
	return g.war_squads[squad_index]

# 门客所在小队序号（-1 = 未编队）
func get_hero_squad(hero_id: String) -> int:
	for i in range(g.war_squads.size()):
		if hero_id in g.war_squads[i]:
			return i
	return -1

# 编入门客到某队某格（每个门客全庄园只能占一个格子；本队同格替换允许）
func assign_hero(squad_index: int, slot: int, hero_id: String) -> Dictionary:
	if squad_index < 0 or squad_index >= get_max_squads():
		return {"ok": false, "reason": "小队不存在（小队上限=门客总数÷6）"}
	if not g.heroes.has(hero_id):
		return {"ok": false, "reason": "未拥有该门客"}
	var owner = get_hero_squad(hero_id)
	if owner >= 0 and owner != squad_index:
		return {"ok": false, "reason": "该门客已在第%d小队" % (owner + 1)}
	# 拦截"本队其他格"重复（修复：同一人曾可占满6格）
	var sq = get_squad(squad_index)
	for s in range(sq.size()):
		if sq[s] == hero_id and s != slot:
			return {"ok": false, "reason": "该门客已在本小队其他位置"}
	get_squad(squad_index)[slot] = hero_id
	return {"ok": true}

# 移出某队某格的门客
func remove_hero(squad_index: int, slot: int) -> Dictionary:
	get_squad(squad_index)[slot] = ""
	return {"ok": true}

# 小队战力 = 队内门客赚速之和
func get_squad_power(squad_index: int) -> int:
	var total = 0
	for hid in get_squad(squad_index):
		if hid != "":
			total += g.get_hero_income(hid)
	return total

# 今日是否可出战（每队每天1次，按日期字符串跨天重置）
func can_battle(squad_index: int) -> bool:
	var today = Time.get_date_string_from_system()
	return g.war_last_battle.get(str(squad_index), "") != today

# 出战：NPC商队战力 = 小队战力 × 随机0.8~1.3；胜=全奖，负=30%
# 奖励：商战积分 = 战力×0.01，商战税引 = 战力×0.005（负方再×0.3）
func battle(squad_index: int) -> Dictionary:
	if squad_index < 0 or squad_index >= get_max_squads():
		return {"ok": false, "reason": "小队不存在"}
	if not can_battle(squad_index):
		return {"ok": false, "reason": "该小队今日已出战"}
	var power = get_squad_power(squad_index)
	if power <= 0:
		return {"ok": false, "reason": "小队没有战力（至少编入1名门客）"}
	var st = get_settings()
	var npc = power * randf_range(float(st.get("npc_power_min", 0.8)), float(st.get("npc_power_max", 1.3)))
	var win = power >= npc
	var reward_pct = 1.0 if win else float(st.get("lose_reward_pct", 0.3))
	var points = power * float(st.get("points_rate_win", 0.01)) * reward_pct
	var yin = power * float(st.get("yin_rate_win", 0.005)) * reward_pct
	g.war_points += points
	g.war_tax_yin += yin
	g.war_last_battle[str(squad_index)] = Time.get_date_string_from_system()
	# 【第6批新增】商战击败人数计数（胜场30-60人，败场1-30人，挚友目标用）
	var kills = randi_range(30, 60) if win else randi_range(1, 30)
	g.goal_system.add_stat("war_kills", kills)
	return {"ok": true, "win": win, "power": power, "npc_power": int(npc), "points": int(points), "yin": int(yin),"kills": kills,}

# ============ 兑换商店 ============
# 用商战积分兑换道具（不限购；新道具 patient_manual/cricket_cage 为后续玩法预留）
func exchange_item(item_id: String) -> Dictionary:
	var cost = -1
	for e in get_exchange_list():
		if e.get("item", "") == item_id:
			cost = int(e.get("cost", 0))
			break
	if cost < 0:
		return {"ok": false, "reason": "兑换表无此道具"}
	if g.war_points < cost:
		return {"ok": false, "reason": "商战积分不足（需要%d）" % cost}
	g.war_points -= cost
	g.items[item_id] = g.items.get(item_id, 0) + 1
	return {"ok": true}
