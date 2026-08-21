class_name GameData
extends RefCounted

func _init():
	_load_all_configs()

#保存路径
const SAVE_PATH = "user://save.json"
const OFFLINE_RATE = 0.8

const BEAST_CONFIG_PATH = "res://data/beasts.json"

# ========== VIP 等级经验表（累计经验，单位：10经验=1元）==========
const VIP_EXP_TABLE = [
	0,          # VIP0  → 0元
	300,        # VIP1  → 30元
	1000,       # VIP2  → 100元
	3000,       # VIP3  → 300元
	10000,      # VIP4  → 1000元
	30000,      # VIP5  → 3000元
	100000,     # VIP6  → 1万元
	300000,     # VIP7  → 3万元
	1000000,    # VIP8  → 10万元
	2000000,    # VIP9  → 20万元
	4000000,    # VIP10 → 40万元
	6000000,    # VIP11 → 60万元
	8000000,    # VIP12 → 80万元
	10000000,   # VIP13 → 100万元
	20000000,   # VIP14 → 200万元
	50000000,   # VIP15 → 500万元
	100000000,  # VIP16 → 1000万元
]

const SHOP_ORDER = ["ke_zhan", "yi_guan", "shuoshu_tan", "xiangliao_pu", "dang_pu", "yao_pu", "jiu_si", "yi_zhan", "miaoyin_fang", "jiu_fang", "changle_fang", "chengyi_pu", "suanming_tan", "chuan_wu", "chema_hang", "cha_si", "xi_lou", "zao_tang", "biao_ju", "yao_chang"]

const SHOP_UNLOCK_TABLE = {
	"ke_zhan": 1,
	"yi_guan": 5,
	"shuoshu_tan": 15,
	"xiangliao_pu": 40,
	"dang_pu": 80,
	"yao_pu": 130,
	"jiu_si": 200,
	"yi_zhan": 300,
	"miaoyin_fang": 450,
	"jiu_fang": 650,
	"changle_fang": 950,
	"chengyi_pu": 1400,
	"suanming_tan": 2100,
	"chuan_wu": 3200,
	"chema_hang": 4800,
	"cha_si": 7000,
	"xi_lou": 10000,
	"zao_tang": 13000,
	"biao_ju": 16500,
	"yao_chang": 20000,
}

# ========== 抽奖系统 ==========
const LOTTERY_POOL = [
	{"item": "hero_token", "count": 1, "weight": 0.0012},
	{"item": "friend_token", "count": 1, "weight": 0.0012},
	{"item": "zou_yu", "count": 1, "weight": 0.0012, "is_beast": true},
	{"item": "ginseng_1000", "count": 1, "weight": 0.05},
	{"item": "hq_blueprint", "count": 1, "weight": 0.05},
	{"item": "fengyasong", "count": 5, "weight": 0.05},
	{"item": "energy_pill", "count": 10, "weight": 0.05},
	{"item": "shop_blueprint", "count": 2, "weight": 0.1},
	{"item": "hour_card", "count": 10, "weight": 0.1},
	{"item": "ginseng", "count": 1, "weight": 0.1},
	{"item": "abacus", "count": 3, "weight": 0.1},
	{"item": "aroma_fruit", "count": 10, "weight": 0.1},
	{"item": "vitality_pill", "count": 10, "weight": 0.1},
	{"item": "aptitude_pill", "count": 2, "weight": 0.05},
	{"item": "wood_comb", "count": 100, "weight": 0.05},
	{"item": "rouge", "count": 100, "weight": 0.05},
	{"item": "exp_box", "count": 10, "weight": 0.0458},
	{"item": "feng_shen_zhi", "count": 1, "weight": 0.00015},
	{"item": "shan_hai_shi", "count": 1, "weight": 0.0001},
	{"item": "hong_huang_huo", "count": 1, "weight": 0.0001},
	{"item": "jiu_yuan_shui", "count": 1, "weight": 0.0001},
	{"item": "long_zhuo_xi", "count": 1, "weight": 0.00005},
	{"item": "xing_wu_po", "count": 1, "weight": 0.00005},
	{"item": "xing_shu_lin", "count": 1, "weight": 0.00005},
]
const LOTTERY_GUARANTEE = 500
const LOTTERY_TICKET_YUANBAO_RATE = 50

var lottery_draw_count: int = 0

