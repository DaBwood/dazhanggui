# ============================================================
# 游历系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name TravelSystem
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
		"stamina": g.stamina,   # 体力
		"stamina_time": g.stamina_time,   # 体力结算时间戳
		"friend_affection": g.friend_affection,   # 表2挚友好感进度
		"yuelao_count": g.yuelao_count,   # 月老祝福层数
		"guanyin_count": g.guanyin_count,   # 观音祝福层数
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	# 老存档没有这些字段则保持初始值
	if s.has("stamina"): g.stamina = s.stamina
	if s.has("stamina_time"): g.stamina_time = s.stamina_time
	if s.has("friend_affection"): g.friend_affection = s.friend_affection
	if s.has("yuelao_count"): g.yuelao_count = s.yuelao_count
	if s.has("guanyin_count"): g.guanyin_count = s.guanyin_count

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 懒结算体力：每20分钟恢复1点，30只是自动恢复的上限（杜康事件可超上限）
func _settle_stamina():

	var now = int(Time.get_unix_time_from_system())
	if g.stamina_time <= 0:
		g.stamina_time = now
		return
	# 体力已满（或超出上限）：不再恢复，但绝不能截断超出部分
	if g.stamina >= g.STAMINA_MAX:
		g.stamina_time = now
		return
	@warning_ignore("integer_division")
	var regen = (now - g.stamina_time) / g.STAMINA_RECOVER_SECONDS
	if regen > 0:
		g.stamina = min(g.STAMINA_MAX, g.stamina + regen)
		g.stamina_time = g.stamina_time + regen * g.STAMINA_RECOVER_SECONDS

# 获取当前体力（先懒结算恢复）
func get_stamina() -> int:
	_settle_stamina()
	return g.stamina

# 游历：消耗1点体力，固定声望+20，再按50%/40%/10%触发地点/物品/事件
func do_travel() -> Dictionary:
	_settle_stamina()
	if g.stamina < 1:
		return {"ok": false, "msg": "体力不足"}
	g.stamina -= 1
	g.reputation += g.TRAVEL_REPUTATION
	g.goal_system.add_stat("travel_count")   # 【第6批新增】挚友目标：累计游历计数
	var roll = randf()
	if roll < g.TRAVEL_LOCATION_CHANCE:
		return _do_travel_location()
	elif roll < g.TRAVEL_LOCATION_CHANCE + g.TRAVEL_ITEM_CHANCE:
		return _do_travel_item()
	return _do_travel_event()

# 游历到地点：随机一个地点，从该地点「已拥有挚友 + 未拥有的表2挚友」中随机相遇
# 已拥有挚友友好+1；未拥有表2挚友好感+1，达标即获得
func _do_travel_location() -> Dictionary:
	var loc_ids = g.TRAVEL_LOCATIONS.keys()
	var loc_id = loc_ids[randi() % loc_ids.size()]
	var loc = g.TRAVEL_LOCATIONS[loc_id]
	# 筛选候选：该地点中已拥有的挚友 + 未拥有但属于表2的挚友
	var candidates = []
	for fid in loc.friends:
		if g.friends.has(fid):
			candidates.append(fid)
		elif g.TRAVEL_AFFECTION.has(fid):
			candidates.append(fid)
	if candidates.is_empty():
		return {"ok": true, "type": "location", "msg": "游历到【%s】，没有遇到熟人，声望+%d" % [loc.name, g.TRAVEL_REPUTATION]}
	var fid = candidates[randi() % candidates.size()]
	var cfg = g.get_friend_config(fid)
	if g.friends.has(fid):
		# 已拥有：友好+1
		g.friends[fid].friendly += 1
		return {"ok": true, "type": "location", "msg": "游历到【%s】，偶遇挚友【%s】，友好+1，声望+%d" % [loc.name, cfg.get("name", fid), g.TRAVEL_REPUTATION]}
	# 未拥有的表2挚友：好感+1，达标则获得
	g.friend_affection[fid] = g.friend_affection.get(fid, 0) + 1
	var need = g.TRAVEL_AFFECTION[fid]
	if g.friend_affection[fid] >= need:
		g.unlock_friend(fid)
		g.friend_affection.erase(fid)
		return {"ok": true, "type": "location", "msg": "游历到【%s】，与【%s】好感已满，喜获挚友！声望+%d" % [loc.name, cfg.get("name", fid), g.TRAVEL_REPUTATION], "unlock_friend": fid}
	return {"ok": true, "type": "location", "msg": "游历到【%s】，与【%s】相遇，好感+1（%d/%d），声望+%d" % [loc.name, cfg.get("name", fid), g.friend_affection[fid], need, g.TRAVEL_REPUTATION]}

