class_name HeroData
extends RefCounted

# ============================================================
# 门客领域库：资质/赚速的所有计算唯一入口，要改公式只改这里
# 聚合方法第一个参数 g = GameData 中枢（挚友/珍兽数据在中枢上；
# g 不标类型以避免循环引用）
# ============================================================

# 【新增】亲和（沉香）无兽计算开关：置真期间珍兽系贡献行全部跳过（见 get_beast_income_contribution）
static var _beastless_calc := false

# ============ 资质 ============

# 品质→初始资质表（2026-09-24 用户拍板：初始资质由品质决定，优秀33/卓越66/传奇99/无双333）
const INITIAL_APTITUDE_BY_QUALITY = {0: 33, 1: 66, 2: 99, 3: 333}

# 初始资质唯一入口：一切按当前品质取表，存档里的 initial_aptitude 字段已废弃（不再读）
static func get_initial_aptitude(quality: int) -> int:
	return INITIAL_APTITUDE_BY_QUALITY.get(clampi(quality, 0, 3), 66)

# 门客总资质 = 初始资质 + 资质技能 + 晋升 + 珍兽资质 + 宅院门客卷二
# 【改】签名带 g，珍兽资质并入（原只算门客自身）；以后新资质来源加在这里
static func get_total_aptitude(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	# 【改】2026-09-24 初始资质由品质决定（表驱动，晋升升品质自动涨），不再读存档旧值
	var total = get_initial_aptitude(int(hero.get("quality", 0)))
	# 【新增】2026-09-24 师徒光环（小八）：童叟无欺资质加成（自身与师傅各一份）
	total += g.hero_system.get_master_aura_aptitude(hero_id)
	# 【新增】2026-09-24 双人光环（小舞）：三五组合 资质加成（小舞与杨戬各一份）
	total += g.hero_system.get_pair_aura_aptitude(hero_id)
	# 【新增】2026-09-25 自带光环（小柒）：云裳羽衣资质加成（小柒与秦淮五艳各一份）
	total += g.hero_system.get_self_aura_aptitude(hero_id)
	for skill in hero.aptitude_skills:
		total += skill.level * skill.aptitude_per_level
	if hero.has("promotion"):
		total += hero.promotion.level * hero.promotion.aptitude_per_level
	# 【新增】2026-09-25 凤魁（秦淮五艳）：凤临乐宴本体资质（等级×每级资质，仅凤魁计入）
	total += g.hero_system.get_fengkui_promo_aptitude(hero_id)
	# 【新增】2026-09-25 凤魁（秦淮五艳）：凤临乐宴解锁技能资质（才貌双全/拈韵吟诗/度曲画兰，仅凤魁计入）
	total += g.hero_system.get_fengkui_skill_aptitude(hero_id)
	# 【新增】2026-09-25 凤魁（秦淮五艳）：山河五岳系列服装技能资质（五件集中计入凤魁）
	total += g.hero_system.get_wuyue_aptitude(hero_id)
	
	# 珍兽资质加成（装备珍兽的资质计入总资质）
	# 【新增】亲和（沉香）无兽计算时跳过（兽魂/魂力资质同理，随下方守卫一并归零）
	var beast_id = hero.get("equipped_beast", "")
	if beast_id != "" and not _beastless_calc:
		total += g.get_beast_aptitude(beast_id, hero.get("equipped_beast_index", 0))
	# 【新增】宅院门客卷二资质加成（按固定门客分组反查对应卷轴等级）
	total += g.get_courtyard_hero_aptitude_bonus(hero_id)
	# 【第8批新增】渔获技能资质
	total += g.get_hero_fish_aptitude(hero_id)
	# 【服装系统】服装技能资质 + 同category门客光环资质
	total += g.get_hero_costume_aptitude(hero_id)   
	# 【新增】兽魂词条资质（装备珍兽魂盘的激发格词条之和）
	if not _beastless_calc:
		total += g.get_hero_soul_aptitude(hero_id)
	# 【厢房批次④】家具资质（无双/传奇·按职业）+ 套装资质（潇湘幽竹类·全体）+ 命格资质（外圈槽）
	total += g.get_hero_xiangfang_furniture_aptitude(hero_id)
	total += g.get_hero_xiangfang_set_aptitude(hero_id)
	total += g.get_hero_mingpan_aptitude(hero_id)
	# 【批次③】系列光环资质：自身 series_aptitude 技能 等级×每级资质
	total += g.talent_system.get_series_aptitude_bonus(hero_id)
	# 【新增】魂力资质（装备珍兽魂体：等级+魂骨+技能+共鸣）
	if not _beastless_calc:
		total += g.get_hero_hunli_aptitude(hero_id)
	# 【新增】促织装备资质加成（无双6/级，极无双7/级）
	total += g.cuzhi_system.get_equip_aptitude_bonus(hero_id)
	# 【新增】守护灵技能资质
	total += g.get_hero_guardian_aptitude(hero_id)
	# 【新增】守护灵幻化固定资质
	total += g.get_hero_guardian_avatar_aptitude(hero_id)
	# 【新增】信物资质：信物主人=技能等级×每级资质+绑定门客总资质×1%/个；被绑定门客=主人等级×每级资质
	total += g.token_system.get_owner_aptitude(hero_id)
	total += g.token_system.get_bound_aptitude(hero_id)
	# 【批次④】信物伴生技能资质：Σ 已解锁技能 等级×星级
	total += g.token_system.get_token_skill_aptitude(hero_id)
	# 【新增】风姿资质：醉墨挥毫等级×每级资质（无上限）
	total += g.fengzi_system.get_aptitude(hero_id)
	# 【新增】金兰（花木兰）：金兰义（自身侧）+ 风姿资质100%/金兰义（金兰门客伙伴侧）
	total += g.hero_system.get_jinlan_self_aptitude(hero_id)
	total += g.hero_system.get_jinlan_partner_aptitude(hero_id)
	# 【新增】藏品基础资质（每级+每星，含特殊效果资质每星）
	total += g.collection_system.get_aptitude_bonus(hero_id)
	# 【新增】虫师副业技能资质（虫书Lv≥1解锁，副业等级×星级）
	total += g.cuzhi_system.get_hero_side_aptitude(hero_id)
	# 【新增】副业资质技能：市井百业/百工百业/物宝天华/庖丁解牛/XX之道 每级各+1资质（side_skill_system 统一管）
	total += g.side_skill_system.get_hero_aptitude_bonus(hero_id)
	# 【新增】超群绝伦（挚友才艺技能）：每位绑定挚友每级为该门客资质 +1
	for fid in g.friends:
		if g.friends[fid].get("bound_heroes", []).has(hero_id):
			total += g.friend_system.get_friend_aptitude_bonus(fid)
	
	return total

# 【改】门客品质名：四档（2026-09-21 拍板：0=优秀/1=卓越/2=传奇/3=无双；旧三档 0=卓越/1=传奇/2=无双 已由读档迁移整体+1）
static func get_quality_name(quality: int) -> String:
	var names = {0: "优秀", 1: "卓越", 2: "传奇", 3: "无双"}
	return names.get(quality, "")

# 【改】门客品质颜色：优秀蓝/卓越紫/传奇橙/无双红（与全仓品质色规范一致）
static func get_quality_color(quality: int) -> String:
	var colors = {0: "#3498db", 1: "#9b59b6", 2: "#e67e22", 3: "#e74c3c"}
	return colors.get(quality, "#f2f2f2")

# ============ 赚速（唯一入口，外部一律调这里） ============

# 门客基础赚速 = 总资质 × 等级 × 突破次数
# 【改】公式由 突破次数² 改为 突破次数
static func get_base_income(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var hero = g.heroes[hero_id]
	# 【批次③】copy_max_level（王昭君·宁胡和议/花木兰·替父从军）：等级与突破都复制全门客最高者（2026-09-22 用户补拍板）
	var eff_level = int(hero.level)
	var eff_bt = int(hero.breakthrough_count)
	var copy_stats: Dictionary = g.talent_system.get_copy_stats(hero_id)
	if not copy_stats.is_empty():
		eff_level = maxi(eff_level, int(copy_stats.get("level", 0)))
		eff_bt = maxi(eff_bt, int(copy_stats.get("bt", 0)))
	return int(get_total_aptitude(g, hero_id) * eff_level * eff_bt)

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
	# 【厢房批次④】家具固定赚钱（卓越/优秀/普通·按职业）
	extra += g.get_hero_xiangfang_furniture_income(hero_id)
	
	# 【促织培育】部位固定赚速（按职业汇总极无双促织）
	extra += g.cuzhi_system.get_career_peiyu_flat_income(hero.get("category", ""))
	# 【虫师】虫书固定赚速加成（star 1~4 累加）
	extra += g.cuzhi_system.get_hero_worm_flat_bonus(hero_id)
	# 【新增】天赋固定赚钱（鬼斧神工星级·替换制：只取当前星级配置值，不累加）
	extra += g.talent_system.get_flat_income(hero_id)
	# 【新增】苦情契约固定赚速（白月初独有：指定挚友提供赚钱总值 × 契约等级 × 0.1%）
	extra += g.token_system.get_contract_income(hero_id)
	# 【新增】藏品固定赚速（基础效果赚钱类 每级+每星）
	extra += g.collection_system.get_flat_income_bonus(hero_id)
	# 【新增】客栈菜谱固定赚钱：同职业门客 Σ每道菜 500×升级所需烹饪次数（累加制）
	extra += g.inn_system.get_career_income_bonus(hero.get("category", ""))
	# 【新增】酒坊名酒记固定赚速（绑定职业门客：Σ品质序×10000 + 品质序×5000×(级-1)；2026-09-18 用户拍板按职业接入，读取式）
	extra += g.winery_system.get_career_wine_income(hero.get("category", ""))
	# 【新增】亲和（沉香）光环②：伙伴获得沉香珍兽贡献×转化比例（读取式固定赚钱，hero_system 内反查）
	extra += g.hero_system.get_qinhe_income_bonus(hero_id)

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
	var beast = {"percent": 0.0} if _beastless_calc else g.get_hero_beast_bonus(hero_id)
	bonus += beast.percent
	# 【第8批新增】无双渔获 阶×5%
	bonus += g.get_hero_fish_percent(hero_id)
	# 【服装系统】系列服装光环（群体+3%×关联系列件数 / 自身+3%×件数）
	bonus += g.get_hero_costume_series_pct(hero_id)  
	# 【新增】兽魂赚速%（装备珍兽魂盘的激发格，按魂盘等级3/5/10/15/20%每格）
	if not _beastless_calc:
		bonus += g.get_hero_soul_percent(hero_id)
	# 【新增】魂力赚钱%（魂骨 阶×品级 income_pct_per_tier：十万年5%/阶、百万年16%/阶，2026-09-24 起；灵兔骨技能百分比同口径）
	if not _beastless_calc:
		bonus += g.get_hero_hunli_percent(hero_id)
	#促织庙百分比加成
	bonus += g.cuzhi_system.get_temple_bonus(hero_id)
	# 【促织培育】阶段百分比加成（按职业汇总极无双促织）
	bonus += g.cuzhi_system.get_career_peiyu_percent(hero.get("category", "")) 
	# 【虫师】虫书百分比赚速加成（star 5~6 累加）
	bonus += g.cuzhi_system.get_hero_worm_percent_bonus(hero_id)
	# 【新增】守护灵阶段赚钱百分比
	bonus += g.get_hero_guardian_percent(hero_id)
	# 【新增】守护灵幻化赚钱百分比
	bonus += g.get_hero_guardian_avatar_percent(hero_id)
	# 【新增】守护灵幻化同类门客光环
	bonus += g.get_hero_guardian_career_bonus(hero_id)
	# 【新增】信物羁绊：被绑定门客赚钱+10%（固定百分比）
	bonus += g.token_system.get_bound_income_pct(hero_id)
	# 【新增】风姿：已解锁技能数×5%赚钱（全部解锁后封顶）
	bonus += g.fengzi_system.get_income_pct(hero_id)
	# 【新增】天赋赚钱百分比（鬼斧神工星级·替换制：只取当前星级配置值，不累加）
	bonus += g.talent_system.get_income_pct(hero_id)
	# 【新增】藏品特殊效果百分比（指定/类别/五艳/自选/无双以上门客 + 套装已接入类）
	bonus += g.collection_system.get_percent_bonus(hero_id)
	# 【厢房批次④】套装职业赚钱%（表值×套装等级）+ 命格四象赚钱%（内圈槽）
	bonus += g.get_hero_xiangfang_set_percent(hero_id)
	bonus += g.get_hero_mingpan_pct(hero_id)
	# 【批次③】品质天赋%（同职业/全体/系列）+ 系列光环%（自身/同职业）
	bonus += g.talent_system.get_hero_talent_pct(hero_id)
	bonus += g.talent_system.get_aura_pct(hero_id)
	# 【新增】金兰（花木兰）：巾帼英风/同袍同泽（自身侧）+ 风姿赚钱100%/同袍同泽（金兰门客伙伴侧）
	bonus += g.hero_system.get_jinlan_self_income_pct(hero_id)
	bonus += g.hero_system.get_jinlan_partner_income_pct(hero_id)
	# 【新增】2026-09-24 师徒光环（小八）：市井之学/广结良缘/日进斗金 赚钱%
	bonus += g.hero_system.get_master_aura_income_pct(hero_id)
	# 【新增】2026-09-24 双人光环（小舞）：落日起誓 赚钱%（小舞与杨戬各一份）
	bonus += g.hero_system.get_pair_aura_income_pct(hero_id)
	# 【新增】2026-09-25 自带光环（小柒）：玉蝶轻舞（自身）/ 花影翩跹（同职业含本人）赚钱%
	bonus += g.hero_system.get_self_aura_income_pct(hero_id)

	return bonus

# 门客总赚速 = 基础赚速 × (1 + 百分比加成) + 额外赚速
static func get_income(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	return int(get_base_income(g, hero_id) * (1.0 + get_percent_bonus(g, hero_id)) + get_extra_income(g, hero_id))

# 门客对全局的赚速贡献 = 总赚速 × 突破次数 × 0.5
# （原 hero_system 的 income==0 短路不再保留：0×突破×0.5 恒为0，行为等价）
static func get_global_contribution(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	# 【改】copy_max_level：全局贡献的突破倍率同样取复制值（与 get_base_income 同口径）
	var eff_bt = int(g.heroes[hero_id].breakthrough_count)
	var copy_stats: Dictionary = g.talent_system.get_copy_stats(hero_id)
	if not copy_stats.is_empty():
		eff_bt = maxi(eff_bt, int(copy_stats.get("bt", 0)))
	return int(get_income(g, hero_id) * eff_bt * 0.5)

# 全门客总赚速（战力）= 所有门客总赚速之和
# 【新增】从 hero_system.get_heroes_total_income 搬入
static func get_total_income(g) -> int:
	var total = 0
	for hero_id in g.heroes.keys():
		total += get_income(g, hero_id)
	return total

# 【新增】亲和（沉香）光环②：装备珍兽为门客提升的赚钱
# = 有兽总赚钱 − 无兽总赚钱（含珍兽资质/百分比、兽魂资质/%、魂力资质/固定/% 全部贡献；
# 这些贡献统一读 equipped_beast，无兽计算置 _beastless_calc 后上述守卫行整体跳过，不用逐项剔除）
static func get_beast_income_contribution(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	if _beastless_calc: return 0   # 重入保护
	_beastless_calc = true
	var without_beast := get_income(g, hero_id)
	_beastless_calc = false
	return maxi(0, get_income(g, hero_id) - without_beast)

# ============ 店铺 ============

# 门客店铺加成（只读门客字典，shop_system 在用）
static func get_shop_bonus(hero: Dictionary) -> float:
	if hero.assigned_shop == "": return 0.0
	var total = 0.0
	for skill in hero.shop_skills:
		total += skill.base_percent + (skill.level - 1) * skill.percent_per_level
		# 钱庄「财源广进」是独立店铺技能，在此自然计入（委任加成=两技能相加，用户 2026-09-12 拍板）
	return total
