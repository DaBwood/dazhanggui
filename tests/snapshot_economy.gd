extends SceneTree

# ============================================================
# 经济快照（B1 Shop 加成注册表 的验收工具）
# 目的：重构前后逐字节一致。不测"数值对不对"，只测"和改之前一模一样"。
#
# 用法：
#   godot --headless --path . --script res://tests/snapshot_economy.gd -- <输出路径>
#   输出路径缺省 = res://tests/golden/economy_current.json
#
# 两层校验：
#   1) 快照层：F1/F2/F3 三档 fixture 的全部店铺赚速 + 钱庄赚速 + 总赚速 → JSON
#   2) 等价层：脚本内保留一份"重构前的 14 项链"副本（_legacy_bonus），
#      与当前实现逐店比对。B1 之后若漏接/错接某一项，这里直接失败。
#      同时校验注册表条目数=14、顺序与标签与现链一致。
# ============================================================

const OUT_DEFAULT := "res://tests/golden/economy_current.json"

# 现链 14 项，顺序即浮点求和顺序，不得重排（重排会改尾数）
const EXPECTED_LABELS := [
	"钱庄", "门客派遣", "挚友", "宅院", "庄园", "商会", "医馆",
	"药铺勋章", "酒坊勋章", "酒坊职业", "妙音坊勋章", "垂钓勋章", "藏品勋章", "厢房勋章",
]

var _failed := false
var _exit_code := 0
var _ready_to_quit := false


func _initialize() -> void:
	var out_path := OUT_DEFAULT
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		out_path = str(uargs[0])

	var root := {}
	for fx in ["F1", "F2", "F3"]:
		var g = _build_fixture(fx)
		root[fx] = _measure(g, fx)
		g = null

	var text := JSON.stringify(root)
	print("##SNAPSHOT##" + text)

	if not _write_text(out_path, text):
		_failed = true

	if _failed:
		printerr("##SNAPSHOT-FAIL##")
		_exit_code = 1
	else:
		print("##SNAPSHOT-OK## " + out_path)
		_exit_code = 0
	_ready_to_quit = true


# 等主循环跑完一帧再退：在 _initialize 里直接 quit 会在引擎退出清理阶段段错误
func _process(_delta: float) -> bool:
	if not _ready_to_quit:
		return false
	quit(_exit_code)
	return true


# ============================================================
# fixture：三档档位。全部走公开 API 造，不手写整份存档。
# ============================================================

func _build_fixture(fx: String):
	var g = GameData.new()
	match fx:
		"F1":
			pass   # 新档：不碰任何状态（验证空链路径）
		"F2":
			_fixture_mid(g)
		"F3":
			_fixture_late(g)
		_:
			push_error("未知 fixture: " + fx)
			_failed = true
	HeroData.invalidate_income_cache()
	return g


# 中期：650 关 / 前 10 家店 10 级 10 店员 / 6 门客 50 级
func _fixture_mid(g) -> void:
	g.stage_main = 650   # 第 10 家（酒坊）解锁线；交接文档写的 50 关只能开 4 家
	_grant_money(g)
	_unlock_and_upgrade_shops(g, 10, 10)
	_unlock_and_assign_heroes(g, 6, 50)
	_unlock_friends(g, 2, 2000)
	_set_medals(g, 5)
	_set_guild_cache(g)
	_set_winery_workshops(g, 3)
	_set_clinic(g, 5)


# 后期：20000 关（全 20 店）/ 全部 20 级 20 店员 / 20 门客 100 级
func _fixture_late(g) -> void:
	g.stage_main = 20000
	_grant_money(g)
	_unlock_and_upgrade_shops(g, 20, 20)
	_unlock_and_assign_heroes(g, 20, 100)
	_unlock_friends(g, 3, 20000)
	_set_medals(g, 15)
	_set_guild_cache(g)
	_set_winery_workshops(g, 10)
	_set_clinic(g, 10)


func _grant_money(g) -> void:
	g.money = 1000000000
	g.items["shop_blueprint"] = 1000000000
	g.items["hq_blueprint"] = 1000000000


func _unlock_and_upgrade_shops(g, level_target: int, staff_target: int) -> void:
	for sid in GameData.SHOP_ORDER:
		if g.shop_system.can_unlock_shop(sid):
			g.shop_system.unlock_shop(sid)
	for sid in g.shops.keys():
		var guard := 0
		while int(g.shops[sid].level) < level_target and guard < 500:
			if not g.shop_system.upgrade_shop(sid):
				break
			guard += 1
		guard = 0
		while int(g.shops[sid].staff) < staff_target and guard < 500:
			if not g.shop_system.hire_staff(sid):
				break
			guard += 1


