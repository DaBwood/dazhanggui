class_name GameData
extends RefCounted

#保存路径
const SAVE_PATH = "user://save.json"
const OFFLINE_RATE = 0.8

#==============道具物品=========================
const ITEM_CONFIG = {
	"shop_blueprint":  {"name": "商铺图纸", "desc": "用于解锁新商铺"},
	"hq_blueprint":    {"name": "钱庄图纸", "desc": "用于升级钱庄建筑"},
	"aptitude_pill":   {"name": "资质丹",   "desc": "提升门客资质"},
	"experience":      {"name": "阅历",     "desc": "门客升级所需经验"},
	"abacus":          {"name": "算盘",     "desc": "提升店铺算力效率"},
	"fengyasong": {"name": "风雅颂", "desc": "门客突破所需"},
	"exp_box":         {"name": "阅历箱",   "desc": "打开获得99999阅历"},      
	"ginseng":         {"name": "百年人参", "desc": "指定门客基础赚速+2000"},
	"wood_comb":      {"name": "木梳",   "desc": "赠送给挚友，友好+1"},
	"rouge":          {"name": "胭脂",   "desc": "赠送给挚友，才华+1"},
	"energy_pill":    {"name": "精力丹", "desc": "恢复3点精力"},
	"zui_xian_niang":  {"name": "醉仙酿", "desc": "李白赋诗升级所需"},
}
#=========道具初始数量===========
var items = {
	"shop_blueprint": 999,
	"hq_blueprint": 999,
	"aptitude_pill": 999,
	"experience": 999999,
	"abacus": 999,
	"fengyasong": 999,
	"exp_box": 999,      
	"ginseng": 999,
	"wood_comb":999,
	"rouge": 999,
	"energy_pill":999,
	"zui_xian_niang": 48600,
}

#引用门客数据
var heroes: Dictionary = HeroData.get_default_heroes().duplicate(true)

var last_login_time: int = 0      # 本次登录时间
var last_logout_time: int = 0     # 上次正常退出时间

# ========== 初始货币 ==========
var money: int = 0
var yuanbao: int = 0
var energy: int = 100

# ========== 挚友 ==========
var friends = {
	"shu_xiang_nv": {
		"name": "书香女",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["wan_jinya", "liu_bukuai"],
	},
	"zhen_xian_nv": {
		"name": "针线女",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["kang_chashi", "niu_fushi"],
	},
	"wu_nv": {
		"name": "舞女",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["he_yashi"],
	},
	"jian_wuzhe": {
		"name": "剑舞者",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["liang_waiqi"],
	},
	"dou_fu_nv": {
		"name": "豆腐女",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["luo_sunshan", "tang_hulu"],
	},
	"xiu_niang": {
		"name": "秀娘",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["li_gushi", "zheng_guonong"],
	},
	"xi_zi": {
		"name": "戏子",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["wu_shiren", "liu_xizi"],
	},
	"mai_san_nv": {
		"name": "买伞女",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["zhang_laobo", "zhu_huolang"],
	},
	"ya_huan": {
		"name": "丫鬟",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["hu_qigai"],
	},
	"xiao_shijie": {
		"name": "小师姐",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["jia_houzi"],
	},
	"meng_qier": {
		"name": "蒙琪儿",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["zhu_daliang"],
	},
	"jing_an": {
		"name": "静庵",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["zheng_chuzi"],
	},
	"cu_ju_nv": {
		"name": "蹴鞠女",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["cai_yufu"],
	},
	"li_shishi": {
		"name": "李师师",
		"friendly": 100,
		"talent": 100,
		"bond": 0,
		"fixed_skill_level": 0,
		"percent_skill_level": 0,
		"bound_heroes": ["ge_langzhong"],
	},
}


# ========== 钱庄（特殊建筑）==========
var hq = {
	"name": "钱庄",
	"click_income": 100,
	"auto_base": 100,
	"level": 1,
	"upgrade_cost": 1,
	"income_mult": 1.5,
	"global_bonus": 0.05,
}
# ========== 普通店铺数据库 ==========
var shops = {
	"tea_shop": { 
		"name": "茶楼", 
		"auto_base": 5, 
		"level": 1, 
		"staff": 0, 
		"upgrade_cost": 1, 
		"income_mult": 1.5, 
		"staff_income": 3,
		"hire_cost":50,
		"category": "工"
	},
	"inn_shop": { 
		"name": "客栈", 
		"auto_base": 8, 
		"level": 1, 
		"staff": 0, 
		"upgrade_cost": 1, 
		"income_mult": 1.6, 
		"staff_income": 4,
		"hire_cost":60,
		"category": "商"
	},
}


