# ============================================================
# 垂钓系统（第8批新增：闯荡页【垂钓】子视图 + 门客渔获装备养成）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 配置外置 res://data/fishing.json（由 GameData._load_all_configs 加载进 g._fishing_configs）
# 规则要点：
#   时段按现实时间 06:00-18:00 白天 / 18:00-06:00 黑夜；天气晴雨雪随机，每次持续6小时（懒结算）
#   每次钓鱼消耗1个钓点道具：瀑湖=地龙（每小时恢复1个、无上限，懒结算）；天池=赤龙（不恢复，仅礼包/活动获取）【改】
#   天池（tianchi）：鱼池=瀑湖基础池+极.无双额外池；极.无双权重1、图鉴奖励翻倍、养成=晋升6%/阶+技能6资质/级【新增】
#   渔获可带 unlock_fish/unlock_tier 解锁条件：对应鱼种养成阶数达标才入池（如龙涎巨鲸20阶→绵阳海兔）【新增】
#   任务不满3个时每次钓鱼有10%几率改为触发任务；满3个则跳过任务roll
#   渔获存钓鱼仓库（g.fishing_storage），不进背包；首次获得解锁图鉴可领奖励
#   道具类（kind=item，水晶瓦/黄金甲等9种）仅在已接对应交付任务时才进入鱼池
#   计数类任务只统计渔获（kind=fish），道具不计数
# 渔获装备养成（模型A·按种类养成，数据存 g.fishing_fish_dev）：
#   只有 kind=fish 且品质为 无双/传奇/普通 的渔获可装备；一鱼一门客；装备不扣库存
#   晋升消耗同名鱼库存（被装备的鱼种至少保留1只）；无双赚钱=阶×5%（入门客百分比加成），
#   传奇/普通赚钱=等差固定值（入 extra_income）；技能按阶解锁，喂材料升级加资质（入总资质）
# 可拓展：新增钓点/钓具只需改 fishing.json 的 locations/gears/extra_pools，本类已按 location_id 取池
# ============================================================
class_name FishingSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 品质顺延顺序（roll到的品质当前池无候选时按此顺序向下找）
const QUALITY_ORDER: Array = ["极.无双", "无双", "传奇", "普通", "无"]   # 【改】新增极.无双档（最高档，顺延顺序龙头）

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 提供本系统的存档字段（由 GameData.save_game 合并进扁平存档表）
func get_save_data() -> Dictionary:
	return {
		"fishing_dilong": g.fishing_dilong,                 # 地龙数量
		"fishing_dilong_time": g.fishing_dilong_time,       # 上次地龙恢复结算时间戳
		"fishing_chilong": g.fishing_chilong,               # 赤龙数量（下一钓点消耗道具，预留）
		"fishing_weather": g.fishing_weather,               # 当前天气（晴/雨/雪）
		"fishing_weather_expire": g.fishing_weather_expire, # 天气过期时间戳
		"fishing_storage": g.fishing_storage,               # 钓鱼仓库 {渔获id: 数量}
		"fishing_tasks": g.fishing_tasks,                   # 已接任务 [{id, progress}]
		"fishing_dex": g.fishing_dex,                       # 图鉴 {渔获id: 1已解锁未领取/2已领取}
		"fishing_fish_dev": g.fishing_fish_dev,             # 渔获养成 {渔获id: {tier, skills:{索引:等级}, xp:{索引:当前经验}}}
		"fishing_dilong_spent": g.fishing_dilong_spent,       # 【新增】地龙累计消耗（保底进度）
		"fishing_chilong_spent": g.fishing_chilong_spent,     # 【新增】赤龙累计消耗（保底进度）
	}

# 从扁平存档表认领本系统字段（老存档缺字段则保持初始值，自动兼容）
func load_save_data(s: Dictionary):
	if s.has("fishing_dilong"): g.fishing_dilong = int(s.fishing_dilong)
	if s.has("fishing_dilong_time"): g.fishing_dilong_time = int(s.fishing_dilong_time)
	if s.has("fishing_chilong"): g.fishing_chilong = int(s.fishing_chilong)
	if s.has("fishing_weather"): g.fishing_weather = s.fishing_weather
	if s.has("fishing_weather_expire"): g.fishing_weather_expire = int(s.fishing_weather_expire)
	if s.has("fishing_storage"): g.fishing_storage = s.fishing_storage.duplicate(true)
	if s.has("fishing_tasks"): g.fishing_tasks = s.fishing_tasks.duplicate(true)
	if s.has("fishing_dex"): g.fishing_dex = s.fishing_dex.duplicate(true)
	if s.has("fishing_fish_dev"): g.fishing_fish_dev = s.fishing_fish_dev.duplicate(true)
	if s.has("fishing_dilong_spent"): g.fishing_dilong_spent = int(s.fishing_dilong_spent)     # 【新增】旧档缺字段保持0，不追溯
	if s.has("fishing_chilong_spent"): g.fishing_chilong_spent = int(s.fishing_chilong_spent)   # 【新增】