# ========== 身份等级奖励表 ==========
const IDENTITY_REWARD_TABLE = {
	2: {"type": "hero", "id": "zheng_guonong", "name": "郑果农"},
	3: {"type": "hero", "id": "zhu_huolang", "name": "祝货郎"},
	4: {"type": "hero", "id": "kang_chashi", "name": "康茶师"},
	5: {"type": "hero", "id": "liang_waiqi", "name": "梁歪七"},
	6: {"type": "hero", "id": "ge_langzhong", "name": "葛郎中"},
	7: {"type": "hero", "id": "liu_bukuai", "name": "柳捕快"},
	8: {"type": "hero", "id": "hu_qigai", "name": "胡乞丐"},
	9: {"type": "hero", "id": "wu_shiren", "name": "武石仁"},
	10: {"type": "hero", "id": "zhu_daliang", "name": "朱大亮"},
	11: {"type": "hero", "id": "yan_xiaoer", "name": "严小二"},
	12: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	13: {"type": "hero", "id": "zheng_chuzi", "name": "郑厨子"},
	14: {"type": "hero", "id": "he_yashi", "name": "何雅士"},
	15: {"type": "hero", "id": "zhang_laobo", "name": "张老伯"},
	16: {"type": "hero", "id": "li_gushi", "name": "黎蛊师"},
	17: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	18: {"type": "hero", "id": "liu_silang", "name": "刘四郎"},
	19: {"type": "hero", "id": "jia_houzi", "name": "贾猴子"},
	20: {"type": "hero", "id": "wan_jinya", "name": "万金牙"},
	21: {"type": "hero", "id": "qin_jianxian", "name": "秦剑仙"},
	22: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	23: {"type": "hero", "id": "luo_sunshan", "name": "洛孙山"},
	24: {"type": "hero", "id": "zhuang_gengfu", "name": "庄更夫"},
	25: {"type": "hero", "id": "liu_xizi", "name": "刘戏子"},
	26: {"type": "hero", "id": "xing_huwei", "name": "邢护卫"},
	27: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	28: {"type": "hero", "id": "cai_yufu", "name": "蔡渔夫"},
	29: {"type": "hero", "id": "yao_wuzuo", "name": "姚仵作"},
	30: {"type": "hero", "id": "tang_hulu", "name": "唐葫芦"},
	31: {"type": "hero", "id": "yun_youren", "name": "云游人"},
	32: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	33: {"type": "hero", "id": "tian_shiren", "name": "田诗人"},
	34: {"type": "hero", "id": "niu_fushi", "name": "牛符师"},
	35: {"type": "hero", "id": "jia_jiguan", "name": "贾机关"},
	36: {"type": "hero", "id": "li_jianchi", "name": "李剑痴"},
}

var identity_rewards_claimed: Dictionary = {}

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
	"stage_box": {"name": "关卡宝箱", "desc": "通关小关获得的宝箱"},
	"hour_card":       {"name": "小时卡",   "desc": "使用后获得当前总赚速一小时的铜钱"},
	"beast_fruit":     {"name": "珍兽果",   "desc": "升级珍兽等级"},
	"aroma_fruit":     {"name": "奇香果",   "desc": "刷新珍兽技能"},
	"feng_shen_zhi":   {"name": "封神志",   "desc": "兑换封神灵兽"},
	"shan_hai_shi":    {"name": "山海石",   "desc": "兑换山海异兽"},
	"hong_huang_huo":  {"name": "鸿荒火",   "desc": "兑换上古凶兽"},
	"jiu_yuan_shui":   {"name": "九渊之水", "desc": "兑换蛮荒主兽"},
	"long_zhuo_xi":    {"name": "龙擢星玺", "desc": "兑换星神圣兽"},
	"xing_wu_po":      {"name": "星武珀石", "desc": "兑换星神圣兽"},
	"xing_shu_lin":    {"name": "星枢麟角", "desc": "兑换星神圣兽"},
	"lottery_ticket": {"name": "抽奖券", "desc": "用于闯荡页面的抽奖"},
	"hero_token":      {"name": "门客帖",   "desc": "用于兑换门客"},
	"friend_token":    {"name": "挚友帖",   "desc": "用于兑换挚友"},
	"ginseng_1000":    {"name": "千年人参", "desc": "指定门客基础赚速+20000"},
	"vitality_pill":   {"name": "活力丹",   "desc": "后续玩法更新后使用"},
	"wish_stone":      {"name": "许愿石",   "desc": "用于刷新挚友店铺技能，必定获得20%-30%加成"},
}