# ========== 计算函数 ==========

# 挚友店铺技能列表
func get_friend_shop_skills(friend_id: String) -> Array:
	if not friends.has(friend_id): return []
	var f = friends[friend_id]
	var count = int(f.friendly / 50)
	var categories = ["士", "农", "工", "商", "侠"]
	var skills = []
	for i in range(count):
		skills.append({"category": categories[i % 5], "bonus": 0.05})
	return skills

# 挚友给门客的加成
func get_friend_hero_bonus(friend_id: String) -> int:
	if not friends.has(friend_id): return 0
	var f = friends[friend_id]
	var fixed_total = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
	var percent = 1.0 + f.percent_skill_level * 0.05
	return int(fixed_total * percent)

# 挚友的固定加成（天生丽质 → 额外赚速）
func get_friend_fixed_bonus(friend_id: String) -> int:
	if not friends.has(friend_id): return 0
	var f = friends[friend_id]
	return f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))

# 挚友的百分比加成（花开富贵 → 百分比）
func get_friend_percent_bonus(friend_id: String) -> float:
	if not friends.has(friend_id): return 0.0
	var f = friends[friend_id]
	return f.percent_skill_level * 0.05

# 门客的额外赚速总和（人参 + 挚友固定加成）
func get_hero_extra_income(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var extra = heroes[hero_id].get("base_income", 0)
	for fid in friends.keys():
		if hero_id in friends[fid].bound_heroes:
			extra += get_friend_fixed_bonus(fid)
	return extra

# 门客的百分比加成总和（挚友 + 预留灵兽/藏宝）
func get_hero_percent_bonus(hero_id: String) -> float:
	if not heroes.has(hero_id): return 0.0
	var bonus = 0.0
	for fid in friends.keys():
		if hero_id in friends[fid].bound_heroes:
			bonus += get_friend_percent_bonus(fid)
	# TODO: 灵兽加成
	# TODO: 藏宝加成
	return bonus

# 门客总赚速（供 UI 显示）
func get_hero_income(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var h = heroes[hero_id]
	return HeroData.get_income(h, get_hero_percent_bonus(hero_id), get_hero_extra_income(hero_id))

# 门客对全局的贡献（供自动收入）
func get_hero_contribution(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var h = heroes[hero_id]
	return HeroData.get_global_contribution(h, get_hero_percent_bonus(hero_id), get_hero_extra_income(hero_id))

# 谈心
func chat_with_friend(once: bool = true) -> Dictionary:
	if energy <= 0: return {"ok": false, "reason": "精力不足"}
	
	var results = []
	if once:
		energy -= 1
		var keys = friends.keys()
		var fid = keys[randi() % keys.size()]
		var f = friends[fid]
		f.bond += f.talent
		results.append({"friend_id": fid, "name": f.name, "gain": f.talent})
	else:
		while energy > 0:
			energy -= 1
			var keys = friends.keys()
			var fid = keys[randi() % keys.size()]
			var f = friends[fid]
			f.bond += f.talent
			results.append({"friend_id": fid, "name": f.name, "gain": f.talent})
	
	return {"ok": true, "results": results}

# 升级固定技能
func upgrade_friend_fixed(friend_id: String) -> bool:
	if not friends.has(friend_id): return false
	var f = friends[friend_id]
	var cost = (f.fixed_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.fixed_skill_level += 1
	return true

# 升级百分比技能
func upgrade_friend_percent(friend_id: String) -> bool:
	if not friends.has(friend_id): return false
	var f = friends[friend_id]
	var cost = (f.percent_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.percent_skill_level += 1
	return true

# 赠送
func gift_friend(friend_id: String, item_id: String) -> bool:
	if not friends.has(friend_id): return false
	if not items.has(item_id) or items[item_id] <= 0: return false
	var f = friends[friend_id]
	match item_id:
		"wood_comb":
			items.wood_comb -= 1
			f.friendly += 1
		"rouge":
			items.rouge -= 1
			f.talent += 1
		"energy_pill":
			items.energy_pill -= 1
			energy = min(100, energy + 3)
		_:
			return false
	return true





#钱庄赚速
func get_hq_auto_income() -> int:
	return int(hq.auto_base * pow(hq.income_mult, hq.level - 1))

#钱庄全局加成
func get_global_bonus_percent() -> float:
	return hq.global_bonus * (hq.level - 1)

#店铺赚速
func get_shop_auto_income(shop_id: String) -> int:
	var s = shops[shop_id]
	#基础赚速
	var base = int(s.auto_base * pow(s.income_mult, s.level - 1))
	#店员赚速
	var staff = s.staff * s.staff_income
	
	# 门客派遣加成
	var hero_bonus = 0.0
	for hero_id in heroes.keys():
		if heroes[hero_id].assigned_shop == shop_id:
			hero_bonus += HeroData.get_shop_bonus(heroes[hero_id])

	# 挚友加成
	var friend_shop_bonus = 0.0
	for fid in friends.keys():
		for sk in get_friend_shop_skills(fid):
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
	for shop_id in shops.keys():
		total += get_shop_auto_income(shop_id)
	for hero_id in heroes.keys():
		total += get_hero_contribution(hero_id)
	return total
	
#钱庄升级
func upgrade_hq() -> bool:
	if items.hq_blueprint >= hq.upgrade_cost:
		items.hq_blueprint -= hq.upgrade_cost
		hq.level += 1
		hq.upgrade_cost = int(ceil(hq.upgrade_cost * 1.3))
		hq.click_income *= 1.5 
		return true
	return false
	
#店铺升级
func upgrade_shop(shop_id: String) -> bool:
	if shop_id == "": return false
	if not shops.has(shop_id): return false
	var s = shops[shop_id]
	if items.shop_blueprint >= s.upgrade_cost:
		items.shop_blueprint -= s.upgrade_cost
		s.level += 1
		s.upgrade_cost = int(ceil(s.upgrade_cost * 1.5))
		return true
	return false

#店铺招募
func hire_staff(shop_id: String) -> bool:
	if shop_id == "": return false
	if not shops.has(shop_id): return false
	var s = shops[shop_id]
	if money >= s.hire_cost:
		money -= s.hire_cost
		s.staff += 1
		s.hire_cost = int(ceil(s.hire_cost*1.01))
		return true
	return false

#门客升级
func upgrade_hero_level(hero_id: String, batch: bool = false) -> int:
	if not heroes.has(hero_id): return 0
	var hero = heroes[hero_id]
	var max_level = 50 + hero.breakthrough_count * 50
	if hero.level >= max_level:
		return 0
	
	var exp_count = items.get("experience", 0)
	if exp_count <= 0: return 0
	
	var target = hero.level + (10 if batch else 1)
	target = min(target, max_level)  # 不能超过上限
	
	var total_cost = 0
	var levels = 0
	for lv in range(hero.level, target):
		var cost = int(ceil(100 * pow(1.05, lv)))
		if exp_count < total_cost + cost:
			break
		total_cost += cost
		levels += 1
	
	if levels > 0:
		items.experience -= total_cost
		hero.level += levels
		hero.base_income += levels * hero.breakthrough_count * hero.breakthrough_count * 100
		return levels
	return 0

#门客突破
func breakthrough_hero(hero_id: String) -> bool:
	if not heroes.has(hero_id): return false
	var hero = heroes[hero_id]
	var max_level = 50 + hero.breakthrough_count * 50
	if hero.level < max_level:
		return false  # 还没到突破节点
	
	var cost = hero.breakthrough_count * 10
	if not items.has("fengyasong") or items.fengyasong < cost:
		return false
	
	items.fengyasong -= cost
	hero.breakthrough_count += 1
	return true

#门客资质技能升级
func upgrade_hero_aptitude_skill(hero_id: String, skill_index: int) -> bool:
	if not heroes.has(hero_id): return false
	var skills = heroes[hero_id].aptitude_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	var skill = skills[skill_index]
	if skill.level >= skill.max_level: return false
	skill.level += 1
	return true

#门客店铺技能升级
func upgrade_hero_shop_skill(hero_id: String, skill_index: int, mode: String = "single") -> bool:
	if not heroes.has(hero_id): return false
	var skills = heroes[hero_id].shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	var skill = skills[skill_index]
	if skill.level >= skill.max_level: return false
	
	var abacus_count = items.get("abacus", 0)
	if abacus_count <= 0: return false
	
	if mode == "single":
		var cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		if abacus_count < cost: return false
		items.abacus -= cost
		skill.level += 1
		return true
	else:
		# 一键升满：能升多少升多少
		var remaining = skill.max_level - skill.level
		var upgraded = 0
		while upgraded < remaining:
			var cost = max(1, int(ceil(pow(1.05, skill.level + upgraded - 1))))
			if items.abacus < cost: break
			items.abacus -= cost
			upgraded += 1
		if upgraded > 0:
			skill.level += upgraded
			return true
		return false

# 门客晋升升级（通用，不绑定任何具体门客）
func upgrade_promotion(hero_id: String, batch: bool = false) -> int:
	if not heroes.has(hero_id): return 0
	var hero = heroes[hero_id]
	if not hero.has("promotion"): return 0
	var promo = hero.promotion
	if promo.level >= promo.max_level: return 0
	
	var cost = promo.cost_amount
	var max_item = items.get(promo.cost_item, 0)
	
	var max_times = 1
	if batch:
		max_times = min(promo.max_level - promo.level, int(max_item / cost))
	else:
		if max_item < cost: return 0
	
	if max_times <= 0: return 0
	
	var upgraded = 0
	for i in range(max_times):
		if promo.level >= promo.max_level: break
		if items.get(promo.cost_item, 0) < cost: break
		items[promo.cost_item] -= cost
		promo.level += 1
		upgraded += 1
		_check_promotion(hero)
	
	return upgraded

func _check_promotion(hero: Dictionary):
	if not hero.has("promotion"): return
	var promo = hero.promotion
	var lv = promo.level
	
	for tier in promo.tiers:
		if lv >= tier.threshold:
			if tier.has("quality"):
				hero.quality = tier.quality
			if tier.has("initial_aptitude"):
				hero.initial_aptitude = tier.initial_aptitude
			if tier.has("new_skills"):
				for new_skill in tier.new_skills:
					var has_it = false
					for sk in hero.aptitude_skills:
						if sk.name == new_skill.name:
							has_it = true
							break
					if not has_it:
						hero.aptitude_skills.append({
							"name": new_skill.name,
							"level": 0,
							"max_level": 200,
							"aptitude_per_level": new_skill.aptitude_per_level
						})


# ========== 存档 ==========
func save_game():
	@warning_ignore("narrowing_conversion")
	last_logout_time = Time.get_unix_time_from_system()
	var save_data = {
		"money": money,
		"items": items,
		"hq": hq,
		"shops": shops,
		"last_login_time": last_login_time,
		"last_logout_time": last_logout_time,
		"heroes": heroes,
		"energy": energy,
		"friends": friends,
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()

func load_game():
	
	if not FileAccess.file_exists(SAVE_PATH): return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close(); return
	var data = json.get_data()
	file.close()	

	if data.has("money"): money = data.money
	if data.has("items"): 
		items = data.items
		for item_id in ITEM_CONFIG.keys():
			if not items.has(item_id):
				items[item_id] = 0
	if data.has("hq"): hq = data.hq
	if data.has("shops"): shops = data.shops
	if data.has("last_login_time"): last_login_time = data.last_login_time
	if data.has("last_logout_time"): last_logout_time = data.last_logout_time
	if data.has("heroes"):
		# 只覆盖存档里有的门客（保留老进度）
		# 存档里没有的新门客，自动保持上面的初始值
		for hero_id in data.heroes.keys():
			if heroes.has(hero_id):
				heroes[hero_id] = data.heroes[hero_id]
	if data.has("energy"): energy = data.energy
	if data.has("friends"): friends = data.friends

#计算离线收益
func calculate_offline_income() -> int:
	
	if last_logout_time <= 0 and last_login_time <= 0: return 0
	var now = Time.get_unix_time_from_system()
	var offline_seconds: int = 0
	
	if last_logout_time > last_login_time:
		# 上次正常退出过：用"上次退出 → 现在"这段时间
		@warning_ignore("narrowing_conversion")
		offline_seconds = now - last_logout_time
		print("正常离线，时长：", offline_seconds, "秒")
	elif last_login_time > 0:
		# 闪退或强退：last_logout_time 没被更新，用"上次登录 → 现在"
		@warning_ignore("narrowing_conversion")
		offline_seconds = now - last_login_time
		print("检测到闪退，按上次在线时间计算，时长：", offline_seconds, "秒")
	
	# 限制最多24小时，防止数据爆炸
	offline_seconds = clamp(offline_seconds, 0, 86400)
	return int(get_total_auto_income() * offline_seconds * OFFLINE_RATE)