# 游历获得物品：物品池20项等概率，抽中给 entry.count 个
func _do_travel_item() -> Dictionary:
	var entry = g.TRAVEL_ITEM_POOL[randi() % g.TRAVEL_ITEM_POOL.size()]
	var item_id = entry.item
	var count = entry.count
	# 珍兽果/奇香果是独立货币（珍兽页面消费用变量），其余进背包
	match item_id:
		"beast_fruit":
			g.beast_fruit += count
		"aroma_fruit":
			g.aroma_fruit += count
		_:
			g.items[item_id] = g.items.get(item_id, 0) + count
	var item_name = g.ITEM_CONFIG.get(item_id, {}).get("name", item_id)
	return {"ok": true, "type": "item", "msg": "游历途中获得【%s】×%d，声望+%d" % [item_name, count, g.TRAVEL_REPUTATION]}

# 游历遭遇事件：5个事件等概率
# 财神到=元宝+1000；月老/观音=祝福层数+1（可累计）；杜康=体力+1~3（可超上限）；今日新菜=赚速最高门客基础赚速+2000
func _do_travel_event() -> Dictionary:
	var events = ["cai_shen", "yue_lao", "guan_yin", "du_kang", "new_dish"]
	var event_id = events[randi() % events.size()]
	match event_id:
		"cai_shen":
			g.yuanbao += g.EV_CAI_SHEN_YUANBAO   # 【重构】数值走变量（travel.json可调）
			return {"ok": true, "type": "event", "msg": "遭遇【财神到】！元宝+%d，声望+%d" % [g.EV_CAI_SHEN_YUANBAO, g.TRAVEL_REPUTATION]}
		"yue_lao":
			g.yuelao_count += 1
			return {"ok": true, "type": "event", "msg": "遭遇【月老】！获得1层祝福：下次谈心（能领养徒弟时）将与友好最高的挚友谈心（当前累计%d层），声望+%d" % [g.yuelao_count, g.TRAVEL_REPUTATION]}
		"guan_yin":
			g.guanyin_count += 1
			return {"ok": true, "type": "event", "msg": "遭遇【观音】！获得1层祝福：下次谈心（能领养徒弟时）必为双胞胎（当前累计%d层），声望+%d" % [g.guanyin_count, g.TRAVEL_REPUTATION]}
		"du_kang":
			# 杜康赠酒：体力+MIN~MAX，不受自动恢复上限限制
			_settle_stamina()
			var gain = randi_range(g.EV_DU_KANG_MIN, g.EV_DU_KANG_MAX)   # 【重构】数值走变量
			g.stamina += gain
			return {"ok": true, "type": "event", "msg": "遭遇【杜康】！共饮美酒，体力+%d（当前%d点），声望+%d" % [gain, g.stamina, g.TRAVEL_REPUTATION]}
		"new_dish":
			# 今日新菜：当前总赚速最高的已拥有门客基础赚速+N
			var best_id = ""
			var best_income = -1
			for hid in g.heroes.keys():
				var income = g.get_hero_income(hid)
				if income > best_income:
					best_income = income
					best_id = hid
			if best_id == "":
				return {"ok": true, "type": "event", "msg": "遭遇【今日新菜】，但还没有门客可以享用，声望+%d" % g.TRAVEL_REPUTATION}
			g.heroes[best_id].base_income += g.EV_NEW_DISH_INCOME   # 【重构】数值走变量
			return {"ok": true, "type": "event", "msg": "遭遇【今日新菜】！【%s】大快朵颐，基础赚速+%d，声望+%d" % [g.heroes[best_id].name, g.EV_NEW_DISH_INCOME, g.TRAVEL_REPUTATION]}
	# 安全兜底：match 五个分支均已return，此行理论上不可达
	return {"ok": false, "msg": "未知事件"}
