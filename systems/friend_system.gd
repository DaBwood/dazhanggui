# ============================================================
# 挚友系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name FriendSystem
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
		"friends": g.friends,   # 挚友数据
		"energy": g.energy,   # 精力（谈心消耗）
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("friends"): g.friends = s.friends
	if s.has("energy"): g.energy = s.energy
	# 清理存档中已不存在的挚友（防止配置删了存档还残留）
	for friend_id in g.friends.keys():
		if not g._friend_configs.has(friend_id):
			g.friends.erase(friend_id)
	# 旧存档兼容：没有店铺技能数据的挚友补初始化
	for friend_id in g.friends.keys():
		if not g.friends[friend_id].has("shop_skills"):
			_init_friend_shop_skills(friend_id)

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 当前友好最高的已拥有挚友ID（月老牵线的谈心对象）；没有挚友时返回空串
func _get_highest_friendly_friend() -> String:
	var best_id = ""
	var best_friendly = -1
	for fid in g.friends.keys():
		var fv = g.friends[fid].get("friendly", 0)
		if fv > best_friendly:
			best_friendly = fv
			best_id = fid
	return best_id

# 谈心前的祝福结算：返回 {"target"=谈心挚友ID, "force_twin"=是否必双胞胎, "yuelao"=月老是否生效, "guanyin"=观音是否生效}
# 只有存在徒弟空位（本次谈心能领养）时才消耗层数；没有空位则层数保留、继续累计
func _prepare_chat_adoption(default_friend_id: String) -> Dictionary:
	var bless = {"target": default_friend_id, "force_twin": false, "yuelao": false, "guanyin": false}
	if not g._has_empty_apprentice_slot():
		return bless
	if g.yuelao_count > 0:
		g.yuelao_count -= 1
		var top_id = _get_highest_friendly_friend()
		if top_id != "":
			bless.target = top_id
		bless.yuelao = true
	if g.guanyin_count > 0:
		g.guanyin_count -= 1
		bless.force_twin = true
		bless.guanyin = true
	return bless

func unlock_friend(friend_id: String) -> bool:
	if g.friends.has(friend_id): return false
	var cfg = g.get_friend_config(friend_id)
	if cfg.is_empty(): return false
	g.friends[friend_id] = cfg
	_init_friend_shop_skills(friend_id)
	return true

# ========== 计算函数 ==========

# 挚友店铺技能列表
func _init_friend_shop_skills(friend_id: String):
	if not g.friends.has(friend_id): return
	var f = g.friends[friend_id]
	var categories = ["士", "农", "工", "商", "侠"]
	var skills = []
	for i in range(400):
		skills.append({
			"category": categories[i % 5],
			"bonus": 0.05,
			"refresh_count": 0
		})
	f.shop_skills = skills

func get_friend_shop_skills(friend_id: String) -> Array:
	if not g.friends.has(friend_id): return []
	var f = g.friends[friend_id]
	if not f.has("shop_skills"):
		_init_friend_shop_skills(friend_id)
	var max_slots = min(400, int(f.friendly / 500))
	var skills = f.shop_skills
	var result = []
	for i in range(min(max_slots, skills.size())):
		result.append(skills[i])
	return result

func refresh_friend_shop_skill(friend_id: String, skill_index: int, use_wish_stone: bool = false) -> bool:
	if not g.friends.has(friend_id): return false
	var f = g.friends[friend_id]
	if not f.has("shop_skills"): _init_friend_shop_skills(friend_id)
	var skills = f.shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	
	var max_slots = min(400, int(f.friendly / 500))
	if skill_index >= max_slots: return false
	
	var skill = skills[skill_index]
	if skill.bonus >= 0.30: return false
	
	if use_wish_stone:
		var wish_cost = 1
		if g.items.get("wish_stone", 0) < wish_cost:
			return false
		g.items.wish_stone -= wish_cost
		skill.refresh_count += 1
		var new_bonus = randf_range(0.20, 0.31)
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	else:
		var cost = 100 * int(pow(2, skill.refresh_count))
		if g.money < cost: return false
		g.money -= cost
		skill.refresh_count += 1
		
		var roll = randf()
		var new_bonus: float
		if roll < 0.9:
			# 90% 概率刷新出 5% ~ 19% 的加成
			new_bonus = randf_range(0.05, 0.199)
		else:
			# 10% 概率刷新出 20% ~ 30% 的加成
			new_bonus = randf_range(0.20, 0.31)
		
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	return true

# 挚友给门客的加成
func get_friend_hero_bonus(friend_id: String) -> int:
	if not g.friends.has(friend_id): return 0
	var f = g.friends[friend_id]
	var fixed_total = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
	var percent = 1.0 + f.percent_skill_level * 0.05
	return int(fixed_total * percent)

# 挚友的固定加成（天生丽质 → 额外赚速）
func get_friend_fixed_bonus(friend_id: String) -> int:
	if not g.friends.has(friend_id): return 0
	var f = g.friends[friend_id]
	return f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))

