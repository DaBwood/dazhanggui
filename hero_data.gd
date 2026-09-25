class_name HeroData
extends RefCounted

# ============================================================
# 门客领域库：资质/赚速的所有计算唯一入口，要改公式只改这里
# 聚合方法第一个参数 g = GameData 中枢（挚友/珍兽数据在中枢上；
# g 不标类型以避免循环引用）
# ============================================================

# 【新增】亲和（沉香）无兽计算开关：置真期间珍兽系贡献行全部跳过（见 get_beast_income_contribution）
static var _beastless_calc := false

# ============ 收入缓存表（2026-09-25 用户拍板"赚速写入式表格"） ============
# 全门客收入/全局贡献算一次存表，一切读取查表；公式仍只住本文件（get_income 等为唯一计算入口），
# 缓存只是结果快照。任何养成操作后由 game_controller.update_all_ui 统一置脏（汇流点），
# 置脏后首次读取时重建（lazy 重建：避开多步操作做到一半的半成品状态被算进表）。
static var _income_cache: Dictionary = {}     # hero_id -> 门客总赚钱（get_income 快照）
static var _contrib_cache: Dictionary = {}    # hero_id -> 全局贡献（收入×突破×0.5 快照）
static var _income_cache_dirty: bool = true   # 初始即脏：进游戏首次读取时建表

# 置脏入口：任何可能改动门客收入的操作后调用（汇流点 update_all_ui 统一调，各系统无需各自接线）
static func invalidate_income_cache() -> void:
	_income_cache_dirty = true

# 重建：全量扫荡一次。贡献不重复调 get_global_contribution（它内部会再算一遍 get_income），
# 拆出 _contribution_from_income 复用同一份收入快照，一次重建每门客只算一遍
static func _rebuild_income_cache(g) -> void:
	_income_cache.clear()
	_contrib_cache.clear()
	for hero_id in g.heroes.keys():
		var inc: int = get_income(g, hero_id)
		_income_cache[hero_id] = inc
		_contrib_cache[hero_id] = _contribution_from_income(g, hero_id, inc)
	_income_cache_dirty = false

# 查表读门客赚钱（外部读取一律走这里；表外门客返回 0）
static func get_income_cached(g, hero_id: String) -> int:
	if _income_cache_dirty: _rebuild_income_cache(g)
	return int(_income_cache.get(hero_id, 0))

# 查表读门客全局贡献（shop_system 总赚速用）
static func get_contribution_cached(g, hero_id: String) -> int:
	if _income_cache_dirty: _rebuild_income_cache(g)
	return int(_contrib_cache.get(hero_id, 0))

# ============ 加成源注册表（2026-09-25 架构批次A）============
# 全部门客资质/百分比/固定收入加成源统一登记在此（注册点在 game_data._register_hero_bonuses），
# get_total_aptitude / get_percent_bonus / get_extra_income / get_attr_breakdown 四处共用同一份遍历：
# 新增加成源 = 注册一行，不再逐个改 4 个函数（防漏接，构成面板自动多一行）。
# 条目字段：label=构成面板行名；kind="apt"/"pct"/"flat"；fn=Callable(g, hero_id)->数值；
#           beast=true 表示珍兽系来源，亲和转移的无兽试算（_beastless_calc）时跳过
static var _bonus_registry: Array = []

# 清空注册表（game_data._init 注册前先清，防重复注册）
static func clear_bonus_registry() -> void:
	_bonus_registry.clear()

# 注册一条加成源（kind 仅接受 "apt"/"pct"/"flat"）
static func register_bonus(label: String, kind: String, fn: Callable, beast: bool = false) -> void:
	_bonus_registry.append({"label": label, "kind": kind, "fn": fn, "beast": beast})

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
	# 【改】2026-09-25 架构批次A：全部资质来源走注册表遍历（注册点 game_data._register_hero_bonuses），
	#       来源集合与构成面板行天然一致；beast 标记来源在无兽试算（亲和转移）时跳过
	var total := 0
	for src in _bonus_registry:
		if src.kind != "apt": continue
		if _beastless_calc and src.beast: continue
		total += int(src.fn.call(g, hero_id))
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
	# 【改】2026-09-25 架构批次A：全部固定收入来源走注册表遍历
	# 【修】魂力固定收入（注册表内 beast 标记）此前漏挂无兽守卫，亲和转移试算时未剔除，
	#       导致珍兽贡献少算魂骨固定收入部分——本批随注册表一并修正
	var extra := 0
	for src in _bonus_registry:
		if src.kind != "flat": continue
		if _beastless_calc and src.beast: continue
		extra += int(src.fn.call(g, hero_id))
	return extra

