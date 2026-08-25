# ============================================================
# 道具系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name ItemSystem
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
		"items": g.items,   # 背包道具
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("items"):
		g.items = s.items
		# 旧存档兼容：配置里新增的道具自动补0
		for item_id in g.ITEM_CONFIG.keys():
			if not g.items.has(item_id):
				g.items[item_id] = 0

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# ========== 通用道具使用（数量型） ==========
# 背包"使用/打开"按钮统一走这里，返回 {"ok", "msg"}；加新数量型道具只需加个分支
func use_item(item_id: String, count: int) -> Dictionary:
	if count <= 0: return {"ok": false, "msg": "数量错误"}
	if g.items.get(item_id, 0) < count: return {"ok": false, "msg": "道具不足"}
	match item_id:
		"exp_box":
			g.items.exp_box -= count
			g.items.experience += 99999 * count
			return {"ok": true, "msg": "获得阅历 ×%d" % (99999 * count)}
		"hour_card":
			g.items.hour_card -= count
			var gain = g.get_total_auto_income() * 3600 * count
			g.money += gain
			return {"ok": true, "msg": "获得铜钱 ×%d" % gain}
		"reputation_card":
			g.items.reputation_card -= count
			g.reputation += 10 * count
			return {"ok": true, "msg": "声望 +%d" % (10 * count)}
		"reputation_card_adv":
			g.items.reputation_card_adv -= count
			g.reputation += 100 * count
			return {"ok": true, "msg": "声望 +%d" % (100 * count)}
		"recruit_bronze", "recruit_silver", "recruit_gold":
			# 募工牌：随机已解锁店铺店员 +1/3/5，不消耗铜钱
			if g.shops.is_empty(): return {"ok": false, "msg": "还没有已解锁的店铺"}
			var per_use = {"recruit_bronze": 1, "recruit_silver": 3, "recruit_gold": 5}[item_id]
			g.items[item_id] -= count
			var gains = {}
			for i in range(count):
				var keys = g.shops.keys()
				var sid = keys[randi() % keys.size()]
				g.shops[sid].staff += per_use
				gains[sid] = gains.get(sid, 0) + per_use
			var parts = []
			for sid in gains.keys():
				parts.append("【%s】店员+%d" % [g.shops[sid].name, gains[sid]])
			return {"ok": true, "msg": "、".join(parts)}
		"huo_qi", "ci_qi", "qiong_jiang", "cha_ye", "xuan_zhi":
			# 【新增】游历道具：每使用1个，随机一名对应职业门客基础赚速+500（逐个随机，可命中同一门客）
			var buff_category = {"huo_qi": "侠", "ci_qi": "商", "qiong_jiang": "工", "cha_ye": "农", "xuan_zhi": "士"}[item_id]
			var buff_pool = []
			for hid in g.heroes.keys():
				if g.heroes[hid].get("category", "") == buff_category:
					buff_pool.append(hid)
			if buff_pool.is_empty():
				return {"ok": false, "msg": "没有已拥有的%s类门客" % buff_category}
			g.items[item_id] -= count
			var buff_gains = {}
			for i in range(count):
				var hid = buff_pool[randi() % buff_pool.size()]
				g.heroes[hid].base_income += 500
				buff_gains[hid] = buff_gains.get(hid, 0) + 500
			var buff_parts = []
			for hid in buff_gains.keys():
				buff_parts.append("【%s】基础赚速+%d" % [g.heroes[hid].name, buff_gains[hid]])
			return {"ok": true, "msg": "、".join(buff_parts)}
		"random_book":
			# 【新增】随机书籍：每打开1个，从五种之道中随机获得一本
			g.items.random_book -= count
			var book_pool = ["shi_way", "nong_way", "gong_way", "shang_way", "xia_way"]
			var book_gains = {}
			for i in range(count):
				var bid = book_pool[randi() % book_pool.size()]
				g.items[bid] = g.items.get(bid, 0) + 1
				book_gains[bid] = book_gains.get(bid, 0) + 1
			var book_parts = []
			for bid in book_gains.keys():
				book_parts.append("【%s】×%d" % [g.ITEM_CONFIG[bid].name, book_gains[bid]])
			return {"ok": true, "msg": "获得：" + "、".join(book_parts)}
	return {"ok": false, "msg": "该道具不可使用"}

# 门客帖兑换（门客/挚友统一消耗 hero_token）
func exchange_role_with_token(role_type: String, role_id: String, cost: int) -> Dictionary:
	if g.items.get("hero_token", 0) < cost:
		return {"ok": false, "reason": "门客帖不足"}
	var success = false
	if role_type == "hero":
		if g.heroes.has(role_id):
			return {"ok": false, "reason": "已拥有该门客"}
		success = g.unlock_hero(role_id)
	else:
		if g.friends.has(role_id):
			return {"ok": false, "reason": "已拥有该挚友"}
		success = g.unlock_friend(role_id)
	if not success:
		return {"ok": false, "reason": "兑换失败"}
	g.items.hero_token -= cost
	return {"ok": true}