# ============ 配置读取 ============
# settings 数值段（缺项给默认值兜底）
func _settings() -> Dictionary:
	return g._fishing_configs.get("settings", {})

func _setting_int(key: String, default_val: int) -> int:
	return int(_settings().get(key, default_val))

func _setting_float(key: String, default_val: float) -> float:
	return float(_settings().get(key, default_val))

# 当前钓点显示名（预留多钓点：按 location_id 查 locations 配置）
func get_location_name(location_id: String = "pond") -> String:
	for loc in g._fishing_configs.get("locations", []):
		if loc.get("id", "") == location_id:
			return loc.get("name", location_id)
	return location_id

# 【新增】全部钓点配置（供界面列出/切换钓点）
func get_locations() -> Array:
	return g._fishing_configs.get("locations", [])

# 【新增】钓点的消耗道具键（locations 配置的 bait 字段：dilong地龙/chilong赤龙，缺省地龙）
func get_location_bait(location_id: String = "pond") -> String:
	for loc in get_locations():
		if loc.get("id", "") == location_id:
			return loc.get("bait", "dilong")
	return "dilong"

# 【新增】钓点消耗道具的显示名
func get_bait_name(location_id: String = "pond") -> String:
	return "赤龙" if get_location_bait(location_id) == "chilong" else "地龙"

# 【新增】钓点消耗道具当前数量（地龙先懒结算；赤龙不自动恢复，直接读数）
func get_bait_count(location_id: String = "pond") -> int:
	if get_location_bait(location_id) == "chilong":
		return int(g.fishing_chilong)
	return get_dilong()

# 【新增】抛竿扣1个对应钓点的消耗道具，不足返回false（赤龙只出不进，地龙走懒结算）
# 抛竿扣1个对应钓点的消耗道具，不足返回false（赤龙只出不进，地龙走懒结算）
func _consume_bait(location_id: String) -> bool:
	if get_location_bait(location_id) == "chilong":
		if g.fishing_chilong < 1:
			return false
		g.fishing_chilong -= 1
		g.fishing_chilong_spent += 1   # 【新增】累计消耗=天池保底进度
		return true
	_settle_dilong()
	if g.fishing_dilong < 1:
		return false
	g.fishing_dilong -= 1
	g.fishing_dilong_spent += 1   # 【新增】累计消耗=瀑湖保底进度
	return true


# ============ 时段 / 天气 ============
# 当前时段：现实时间 06:00-18:00 为白天，其余为黑夜（不入存档，实时读取）
func get_period() -> String:
	var hour = Time.get_datetime_dict_from_system().hour
	return "白天" if (hour >= 6 and hour < 18) else "黑夜"

# 当前天气：过期或无天气时重新随机（晴/雨/雪各1/3），持续 weather_seconds（默认6小时）
func get_weather() -> String:
	@warning_ignore("narrowing_conversion")
	var now: int = Time.get_unix_time_from_system()
	if g.fishing_weather == "" or now >= g.fishing_weather_expire:
		var weathers = ["晴天", "雨天", "雪天"]
		g.fishing_weather = weathers[randi() % weathers.size()]
		g.fishing_weather_expire = now + _setting_int("weather_seconds", 21600)
	return g.fishing_weather

# 天气剩余秒数（界面显示用）
func get_weather_remain() -> int:
	@warning_ignore("narrowing_conversion")
	var now: int = Time.get_unix_time_from_system()
	return max(0, g.fishing_weather_expire - now)

# ============ 地龙（钓鱼消耗，每小时恢复1个，无上限，懒结算） ============
# 懒结算地龙恢复：按经过整小时数补地龙
func _settle_dilong():
	@warning_ignore("narrowing_conversion")
	var now: int = Time.get_unix_time_from_system()
	if g.fishing_dilong_time <= 0:
		g.fishing_dilong_time = now
		return
	var per = _setting_int("dilong_recover_seconds", 3600)
	var gain = int((now - g.fishing_dilong_time) / per)
	if gain > 0:
		g.fishing_dilong += gain   # 无上限，直接累加
		g.fishing_dilong_time += gain * per

# 当前地龙数量（先懒结算再返回）
func get_dilong() -> int:
	_settle_dilong()
	return g.fishing_dilong

# ============ 鱼池 ============
# 取当前可钓池：时段_天气基础池 + 任意池渔获 + 已接交付任务对应的道具 + 该钓点额外池（新增钓点只改JSON）
# 【改】所有来源统一过 is_fish_catchable 解锁过滤（带 unlock_fish 的鱼种需养成达标才入池）
func get_current_pool(location_id: String = "pond") -> Array:
	var key = "%s_%s" % [get_period(), get_weather()]
	var pool: Array = []
	for f in g._fishing_configs.get("pools", {}).get(key, []):   # 【改】append_array 改逐个过滤
		if is_fish_catchable(f):
			pool.append(f)
	# 任意池：渔获（金龙/帝王蟹）始终可钓；道具（kind=item）仅在已接对应交付任务时可钓
	for f in g._fishing_configs.get("common_pool", []):
		if f.get("kind", "fish") == "fish":
			if is_fish_catchable(f):   # 【改】统一过解锁过滤（当前任意池无条件鱼，恒通过）
				pool.append(f)
		elif _has_deliver_task_for(f.id):
			pool.append(f)
	# 钓点额外池：天池的极.无双在这里叠加
	var extra: Dictionary = g._fishing_configs.get("extra_pools", {}).get(location_id, {})
	for f in extra.get(key, []):   # 【改】append_array 改逐个过滤
		if is_fish_catchable(f):
			pool.append(f)
	for f in extra.get("common", []):   # 【改】同上
		if is_fish_catchable(f):
			pool.append(f)
	return pool

