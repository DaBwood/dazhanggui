class_name HeroData
extends RefCounted


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
