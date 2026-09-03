class_name HeroData
extends RefCounted

# ============================================================
# 门客领域库：资质/赚速的所有计算唯一入口，要改公式只改这里
# 聚合方法第一个参数 g = GameData 中枢（挚友/珍兽数据在中枢上；
# g 不标类型以避免循环引用）
# ============================================================

# ============ 资质 ============

# 门客总资质 = 初始资质 + 资质技能 + 晋升 + 珍兽资质 + 宅院门客卷二
# 【改】签名带 g，珍兽资质并入（原只算门客自身）；以后新资质来源加在这里
static func get_total_aptitude(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	var total = hero.get("initial_aptitude", 66)
	for skill in hero.aptitude_skills:
		total += skill.level * skill.aptitude_per_level
	if hero.has("promotion"):
		total += hero.promotion.level * hero.promotion.aptitude_per_level
	
	# 珍兽资质加成（装备珍兽的资质计入总资质）
	var beast_id = hero.get("equipped_beast", "")
	if beast_id != "":
		total += g.get_beast_aptitude(beast_id, hero.get("equipped_beast_index", 0))
	# 【新增】宅院门客卷二资质加成（按固定门客分组反查对应卷轴等级）
	total += g.get_courtyard_hero_aptitude_bonus(hero_id)
	# 【第8批新增】渔获技能资质
	total += g.get_hero_fish_aptitude(hero_id)
	# 【服装系统】服装技能资质 + 同category门客光环资质
	total += g.get_hero_costume_aptitude(hero_id)   
	# 【新增】兽魂词条资质（装备珍兽魂盘的激发格词条之和）
	total += g.get_hero_soul_aptitude(hero_id)
	# 【新增】魂力资质（装备珍兽魂体：等级+魂骨+技能+共鸣）
	total += g.get_hero_hunli_aptitude(hero_id)
	# 【新增】促织装备资质加成（无双6/级，极无双7/级）
	total += g.cuzhi_system.get_equip_aptitude_bonus(hero_id)
	
	return total

# 门客品质名
static func get_quality_name(quality: int) -> String:
	var names = {0: "", 1: "传奇", 2: "无双"}
	return names.get(quality, "")

# ============ 赚速（唯一入口，外部一律调这里） ============

# 门客基础赚速 = 总资质 × 等级 × 突破次数
# 【改】公式由 突破次数² 改为 突破次数
static func get_base_income(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	return int(get_total_aptitude(g, hero_id) * hero.level * hero.breakthrough_count)

# 门客的额外赚速总和 = 额外赚速池 + 挚友固定加成 + 宅院门客卷一
# 额外赚速池（hero.extra_income）：人参/五道道具/今日新菜等固定数值加成的累计
# 【新增】从 hero_system.get_hero_extra_income 搬入
static func get_extra_income(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	var extra = hero.get("extra_income", 0)
	for fid in g.friends.keys():
		if hero_id in g.friends[fid].bound_heroes:
			extra += g.get_friend_fixed_bonus(fid)
	# 【新增】宅院门客卷一固定赚速加成（每级+5000，按固定门客分组生效）
	extra += g.get_courtyard_hero_income_bonus(hero_id)
	# 【第8批新增】渔获固定赚速（传奇/普通）
	extra += g.get_hero_fish_flat_income(hero_id)
	# 【新增】魂力固定赚速（装备珍兽魂骨的赚钱技能）
	extra += g.get_hero_hunli_income(hero_id)
	
	# 【促织培育】部位固定赚速（按职业汇总极无双促织）
	extra += g.cuzhi_system.get_career_peiyu_flat_income(hero.get("category", ""))
	# 【虫师】虫书固定赚速加成（star 1~4 累加）
	extra += g.cuzhi_system.get_hero_worm_flat_bonus(hero_id)
	
	return extra

# 门客的百分比加成总和（挚友 + 珍兽；TODO: 藏宝加成）
# 【新增】从 hero_system.get_hero_percent_bonus 搬入
static func get_percent_bonus(g, hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	var hero = g.heroes[hero_id]
	var bonus = 0.0
	for fid in g.friends.keys():
		if hero_id in g.friends[fid].bound_heroes:
			bonus += g.get_friend_percent_bonus(fid)
	var beast = g.get_hero_beast_bonus(hero_id)
	bonus += beast.percent
	# 【第8批新增】无双渔获 阶×5%
	bonus += g.get_hero_fish_percent(hero_id)
	# 【服装系统】系列服装光环（群体+3%×关联系列件数 / 自身+3%×件数）
	bonus += g.get_hero_costume_series_pct(hero_id)  
	# 【新增】兽魂赚速%（装备珍兽魂盘的激发格，按魂盘等级3/5/10/15/20%每格）
	bonus += g.get_hero_soul_percent(hero_id)
	# 【新增】魂力赚钱%（装备珍兽的百万年魂骨 阶×10%）
	bonus += g.get_hero_hunli_percent(hero_id)
	#促织庙百分比加成
	bonus += g.cuzhi_system.get_temple_bonus(hero_id)
	# 【促织培育】阶段百分比加成（按职业汇总极无双促织）
	bonus += g.cuzhi_system.get_career_peiyu_percent(hero.get("category", "")) 
	# 【虫师】虫书百分比赚速加成（star 5~6 累加）
	bonus += g.cuzhi_system.get_hero_worm_percent_bonus(hero_id)
	
	return bonus

# 门客总赚速 = 基础赚速 × (1 + 百分比加成) + 额外赚速
static func get_income(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	return int(get_base_income(g, hero_id) * (1.0 + get_percent_bonus(g, hero_id)) + get_extra_income(g, hero_id))

# 门客对全局的赚速贡献 = 总赚速 × 突破次数 × 0.5
# （原 hero_system 的 income==0 短路不再保留：0×突破×0.5 恒为0，行为等价）
static func get_global_contribution(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	return int(get_income(g, hero_id) * g.heroes[hero_id].breakthrough_count * 0.5)

# 全门客总赚速（战力）= 所有门客总赚速之和
# 【新增】从 hero_system.get_heroes_total_income 搬入
static func get_total_income(g) -> int:
	var total = 0
	for hero_id in g.heroes.keys():
		total += get_income(g, hero_id)
	return total

# ============ 店铺 ============

# 门客店铺加成（只读门客字典，shop_system 在用）
static func get_shop_bonus(hero: Dictionary) -> float:
	if hero.assigned_shop == "": return 0.0
	var total = 0.0
	for skill in hero.shop_skills:
		total += skill.base_percent + (skill.level - 1) * skill.percent_per_level
	return total