# 【新增】渔获当前是否可钓：无解锁条件恒可钓；有 unlock_fish 时需该鱼种养成阶数≥unlock_tier（如龙涎巨鲸20阶解锁绵阳海兔）
func is_fish_catchable(f: Dictionary) -> bool:
	var uf = f.get("unlock_fish", "")
	if uf == "":
		return true
	return get_fish_tier(uf) >= int(f.get("unlock_tier", 20))


# 是否已接目标为 target 的交付类任务（决定道具是否入池）
func _has_deliver_task_for(target: String) -> bool:
	for t in g.fishing_tasks:
		var cfg = _get_task_cfg(t.get("id", ""))
		if cfg.get("type", "") == "deliver" and cfg.get("target", "") == target:
			return true
	return false

# ============ 钓鱼主流程 ============
# 抛竿一次：扣1地龙 → （任务未满3个时10%触发任务）→ roll品质 → 品质内均分 → 入仓库/解锁图鉴/累计任务
# 返回 {ok, type: "fish"/"task", ...} 供视图弹窗
func do_fishing(location_id: String = "pond") -> Dictionary:
	# 【改】按钓点扣对应消耗道具（原固定扣地龙）
	if not _consume_bait(location_id):
		if get_location_bait(location_id) == "chilong":   # 【新增】赤龙不足提示（不自动恢复）
			return {"ok": false, "reason": "赤龙不足，可通过礼包/活动获取"}
		return {"ok": false, "reason": "地龙不足，每小时恢复1个"}

	# 任务触发：已接任务数 < 上限时有10%几率本次改为接到任务（无渔获）；满3个跳过任务roll
	var task_max = _setting_int("task_max", 3)
	if g.fishing_tasks.size() < task_max and randf() < _setting_float("task_chance", 0.10):
		var task = _roll_new_task()
		if not task.is_empty():
			return {"ok": true, "type": "task", "task": task}

	# roll渔获
	var pool = get_current_pool(location_id)
	if pool.is_empty():
		return {"ok": false, "reason": "鱼池配置为空"}
	var weights: Dictionary = _settings().get("quality_weights", {"无双": 3, "传奇": 12, "普通": 30, "无": 55})
	var quality = _roll_quality(pool, weights)
	var candidates = []
	for f in pool:
		if f.get("quality", "无") == quality:
			candidates.append(f)
	var fish: Dictionary = candidates[randi() % candidates.size()]

	# 入钓鱼仓库
	var fid: String = fish.id
	g.fishing_storage[fid] = int(g.fishing_storage.get(fid, 0)) + 1

	# 图鉴解锁（首次获得）
	var dex_new = false
	if not g.fishing_dex.has(fid):
		g.fishing_dex[fid] = 1   # 1=已解锁未领取
		dex_new = true

	# 计数类任务进度累计：只统计渔获（kind=fish），道具不计数
	# putong_up=普通及以上品质；any=任意渔获
	if fish.get("kind", "fish") == "fish":
		for t in g.fishing_tasks:
			var cfg = _get_task_cfg(t.get("id", ""))
			if cfg.get("type", "") != "count": continue
			if cfg.get("count_type", "any") == "putong_up" and quality == "无": continue
			t["progress"] = int(t.get("progress", 0)) + 1

	return {"ok": true, "type": "fish", "id": fid, "name": fish.get("name", fid), "quality": quality, "kind": fish.get("kind", "fish"), "dex_new": dex_new}

# 撒网捕鱼：依次钓鱼 times 次（默认10连），地龙不足自动停；任务满3个后自动跳过任务roll不会溢出
# 返回 {ok, count, fishes: {id:{name,quality,count}}, tasks: [任务desc...], reason}
func do_fishing_multi(times: int = 10, location_id: String = "pond") -> Dictionary:
	var summary = {"ok": true, "count": 0, "fishes": {}, "tasks": [], "reason": ""}
	for i in range(times):
		var res = do_fishing(location_id)
		if not res.get("ok", false):
			summary.reason = res.get("reason", "")
			break   # 地龙不足等原因，中途停止
		summary.count += 1
		if res.get("type") == "task":
			summary.tasks.append(res.task.get("desc", ""))
		else:
			var fid: String = res.id
			if not summary.fishes.has(fid):
				summary.fishes[fid] = {"name": res.get("name", fid), "quality": res.get("quality", "无"), "count": 0}
			summary.fishes[fid].count += 1
	if summary.count <= 0:
		return {"ok": false, "reason": summary.reason if summary.reason != "" else "钓鱼失败"}
	return summary