# 门客的百分比加成总和（挚友 + 珍兽；TODO: 藏宝加成）
# 【新增】从 hero_system.get_hero_percent_bonus 搬入
static func get_percent_bonus(g, hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	# 【改】2026-09-25 架构批次A：全部百分比来源走注册表遍历；品质天赋/系列光环的百分数口径 /100
	#       已烘进注册 lambda（game_data 侧），此处无需再区分口径
	var bonus := 0.0
	for src in _bonus_registry:
		if src.kind != "pct": continue
		if _beastless_calc and src.beast: continue
		bonus += float(src.fn.call(g, hero_id))
	return bonus

# 门客总赚速 = 基础赚速 × (1 + 百分比加成) + 额外赚速
static func get_income(g, hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	return int(get_base_income(g, hero_id) * (1.0 + get_percent_bonus(g, hero_id)) + get_extra_income(g, hero_id))

# 【新增】贡献倍率部分（从 get_global_contribution 拆出，缓存重建时复用同一份收入快照）：
# 收入 × 突破次数（copy_max_level 复制档取复制值，与 get_base_income 同口径）× 0.5
static func _contribution_from_income(g, hero_id: String, income: int) -> int:
	var eff_bt = int(g.heroes[hero_id].breakthrough_count)
	var copy_stats: Dictionary = g.talent_system.get_copy_stats(hero_id)
	if not copy_stats.is_empty():
		eff_bt = maxi(eff_bt, int(copy_stats.get("bt", 0)))
	return int(income * eff_bt * 0.5)

# 全门客总赚速（战力）= 所有门客总赚速之和
# 【新增】从 hero_system.get_heroes_total_income 搬入
# 【改】走收入缓存表求和（原逐门客实时重算；数值同口径，表脏时先重建）
static func get_total_income(g) -> int:
	if _income_cache_dirty: _rebuild_income_cache(g)
	var total = 0
	for hero_id in _income_cache.keys():
		total += int(_income_cache[hero_id])
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

# ============ 门客属性构成表（2026-09-25 用户拍板，门客面板资质行"?"钮的数据源） ============
# 把 get_total_aptitude / get_percent_bonus / get_extra_income 的逐来源值分项返回（同一批 getter，
# 不复制公式，显示值与生效值天然同口径）；零值行也返回（测试对账用，玩家同可见）。
# 行结构：[来源名, 数值]；pct_rows 为小数制（0.02=2%）。等级上限公式与 hero_system 升级处一致（50+突破×50）。
static func get_attr_breakdown(g, hero_id: String) -> Dictionary:
	var bd: Dictionary = {"apt_total": 0, "apt_rows": [], "level": 0, "bt": 0, "level_cap": 0,
		"income_total": 0, "income_base": 0, "flat_rows": [], "pct_rows": []}
	if not g.heroes.has(hero_id): return bd
	var hero = g.heroes[hero_id]

	# ── 资质/赚钱构成行（2026-09-25 架构批次A：与聚合器共用注册表遍历，行序=注册顺序，
	#    来源新增后此处自动多一行；面板展示真实值，不受无兽试算标记影响）──
	var apt_rows: Array = []
	var pct_rows: Array = []
	var flat_rows: Array = []
	for src in _bonus_registry:
		if src.kind == "apt":
			apt_rows.append([src.label, int(src.fn.call(g, hero_id))])
		elif src.kind == "pct":
			pct_rows.append([src.label, float(src.fn.call(g, hero_id))])
		elif src.kind == "flat":
			flat_rows.append([src.label, int(src.fn.call(g, hero_id))])
	bd["apt_rows"] = apt_rows
	bd["apt_total"] = get_total_aptitude(g, hero_id)

	# ── 等级 / 等级上限（上限公式=50+突破×50，与 hero_system 升级处一致）──
	bd["level"] = int(hero.level)
	bd["bt"] = int(hero.breakthrough_count)
	bd["level_cap"] = 50 + int(hero.breakthrough_count) * 50

	bd["income_base"] = get_base_income(g, hero_id)
	bd["pct_rows"] = pct_rows
	bd["flat_rows"] = flat_rows
	bd["income_total"] = get_income(g, hero_id)
	return bd

# ============ 店铺 ============

# 门客店铺加成（只读门客字典，shop_system 在用）
static func get_shop_bonus(hero: Dictionary) -> float:
	if hero.assigned_shop == "": return 0.0
	var total = 0.0
	for skill in hero.shop_skills:
		total += skill.base_percent + (skill.level - 1) * skill.percent_per_level
		# 钱庄「财源广进」是独立店铺技能，在此自然计入（委任加成=两技能相加，用户 2026-09-12 拍板）
	return total