# 已领取的VIP奖励等级（true=已领取）
var vip_claimed_rewards: Dictionary = {}

# ========== 关卡系统 ==========
var stage_main: int = 1
var stage_sub: int = 1
var stage_trade_count: int = 0
var reputation: int = 0
var lottery_ticket: int = 0

# 门客字典（仅包含已拥有的）
var heroes: Dictionary = {}
var friends: Dictionary = {}
var shops: Dictionary = {}


# ========== 配置表（运行时只读） ==========
var _hero_configs: Dictionary = {}
var _friend_configs: Dictionary = {}
var _vip_rewards: Dictionary = {}
var _shop_configs: Dictionary = {}
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("配置缺失: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON解析失败: " + path)
		return {}
	return json.get_data()



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
	"wood_comb":200000,
	"rouge": 999,
	"energy_pill":999,
	"zui_xian_niang": 48600,
	"hour_card": 0,
	"beast_fruit": 0,
	"aroma_fruit": 0,
	"feng_shen_zhi": 0,
	"shan_hai_shi": 0,
	"hong_huang_huo": 0,
	"jiu_yuan_shui": 0,
	"long_zhuo_xi": 0,
	"xing_wu_po": 0,
	"xing_shu_lin": 0,
	"lottery_ticket":0,
	"hero_token": 0,
	"friend_token": 0,
	"ginseng_1000": 0,
	"vitality_pill": 0,
	"wish_stone": 0,
}

const SURNAMES = ["赵","钱","孙","李","周","吴","郑","王","冯","陈","褚","卫","蒋","沈","韩","杨","朱","秦","尤","许"]
const NAME_PARTS = ["富贵","旺财","来福","德财","金宝","元宝","招财","进宝","大发","鸿运","兴隆","昌盛","鼎盛","荣华","锦绣","吉祥","如意","平安","康泰","兴旺"]

var last_login_time: int = 0      # 本次登录时间
var last_logout_time: int = 0     # 上次正常退出时间

# ========== 初始货币 ==========
var money: int = 0
var yuanbao: int = 0
var energy: int = 100
var vip_level: int = 0
var vip_exp: int = 0

# ========== 个人信息 ==========
var player_name: String = ""
var identity_level: int = 1
var last_daily_reward_time: int = 0

var _beast_configs: Dictionary = {}

var beasts: Dictionary = {}
var beast_fruit: int = 0
var aroma_fruit: int = 0

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

func _load_all_configs():
	_hero_configs = _load_json("res://data/heroes.json")
	_friend_configs = _load_json("res://data/friends.json")
	_vip_rewards = _load_json("res://data/vip_rewards.json")
	_shop_configs = _load_json("res://data/shops.json")
	_beast_configs = _load_json(BEAST_CONFIG_PATH)

# 获取门客配置（只读模板）
func get_hero_config(hero_id: String) -> Dictionary:
	return _hero_configs.get(hero_id, {}).duplicate(true)

# 获取挚友配置（只读模板）
func get_friend_config(friend_id: String) -> Dictionary:
	return _friend_configs.get(friend_id, {}).duplicate(true)

# 获取全部门客配置ID（用于UI显示未解锁）
func get_all_hero_ids() -> Array:
	return _hero_configs.keys()

# 获取全部挚友配置ID
func get_all_friend_ids() -> Array:
	return _friend_configs.keys()

# 获取VIP奖励表
func get_vip_rewards() -> Dictionary:
	return _vip_rewards

func get_shop_config(shop_id: String) -> Dictionary:
	return _shop_configs.get(shop_id, {}).duplicate(true)

func get_shop_unlock_chapter(shop_id: String) -> int:
	return SHOP_UNLOCK_TABLE.get(shop_id, 999999)

func can_unlock_shop(shop_id: String) -> bool:
	if shops.has(shop_id): return false
	return stage_main >= get_shop_unlock_chapter(shop_id)

func unlock_shop(shop_id: String) -> bool:
	if not can_unlock_shop(shop_id): return false
	if not _shop_configs.has(shop_id): return false
	shops[shop_id] = _shop_configs[shop_id].duplicate(true)
	return true


