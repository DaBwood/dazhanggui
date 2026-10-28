extends SceneTree

# ============================================================
# B2 时间结算原语验收：假时钟驱动 5 个系统，重构前后逐字节一致。
# 用法：
#   godot --headless --path . --script res://tests/snapshot_accrual.gd -- <输出路径>
#   输出路径缺省 = res://tests/golden/accrual_current.json
#
# 覆盖：
#   - 妙音坊 settle_jar：初始化 / +1h / 幂等 / 改速率 / 120h 封顶 / 连领两次
#   - 庄园 settle / settle_offline：初始化 / +1h / 幂等 / 改速率 / 离线 24h 封顶
#   - 酒肆叫号、医馆病人、药铺体力：+1 点 / 余数保留 / 封顶 / 超上限回落 / 倒计时
#
# 基线：重构前用同一脚本产出 tests/golden/accrual_baseline.json，
#       重构后重跑必须同哈希。Clock.override_now 让两次都走同一串假时间。
# ============================================================

const OUT_DEFAULT := "res://tests/golden/accrual_current.json"

var _failed := false
var _exit_code := 0
var _ready_to_quit := false


func _initialize() -> void:
	var out_path := OUT_DEFAULT
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		out_path = str(uargs[0])

	var root := {}
	root["miaoyin"] = _test_miaoyin()
	root["manor"] = _test_manor()
	root["tavern"] = _test_tavern()
	root["clinic"] = _test_clinic()
	root["drugshop"] = _test_drugshop()
	Clock.override_now = -1

	var text := JSON.stringify(root, "", true, true)
	print("##ACCRUAL##" + text)

	if not _write_text(out_path, text):
		_failed = true

	if _failed:
		printerr("##ACCRUAL-FAIL##")
		_exit_code = 1
	else:
		print("##ACCRUAL-OK## " + out_path)
		_exit_code = 0
	_ready_to_quit = true


# 等主循环跑完一帧再退：在 _initialize 里直接 quit 会在引擎退出清理阶段段错误
func _process(_delta: float) -> bool:
	if not _ready_to_quit:
		return false
	quit(_exit_code)
	return true


# ============================================================
# 妙音坊：三轨浮点罐
# ============================================================

func _test_miaoyin() -> Dictionary:
	Clock.override_now = 1000
	var g = GameData.new()
	var m = g.miaoyin_system
	m.medal_lv = m.get_medal_count()
	var builds := {}
	for b in m.get_building_list():
		var bid := str(b.get("id", ""))
		var facs: Array = b.get("facilities", [])
		var arr: Array = []
		for i in range(facs.size()):
			arr.append(1 + (i % 3))
		builds[bid] = arr
	m.buildings = builds
	m.jar = {"last": 0, "yyb": 0.0, "yyw": {}, "yyf": {}}

	var out := {}
	# 1) 新罐：只落 last，不产出
	m.settle_jar()
	out["init"] = _snap_miaoyin(m)
	# 2) +1h
	Clock.override_now = 1000 + 3600
	m.settle_jar()
	out["plus_1h"] = _snap_miaoyin(m)
	# 3) 同一 now 再结算：幂等
	m.settle_jar()
	out["idempotent"] = _snap_miaoyin(m)
	# 4) 再 +1h
	Clock.override_now = 1000 + 7200
	m.settle_jar()
	out["plus_2h"] = _snap_miaoyin(m)
	# 5) 第 2h 后改速率，再 +1h：前 2h 已按旧速率落罐，新 1h 按新速率
	_bump_miaoyin(m)
	Clock.override_now = 1000 + 10800
	m.settle_jar()
	out["rate_changed"] = _snap_miaoyin(m)
	# 6) +121h：按 120h 封顶
	Clock.override_now = 1000 + 10800 + (m.get_jar_cap_hours() + 1) * 3600
	m.settle_jar()
	out["cap_120h"] = _snap_miaoyin(m)
	# 7) 连领两次：第二次只剩小数余量，取整为 0
	var c1 = m.claim_jar()
	out["claim_1"] = {"gains": c1, "state": _snap_miaoyin(m)}
	var c2 = m.claim_jar()
	out["claim_2"] = {"gains": c2, "state": _snap_miaoyin(m)}
	return out


