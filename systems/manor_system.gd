# ============================================================
# 庄园系统（第4批新增：农场+牧场挂机产出）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 配置外置 res://data/manor.json（由 GameData._load_all_configs 加载进 g._manor_configs）
# ============================================================
class_name ManorSystem
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
		"manor_plots": g.manor_plots,               # 各地块 品种等级/土地血统等级
		"manor_goods": g.manor_goods,               # 庄园仓库
		"manor_last_settle": g.manor_last_settle,   # 上次结算时间戳
	}

# 从扁平存档表认领本系统字段（老存档缺字段则保持初始值，自动兼容）
func load_save_data(s: Dictionary):
	if s.has("manor_plots"): g.manor_plots = s.manor_plots.duplicate(true)
	if s.has("manor_goods"): g.manor_goods = s.manor_goods.duplicate(true)
	if s.has("manor_last_settle"): g.manor_last_settle = int(s.manor_last_settle)
	# 清理存档中已不存在的品种（防止配置删了存档还残留）
	for sid in g.manor_plots.keys():
		if get_species_cfg(sid).is_empty():
			g.manor_plots.erase(sid)

# ============ 配置读取 ============
# 庄园全局参数（manor.json 的 settings 段）
func get_settings() -> Dictionary:
	return g._manor_configs.get("settings", {})

# 品种表（kind = "crops" 农场 / "animals" 牧场）
func get_species_list(kind: String) -> Array:
	return g._manor_configs.get(kind, [])

# 每品种的地/圈数量（配置驱动，当前为4）
func get_plots_per_species() -> int:
	return int(get_settings().get("plots_per_species", 4))

# 按 id 查品种配置（农场/牧场两个表都找；找不到返回空字典）
func get_species_cfg(species_id: String) -> Dictionary:
	for kind in ["crops", "animals"]:
		for cfg in get_species_list(kind):
			if cfg.get("id", "") == species_id:
				return cfg
	return {}

# ============ 解锁推导（身份等级驱动，无需入存档） ============
# 品种是否已解锁（身份达到品种的解锁等级）
func is_species_unlocked(species_id: String) -> bool:
	var cfg = get_species_cfg(species_id)
	if cfg.is_empty(): return false
	return g.identity_level >= int(cfg.get("unlock_identity", 1))

# 某品种已解锁的地/圈数量（0~4）：第N块要求身份 = 品种解锁等级 + 阶梯偏移
func get_unlocked_plot_count(species_id: String) -> int:
	if not is_species_unlocked(species_id): return 0
	var base_lv = int(get_species_cfg(species_id).get("unlock_identity", 1))
	var steps = get_settings().get("plot_identity_steps", [0, 4, 8, 12])
	var count = 0
	for s in steps:
		if g.identity_level >= base_lv + int(s):
			count += 1
	return count

# 第 plot_index 块解锁所需的身份等级（供 UI 显示"第N块 身份X级解锁"）
func get_plot_need_identity(species_id: String, plot_index: int) -> int:
	var steps = get_settings().get("plot_identity_steps", [0, 4, 8, 12])
	if plot_index < 0 or plot_index >= steps.size(): return 999
	return int(get_species_cfg(species_id).get("unlock_identity", 1)) + int(steps[plot_index])

# ============ 地块数据（每块独立 品种等级 / 土地血统等级） ============
# 取某品种全部地块数据，首次访问自动初始化为 品种Lv1 / 土地Lv0
func _get_plots(species_id: String) -> Array:
	if not g.manor_plots.has(species_id):
		var arr = []
		for i in range(get_plots_per_species()):
			arr.append({"level": 1, "land": 0})
		g.manor_plots[species_id] = arr
	return g.manor_plots[species_id]

# 取某一块的数据（{"level": 品种等级, "land": 土地/血统等级}）
func get_plot(species_id: String, plot_index: int) -> Dictionary:
	return _get_plots(species_id)[plot_index]

# ============ 产量计算 ============
# 品种等级上限 = 土地/血统当前等级 × 50
func get_plot_level_cap(land_level: int) -> int:
	return land_level * int(get_settings().get("level_per_land", 50))

# 单块产量/分钟 = 基础产量 × (1 + 土地/血统加成) × (1 + 其他加成[宅院等，后续开发])
# 基础产量 = 60 + (品种等级-1) × 1；土地/血统加成 = 土地/血统等级 × 25%
func get_plot_rate(species_id: String, plot_index: int) -> float:
	var st = get_settings()
	var plot = get_plot(species_id, plot_index)
	var base = float(st.get("base_rate", 60)) + (int(plot.level) - 1) * float(st.get("rate_per_level", 1))
	var land_pct = int(plot.land) * float(st.get("land_pct_per_level", 0.25))
	var other_pct = 0.0   # 其他加成（预留）
	return base * (1.0 + land_pct) * (1.0 + other_pct)

# 品种总产量/分钟 = 已解锁几块地的产量之和
func get_species_rate(species_id: String) -> float:
	var total = 0.0
	for i in range(get_unlocked_plot_count(species_id)):
		total += get_plot_rate(species_id, i)
	return total

# ============ 升级 ============
# 品种等级升级费用（铜钱）= 5000 × 当前等级²
func get_level_up_cost(cur_level: int) -> int:
	return int(get_settings().get("level_up_money_base", 5000)) * cur_level * cur_level

