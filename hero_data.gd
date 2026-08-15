class_name HeroData
extends RefCounted

# ========== 默认门客定义 ==========
static func get_default_heroes() -> Dictionary:
	return {
		"ge_langzhong": {
		"name": "葛郎中","category": "士","level": 1,"base_income": 0,
		"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zheng_guonong": {
		"name": "郑果农","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"liang_waiqi": {
		"name": "梁歪七","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zhu_huolang": {
		"name": "祝货郎","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"kang_chashi": {
		"name": "康茶师","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"cai_yufu": {
		"name": "蔡渔夫","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"liu_xizi": {
		"name": "刘戏子","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zheng_chuzi": {
		"name": "郑厨子","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"he_yashi": {
		"name": "何雅士","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"liu_bukuai": {
		"name": "柳捕快","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"luo_sunshan": {
		"name": "洛孙山","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"li_gushi": {
		"name": "黎蛊师","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"wu_shiren": {
		"name": "武石仁","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"wan_jinya": {
		"name": "万金牙","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"niu_fushi": {
		"name": "牛符师","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"tang_hulu": {
		"name": "唐葫芦","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zhu_daliang": {
		"name": "朱大亮","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"jia_houzi": {
		"name": "贾猴子","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"hu_qigai": {
		"name": "胡乞丐","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zhang_laobo": {
		"name": "张老伯","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "普通资质", "level": 1, "max_level": 200, "aptitude_per_level": 1}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zhao_liehu": {
		"name": "赵猎户","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"jia_jiguan": {
		"name": "贾机关","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"liu_silang": {
		"name": "刘四郎","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"yun_youren": {
		"name": "云游人","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"zhuang_gengfu": {
		"name": "庄更夫","category": "农","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"qin_jianxian": {
		"name": "秦剑仙","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"li_jianchi": {
		"name": "李剑痴","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"cao_tiejiang": {
		"name": "曹铁匠","category": "工","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"xing_huwei": {
		"name": "邢护卫","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"yan_xiaoer": {
		"name": "严小二","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"qian_caizhu": {
		"name": "钱财主","category": "商","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"wu_biaoshi": {
		"name": "武镖师","category": "侠","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"yao_wuzuo": {
		"name": "姚仵作","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"pi_yingjiang": {
		"name": "皮影匠人","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"tian_shiren": {
		"name": "田诗人","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"shen_suanzi": {
		"name": "神算子","category": "士","level": 1,
		"base_income": 0,"breakthrough_count": 1,"initial_aptitude": 66,"assigned_shop": "",
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	},
	"li_bai": {
		"name": "李白","category": "士","level": 1,"base_income": 0,
		"breakthrough_count": 1,"initial_aptitude": 66,"quality": 0,
		"fu_shi_level": 0,"assigned_shop": "",
		"promotion": {
			"name": "赋诗",
			"level": 0,
			"max_level": 300,
			"cost_item": "zui_xian_niang",
			"cost_amount": 600,
			"aptitude_per_level": 6,
			"tiers": [
				{"threshold": 5, "quality": 1, "initial_aptitude": 99, "new_skills": [{"name": "月下独酌", "aptitude_per_level": 3}]},
				{"threshold": 15, "new_skills": [{"name": "侠客行", "aptitude_per_level": 3}]},
				{"threshold": 30, "new_skills": [{"name": "长风破浪", "aptitude_per_level": 3}]},
				{"threshold": 45, "new_skills": [{"name": "扶摇直上", "aptitude_per_level": 3}]},
				{"threshold": 60, "new_skills": [{"name": "天仙狂醉", "aptitude_per_level": 4}]},
				{"threshold": 80, "quality": 2, "initial_aptitude": 333, "new_skills": []},
		]},
		"aptitude_skills": [
			{"name": "非凡资质", "level": 1, "max_level": 200, "aptitude_per_level": 2}],
		"shop_skills": [
			{"name": "门客委任", "level": 1, "max_level": 200, "base_percent": 0.05, "percent_per_level": 0.03}]
	}
	
}  


#门客总资质
static func get_total_aptitude(hero: Dictionary) -> int:
	var total = hero.get("initial_aptitude", 66)
	for skill in hero.aptitude_skills:
		total += skill.level * skill.aptitude_per_level
	if hero.has("promotion"):
		total += hero.promotion.level * hero.promotion.aptitude_per_level
	return total

#门客品质
static func get_quality_name(quality: int) -> String:
	var names = {0: "", 1: "传奇", 2: "无双"}
	return names.get(quality, "")

# 门客基础赚速 = 资质 × 等级 × 突破次数²
static func get_base_income(hero: Dictionary) -> int:
	var aptitude = get_total_aptitude(hero)
	return int(aptitude * hero.level * pow(hero.breakthrough_count, 2))

# 门客总赚速 = 基础 × (1 + 百分比加成) + 额外赚速
static func get_income(hero: Dictionary, percent_bonus: float = 0.0, extra_income: int = 0) -> int:
	var base = get_base_income(hero)
	return int(base * (1.0 + percent_bonus) + extra_income)

# 门客对全局的赚速贡献 = 总赚速 × 突破次数 × 0.5
static func get_global_contribution(hero: Dictionary, percent_bonus: float = 0.0, extra_income: int = 0) -> int:
	var total = get_income(hero, percent_bonus, extra_income)
	return int(total * hero.breakthrough_count * 0.5)

#门客店铺加成
static func get_shop_bonus(hero: Dictionary) -> float:
	if hero.assigned_shop == "": return 0.0
	var total = 0.0
	for skill in hero.shop_skills:
		total += skill.base_percent + (skill.level - 1) * skill.percent_per_level
	return total