# 按权重roll品质；roll中的品质在当前池无候选时按 无双→传奇→普通→无 顺延，保证必出货
func _roll_quality(pool: Array, weights: Dictionary) -> String:
	var total = 0.0
	for q in QUALITY_ORDER:
		total += float(weights.get(q, 0))
	var r = randf() * total
	var picked = "无"
	var acc = 0.0
	for q in QUALITY_ORDER:
		acc += float(weights.get(q, 0))
		if r < acc:
			picked = q
			break
	# 顺延：从 picked 起向下找第一个有候选的品质
	var start = QUALITY_ORDER.find(picked)
	for i in range(start, QUALITY_ORDER.size()):
		var q = QUALITY_ORDER[i]
		for f in pool:
			if f.get("quality", "无") == q:
				return q
	return "无"

# ============ 元宝礼包 ============
# 购买元宝礼包：1988元宝 → 地龙×50 + 赤龙×50（数值走 fishing.json settings.pack_*，可重复购买）
func buy_bait_pack() -> Dictionary:
	var cost = _setting_int("pack_cost", 1988)
	if g.yuanbao < cost:
		return {"ok": false, "reason": "元宝不足（需要%d）" % cost}
	g.yuanbao -= cost
	var n_dilong = _setting_int("pack_dilong", 50)
	var n_chilong = _setting_int("pack_chilong", 50)
	g.fishing_dilong += n_dilong
	g.fishing_chilong += n_chilong
	return {"ok": true, "dilong": n_dilong, "chilong": n_chilong}

# ============ 任务 ============
# 任务配置表
func get_task_cfgs() -> Array:
	return g._fishing_configs.get("tasks", [])

# 按id查任务配置
func _get_task_cfg(task_id: String) -> Dictionary:
	for t in get_task_cfgs():
		if t.get("id", "") == task_id:
			return t
	return {}

# 已接任务列表（[{id, progress}]，存于 GameData.fishing_tasks）
func get_tasks() -> Array:
	return g.fishing_tasks

# 随机接一个未持有的任务，返回该任务配置；无可接返回 {}
func _roll_new_task() -> Dictionary:
	var held = []
	for t in g.fishing_tasks:
		held.append(t.get("id", ""))
	var available = []
	for cfg in get_task_cfgs():
		if not held.has(cfg.get("id", "")):
			available.append(cfg)
	if available.is_empty():
		return {}
	var cfg: Dictionary = available[randi() % available.size()]
	g.fishing_tasks.append({"id": cfg.id, "progress": 0})
	return cfg

# 单个任务当前是否可交付/领取
func is_task_ready(t: Dictionary) -> bool:
	var cfg = _get_task_cfg(t.get("id", ""))
	if cfg.is_empty(): return false
	if cfg.get("type", "") == "deliver":
		# 交付类：检查钓鱼仓库库存
		return int(g.fishing_storage.get(cfg.get("target", ""), 0)) >= int(cfg.get("need", 1))
	# 计数类：检查进度
	return int(t.get("progress", 0)) >= int(cfg.get("need", 1))

# 任务按钮红点：任一已接任务可交付/领取
func has_ready_task() -> bool:
	for t in g.fishing_tasks:
		if is_task_ready(t): return true
	return false

# 交付/领取任务：交付类扣钓鱼仓库物品；奖励发背包（beast_fruit走独立货币）；完成后移出任务列表
# 返回 {ok, gains, reason}
func claim_task(task_id: String) -> Dictionary:
	var idx = -1
	for i in range(g.fishing_tasks.size()):
		if g.fishing_tasks[i].get("id", "") == task_id:
			idx = i
			break
	if idx < 0:
		return {"ok": false, "reason": "任务不存在"}
	var t: Dictionary = g.fishing_tasks[idx]
	if not is_task_ready(t):
		return {"ok": false, "reason": "任务未达成"}
	var cfg = _get_task_cfg(task_id)
	# 交付类扣除钓鱼仓库物品
	if cfg.get("type", "") == "deliver":
		var target: String = cfg.get("target", "")
		g.fishing_storage[target] = int(g.fishing_storage.get(target, 0)) - int(cfg.get("need", 1))
		if g.fishing_storage[target] <= 0:
			g.fishing_storage.erase(target)
	var gains = _give_rewards(cfg.get("rewards", {}))
	g.fishing_tasks.remove_at(idx)
	return {"ok": true, "gains": gains}

# ============ 图鉴 ============
# 全部图鉴条目（基础池+任意池+所有钓点额外池，供界面按品级分组展示）
func get_dex_entries() -> Array:
	var seen = {}
	var entries = []
	var pools_cfg: Dictionary = g._fishing_configs.get("pools", {})
	for key in pools_cfg.keys():
		for f in pools_cfg[key]:
			if not seen.has(f.id):
				seen[f.id] = true
				entries.append(f)
	for f in g._fishing_configs.get("common_pool", []):
		if not seen.has(f.id):
			seen[f.id] = true
			entries.append(f)
	var extras: Dictionary = g._fishing_configs.get("extra_pools", {})
	for loc in extras.keys():
		for key in extras[loc].keys():
			for f in extras[loc][key]:
				if not seen.has(f.id):
					seen[f.id] = true
					entries.append(f)
	return entries

