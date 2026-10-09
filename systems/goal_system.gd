# ============================================================
# 挚友目标系统（第6批新增：府邸页挚友目标，达成条件自动解锁挚友）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 配置外置 res://data/goals.json（由 GameData._load_all_configs 加载进 g._goal_configs）
# 计数由 5 个业务系统在行为成功后调用 add_stat() 写入：
#   充值 mall_system / 商战 war_system / 游历 travel_system / 道具 item_system / 联姻 apprentice_system
# ============================================================
class_name GoalSystem
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
		"goal_stats": g.goal_stats,   # 各目标计数 {统计项: 累计值}
	}

# 从扁平存档表认领本系统字段（老存档缺字段则保持初始值，自动兼容）
func load_save_data(s: Dictionary):
	if s.has("goal_stats"): g.goal_stats = s.goal_stats.duplicate(true)

# ============ 配置读取 ============
# 挚友目标表（goals.json 的 goals 段）
func get_goal_list() -> Array:
	return g._goal_configs.get("goals", [])

# ============ 计数 ============
# 取某统计项当前值（首充领取式 2026-10-09：仅"领取"动作置 1，不再看 vip_exp——老玩家走弹窗补领，无迁移代码）
func get_stat(stat: String) -> int:
	if stat == "recharge_done":
		return 1 if int(g.goal_stats.get("recharge_done", 0)) > 0 else 0
	return int(g.goal_stats.get(stat, 0))

# 累加某统计项（各业务系统在行为成功后调用）
func add_stat(stat: String, delta: int = 1):
	g.goal_stats[stat] = int(g.goal_stats.get(stat, 0)) + delta

# ============ 目标判定 ============
# 单个目标是否达成
func is_goal_done(goal: Dictionary) -> bool:
	return get_stat(goal.get("stat", "")) >= int(goal.get("need", 1))

# 全部目标是否达成（府邸"挚友目标"区整块隐藏的依据）
func all_goals_done() -> bool:
	for goal in get_goal_list():
		if not is_goal_done(goal): return false
	return true

# 检查并自动解锁已达成的挚友，返回本次新解锁的挚友名列表（供弹窗提示）
# 已拥有的挚友跳过（通过其他途径获得也算达成）
func check_goals() -> Array:
	var newly = []
	for goal in get_goal_list():
		var fid = goal.get("friend", "")
		if fid == "" or g.friends.has(fid): continue
		if is_goal_done(goal):
			if g.unlock_friend(fid):
				newly.append(get_friend_name(fid))
	return newly

# ============ 领取式（2026-10-09 用户定稿：除首充李师师走首充弹窗外，其余挚友手动领取） ============
# 单目标是否已领取
func is_goal_claimed(goal: Dictionary) -> bool:
	return int(g.goal_stats.get("claimed_" + goal.get("friend", ""), 0)) > 0

# 单目标是否可领取（达成+未领取+未拥有）
func is_goal_claimable(goal: Dictionary) -> bool:
	return (not is_goal_claimed(goal)) and (not g.friends.has(goal.get("friend", ""))) and is_goal_done(goal)

# 领取：置 claimed 标记并发挚友（幂等：不可领取时返回 false）
func claim_goal(goal: Dictionary) -> bool:
	if not is_goal_claimable(goal):
		return false
	g.goal_stats["claimed_" + goal.get("friend", "")] = 1
	return g.unlock_friend(goal.get("friend", ""))

# 全部目标已领取（或已拥有）——挚友目标入口隐藏依据
func all_goals_claimed() -> bool:
	for goal in get_goal_list():
		var fid = goal.get("friend", "")
		if g.friends.has(fid): continue
		if not is_goal_claimed(goal): return false
	return true

# 挚友显示名（查 friends.json 配置，兜底返回 id）
func get_friend_name(friend_id: String) -> String:
	return g._friend_configs.get(friend_id, {}).get("name", friend_id)