# ========== 角色解锁（所有获得途径统一走这里） ==========
func unlock_hero(hero_id: String) -> bool:
	if heroes.has(hero_id): return false
	var cfg = get_hero_config(hero_id)
	if cfg.is_empty(): return false
	heroes[hero_id] = cfg
	return true

func unlock_friend(friend_id: String) -> bool:
	if friends.has(friend_id): return false
	var cfg = get_friend_config(friend_id)
	if cfg.is_empty(): return false
	friends[friend_id] = cfg
	_init_friend_shop_skills(friend_id)
	return true




# ========== 计算函数 ==========

# 挚友店铺技能列表
func _init_friend_shop_skills(friend_id: String):
	if not friends.has(friend_id): return
	var f = friends[friend_id]
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
	if not friends.has(friend_id): return []
	var f = friends[friend_id]
	if not f.has("shop_skills"):
		_init_friend_shop_skills(friend_id)
	var max_slots = min(400, int(f.friendly / 500))
	var skills = f.shop_skills
	var result = []
	for i in range(min(max_slots, skills.size())):
		result.append(skills[i])
	return result

func refresh_friend_shop_skill(friend_id: String, skill_index: int, use_wish_stone: bool = false) -> bool:
	if not friends.has(friend_id): return false
	var f = friends[friend_id]
	if not f.has("shop_skills"): _init_friend_shop_skills(friend_id)
	var skills = f.shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	
	var max_slots = min(400, int(f.friendly / 500))
	if skill_index >= max_slots: return false
	
	var skill = skills[skill_index]
	if skill.bonus >= 0.30: return false
	
	if use_wish_stone:
		var wish_cost = 1
		if items.get("wish_stone", 0) < wish_cost:
			return false
		items.wish_stone -= wish_cost
		skill.refresh_count += 1
		var new_bonus = randf_range(0.20, 0.31)
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	else:
		var cost = 100 * int(pow(2, skill.refresh_count))
		if money < cost: return false
		money -= cost
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
	# 珍兽百分比加成
	var beast = get_hero_beast_bonus(hero_id)
	bonus += beast.percent
	# TODO: 藏宝加成
	return bonus