# 图鉴状态：0=未解锁 1=已解锁未领取 2=已领取
func get_dex_state(fish_id: String) -> int:
	return int(g.fishing_dex.get(fish_id, 0))

# 领取图鉴奖励（按品级发奖励到背包），返回 {ok, gains, reason}
func claim_dex_reward(fish_id: String) -> Dictionary:
	if get_dex_state(fish_id) != 1:
		return {"ok": false, "reason": "不可领取"}
	# 找该渔获的品级
	var quality = ""
	for f in get_dex_entries():
		if f.id == fish_id:
			quality = f.get("quality", "无")
			break
	var rewards: Dictionary = g._fishing_configs.get("dex_rewards", {}).get(quality, {})
	var gains = _give_rewards(rewards)
	g.fishing_dex[fish_id] = 2   # 2=已领取
	return {"ok": true, "gains": gains}

# 图鉴按钮红点：任一条目已解锁未领取
func has_claimable_dex() -> bool:
	for fid in g.fishing_dex.keys():
		if int(g.fishing_dex[fid]) == 1:
			return true
	return false

# ============ 渔获装备养成（模型A·按种类养成） ============

# 渔获养成配置段（fish_equip）
func _equip_cfgs() -> Dictionary:
	return g._fishing_configs.get("fish_equip", {})

# 查渔获的图鉴条目（含 quality/kind/name），找不到返回 {}
func _get_fish_entry(fish_id: String) -> Dictionary:
	for f in get_dex_entries():
		if f.id == fish_id:
			return f
	return {}

# 渔获品质（查图鉴条目，兜底"无"）
func get_fish_quality(fish_id: String) -> String:
	return _get_fish_entry(fish_id).get("quality", "无")

# 是否可装备：kind=fish 且品质在 fish_equip 配置里有养成表（无双/传奇/普通）
func is_fish_equippable(fish_id: String) -> bool:
	var f = _get_fish_entry(fish_id)
	if f.is_empty() or f.get("kind", "fish") != "fish": return false
	return _equip_cfgs().has(f.get("quality", ""))

# 取某渔获的养成数据（首次访问自动初始化 1阶/无技能/无经验）
func get_fish_dev(fish_id: String) -> Dictionary:
	if not g.fishing_fish_dev.has(fish_id):
		g.fishing_fish_dev[fish_id] = {"tier": 1, "skills": {}, "xp": {}}
	var dev: Dictionary = g.fishing_fish_dev[fish_id]
	if not dev.has("tier"): dev["tier"] = 1
	if not dev.has("skills"): dev["skills"] = {}
	if not dev.has("xp"): dev["xp"] = {}
	return dev

# 渔获当前阶数
func get_fish_tier(fish_id: String) -> int:
	return int(get_fish_dev(fish_id).get("tier", 1))

# 渔获品级养成配置（无双/传奇/普通段）
func _get_dev_cfg(fish_id: String) -> Dictionary:
	return _equip_cfgs().get(get_fish_quality(fish_id), {})

# ---- 装备 ----

# 门客当前装备的渔获id（无则""）
func get_hero_fish(hero_id: String) -> String:
	if not g.heroes.has(hero_id): return ""
	return g.heroes[hero_id].get("equipped_fish", "")

# 渔获被哪个门客装备着（一鱼一门客反查；无则""）
func get_fish_equipped_hero(fish_id: String) -> String:
	for hid in g.heroes.keys():
		if g.heroes[hid].get("equipped_fish", "") == fish_id:
			return hid
	return ""

# 装备渔获：需库存≥1、可装备、未被其他门客占用；不扣库存
func equip_fish(hero_id: String, fish_id: String) -> Dictionary:
	if not g.heroes.has(hero_id):
		return {"ok": false, "reason": "门客不存在"}
	if not is_fish_equippable(fish_id):
		return {"ok": false, "reason": "该渔获不可装备"}
	if int(g.fishing_storage.get(fish_id, 0)) < 1:
		return {"ok": false, "reason": "仓库没有这条渔获"}
	var holder = get_fish_equipped_hero(fish_id)
	if holder != "" and holder != hero_id:
		return {"ok": false, "reason": "该渔获已被【%s】装备" % g.heroes[holder].get("name", holder)}
	g.heroes[hero_id]["equipped_fish"] = fish_id
	return {"ok": true}

# 卸下渔获
func unequip_fish(hero_id: String) -> Dictionary:
	if not g.heroes.has(hero_id):
		return {"ok": false, "reason": "门客不存在"}
	g.heroes[hero_id]["equipped_fish"] = ""
	return {"ok": true}

# ---- 加成计算（供 HeroData 聚合，经 GameData 转发） ----

# 渔获给门客的百分比加成（无双：阶×5%；其余0）
func get_fish_percent_bonus(fish_id: String) -> float:
	if fish_id == "": return 0.0
	var cfg = _get_dev_cfg(fish_id)
	return get_fish_tier(fish_id) * float(cfg.get("income_pct_per_tier", 0.0))