func _unlock_and_assign_heroes(g, count: int, level: int) -> void:
	var ids: Array = g.get_all_hero_ids()
	var shop_ids: Array = g.shops.keys()
	if shop_ids.is_empty():
		return
	var n: int = mini(count, ids.size())
	for i in range(n):
		var hid := str(ids[i])
		if not g.hero_system.unlock_hero(hid):
			continue
		g.heroes[hid].level = level
		g.heroes[hid].assigned_shop = str(shop_ids[i % shop_ids.size()])


func _unlock_friends(g, count: int, friendly: int) -> void:
	var ids: Array = g.get_all_friend_ids()
	var n: int = mini(count, ids.size())
	for i in range(n):
		var fid := str(ids[i])
		if not g.friend_system.unlock_friend(fid):
			continue
		g.friends[fid].friendly = friendly


# 六套勋章（药铺/酒坊/妙音坊/垂钓/藏品/厢房），其余项由各自 setter 覆盖等级
func _set_medals(g, medal_lv: int) -> void:
	g.drugshop_system.medal_lv = medal_lv
	g.winery_system.medal_lv = medal_lv
	g.miaoyin_system.medal_lv = medal_lv
	g.fishing_system.medal_lv = medal_lv
	g.collection_system.medal_lv = medal_lv
	g.xiangfang_system.medal_lv = medal_lv


# 商会加成来自服务端下发的 cache；对局内只读，直接构造最小结构
func _set_guild_cache(g) -> void:
	var careers := ["士", "农", "工", "商", "侠"]
	var council := {}
	for i in range(careers.size()):
		council["fixture_%d" % i] = {"career": careers[i], "pct": 0.10}
	g.guild_system.cache = {"council": council, "members": []}


func _set_winery_workshops(g, lv: int) -> void:
	for w in g.winery_system._cfg().get("workshops", []):
		var wid := str(w.get("id", ""))
		var procs := {}
		for p in w.get("processes", []):
			procs[str(p.get("id", ""))] = lv
		g.winery_system.ws[wid] = procs


func _set_clinic(g, lv: int) -> void:
	var depts: Dictionary = g.clinic_system._cfg().get("departments", {})
	for dept_id in depts.keys():
		g.clinic_system.dept_levels[str(dept_id)] = 5   # 科室等级≥unlock_level 才会解锁病症
		for iid in depts[dept_id].get("illnesses", {}).keys():
			g.clinic_system.illness_levels[str(iid)] = lv


# ============================================================
# 测量：输出 + 等价校验
# ============================================================

func _measure(g, fx: String) -> Dictionary:
	var shops := {}
	for sid in GameData.SHOP_ORDER:
		if not g.shops.has(sid):
			continue
		var sid_s := str(sid)
		var live: int = g.shop_system.get_shop_auto_income(sid_s)
		var legacy: int = _legacy_income(g, sid_s)
		if live != legacy:
			push_error("[%s] 赚速不一致 %s: live=%d legacy=%d" % [fx, sid_s, live, legacy])
			_failed = true
		shops[sid_s] = live
	_check_registry(g, fx, shops.keys())
	_check_dummy(g, fx)
	_check_perf(g, fx)
	return {
		"hq": int(g.shop_system.get_hq_auto_income()),
		"shops": shops,
		"total": int(g.shop_system.get_total_auto_income()),
	}


# 注册表结构自检：B1 重构后才有 _shop_modifiers；重构前该字段不存在，跳过
func _check_registry(g, fx: String, shop_ids: Array) -> void:
	var mods = g.get("_shop_modifiers")
	if mods == null:
		return
	if mods.size() != EXPECTED_LABELS.size():
		push_error("[%s] 注册表条目数=%d，应为 %d" % [fx, mods.size(), EXPECTED_LABELS.size()])
		_failed = true
		return
	for i in range(mods.size()):
		var label := str(mods[i].get("label", ""))
		if label != EXPECTED_LABELS[i]:
			push_error("[%s] 注册表第 %d 项标签=%s，应为 %s（顺序不得变）" % [fx, i + 1, label, EXPECTED_LABELS[i]])
			_failed = true
	# 逐项求和必须等于整表求和（Callable 全部可调、无 null）
	if not shop_ids.is_empty():
		var sid := str(shop_ids[0])
		var s: Dictionary = g.shops[sid]
		var ctx := {"shop_id": sid, "category": str(s.get("category", ""))}
		var manual := 1.0
		for m in mods:
			manual += float(m.fn.call(g, ctx))
		var api := float(g.get_shop_multiplier(sid))
		if not is_equal_approx(manual, api):
			push_error("[%s] 逐项求和 %.17f != 接口求和 %.17f" % [fx, manual, api])
			_failed = true