func _bump_miaoyin(m) -> void:
	for bid in m.buildings.keys():
		var arr: Array = m.buildings[bid]
		for i in range(arr.size()):
			arr[i] = int(arr[i]) + 1


func _snap_miaoyin(m) -> Dictionary:
	return {
		"last": int(m.jar.get("last", 0)),
		"jar_yyb": float(m.jar.get("yyb", 0.0)),
		"jar_yyw": (m.jar.get("yyw", {}) as Dictionary).duplicate(true),
		"jar_yyf": (m.jar.get("yyf", {}) as Dictionary).duplicate(true),
		"owned_yyb": m.yyb,
		"owned_yyw": (m.yyw as Dictionary).duplicate(true),
	}


# ============================================================
# 庄园：浮点产量仓
# ============================================================

func _test_manor() -> Dictionary:
	Clock.override_now = 1000
	var g = GameData.new()
	g.identity_level = 99
	for kind in ["crops", "animals"]:
		for cfg in g.manor_system.get_species_list(kind):
			var sid := str(cfg.get("id", ""))
			var arr: Array = []
			for i in range(g.manor_system.get_plots_per_species()):
				arr.append({"level": 1 + i, "land": i})
			g.manor_plots[sid] = arr
	g.manor_goods = {}
	g.manor_last_settle = 0

	var out := {}
	# 1) 首次：只落 last，不补产量
	g.manor_system.settle()
	out["init"] = _snap_manor(g)
	# 2) +1h
	Clock.override_now = 1000 + 3600
	g.manor_system.settle()
	out["plus_1h"] = _snap_manor(g)
	# 3) 同一 now：幂等
	g.manor_system.settle()
	out["idempotent"] = _snap_manor(g)
	# 4) 改速率后 +1h
	var first_sid := str(g.manor_system.get_species_list("crops")[0].get("id", ""))
	g.manor_plots[first_sid][0]["level"] = int(g.manor_plots[first_sid][0]["level"]) + 5
	Clock.override_now = 1000 + 7200
	g.manor_system.settle()
	out["rate_changed"] = _snap_manor(g)
	# 5) 离线 48h：按 24h 封顶
	Clock.override_now = 1000 + 7200 + 48 * 3600
	g.last_login_time = 0
	g.last_logout_time = Clock.override_now - 48 * 3600
	g.manor_last_settle = g.last_logout_time
	g.manor_goods = {}
	g.manor_system.settle_offline()
	out["offline_48h"] = _snap_manor(g)
	return out


func _snap_manor(g) -> Dictionary:
	return {
		"last": int(g.manor_last_settle),
		"goods": (g.manor_goods as Dictionary).duplicate(true),
	}


# ============================================================
# 酒肆叫号 / 医馆病人 / 药铺体力：同一个离散恢复形状
# ============================================================

func _test_tavern() -> Dictionary:
	Clock.override_now = 1000
	var g = GameData.new()
	var t = g.tavern_system
	var interval := int(t._st().get("jiaohao_interval", 1200))
	var cap := int(t._st().get("jiaohao_cap", 50))
	t.jiaohao = 0
	t.jiaohao_time = 1000

	var out := {}
	out["t0"] = _snap_tavern(t)
	Clock.override_now = 1000 + interval
	t._sync_jiaohao()
	out["plus_1"] = _snap_tavern(t)
	Clock.override_now += interval / 2
	t._sync_jiaohao()
	out["half"] = _snap_tavern(t)
	Clock.override_now += interval / 2
	t._sync_jiaohao()
	out["plus_2"] = _snap_tavern(t)
	# 封顶：差 1 点，跳 5 个间隔
	t.jiaohao = cap - 1
	t.jiaohao_time = Clock.override_now
	Clock.override_now += interval * 5
	t._sync_jiaohao()
	out["cap"] = _snap_tavern(t)
	# 道具超上限后，自然恢复按 min(cap, value+gained) 回落（原口径）
	t.jiaohao = cap + 4
	t.jiaohao_time = Clock.override_now
	Clock.override_now += interval
	t._sync_jiaohao()
	out["overflow_tick"] = _snap_tavern(t)
	# 倒计时：未满时 = interval，满了 = 0
	t.jiaohao = 10
	t.jiaohao_time = Clock.override_now
	out["next_running"] = _snap_tavern(t)
	t.jiaohao = cap
	t.jiaohao_time = Clock.override_now
	out["next_full"] = _snap_tavern(t)
	return out


