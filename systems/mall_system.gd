# ============================================================
# 商城/VIP系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name MallSystem
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
		"vip_level": g.vip_level,   # VIP等级
		"vip_exp": g.vip_exp,   # VIP经验
		"vip_claimed_rewards": g.vip_claimed_rewards,   # VIP已领奖励
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("vip_level"): g.vip_level = s.vip_level
	if s.has("vip_exp"): g.vip_exp = s.vip_exp
	if s.has("vip_claimed_rewards"): g.vip_claimed_rewards = s.vip_claimed_rewards

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 购买特惠礼包（自娱自乐版，直接成功）；quantity 为预留批量参数，UI 层后续可接入
func buy_special_pack(pack: Dictionary, quantity: int = 1) -> bool:
	if quantity <= 0: return false
	g.vip_exp += pack.cost * 10 * quantity
	g.vip_level = get_vip_level()
	for item_id in pack.items.keys():
		g.items[item_id] = g.items.get(item_id, 0) + pack.items[item_id] * quantity
	return true

# 购买商城礼包（通用，加礼包只改上面的表）
func buy_mall_pack(pack: Dictionary) -> bool:
	if g.yuanbao < pack.cost: return false
	g.yuanbao -= pack.cost
	for item_id in pack.get("items", {}).keys():
		g.items[item_id] = g.items.get(item_id, 0) + pack.items[item_id]
	if pack.has("beast"):
		g.add_beast(pack.beast)
	g.items["beast_fruit"] = int(g.items.get("beast_fruit", 0)) + int(pack.get("beast_fruit", 0))   # 【改】珍兽果改走道具
	g.items["aroma_fruit"] = int(g.items.get("aroma_fruit", 0)) + int(pack.get("aroma_fruit", 0))   # 【改】
	return true

# 购买声望礼包：988元宝 → 高级声望卡×10 + 声望卡×100
func buy_reputation_pack() -> bool:
	if g.yuanbao < 988: return false
	g.yuanbao -= 988
	g.items.reputation_card_adv = g.items.get("reputation_card_adv", 0) + 10
	g.items.reputation_card = g.items.get("reputation_card", 0) + 100
	return true

func buy_test_beast_pack() -> bool:
	if g.yuanbao < 19888: return false
	g.yuanbao -= 19888
	g.add_beast("zou_yu")
	g.items["beast_fruit"] = int(g.items.get("beast_fruit", 0)) + 988   # 【改】
	g.items["aroma_fruit"] = int(g.items.get("aroma_fruit", 0)) + 988   # 【改】
	return true

# 充值（自娱自乐版，直接成功）
func do_recharge(amount: int) -> bool:
	if amount <= 0: return false
	g.yuanbao += amount * 10
	g.vip_exp += amount * 10
	g.vip_level = get_vip_level()  # 根据经验重新计算等级
	g.goal_system.add_stat("recharge_done")
	return true

# ========== VIP 等级函数 ==========
func get_vip_level() -> int:
	for i in range(g.VIP_EXP_TABLE.size() - 1, -1, -1):
		if g.vip_exp >= g.VIP_EXP_TABLE[i]:
			return i
	return 0

func get_vip_next_level_exp() -> int:
	var current = get_vip_level()
	if current >= g.VIP_EXP_TABLE.size() - 1:
		return 0  # 已满级
	return g.VIP_EXP_TABLE[current + 1]

func get_vip_exp_progress() -> float:
	var current = get_vip_level()
	if current >= g.VIP_EXP_TABLE.size() - 1:
		return 1.0
	var current_exp = g.VIP_EXP_TABLE[current]
	var next_exp = g.VIP_EXP_TABLE[current + 1]
	var progress = float(g.vip_exp - current_exp) / float(next_exp - current_exp)
	return clamp(progress, 0.0, 1.0)

# 获取门客解锁所需VIP等级（初始门客返回0）
func get_hero_unlock_vip(hero_id: String) -> int:
	for level in g._vip_rewards.keys():
		for reward in g._vip_rewards[level]:
			if reward.type == "hero" and reward.id == hero_id:
				return int(level)
	return 0

# 获取挚友解锁所需VIP等级（初始挚友返回0）
func get_friend_unlock_vip(friend_id: String) -> int:
	for level in g._vip_rewards.keys():
		for reward in g._vip_rewards[level]:
			if reward.type == "friend" and reward.id == friend_id:
				return int(level)
	return 0

# 判断VIP奖励是否已领取
func is_vip_reward_claimed(level: int) -> bool:
	return g.vip_claimed_rewards.get(str(level), false)

# 手动领取VIP奖励
func claim_vip_reward(level: int) -> bool:
	if level <= 0: return false
	if get_vip_level() < level: return false
	if is_vip_reward_claimed(level): return false
	if not g._vip_rewards.has(str(level)): return false   # 注意：JSON key 是字符串
	
	for reward in g._vip_rewards[str(level)]:
		match reward.type:
			"hero": g.unlock_hero(reward.id)
			"friend": g.unlock_friend(reward.id)
	
	g.vip_claimed_rewards[str(level)] = true
	return true