# 渔获给门客的固定赚速（传奇/普通：start~end 按阶等差插值；无双0）
func get_fish_flat_income(fish_id: String) -> int:
	if fish_id == "": return 0
	var cfg = _get_dev_cfg(fish_id)
	if not cfg.has("income_flat_start"): return 0
	var tier = get_fish_tier(fish_id)
	var max_tier = int(cfg.get("max_tier", 30))
	var start = float(cfg.get("income_flat_start", 0))
	var end = float(cfg.get("income_flat_end", 0))
	if max_tier <= 1: return int(start)
	return int(start + (end - start) * float(tier - 1) / float(max_tier - 1))

# 渔获给门客的资质加成（已解锁技能的 每级资质×技能等级 之和）
func get_fish_skill_aptitude(fish_id: String) -> int:
	if fish_id == "": return 0
	var cfg = _get_dev_cfg(fish_id)
	var dev = get_fish_dev(fish_id)
	var tier = int(dev.get("tier", 1))
	var total = 0
	var skills_cfg: Array = cfg.get("skills", [])
	for i in range(skills_cfg.size()):
		var sc: Dictionary = skills_cfg[i]
		if tier < int(sc.get("unlock_tier", 1)): continue   # 未解锁不算
		var lv = int(dev.skills.get(str(i), 0))
		total += lv * int(sc.get("apt_per_level", 0))
	return total

# ---- 晋升 ----

# 晋升到下一阶消耗同名鱼数量（无双 ceil(当前阶/10)、传奇 当前阶、普通 2×当前阶）
func get_promote_cost(fish_id: String) -> int:
	var cfg = _get_dev_cfg(fish_id)
	var tier = get_fish_tier(fish_id)
	match cfg.get("promote_cost_mode", "tier"):
		"ceil_div10": return int(ceil(tier / 10.0))
		"tier_x2": return tier * 2
		_: return tier

# 晋升一阶：扣同名鱼库存（被装备的鱼种至少保留1只），满阶不可再升
func promote_fish(fish_id: String) -> Dictionary:
	var cfg = _get_dev_cfg(fish_id)
	if cfg.is_empty(): return {"ok": false, "reason": "该渔获不可养成"}
	var dev = get_fish_dev(fish_id)
	var tier = int(dev.tier)
	var max_tier = int(cfg.get("max_tier", 30))
	if tier >= max_tier:
		return {"ok": false, "reason": "已满阶"}
	var cost = get_promote_cost(fish_id)
	var have = int(g.fishing_storage.get(fish_id, 0))
	# 被装备中的鱼种必须保留1只本体
	var need = cost + (1 if get_fish_equipped_hero(fish_id) != "" else 0)
	if have < need:
		return {"ok": false, "reason": "同名渔获不足（需要%d只%s）" % [cost, "，装备中的鱼需保留1只" if get_fish_equipped_hero(fish_id) != "" else ""]}
	g.fishing_storage[fish_id] = have - cost
	if g.fishing_storage[fish_id] <= 0:
		g.fishing_storage.erase(fish_id)
	dev.tier = tier + 1
	return {"ok": true, "tier": dev.tier}

# ---- 技能 ----

# 技能列表（含解锁状态/当前等级/经验进度），供界面展示
func get_fish_skills(fish_id: String) -> Array:
	var cfg = _get_dev_cfg(fish_id)
	var dev = get_fish_dev(fish_id)
	var tier = int(dev.get("tier", 1))
	var xp_need = int(cfg.get("skill_xp_per_level", 1500))
	var max_lv = int(cfg.get("skill_max_level", 100))
	var list = []
	var skills_cfg: Array = cfg.get("skills", [])
	for i in range(skills_cfg.size()):
		var sc: Dictionary = skills_cfg[i]
		list.append({
			"index": i,
			"name": sc.get("name", ""),
			"unlock_tier": int(sc.get("unlock_tier", 1)),
			"apt_per_level": int(sc.get("apt_per_level", 0)),
			"unlocked": tier >= int(sc.get("unlock_tier", 1)),
			"level": int(dev.skills.get(str(i), 0)),
			"xp": int(dev.xp.get(str(i), 0)),
			"xp_need": xp_need,
			"max_level": max_lv,
		})
	return list

# 技能材料当前可用数量
# mat: "yu_shi"鱼食(背包) / "无"无品级鱼(任意) / "普通"/"传奇"(该鱼种满阶后库存才可喂)（无双不可喂）
func get_fodder_count(mat: String) -> int:
	if mat == "yu_shi":
		return int(g.items.get("yu_shi", 0))
	var max_tier_map = {"普通": 30, "传奇": 30}
	var total = 0
	for f in get_dex_entries():
		if f.get("kind", "fish") != "fish": continue
		if f.get("quality", "") != mat: continue
		# 普通/传奇鱼种必须晋升满阶才能当材料
		if max_tier_map.has(mat):
			var cfg = _get_dev_cfg(f.id)
			if get_fish_tier(f.id) < int(cfg.get("max_tier", max_tier_map[mat])): continue
		var cnt = int(g.fishing_storage.get(f.id, 0))
		# 被装备中的鱼种保留1只本体
		if get_fish_equipped_hero(f.id) != "":
			cnt = max(0, cnt - 1)
		total += cnt
	return total