# 挚友的百分比加成（花开富贵 → 百分比）
func get_friend_percent_bonus(friend_id: String) -> float:
	if not g.friends.has(friend_id): return 0.0
	var f = g.friends[friend_id]
	return f.percent_skill_level * 0.05

# 谈心
# 谈心：随机一位已拥有挚友，缘分+才华，有空位则领养徒弟
# 【修改】月老层数>0且有徒弟空位：本次谈心对象改为友好最高的挚友；观音层数>0且有徒弟空位：本次领养必为双胞胎
func chat_with_friend(once: bool = true) -> Dictionary:
	if g.energy <= 0: return {"ok": false, "reason": "精力不足"}
	
	var results = []
	if once:
		g.energy -= 1
		var keys = g.friends.keys()
		var fid = keys[randi() % keys.size()]
		# 【新增】月老/观音祝福结算（没有徒弟空位时不消耗层数）
		var bless = _prepare_chat_adoption(fid)
		fid = bless.target
		var f = g.friends[fid]
		f.bond += f.talent
		# 有空位则与本次谈心的挚友领养一位徒弟（观音生效时必双胞胎）
		var n = g.adopt_apprentice(fid, bless.force_twin)
		results.append({"friend_id": fid, "name": f.name, "gain": f.talent, "adopted": n > 0, "twin": n == 2, "yuelao": bless.yuelao, "guanyin": bless.guanyin})
	else:
		while g.energy > 0:
			g.energy -= 1
			var keys = g.friends.keys()
			var fid = keys[randi() % keys.size()]
			# 【新增】一键谈心逐次结算月老/观音祝福
			var bless = _prepare_chat_adoption(fid)
			fid = bless.target
			var f = g.friends[fid]
			f.bond += f.talent
			# 一键谈心：有几个空位，前几位挚友就各领养一位
			var n = g.adopt_apprentice(fid, bless.force_twin)
			results.append({"friend_id": fid, "name": f.name, "gain": f.talent, "adopted": n > 0, "twin": n == 2, "yuelao": bless.yuelao, "guanyin": bless.guanyin})
	
	return {"ok": true, "results": results}

# 与指定挚友谈心（游山玩水/吟诗作对共用）：缘分+才华，有空位则领养徒弟
# 不消耗精力，消耗由调用方（元宝/玫瑰香水）负责
# 【修改】指定谈心不触发月老（对象已由玩家指定），观音祝福正常生效（必双胞胎）
func chat_with_specific_friend(friend_id: String) -> Dictionary:
	if not g.friends.has(friend_id): return {"ok": false, "reason": "未拥有该挚友"}
	var f = g.friends[friend_id]
	f.bond += f.talent
	# 【新增】观音祝福：有徒弟空位才生效并消耗一层
	var force_twin = false
	var guanyin_used = false
	if g.guanyin_count > 0 and g._has_empty_apprentice_slot():
		g.guanyin_count -= 1
		force_twin = true
		guanyin_used = true
	var n = g.adopt_apprentice(friend_id, force_twin)
	return {"ok": true, "name": f.name, "gain": f.talent, "adopted": n > 0, "twin": n == 2, "guanyin": guanyin_used}

# 升级固定技能
func upgrade_friend_fixed(friend_id: String) -> bool:
	if not g.friends.has(friend_id): return false
	var f = g.friends[friend_id]
	var cost = (f.fixed_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.fixed_skill_level += 1
	return true

# 升级百分比技能
func upgrade_friend_percent(friend_id: String) -> bool:
	if not g.friends.has(friend_id): return false
	var f = g.friends[friend_id]
	var cost = (f.percent_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.percent_skill_level += 1
	return true

# 赠送
func gift_friend(friend_id: String, item_id: String) -> bool:
	if not g.friends.has(friend_id): return false
	if not g.items.has(item_id) or g.items[item_id] <= 0: return false
	var f = g.friends[friend_id]
	match item_id:
		"wood_comb":
			g.items.wood_comb -= 1
			f.friendly += 1
		"rouge":
			g.items.rouge -= 1
			f.talent += 1
		"energy_pill":
			g.items.energy_pill -= 1
			g.energy = min(100, g.energy + 3)
		_:
			return false
	return true

# 挚友当前美名下标：友好和才华都达标才算，-1=无美名
func get_friend_title_index(friend_id: String) -> int:
	if not g.friends.has(friend_id): return -1
	var f = g.friends[friend_id]
	var idx = -1
	for i in range(g.FRIEND_TITLES.size()):
		if f.friendly >= g.FRIEND_TITLES[i].req and f.talent >= g.FRIEND_TITLES[i].req:
			idx = i
	return idx

# 挚友当前美名（无美名返回"无"）
func get_friend_title(friend_id: String) -> String:
	var idx = get_friend_title_index(friend_id)
	return g.FRIEND_TITLES[idx].title if idx >= 0 else "无"
