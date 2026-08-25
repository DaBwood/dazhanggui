# ============================================================
# 抽奖系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name LotterySystem
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
		"lottery_ticket": g.lottery_ticket,   # 抽奖券
		"lottery_draw_count": g.lottery_draw_count,   # 累计抽数（保底用）
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("lottery_ticket"): g.lottery_ticket = s.lottery_ticket
	if s.has("lottery_draw_count"): g.lottery_draw_count = s.lottery_draw_count

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

func _draw_from_pool() -> Dictionary:
	var r = randf()
	var cumulative = 0.0
	for entry in g.LOTTERY_POOL:
		cumulative += entry.weight
		if r <= cumulative:
			return entry.duplicate(true)
	# 未命中，给铜钱安慰奖
	return {"item": "money", "count": randi_range(1000, 10000)}

func _give_lottery_reward(reward: Dictionary):
	if reward.get("is_beast", false):
		g.add_beast(reward.item)
	elif reward.item == "money":
		g.money += reward.count
	else:
		g.items[reward.item] = g.items.get(reward.item, 0) + reward.count

func do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao_for_short: bool = false) -> Dictionary:
	var ticket_cost = min(ticket_need, g.lottery_ticket)
	var ticket_short = ticket_need - ticket_cost
	var yuanbao_cost = ticket_short * g.LOTTERY_TICKET_YUANBAO_RATE
	
	if use_yuanbao_for_short:
		if g.yuanbao < yuanbao_cost:
			return {"ok": false, "reason": "元宝不足"}
		g.yuanbao -= yuanbao_cost
		g.lottery_ticket -= ticket_cost
	else:
		if g.lottery_ticket < draw_count:
			return {"ok": false, "reason": "抽奖券不足"}
		g.lottery_ticket -= draw_count
	
	var results = []
	for i in range(draw_count):
		g.lottery_draw_count += 1
		var reward = null
		if g.lottery_draw_count >= g.LOTTERY_GUARANTEE:
			reward = {"item": "hero_token", "count": 1}
			g.lottery_draw_count = 0
		else:
			reward = _draw_from_pool()
		_give_lottery_reward(reward)
		results.append(reward)
	
	return {"ok": true, "results": results, "ticket_cost": ticket_cost, "yuanbao_cost": yuanbao_cost}