# 土地/血统升级费用（商铺图纸张数）：第1~5次各20张，第6次起增量按 +5/+10/+15 循环
# （第6次25、第7次35、第8次50、第9次55、第10次65……）
func get_land_up_cost(cur_land: int) -> int:
	var st = get_settings()
	var flat = int(st.get("blueprint_flat", 20))
	var flat_count = int(st.get("blueprint_flat_count", 5))
	var nth = cur_land + 1   # 第几次升级（0级升1级 = 第1次）
	if nth <= flat_count: return flat
	var cost = flat
	var incs = st.get("blueprint_increments", [5, 10, 15])
	for i in range(flat_count, nth):
		cost += int(incs[(i - flat_count) % incs.size()])
	return cost

# 升级某块的品种等级（耗铜钱；上限 = 土地/血统等级 × 50）
func upgrade_plot_level(species_id: String, plot_index: int) -> Dictionary:
	if plot_index >= get_unlocked_plot_count(species_id):
		return {"ok": false, "reason": "该地块尚未解锁"}
	var plot = get_plot(species_id, plot_index)
	var lv = int(plot.level)
	var cap = get_plot_level_cap(int(plot.land))
	if lv >= cap:
		return {"ok": false, "reason": "已达等级上限（土地/血统等级×50），请先升级土地/血统"}
	var cost = get_level_up_cost(lv)
	if g.money < cost:
		return {"ok": false, "reason": "铜钱不足"}
	g.money -= cost
	plot.level = lv + 1
	return {"ok": true}

# 升级某块的土地/血统（耗商铺图纸；上限20级）
func upgrade_plot_land(species_id: String, plot_index: int) -> Dictionary:
	if plot_index >= get_unlocked_plot_count(species_id):
		return {"ok": false, "reason": "该地块尚未解锁"}
	var plot = get_plot(species_id, plot_index)
	var land = int(plot.land)
	if land >= int(get_settings().get("max_land_level", 20)):
		return {"ok": false, "reason": "土地/血统已满级"}
	var cost = get_land_up_cost(land)
	if g.items.get("shop_blueprint", 0) < cost:
		return {"ok": false, "reason": "商铺图纸不足（需要%d张）" % cost}
	g.items["shop_blueprint"] -= cost
	plot.land = land + 1
	return {"ok": true}

# ============ 产量结算 ============
# 仓库中某产物的数量
func get_goods_count(product: String) -> int:
	return int(g.manor_goods.get(product, 0))

# 按经过的分钟数，把所有已解锁地块的产量入仓库（内部方法）
func _add_production(minutes: float):
	if minutes <= 0.0: return
	for kind in ["crops", "animals"]:
		for cfg in get_species_list(kind):
			var sid = cfg.get("id", "")
			if get_unlocked_plot_count(sid) <= 0: continue
			var product = cfg.get("product", cfg.get("name", sid))
			g.manor_goods[product] = g.manor_goods.get(product, 0.0) + get_species_rate(sid) * minutes

# 在线懒结算：按距上次结算的时间差入库（挂在每秒自动收益处调用）
func settle():
	var now = int(Time.get_unix_time_from_system())
	if g.manor_last_settle <= 0:
		g.manor_last_settle = now   # 首次（新档/旧档升级）只初始化时间戳，不补产量
		return
	var elapsed = now - g.manor_last_settle
	if elapsed <= 0: return
	g.manor_last_settle = now
	_add_production(elapsed / 60.0)

# 离线结算：登录时调用，按离线时长 × 100%产量 入库（上限24小时）
# 离线秒数口径与店铺离线收益一致（正常退出用登出时间，闪退用上次登录时间）
# 注意：必须在 last_login_time 被更新为"本次登录"之前调用
func settle_offline():
	if g.last_logout_time <= 0 and g.last_login_time <= 0: return
	var now = int(Time.get_unix_time_from_system())
	var offline_seconds = 0
	if g.last_logout_time > g.last_login_time:
		offline_seconds = now - g.last_logout_time   # 上次正常退出
	elif g.last_login_time > 0:
		offline_seconds = now - g.last_login_time    # 闪退/强退
	offline_seconds = clamp(offline_seconds, 0, int(get_settings().get("offline_cap_hours", 24)) * 3600)
	if offline_seconds <= 0: return
	_add_production(offline_seconds / 60.0)
	# 结算后同步时间戳，避免在线 settle 重复结算同一段时间
	g.manor_last_settle = now
	print("庄园离线产量已结算，离线时长：", offline_seconds, "秒")
	
# 连升某块的品种等级（默认10次：逐次结算，费用随等级递增；满级或铜钱不足即停）
# 返回 {"ok": 是否至少升了1级, "done": 实际升级次数, "reason": 失败原因（一次都没升成时）}
func upgrade_plot_level_batch(species_id: String, plot_index: int, times: int = 10) -> Dictionary:
	var done = 0
	var last_reason = ""
	for i in range(times):
		var r = upgrade_plot_level(species_id, plot_index)
		if not r.ok:
			last_reason = r.reason
			break
		done += 1
	if done == 0:
		return {"ok": false, "done": 0, "reason": last_reason}
	return {"ok": true, "done": done}
