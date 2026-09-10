# ============================================================
# 商战系统（第5批新增：税所 / 小队战斗 / 兑换商店）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 配置外置 res://data/war.json（由 GameData._load_all_configs 加载进 g._war_configs）
# 【改】2026-09-10 商战重构：
#       1) 出战限制改为按门客——队内门客全部今日出战过才不可出战；
#          结算战力 = 队内"今日未出战门客"的赚速之和，结算后这些门客标记今日已出战
#       2) 奖励改为战力基数制（war.json power_bases 分档表，见 get_reward_base）
#       3) 小队不再设上限，玩家手动增删（add_squad / remove_squad）
# ============================================================
class_name WarSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 【新增】门客级出战记录 {hero_id: "YYYY-MM-DD"}——今日限制按门客而非按小队。
# 本字段由本系统内部持有（不占用 GameData 声明），随 get_save_data 落盘、load_save_data 认领
var hero_battle: Dictionary = {}

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
		"war_last_battle": g.war_last_battle, # 【legacy】旧版按小队的出战日期（新逻辑不再写入，仅兼容旧档读取）
		"war_points": g.war_points,           # 商战积分
		"war_tax_yin": g.war_tax_yin,         # 商战税引
		"war_hero_battle": hero_battle,       # 【新增】门客级出战记录（按门客的今日限制）
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
	# 【新增】门客出战记录（旧档无此字段 = 全员今日未出战，自然兼容）
	if s.has("war_hero_battle") and s.war_hero_battle is Dictionary:
		hero_battle = s.war_hero_battle.duplicate(true)

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
# 【改】小队数量不再设上限（原 上限=门客总数÷6+1 作废），玩家手动增删
# 当前小队数量
func get_squad_count() -> int:
	return g.war_squads.size()

# 【legacy】旧接口保留兼容（game_data 转发层仍在用），语义=当前小队数量
func get_max_squads() -> int:
	return get_squad_count()

# 取小队数据（6格，空位为""；首次访问自动补齐）
func get_squad(squad_index: int) -> Array:
	var size = int(get_settings().get("squad_size", 6))
	while g.war_squads.size() <= squad_index:
		var sq = []
		for i in range(size):
			sq.append("")
		g.war_squads.append(sq)
	return g.war_squads[squad_index]

# 【新增】新增一支空小队（6 个空格子）
func add_squad() -> Dictionary:
	var size = int(get_settings().get("squad_size", 6))
	var sq = []
	for i in range(size):
		sq.append("")
	g.war_squads.append(sq)
	return {"ok": true}

# 【新增】删除小队（队内门客自然移出；后续小队编号前移，
#       legacy 的 war_last_battle 按小队序号记录同步移位，防止语义错乱）
func remove_squad(squad_index: int) -> Dictionary:
	if squad_index < 0 or squad_index >= g.war_squads.size():
		return {"ok": false, "reason": "小队不存在"}
	g.war_squads.remove_at(squad_index)
	var shifted := {}
	for k in g.war_last_battle.keys():
		var i = int(k)
		if i < squad_index:
			shifted[str(i)] = g.war_last_battle[k]
		elif i > squad_index:
			shifted[str(i - 1)] = g.war_last_battle[k]
		# i == squad_index 的记录随小队一并删除
	g.war_last_battle = shifted
	return {"ok": true}

# 门客所在小队序号（-1 = 未编队）
func get_hero_squad(hero_id: String) -> int:
	for i in range(g.war_squads.size()):
		if hero_id in g.war_squads[i]:
			return i
	return -1

# 编入门客到某队某格（每个门客全庄园只能占一个格子；本队同格替换允许）
func assign_hero(squad_index: int, slot: int, hero_id: String) -> Dictionary:
	# 【改】上限判断改为"小队必须已存在"（不再随门客数自动扩编）
	if squad_index < 0 or squad_index >= g.war_squads.size():
		return {"ok": false, "reason": "小队不存在"}
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

# 小队总战力 = 队内全部门客赚速之和（显示用）
func get_squad_power(squad_index: int) -> int:
	var total = 0
	for hid in get_squad(squad_index):
		if hid != "":
			total += g.get_hero_income(hid)
	return total

# ============ 出战（按门客的今日限制） ============
# 今日日期串
func _today() -> String:
	return Time.get_date_string_from_system()

# 门客今日是否已出战
func is_hero_battled(hero_id: String) -> bool:
	return hero_battle.get(hero_id, "") == _today()

