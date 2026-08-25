# ============================================================
# 店铺系统（含钱庄）（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name ShopSystem
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
		"hq": g.hq,   # 钱庄数据
		"shops": g.shops,   # 店铺数据
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("hq"): g.hq = s.hq
	if g._shop_configs.is_empty():
		g._shop_configs = g._load_json("res://data/shops.json")
	if s.has("shops"):
		var saved = s.shops
		g.shops.clear()
		# 只恢复配置里仍存在的店铺（防止配置删除后残留）
		for sid in saved.keys():
			if g._shop_configs.has(sid): g.shops[sid] = saved[sid].duplicate(true)
	else:
		g.shops.clear()

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

func get_shop_config(shop_id: String) -> Dictionary:
	return g._shop_configs.get(shop_id, {}).duplicate(true)

func get_shop_unlock_chapter(shop_id: String) -> int:
	return g.SHOP_UNLOCK_TABLE.get(shop_id, 999999)

func can_unlock_shop(shop_id: String) -> bool:
	if g.shops.has(shop_id): return false
	return g.stage_main >= get_shop_unlock_chapter(shop_id)

func unlock_shop(shop_id: String) -> bool:
	if not can_unlock_shop(shop_id): return false
	if not g._shop_configs.has(shop_id): return false
	g.shops[shop_id] = g._shop_configs[shop_id].duplicate(true)
	return true

#钱庄赚速
func get_hq_auto_income() -> int:
	return int(g.hq.auto_base * pow(g.hq.income_mult, g.hq.level - 1))

#钱庄全局加成
func get_global_bonus_percent() -> float:
	return g.hq.global_bonus * (g.hq.level - 1)

#店铺赚速
func get_shop_auto_income(shop_id: String) -> int:
	var s = g.shops[shop_id]
	#基础赚速
	var base = int(s.auto_base * pow(s.income_mult, s.level - 1))
	#店员赚速
	var staff = s.staff * s.staff_income
	
	# 门客派遣加成
	var hero_bonus = 0.0
	for hero_id in g.heroes.keys():
		if g.heroes[hero_id].assigned_shop == shop_id:
			hero_bonus += HeroData.get_shop_bonus(g.heroes[hero_id])

	# 挚友加成
	var friend_shop_bonus = 0.0
	for fid in g.friends.keys():
		for sk in g.get_friend_shop_skills(fid):
			if sk.category == s.get("category", ""):
				friend_shop_bonus += sk.bonus

	#基础+店员
	var subtotal = base + staff
	
	#总百分比
	var bonus = 1.0 + get_global_bonus_percent()+hero_bonus + friend_shop_bonus
	#返回最终赚速
	return int(subtotal * bonus)

#总赚速
func get_total_auto_income() -> int:
	var total = get_hq_auto_income()
	for shop_id in g.shops.keys():
		total += get_shop_auto_income(shop_id)
	for hero_id in g.heroes.keys():
		total += g.get_hero_contribution(hero_id)
	# 徒弟赚速（含魔法师/联姻加成）
	for i in range(5):
		total += g.get_apprentice_income(i)
	return total

#钱庄升级
func upgrade_hq() -> bool:
	if g.items.hq_blueprint >= g.hq.upgrade_cost:
		g.items.hq_blueprint -= g.hq.upgrade_cost
		g.hq.level += 1
		g.hq.upgrade_cost = int(ceil(g.hq.upgrade_cost * 1.3))
		g.hq.click_income *= 1.5 
		return true
	return false

#店铺升级
func upgrade_shop(shop_id: String) -> bool:
	if shop_id == "": return false
	if not g.shops.has(shop_id): return false
	var s = g.shops[shop_id]
	if g.items.shop_blueprint >= s.upgrade_cost:
		g.items.shop_blueprint -= s.upgrade_cost
		s.level += 1
		s.upgrade_cost = int(ceil(s.upgrade_cost * 1.5))
		return true
	return false

#店铺招募
func hire_staff(shop_id: String) -> bool:
	if shop_id == "": return false
	if not g.shops.has(shop_id): return false
	var s = g.shops[shop_id]
	if g.money >= s.hire_cost:
		g.money -= s.hire_cost
		s.staff += 1
		s.hire_cost = int(ceil(s.hire_cost*1.01))
		return true
	return false

#计算离线收益
func calculate_offline_income() -> int:
	
	if g.last_logout_time <= 0 and g.last_login_time <= 0: return 0
	var now = Time.get_unix_time_from_system()
	var offline_seconds: int = 0
	
	if g.last_logout_time > g.last_login_time:
		# 上次正常退出过：用"上次退出 → 现在"这段时间
		@warning_ignore("narrowing_conversion")
		offline_seconds = now - g.last_logout_time
		print("正常离线，时长：", offline_seconds, "秒")
	elif g.last_login_time > 0:
		# 闪退或强退：last_logout_time 没被更新，用"上次登录 → 现在"
		@warning_ignore("narrowing_conversion")
		offline_seconds = now - g.last_login_time
		print("检测到闪退，按上次在线时间计算，时长：", offline_seconds, "秒")
	
	# 限制最多24小时，防止数据爆炸
	offline_seconds = clamp(offline_seconds, 0, 86400)
	return int(get_total_auto_income() * offline_seconds * g.OFFLINE_RATE)