# 实际扣材料（鱼按图鉴顺序逐个扣，遵守满阶/保留本体规则）
func _consume_fodder(mat: String, n: int) -> int:
	if n <= 0: return 0
	if mat == "yu_shi":
		var use = min(n, int(g.items.get("yu_shi", 0)))
		g.items["yu_shi"] = int(g.items.get("yu_shi", 0)) - use
		return use
	var left = n
	for f in get_dex_entries():
		if left <= 0: break
		if f.get("kind", "fish") != "fish": continue
		if f.get("quality", "") != mat: continue
		if mat == "普通" or mat == "传奇":
			var cfg = _get_dev_cfg(f.id)
			if get_fish_tier(f.id) < int(cfg.get("max_tier", 30)): continue
		var cnt = int(g.fishing_storage.get(f.id, 0))
		if get_fish_equipped_hero(f.id) != "":
			cnt = max(0, cnt - 1)
		var use = min(cnt, left)
		if use > 0:
			g.fishing_storage[f.id] = int(g.fishing_storage.get(f.id, 0)) - use
			if g.fishing_storage[f.id] <= 0:
				g.fishing_storage.erase(f.id)
			left -= use
	return n - left

# 喂技能：自动从指定材料扣到升1级（不够则全部扣掉攒经验），返回 {ok, used, level, xp, need, reason}
func feed_skill(fish_id: String, skill_index: int, mat: String) -> Dictionary:
	var cfg = _get_dev_cfg(fish_id)
	if cfg.is_empty(): return {"ok": false, "reason": "该渔获不可养成"}
	var fodder_xp: Dictionary = _equip_cfgs().get("fodder_xp", {"yu_shi": 1, "无": 30, "普通": 130, "传奇": 2000})
	if not fodder_xp.has(mat): return {"ok": false, "reason": "无效材料"}
	var dev = get_fish_dev(fish_id)
	var tier = int(dev.tier)
	var skills_cfg: Array = cfg.get("skills", [])
	if skill_index < 0 or skill_index >= skills_cfg.size():
		return {"ok": false, "reason": "技能不存在"}
	var sc: Dictionary = skills_cfg[skill_index]
	if tier < int(sc.get("unlock_tier", 1)):
		return {"ok": false, "reason": "技能未解锁（需%d阶）" % int(sc.get("unlock_tier", 1))}
	var key = str(skill_index)
	var lv = int(dev.skills.get(key, 0))
	var max_lv = int(cfg.get("skill_max_level", 100))
	if lv >= max_lv:
		return {"ok": false, "reason": "技能已满级"}
	var need = int(cfg.get("skill_xp_per_level", 1500))
	var cur_xp = int(dev.xp.get(key, 0))
	var xp_per = int(fodder_xp.get(mat, 1))
	# 升到下一级还需要的材料数，再与可用量取小（材料不够就全喂，攒部分经验）
	var need_mats = int(ceil(float(need - cur_xp) / float(xp_per)))
	var use = min(need_mats, get_fodder_count(mat))
	if use <= 0:
		return {"ok": false, "reason": "材料不足"}
	var used = _consume_fodder(mat, use)
	cur_xp += used * xp_per
	# 经验够就升级（一次最多升1级，多余经验带入下级）
	var leveled = false
	if cur_xp >= need and lv < max_lv:
		cur_xp -= need
		lv += 1
		leveled = true
		dev.skills[key] = lv
	dev.xp[key] = cur_xp
	return {"ok": true, "used": used, "level": lv, "xp": cur_xp, "need": need, "leveled": leveled}

# 一键喂养：按 鱼食→无品级→普通→传奇（便宜优先，珍贵材料留到最后）循环喂养，直到满级或材料耗尽
# 每轮复用单次 feed_skill（自带"升1级封顶+多余经验累计"规则）；材料耗尽未升满的进度保留在技能上
# 返回 {ok, from_level, to_level, used:{材料:数量}, reason}
func feed_skill_max(fish_id: String, skill_index: int) -> Dictionary:
	var cfg = _get_dev_cfg(fish_id)
	if cfg.is_empty(): return {"ok": false, "reason": "该渔获不可养成"}
	var skills_cfg: Array = cfg.get("skills", [])
	if skill_index < 0 or skill_index >= skills_cfg.size():
		return {"ok": false, "reason": "技能不存在"}
	var dev = get_fish_dev(fish_id)
	var sc: Dictionary = skills_cfg[skill_index]
	var tier = int(dev.tier)
	if tier < int(sc.get("unlock_tier", 1)):
		return {"ok": false, "reason": "技能未解锁（需%d阶）" % int(sc.get("unlock_tier", 1))}
	var key = str(skill_index)
	var from_lv = int(dev.skills.get(key, 0))
	var max_lv = int(cfg.get("skill_max_level", 100))
	if from_lv >= max_lv:
		return {"ok": false, "reason": "技能已满级"}
	var order = ["yu_shi", "无", "普通", "传奇"]   # 消耗顺序：便宜优先
	var used_total = {}
	# 每轮喂第一种还有库存的材料；四种全空则停止
	while int(dev.skills.get(key, 0)) < max_lv:
		var fed = false
		for mat in order:
			if get_fodder_count(mat) <= 0: continue
			var res = feed_skill(fish_id, skill_index, mat)
			if not res.get("ok", false): continue   # 已查库存，理论不触发；保险跳过
			used_total[mat] = int(used_total.get(mat, 0)) + int(res.get("used", 0))
			fed = true
			break
		if not fed: break
	if used_total.is_empty():
		return {"ok": false, "reason": "材料不足"}
	return {"ok": true, "from_level": from_lv, "to_level": int(dev.skills.get(key, 0)), "used": used_total}