# 【新增】队内"今日未出战"的门客列表——出战限制看门客不看小队：
# 只要有任意门客今日未出战，小队就可出战；结算战力也只算这些门客
func get_ready_heroes(squad_index: int) -> Array:
	var ready := []
	if squad_index < 0 or squad_index >= g.war_squads.size():
		return ready
	for hid in g.war_squads[squad_index]:
		if hid != "" and not is_hero_battled(hid):
			ready.append(hid)
	return ready

# 【改】今日是否可出战：队内存在今日未出战的门客即可（空队/全员已出战 = false）
func can_battle(squad_index: int) -> bool:
	return not get_ready_heroes(squad_index).is_empty()

# ============ 战斗奖励（战力基数制） ============
# 奖励基数档默认值：战力越高基数越高，但只分档不随战力无限膨胀
# （war.json settings.power_bases 可覆盖，格式 [[最低战力, 基数], ...] 按最低战力升序）
const DEFAULT_POWER_BASES := [
	[0, 100],            # 1万以内
	[10000, 1000],       # 1万~10万
	[100000, 2000],      # 10万~100万
	[1000000, 3000],     # 100万~1000万
	[10000000, 4000],    # 1000万~1亿
	[100000000, 5000],   # 1亿~100亿
	[10000000000, 6000], # 百亿以上
]

# 按战力查奖励基数：取"最低战力 ≤ 战力"的最高一档
func get_reward_base(power: float) -> int:
	var base = 100
	for pair in get_settings().get("power_bases", DEFAULT_POWER_BASES):
		if power >= float(pair[0]):
			base = int(pair[1])
	return base

# 单场结算（内部方法）：npc = 战力×0.8~1.3 随机；胜=全奖，负=lose_reward_pct
# 奖励：积分 = 基数×胜负系数×(1+c068藏品加成)；税引 = 基数×0.5×胜负系数
func _settle(power: float) -> Dictionary:
	var st = get_settings()
	var npc = power * randf_range(float(st.get("npc_power_min", 0.8)), float(st.get("npc_power_max", 1.3)))
	var win = power >= npc
	var reward_pct = 1.0 if win else float(st.get("lose_reward_pct", 0.3))
	var base = get_reward_base(power)
	var points = base * reward_pct * (1.0 + g.collection_system.get_war_points_pct())   # 积分吃 c068（+5%/星）
	var yin = base * 0.5 * reward_pct
	g.war_points += points
	g.war_tax_yin += yin
	# 商战击败人数计数（胜场30-60人，败场1-30人，挚友目标用）
	var kills = randi_range(30, 60) if win else randi_range(1, 30)
	g.goal_system.add_stat("war_kills", kills)
	return {"win": win, "npc_power": int(npc), "points": int(points), "yin": int(yin), "kills": kills}

# 把一组门客标记为今日已出战（内部方法）
func _mark_battled(hero_ids: Array):
	var today = _today()
	for hid in hero_ids:
		hero_battle[hid] = today

# 【改】单队出战：以队内"今日未出战门客"的赚速之和为战力结算；
#       结算后这些门客全部标记今日已出战（门客今日不可再参战，换队也不行）
func battle(squad_index: int) -> Dictionary:
	if squad_index < 0 or squad_index >= g.war_squads.size():
		return {"ok": false, "reason": "小队不存在"}
	var ready = get_ready_heroes(squad_index)
	if ready.is_empty():
		return {"ok": false, "reason": "队内门客今日均已出战"}
	var power = 0
	for hid in ready:
		power += g.get_hero_income(hid)
	var r = _settle(power)
	_mark_battled(ready)
	g.war_last_battle[str(squad_index)] = _today()   # legacy 字段同步写一份（无害，兼容旧读档路径）
	return {"ok": true, "win": r.win, "power": power, "npc_power": r.npc_power, "points": r.points, "yin": r.yin, "kills": r.kills}

# 【新增】快速战斗：所有可出战小队各自动结算一场（今日已出战门客跳过、空队跳过），返回汇总
func quick_battle() -> Dictionary:
	var results := []
	var wins = 0
	var total_points = 0
	var total_yin = 0
	for idx in range(g.war_squads.size()):
		var ready = get_ready_heroes(idx)
		if ready.is_empty():
			continue    # 空队或队内门客今日均已出战，跳过
		var power = 0
		for hid in ready:
			power += g.get_hero_income(hid)
		if power <= 0:
			continue
		var r = _settle(power)
		_mark_battled(ready)
		g.war_last_battle[str(idx)] = _today()   # legacy 字段同步
		if r.win:
			wins += 1
		total_points += r.points
		total_yin += r.yin
		results.append({"idx": idx, "win": r.win, "power": power, "npc_power": r.npc_power, "points": r.points, "yin": r.yin})
	return {"ok": true, "battles": results.size(), "wins": wins, "points": total_points, "yin": total_yin, "results": results}

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