# 只注册即生效：临时注册 +1.0，总赚速必须变；重建注册表后必须复原
func _check_dummy(g, fx: String) -> void:
	if g.get("_shop_modifiers") == null or g.shops.is_empty():
		return
	var before: int = g.shop_system.get_total_auto_income()
	g.register_shop_modifier("__dummy__", func(_g, _ctx): return 1.0)
	var with_dummy: int = g.shop_system.get_total_auto_income()
	g._register_shop_bonuses()
	var restored: int = g.shop_system.get_total_auto_income()
	if with_dummy <= before:
		push_error("[%s] dummy 加成未生效：%d -> %d" % [fx, before, with_dummy])
		_failed = true
	if restored != before:
		push_error("[%s] 撤销 dummy 后未复原：%d -> %d" % [fx, before, restored])
		_failed = true


# 性能：F3（20 店 + 20 门客）总赚速单次耗时。超 20ms 只报告，不擅自加缓存。
func _check_perf(g, fx: String) -> void:
	if fx != "F3":
		return
	g.shop_system.get_total_auto_income()   # 预热门客收入缓存
	var t0 := Time.get_ticks_usec()
	var total: int = g.shop_system.get_total_auto_income()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("##PERF## %s get_total_auto_income=%.3f ms (total=%d)" % [fx, ms, total])
	if ms > 20.0:
		push_warning("[%s] 总赚速单次 %.3f ms 超过 20ms 预算" % [fx, ms])


# ============================================================
# 重构前的 14 项链副本（唯一用途：与当前实现比对）
# 这是 2026-10-28 重构前 systems/shop_system.gd:65-104 的逐字拷贝，
# 不要"顺手优化"它——它就是基准本身。
# ============================================================

func _legacy_income(g, shop_id: String) -> int:
	var s = g.shops[shop_id]
	var base = int(s.auto_base * pow(s.income_mult, s.level - 1))
	var staff_income = float(s.staff_income) + g.get_courtyard_shop_staff_income_bonus(shop_id) + g.drugshop_system.get_craft_staff_bonus(str(s.get("category", "")))
	var staff = s.staff * staff_income
	var subtotal = base + staff
	return int(subtotal * _legacy_bonus(g, shop_id))


func _legacy_bonus(g, shop_id: String) -> float:
	var s = g.shops[shop_id]
	# 门客派遣加成
	var hero_bonus = 0.0
	for hero_id in g.heroes.keys():
		if g.heroes[hero_id].assigned_shop == shop_id:
			hero_bonus += HeroData.get_shop_bonus(g.heroes[hero_id])
	# 挚友加成
	var friend_shop_bonus = 0.0
	for fid in g.friends.keys():
		for sk in g.get_friend_shop_skills(fid):
			if sk.category == s.get("category", ""):
				friend_shop_bonus += sk.bonus
	return 1.0 + g.shop_system.get_global_bonus_percent() + hero_bonus + friend_shop_bonus \
		+ g.get_courtyard_shop_percent_bonus(shop_id) \
		+ g.get_manor_shop_pct_bonus(str(s.get("category", ""))) \
		+ g.guild_system.get_career_bonus(str(s.get("category", ""))) \
		+ g.clinic_system.get_category_bonus(str(s.get("category", ""))) \
		+ g.drugshop_system.get_medal_shop_pct() + g.winery_system.get_medal_shop_pct() \
		+ g.winery_system.get_workshop_career_pct(str(s.get("category", ""))) \
		+ g.miaoyin_system.get_medal_shop_pct() + g.fishing_system.get_medal_shop_pct() \
		+ g.collection_system.get_medal_shop_pct() + g.xiangfang_system.get_medal_shop_pct()


# ============================================================
# 工具
# ============================================================

func _write_text(path: String, text: String) -> bool:
	var dir_path := path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入快照: " + path)
		return false
	f.store_string(text)
	f.close()
	return true