# ============ 保底兑换 ============
# 【新增】钓点保底配置（fishing.json settings.exchange：cost=单次消耗数，quality=兑换品质）
func get_exchange_cfg(location_id: String) -> Dictionary:
	return _settings().get("exchange", {}).get(location_id, {})

# 【新增】该钓点当前累计消耗数（按钓点道具分地龙/赤龙两个计数）
func get_exchange_spent(location_id: String) -> int:
	if get_location_bait(location_id) == "chilong":
		return int(g.fishing_chilong_spent)
	return int(g.fishing_dilong_spent)

# 【新增】当前可兑换只数（累计消耗÷单次消耗，溢出部分保留、可累计多份）
func get_exchange_times(location_id: String) -> int:
	var cost = int(get_exchange_cfg(location_id).get("cost", 0))
	if cost <= 0:
		return 0
	@warning_ignore("integer_division")
	return int(get_exchange_spent(location_id) / cost)

# 【新增】保底可兑换的渔获列表：该品质全部渔获（基础池+本钓点额外池，含未解锁条件鱼，玩家自选）
func get_exchange_fish(location_id: String) -> Array:
	var quality: String = get_exchange_cfg(location_id).get("quality", "无双")
	var seen = {}
	var list = []
	for key in g._fishing_configs.get("pools", {}).keys():
		for f in g._fishing_configs.pools[key]:
			if f.get("quality", "") == quality and not seen.has(f.id):
				seen[f.id] = true
				list.append(f)
	var extras: Dictionary = g._fishing_configs.get("extra_pools", {}).get(location_id, {})
	for key in extras.keys():
		for f in extras[key]:
			if f.get("quality", "") == quality and not seen.has(f.id):
				seen[f.id] = true
				list.append(f)
	return list

# 【新增】兑换一只：扣单次进度（溢出保留），渔获入钓鱼仓库+首获解锁图鉴；不算"垂钓"不计任务进度
func exchange_fish(location_id: String, fish_id: String) -> Dictionary:
	var cfg = get_exchange_cfg(location_id)
	var cost = int(cfg.get("cost", 0))
	if cost <= 0:
		return {"ok": false, "reason": "该钓点无兑换"}
	# 校验目标在可兑换列表内
	var ok_fish = false
	var fname = fish_id
	for f in get_exchange_fish(location_id):
		if f.id == fish_id:
			ok_fish = true
			fname = f.get("name", fish_id)
	if not ok_fish:
		return {"ok": false, "reason": "该渔获不可兑换"}
	# 扣进度（分道具扣对应计数）
	if get_location_bait(location_id) == "chilong":
		if g.fishing_chilong_spent < cost:
			return {"ok": false, "reason": "进度不足"}
		g.fishing_chilong_spent -= cost
	else:
		if g.fishing_dilong_spent < cost:
			return {"ok": false, "reason": "进度不足"}
		g.fishing_dilong_spent -= cost
	# 发鱼+图鉴
	g.fishing_storage[fish_id] = int(g.fishing_storage.get(fish_id, 0)) + 1
	var dex_new = false
	if not g.fishing_dex.has(fish_id):
		g.fishing_dex[fish_id] = 1   # 1=已解锁未领取
		dex_new = true
	return {"ok": true, "id": fish_id, "name": fname, "quality": cfg.get("quality", "无双"), "dex_new": dex_new}


# ============ 内部工具 ============
# 发放奖励到背包；beast_fruit/aroma_fruit 走 GameData 独立货币（与关卡宝箱一致）
# 返回 {道具id: 数量} 供弹窗展示
func _give_rewards(rewards: Dictionary) -> Dictionary:
	var gains = {}
	for item_id in rewards.keys():
		var n = int(rewards[item_id])
		if item_id == "beast_fruit":
			g.beast_fruit += n
		elif item_id == "aroma_fruit":
			g.aroma_fruit += n
		else:
			g.items[item_id] = int(g.items.get(item_id, 0)) + n
		gains[item_id] = n
	return gains

# 渔获显示名（查配置，兜底返回id）
func get_fish_name(fish_id: String) -> String:
	for f in get_dex_entries():
		if f.id == fish_id:
			return f.get("name", fish_id)
	return fish_id
