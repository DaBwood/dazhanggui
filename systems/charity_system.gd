# ============================================================
# 行善系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name CharitySystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 提供本系统的存档字段（由 GameData.save_game 合并进扁平存档表，格式与旧版完全一致）
func get_save_data() -> Dictionary:
	return {
		"charity_progress": g.charity_progress,   # 各地行善档位
		"charity_click_count": g.charity_click_count,   # 今日行善次数
		"charity_last_day": g.charity_last_day,   # 上次行善日期
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("charity_progress"): g.charity_progress = s.charity_progress
	if s.has("charity_click_count"): g.charity_click_count = s.charity_click_count
	if s.has("charity_last_day"): g.charity_last_day = s.charity_last_day

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 跨天重置行善消耗次数
func _refresh_charity_daily():
	var today = Time.get_date_string_from_system()
	if g.charity_last_day != today:
		g.charity_last_day = today
		g.charity_click_count = 0

# 当前行善消耗：首次1万，每次×1.5，每天重置
func get_charity_cost() -> int:
	_refresh_charity_daily()
	return int(g.CHARITY_BASE_COST * pow(g.CHARITY_COST_MULT, g.charity_click_count))

# 某地点当前档所需次数：第1档2次，之后每档+1（2、3、4、5…）
func get_charity_tier_need(loc_id: String) -> int:
	var tier = g.charity_progress.get(loc_id, {}).get("tier", 0)
	return tier + 2

# 某职业的徒弟赚速加成池（每档+50）
# 注意：这是累计池，不直接加到徒弟身上，徒弟结业转职时才定格到自己身上
func get_charity_career_bonus(career: String) -> int:
	for loc in g.CHARITY_LOCATIONS:
		if loc.career == career:
			return g.charity_progress.get(loc.id, {}).get("tier", 0) * g.CHARITY_EFFECT_PER_TIER
	return 0

# 行善：扣铜钱 → 随机地点进度+1 → 发奖励；满档加成池+50，余数带进下一档
func do_charity() -> Dictionary:
	_refresh_charity_daily()
	var cost = get_charity_cost()
	if g.money < cost: return {"ok": false, "reason": "铜钱不足"}
	g.money -= cost
	g.charity_click_count += 1
	
	# 随机一个地点
	var loc = g.CHARITY_LOCATIONS[randi() % g.CHARITY_LOCATIONS.size()]
	var p = g.charity_progress.get(loc.id, {"progress": 0, "tier": 0})
	p.progress += 1
	var need = p.tier + 2
	var completed = false
	if p.progress >= need:
		p.progress -= need
		p.tier += 1
		completed = true
	g.charity_progress[loc.id] = p
	
	var rewards = []
	# 必定奖励1：才华1-2，加给随机一位已拥有挚友
	var talent_gain = randi_range(1, 2)
	if not g.friends.is_empty():
		var fkeys = g.friends.keys()
		var fid = fkeys[randi() % fkeys.size()]
		g.friends[fid].talent += talent_gain
		rewards.append("才华+%d（%s）" % [talent_gain, g.friends[fid].name])
	# 必定奖励2：对应该地点的"之道"×1
	g.items[loc.way_item] = g.items.get(loc.way_item, 0) + 1
	rewards.append(g.ITEM_CONFIG[loc.way_item].name + "×1")
	# 其他道具：90%随机1个，10%随机2个
	var pool = [
		{"item": "rouge", "weight": 30},
		{"item": "recruit_bronze", "weight": 30},
		{"item": "recruit_silver", "weight": 5},
		{"item": "recruit_gold", "weight": 3},
		{"item": "shop_blueprint", "weight": 30},
		{"item": "aptitude_pill", "weight": 2},
	]
	var total_w = 0
	for e in pool: total_w += e.weight
	var extra_count = 2 if randf() < 0.1 else 1
	for i in range(extra_count):
		var r = randi() % total_w
		for e in pool:
			if r < e.weight:
				g.items[e.item] = g.items.get(e.item, 0) + 1
				rewards.append(g.ITEM_CONFIG[e.item].name + "×1")
				break
			r -= e.weight
	
	return {"ok": true, "location": loc.name, "career": loc.career, "rewards": rewards,
		"completed": completed, "tier": p.tier, "cost": cost}