func _snap_tavern(t) -> Dictionary:
	return {
		"value": t.jiaohao,
		"ts": t.jiaohao_time,
		"next": t.get_next_jiaohao_seconds(),
	}


func _test_clinic() -> Dictionary:
	Clock.override_now = 1000
	var g = GameData.new()
	var c = g.clinic_system
	var interval := int(c._st().get("patient_interval", 1200))
	var cap := int(c._st().get("patient_cap", 60))
	c.patients = 0
	c.patient_time = 1000

	var out := {}
	out["t0"] = _snap_clinic(c)
	Clock.override_now = 1000 + interval
	c._sync_patients()
	out["plus_1"] = _snap_clinic(c)
	Clock.override_now += interval / 2
	c._sync_patients()
	out["half"] = _snap_clinic(c)
	Clock.override_now += interval / 2
	c._sync_patients()
	out["plus_2"] = _snap_clinic(c)
	c.patients = cap - 1
	c.patient_time = Clock.override_now
	Clock.override_now += interval * 5
	c._sync_patients()
	out["cap"] = _snap_clinic(c)
	c.patients = cap + 4
	c.patient_time = Clock.override_now
	Clock.override_now += interval
	c._sync_patients()
	out["overflow_tick"] = _snap_clinic(c)
	c.patients = 10
	c.patient_time = Clock.override_now
	out["next_running"] = _snap_clinic(c)
	c.patients = cap
	c.patient_time = Clock.override_now
	out["next_full"] = _snap_clinic(c)
	return out


func _snap_clinic(c) -> Dictionary:
	return {
		"value": c.patients,
		"ts": c.patient_time,
		"next": c.get_next_patient_seconds(),
	}


func _test_drugshop() -> Dictionary:
	Clock.override_now = 1000
	var g = GameData.new()
	var d = g.drugshop_system
	var interval := int(d._st().get("stamina_interval", 2400))
	var cap := int(d._st().get("stamina_cap", 30))
	d.stamina = 0
	d.stamina_ts = 1000

	var out := {}
	out["t0"] = _snap_drugshop(d)
	Clock.override_now = 1000 + interval
	d._sync_stamina()
	out["plus_1"] = _snap_drugshop(d)
	Clock.override_now += interval / 2
	d._sync_stamina()
	out["half"] = _snap_drugshop(d)
	Clock.override_now += interval / 2
	d._sync_stamina()
	out["plus_2"] = _snap_drugshop(d)
	d.stamina = cap - 1
	d.stamina_ts = Clock.override_now
	Clock.override_now += interval * 5
	d._sync_stamina()
	out["cap"] = _snap_drugshop(d)
	d.stamina = cap + 4
	d.stamina_ts = Clock.override_now
	Clock.override_now += interval
	d._sync_stamina()
	out["overflow_tick"] = _snap_drugshop(d)
	d.stamina = 10
	d.stamina_ts = Clock.override_now
	out["next_running"] = _snap_drugshop(d)
	d.stamina = cap
	d.stamina_ts = Clock.override_now
	out["next_full"] = _snap_drugshop(d)
	return out


func _snap_drugshop(d) -> Dictionary:
	return {
		"value": d.stamina,
		"ts": d.stamina_ts,
		"next": d.get_next_stamina_seconds(),
	}


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
