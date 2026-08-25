# ============================================================
# 关卡系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name StageSystem
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
		"stage_main": g.stage_main,   # 当前大关
		"stage_sub": g.stage_sub,   # 当前小关
		"stage_trade_count": g.stage_trade_count,   # 通商次数
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("stage_main"): g.stage_main = s.stage_main
	if s.has("stage_sub"): g.stage_sub = s.stage_sub
	if s.has("stage_trade_count"): g.stage_trade_count = s.stage_trade_count

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 【重构】默认参数不能跨文件引用中枢成员，改用-1哨兵表示"当前关卡进度"
func get_stage_trade_cost(main: int = -1, sub: int = -1) -> int:
	if main < 0: main = g.stage_main   # -1 = 当前大关
	if sub < 0: sub = g.stage_sub      # -1 = 当前小关
	return int(500 * pow(main, 3.2) * (1.0 + (sub - 1) * 0.2))

# 【重构】默认参数改用-1哨兵（同上）
func get_stage_boss_income(main: int = -1) -> int:
	if main < 0: main = g.stage_main
	return int(50 * pow(main, 2.3))

func is_stage_boss_ready() -> bool:
	return g.stage_sub == 5 and g.stage_trade_count >= 3

# ========== 关卡操作 ==========
func do_stage_trade() -> Dictionary:
	var cost = get_stage_trade_cost()
	var boss_income = get_stage_boss_income()
	var hero_power = g.get_heroes_total_income()
	var discount = clamp(float(boss_income) / float(max(hero_power, 1)), 0.1, 1.0)
	var actual_cost = int(cost * discount)
	
	if g.money < actual_cost:
		return {"ok": false, "reason": "铜钱不足", "need": actual_cost, "have": g.money}
	
	g.money -= actual_cost
	g.reputation += 1
	g.stage_trade_count += 1
	
	# 每次贸易获得阅历（随章节递增，但不高）
	var exp_reward = 10 * g.stage_main
	g.items.experience += exp_reward
	
	# 达到3次，推进
	if g.stage_trade_count >= 3:
		g.items["stage_box"] = g.items.get("stage_box", 0) + 1
		
		if g.stage_sub < 5:
			g.stage_trade_count = 0      # 【改】只有进下小关才重置
			g.stage_sub += 1
			return {"ok": true, "type": "next_sub", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}
		else:
			# 【改】Boss已出现，保持trade_count>=3，让is_stage_boss_ready能检测到
			return {"ok": true, "type": "boss_ready", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}
	
	return {"ok": true, "type": "trade", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}

func do_stage_boss() -> Dictionary:
	var boss_income = get_stage_boss_income()
	var hero_power = g.get_heroes_total_income()
	
	if hero_power > boss_income:
		g.reputation += 10
		g.lottery_ticket += 1
		g.stage_main += 1
		g.stage_sub = 1
		g.stage_trade_count = 0
		return {"ok": true, "win": true, "boss_income": boss_income, "hero_power": hero_power}
	else:
		return {"ok": true, "win": false, "boss_income": boss_income, "hero_power": hero_power}