func get_hero_aptitude_bonus(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var bonus = 0
	# 珍兽资质加成
	var beast_id = heroes[hero_id].get("equipped_beast", "")
	if beast_id != "":
		var idx = heroes[hero_id].get("equipped_beast_index", 0)
		bonus += get_beast_aptitude(beast_id, idx)
	return bonus

# 门客总赚速（供 UI 显示）
func get_hero_income(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var h = heroes[hero_id]
	var total_apt = HeroData.get_total_aptitude(h) + get_hero_aptitude_bonus(hero_id)
	var base = int(total_apt * h.level * pow(h.breakthrough_count, 2))
	var percent = get_hero_percent_bonus(hero_id)
	var extra = get_hero_extra_income(hero_id)
	return int(base * (1.0 + percent) + extra)

# 门客对全局的贡献（供自动收入）
func get_hero_contribution(hero_id: String) -> int:
	var income = get_hero_income(hero_id)
	if income == 0: return 0
	var h = heroes[hero_id]
	return int(income * h.breakthrough_count * 0.5)

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

func get_identity_reward(level: int) -> Dictionary:
	if IDENTITY_REWARD_TABLE.has(level):
		return IDENTITY_REWARD_TABLE[level]
	if level >= 37 and level <= 100:
		return {"type": "beast", "id": "zou_yu", "name": "驺虞"}
	return {}

func claim_identity_reward(level: int) -> Dictionary:
	var reward = get_identity_reward(level)
	if reward.is_empty():
		return {"ok": false, "reason": "该等级无奖励"}
	if identity_rewards_claimed.get(str(level), false):
		return {"ok": false, "reason": "已领取"}
	if identity_level < level:
		return {"ok": false, "reason": "身份等级不足"}
	
	var result = {"ok": true, "reward": reward, "duplicate": false}
	
	if reward.type == "hero":
		if heroes.has(reward.id):
			result.ok = false
			result.reason = "门客重复"
			result.duplicate = true
		else:
			unlock_hero(reward.id)
	elif reward.type == "beast":
		add_beast(reward.id)
	
	if result.ok:
		identity_rewards_claimed[str(level)] = true
	
	return result



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

# ========== 身份晋升 ==========
func get_identity_income_req(target_level: int) -> int:
	return int(100 * pow(1.4, target_level - 1))

func get_identity_reputation_req(target_level: int) -> int:
	return int(10 * pow(1.22, target_level - 1))

func can_promote_identity() -> bool:
	if identity_level >= 100: return false
	var next = identity_level + 1
	return get_total_auto_income() >= get_identity_income_req(next) and reputation >= get_identity_reputation_req(next)

func promote_identity() -> bool:
	if not can_promote_identity(): return false
	identity_level += 1
	return true

func rename_player(new_name: String) -> bool:
	var trimmed = new_name.strip_edges()
	if trimmed == "": return false
	player_name = trimmed
	return true

# ========== 每日宝箱 ==========
func can_claim_daily_reward() -> bool:
	if last_daily_reward_time <= 0: return true
	var now = Time.get_unix_time_from_system()
	var now_dict = Time.get_date_dict_from_system(now)
	var last_dict = Time.get_date_dict_from_system(last_daily_reward_time)
	return now_dict.year != last_dict.year or now_dict.month != last_dict.month or now_dict.day != last_dict.day

func claim_daily_reward() -> int:
	if not can_claim_daily_reward(): return 0
	var reward = identity_level * 10000
	yuanbao += reward
	@warning_ignore("narrowing_conversion")
	last_daily_reward_time = Time.get_unix_time_from_system()
	return reward

func use_hour_card(count: int) -> int:
	if items.get("hour_card", 0) < count:
		return 0
	items.hour_card -= count
	var gain = get_total_auto_income() * 3600 * count
	money += gain
	return gain

func get_beast_config(beast_id: String) -> Dictionary:
	return _beast_configs.get(beast_id, {}).duplicate(true)

func get_all_beast_ids() -> Array:
	return _beast_configs.keys()

func get_beast_instance(beast_id: String, index: int = 0):
	if not beasts.has(beast_id): return null
	var d = beasts[beast_id]
	if d is Array:
		if index >= 0 and index < d.size(): return d[index]
		return null
	return d

func get_beast_instance_count(beast_id: String) -> int:
	if not beasts.has(beast_id): return 0
	var d = beasts[beast_id]
	if d is Array: return d.size()
	return 1

func get_beast_aptitude(beast_id: String, instance_index: int = 0) -> int:
	var cfg = get_beast_config(beast_id)
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return 0
	var base = cfg.get("aptitude", 0)
	var lv = instance.get("level", 1)
	return base + (lv - 1) * 8

func get_beast_skill_bonus(beast_id: String, instance_index: int = 0) -> float:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return 0.0
	var skills = instance.get("skills", [])
	var total = 0.0
	for sk in skills:
		total += sk.get("percent", 0.0)
	return total

func get_beast_aura_bonus(beast_id: String, _instance_index: int = 0) -> float:
	var cfg = get_beast_config(beast_id)
	var auras = cfg.get("auras", [])
	if auras.is_empty(): return 0.0
	var special_count = _get_special_beast_count()
	var bonus = 0.10 + (special_count - 1) * 0.10
	bonus += 0.05
	return bonus

func _get_special_beast_count() -> int:
	var count = 0
	for bid in beasts.keys():
		if get_beast_config(bid).get("max_count", 1) == 1:
			count += 1
	return count

func get_hero_beast_bonus(hero_id: String) -> Dictionary:
	if not heroes.has(hero_id): return {"aptitude": 0, "percent": 0.0}
	var h = heroes[hero_id]
	var beast_id = h.get("equipped_beast", "")
	if beast_id == "": return {"aptitude": 0, "percent": 0.0}
	var idx = h.get("equipped_beast_index", 0)
	return {
		"aptitude": get_beast_aptitude(beast_id, idx),
		"percent": get_beast_skill_bonus(beast_id, idx) + get_beast_aura_bonus(beast_id, idx)
	}

func _init_beast_skills(count: int) -> Array:
	var skills = []
	for i in range(count):
		skills.append({"percent": 0.01})
	return skills

func add_beast(beast_id: String) -> bool:
	var cfg = get_beast_config(beast_id)
	if cfg.is_empty(): return false
	var max_count = cfg.get("max_count", 1)
	var init_data = {"level": 1, "equipped_hero": "", "skills": _init_beast_skills(cfg.get("skill_count", 0))}
	if max_count == 1:
		if beasts.has(beast_id): return false
		beasts[beast_id] = init_data
	else:
		if not beasts.has(beast_id): beasts[beast_id] = []
		beasts[beast_id].append(init_data)
	return true

func upgrade_beast(beast_id: String, instance_index: int = 0) -> bool:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return false
	if instance.level >= 200: return false
	if beast_fruit < 80: return false
	beast_fruit -= 80
	instance.level += 1
	return true

func refresh_beast_skills(beast_id: String, instance_index: int = 0) -> bool:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return false
	if aroma_fruit < 1: return false
	aroma_fruit -= 1
	var cfg = get_beast_config(beast_id)
	var count = cfg.get("skill_count", 0)
	var skills = []
	for i in range(count):
		skills.append({"percent": randf_range(0.15, 0.25)})
	instance.skills = skills
	return true

func equip_beast(hero_id: String, beast_id: String, instance_index: int) -> bool:
	if not heroes.has(hero_id): return false
	if not beasts.has(beast_id): return false
	
	# 【新增】先卸下当前门客的旧珍兽，并清空 beasts 中的标记
	var old_beast_id = heroes[hero_id].get("equipped_beast", "")
	var old_idx = heroes[hero_id].get("equipped_beast_index", 0)
	if old_beast_id != "":
		var old_inst = get_beast_instance(old_beast_id, old_idx)
		if old_inst != null:
			old_inst.equipped_hero = ""
	
	# 把新珍兽从其他门客身上卸下
	for hid in heroes.keys():
		if heroes[hid].get("equipped_beast", "") == beast_id and heroes[hid].get("equipped_beast_index", 0) == instance_index:
			heroes[hid].equipped_beast = ""
			heroes[hid].equipped_beast_index = 0
	
	# 【新增】设置 beasts 中新实例的 equipped_hero
	var new_inst = get_beast_instance(beast_id, instance_index)
	if new_inst != null:
		new_inst.equipped_hero = hero_id
	
	heroes[hero_id].equipped_beast = beast_id
	heroes[hero_id].equipped_beast_index = instance_index
	return true

func unequip_beast(hero_id: String) -> bool:
	if not heroes.has(hero_id): return false
	# 【新增】同步清空 beasts 中旧实例的 equipped_hero
	var old_beast_id = heroes[hero_id].get("equipped_beast", "")
	var old_idx = heroes[hero_id].get("equipped_beast_index", 0)
	if old_beast_id != "":
		var old_inst = get_beast_instance(old_beast_id, old_idx)
		if old_inst != null:
			old_inst.equipped_hero = ""
	heroes[hero_id].equipped_beast = ""
	heroes[hero_id].equipped_beast_index = 0
	return true

func buy_test_beast_pack() -> bool:
	if yuanbao < 19888: return false
	yuanbao -= 19888
	add_beast("zou_yu")
	beast_fruit += 988
	aroma_fruit += 988
	return true

# 门客总赚钱（战力）= 所有门客 get_hero_income 之和
func get_heroes_total_income() -> int:
	var total = 0
	for hero_id in heroes.keys():
		total += get_hero_income(hero_id)
	return total

# ========== 关卡公式 ==========
func get_stage_trade_cost(main: int = stage_main, sub: int = stage_sub) -> int:
	return int(500 * pow(main, 3.2) * (1.0 + (sub - 1) * 0.2))

func get_stage_boss_income(main: int = stage_main) -> int:
	return int(50 * pow(main, 2.3))

func is_stage_boss_ready() -> bool:
	return stage_sub == 5 and stage_trade_count >= 3

# ========== 关卡操作 ==========
func do_stage_trade() -> Dictionary:
	var cost = get_stage_trade_cost()
	var boss_income = get_stage_boss_income()
	var hero_power = get_heroes_total_income()
	var discount = clamp(float(boss_income) / float(max(hero_power, 1)), 0.1, 1.0)
	var actual_cost = int(cost * discount)
	
	if money < actual_cost:
		return {"ok": false, "reason": "铜钱不足", "need": actual_cost, "have": money}
	
	money -= actual_cost
	reputation += 1
	stage_trade_count += 1
	
	# 每次贸易获得阅历（随章节递增，但不高）
	var exp_reward = 10 * stage_main
	items.experience += exp_reward
	
	# 达到3次，推进
	if stage_trade_count >= 3:
		items["stage_box"] = items.get("stage_box", 0) + 1
		
		if stage_sub < 5:
			stage_trade_count = 0      # 【改】只有进下小关才重置
			stage_sub += 1
			return {"ok": true, "type": "next_sub", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}
		else:
			# 【改】Boss已出现，保持trade_count>=3，让is_stage_boss_ready能检测到
			return {"ok": true, "type": "boss_ready", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}
	
	return {"ok": true, "type": "trade", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}

func do_stage_boss() -> Dictionary:
	var boss_income = get_stage_boss_income()
	var hero_power = get_heroes_total_income()
	
	if hero_power > boss_income:
		reputation += 10
		lottery_ticket += 1
		stage_main += 1
		stage_sub = 1
		stage_trade_count = 0
		return {"ok": true, "win": true, "boss_income": boss_income, "hero_power": hero_power}
	else:
		return {"ok": true, "win": false, "boss_income": boss_income, "hero_power": hero_power}

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


# 充值（自娱自乐版，直接成功）
func do_recharge(amount: int) -> bool:
	if amount <= 0: return false
	yuanbao += amount * 10
	vip_exp += amount * 10
	vip_level = get_vip_level()  # 根据经验重新计算等级
	return true

# ========== VIP 等级函数 ==========
func get_vip_level() -> int:
	for i in range(VIP_EXP_TABLE.size() - 1, -1, -1):
		if vip_exp >= VIP_EXP_TABLE[i]:
			return i
	return 0

func get_vip_next_level_exp() -> int:
	var current = get_vip_level()
	if current >= VIP_EXP_TABLE.size() - 1:
		return 0  # 已满级
	return VIP_EXP_TABLE[current + 1]

func get_vip_exp_progress() -> float:
	var current = get_vip_level()
	if current >= VIP_EXP_TABLE.size() - 1:
		return 1.0
	var current_exp = VIP_EXP_TABLE[current]
	var next_exp = VIP_EXP_TABLE[current + 1]
	var progress = float(vip_exp - current_exp) / float(next_exp - current_exp)
	return clamp(progress, 0.0, 1.0)

# 获取门客解锁所需VIP等级（初始门客返回0）
func get_hero_unlock_vip(hero_id: String) -> int:
	for level in _vip_rewards.keys():
		for reward in _vip_rewards[level]:
			if reward.type == "hero" and reward.id == hero_id:
				return int(level)
	return 0

# 获取挚友解锁所需VIP等级（初始挚友返回0）
func get_friend_unlock_vip(friend_id: String) -> int:
	for level in _vip_rewards.keys():
		for reward in _vip_rewards[level]:
			if reward.type == "friend" and reward.id == friend_id:
				return int(level)
	return 0

# 判断VIP奖励是否已领取
func is_vip_reward_claimed(level: int) -> bool:
	return vip_claimed_rewards.get(str(level), false)

# 手动领取VIP奖励
func claim_vip_reward(level: int) -> bool:
	if level <= 0: return false
	if get_vip_level() < level: return false
	if is_vip_reward_claimed(level): return false
	if not _vip_rewards.has(str(level)): return false   # 注意：JSON key 是字符串
	
	for reward in _vip_rewards[str(level)]:
		match reward.type:
			"hero": unlock_hero(reward.id)
			"friend": unlock_friend(reward.id)
	
	vip_claimed_rewards[str(level)] = true
	return true


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
		"vip_level": vip_level,
		"vip_exp": vip_exp,
		"yuanbao": yuanbao,
		"vip_claimed_rewards": vip_claimed_rewards,
		"stage_main": stage_main,
		"stage_sub": stage_sub,
		"stage_trade_count": stage_trade_count,
		"reputation": reputation,
		"lottery_ticket": lottery_ticket,
		"player_name": player_name,
		"identity_level": identity_level,
		"last_daily_reward_time": last_daily_reward_time,
		"beasts": beasts,
		"beast_fruit": beast_fruit,
		"aroma_fruit": aroma_fruit,
		"lottery_draw_count": lottery_draw_count,
		"identity_rewards_claimed": identity_rewards_claimed,
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
	

func load_game():
	#先加载配置再读档
	if _hero_configs.is_empty():_load_all_configs()
	
	randomize()
	if player_name == "":
		player_name = SURNAMES[randi() % SURNAMES.size()] + NAME_PARTS[randi() % NAME_PARTS.size()]
	
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
	if _shop_configs.is_empty():
		_shop_configs = _load_json("res://data/shops.json")

	if data.has("shops"):
		var saved = data.shops
		shops.clear()
		for sid in saved.keys():
			if _shop_configs.has(sid):shops[sid] = saved[sid].duplicate(true)
	else:shops.clear()
	if data.has("last_login_time"): last_login_time = data.last_login_time
	if data.has("last_logout_time"): last_logout_time = data.last_logout_time
	if data.has("heroes"):
		# 只覆盖存档里有的门客（保留老进度）
		# 存档里没有的新门客，自动保持上面的初始值
		heroes = data.heroes.duplicate(true)
	if data.has("energy"): energy = data.energy
	if data.has("friends"): friends = data.friends
	if data.has("vip_level"): vip_level = data.vip_level
	if data.has("vip_exp"): vip_exp = data.vip_exp
	if data.has("yuanbao"): yuanbao = data.yuanbao
	if data.has("vip_claimed_rewards"):
		vip_claimed_rewards = data.vip_claimed_rewards
	# 加载配置表（如果还没加载）
	if _hero_configs.is_empty():_load_all_configs()
	if data.has("stage_main"): stage_main = data.stage_main
	if data.has("stage_sub"): stage_sub = data.stage_sub
	if data.has("stage_trade_count"): stage_trade_count = data.stage_trade_count
	if data.has("reputation"): reputation = data.reputation
	if data.has("lottery_ticket"): lottery_ticket = data.lottery_ticket
	if data.has("player_name"): player_name = data.player_name
	if data.has("identity_level"): identity_level = data.identity_level
	if data.has("last_daily_reward_time"): last_daily_reward_time = data.last_daily_reward_time
	
	if data.has("beasts"): beasts = data.beasts
	if data.has("beast_fruit"): beast_fruit = data.beast_fruit
	if data.has("aroma_fruit"): aroma_fruit = data.aroma_fruit
	if data.has("lottery_draw_count"): lottery_draw_count = data.lottery_draw_count
	if data.has("identity_rewards_claimed"): identity_rewards_claimed = data.identity_rewards_claimed
	
	# 清理存档中已不存在的角色（防止配置删了存档还残留）
	for hero_id in heroes.keys():
		if not _hero_configs.has(hero_id):
			heroes.erase(hero_id)
	for friend_id in friends.keys():
		if not _friend_configs.has(friend_id):
			friends.erase(friend_id)
	# 挚友店铺技能旧存档兼容
	for friend_id in friends.keys():
		if not friends[friend_id].has("shop_skills"):
			_init_friend_shop_skills(friend_id)

func _draw_from_pool() -> Dictionary:
	var r = randf()
	var cumulative = 0.0
	for entry in LOTTERY_POOL:
		cumulative += entry.weight
		if r <= cumulative:
			return entry.duplicate(true)
	# 未命中，给铜钱安慰奖
	return {"item": "money", "count": randi_range(1000, 10000)}

func _give_lottery_reward(reward: Dictionary):
	if reward.get("is_beast", false):
		add_beast(reward.item)
	elif reward.item == "money":
		money += reward.count
	else:
		items[reward.item] = items.get(reward.item, 0) + reward.count

func do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao_for_short: bool = false) -> Dictionary:
	var ticket_cost = min(ticket_need, lottery_ticket)
	var ticket_short = ticket_need - ticket_cost
	var yuanbao_cost = ticket_short * LOTTERY_TICKET_YUANBAO_RATE
	
	if use_yuanbao_for_short:
		if yuanbao < yuanbao_cost:
			return {"ok": false, "reason": "元宝不足"}
		yuanbao -= yuanbao_cost
		lottery_ticket -= ticket_cost
	else:
		if lottery_ticket < draw_count:
			return {"ok": false, "reason": "抽奖券不足"}
		lottery_ticket -= draw_count
	
	var results = []
	for i in range(draw_count):
		lottery_draw_count += 1
		var reward = null
		if lottery_draw_count >= LOTTERY_GUARANTEE:
			reward = {"item": "hero_token", "count": 1}
			lottery_draw_count = 0
		else:
			reward = _draw_from_pool()
		_give_lottery_reward(reward)
		results.append(reward)
	
	return {"ok": true, "results": results, "ticket_cost": ticket_cost, "yuanbao_cost": yuanbao_cost}

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
