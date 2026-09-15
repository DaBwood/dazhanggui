# ============================================================
# 医馆玩法系统（商铺地图 医馆「▶」入口全屏页；2026-09-13 首批 → 09-15 队列化改造）
# 双队列模型：
#   病人队列(体力池)：20分钟/个自然恢复，上限60，离线照涨；病人手册加人不受上限
#   接诊队列：点【接诊】转入1人 /【一键接诊】全部转入（纯改数字，永不卡）；
#             由视图定时器以【时间盒 4ms/0.05s】批处理（约5000+/秒，帧压力恒定）；
#             队列进存档，离线不做假结算，读档后接着排队治
# 治疗结算（每治一个实时入账）：随机已解锁病人+随机已解锁病症，经过[主科室+额外科室]：
#   医术进【收益罐】(领取后累计,解锁病人)；评分×(1+病人加成)进【该病症自己的评分池】；25%掉科室图纸
# 评分 → 升对应病症图鉴（每病症独立评分池；升到第n级消耗 = 100×科室数×(1+2+…+n) 等差累加；
#        每级使该病症所属科室对应职业店铺赚速 +5%（初始+30%，无上限））
# 图纸 → 新增科室（clinic.json 每科室 unlock_cost，药房初始已建）→ 升科室
#        （1~20级 round(基数×级^1.5)；21级起固定600~900；每级 医术+10 评分+2~4
#        病症在 1/3/5/7/10/13/16/20 级解锁）
# 查询性能：_illness_index O(1) 直达索引 + 已解锁缓存（脏标记重建，见文件中部）
# 状态内部持有随 get_save_data 落盘（game_data 只注册系统+加载配置，零新字段，同 war/inn 惯例）
# ============================================================
class_name ClinicSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有） ----------
var dept_levels: Dictionary = {}    # dept_id: 科室等级（0=未新增，默认仅药房已建；新增后置1）
var illness_levels: Dictionary = {} # illness_id: 病症图鉴等级（默认0）
var illness_scores: Dictionary = {} # illness_id: 该病症独立评分池（接诊该病时入账，升该病图鉴时扣）
var yishu: int = 0                  # 累计医术（收益罐领取后入账，解锁病人用）
var jar_yishu: int = 0              # 收益罐：待领取医术（评分不进罐，直接进病症池）
var patients: int = 0               # 病人队列（体力池）：自然恢复 + 手册补充
var patient_time: int = 0           # 上次队列结算时间戳（离线补发基准）
var treat_queue: int = 0            # 【队列化】接诊队列：已转入待治疗（进存档，离线不做假结算）

func _init(p_g):
	g = p_g

# ---------- 查询索引（O(1) 热路径：80 病症预建直达索引；已解锁列表缓存，状态变更置脏重建） ----------
var _illness_index: Dictionary = {}   # illness_id -> {"dept": 主科室id, "cfg": 病症配置}
var _all_illness_ids: Array = []      # 全部病症 id（建索引时按配置顺序收集）
var _unlocked_cache: Array = []       # 已解锁病症缓存（只读，勿在外部修改）
var _cache_dirty: bool = true         # 科室等级/读档变化时置脏，下次查询重建

func _ensure_index():
	if not _cache_dirty:
		return
	_illness_index.clear()
	_all_illness_ids.clear()
	_unlocked_cache.clear()
	for dept_id in _cfg().get("departments", {}):
		var d: Dictionary = _cfg().get("departments", {})[dept_id]
		for iid in d.get("illnesses", {}):
			_illness_index[iid] = {"dept": dept_id, "cfg": d["illnesses"][iid]}
			_all_illness_ids.append(iid)
	# 内联解锁判定（不经过 get_illness_cfg，避免建索引期间重入）
	for iid in _all_illness_ids:
		var info: Dictionary = _illness_index[iid]
		if get_dept_level(str(info.get("dept", ""))) >= int(info["cfg"].get("unlock_level", 1)):
			_unlocked_cache.append(iid)
	_cache_dirty = false

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {"clinic": {
		"dept_levels": dept_levels, "illness_levels": illness_levels,
		"illness_scores": illness_scores,
		"yishu": yishu, "jar_yishu": jar_yishu,
		"patients": patients, "patient_time": patient_time,
		"treat_queue": treat_queue}}   # 接诊队列持久化：离线不做假结算，读档后接着治

# 从扁平存档表认领本系统字段（旧档缺字段保持初始值；时间戳缺失从当前起算）
func load_save_data(s: Dictionary):
	if not s.has("clinic") or not (s.clinic is Dictionary):
		return
	var d: Dictionary = s.clinic
	dept_levels = d.get("dept_levels", {})
	illness_levels = d.get("illness_levels", {})
	illness_scores = d.get("illness_scores", {})   # 旧档无此字段：各病症评分池从0开始
	yishu = int(d.get("yishu", 0))
	jar_yishu = int(d.get("jar_yishu", 0))
	patients = int(d.get("patients", 0))
	patient_time = int(d.get("patient_time", 0))
	treat_queue = int(d.get("treat_queue", 0))   # 旧版"接诊中"批次状态废弃：残留队列数按0处理
	if patient_time <= 0:
		patient_time = int(Time.get_unix_time_from_system())   # get_unix_time 返回 float，显式转 int 消窄化警告
	# 旧档兼容：首轮默认只建药房（unlock_cost=0 的科室视为已建）
	for dept_id in _cfg().get("departments", {}):
		var dd: Dictionary = _cfg().get("departments", {})[dept_id]
		if not dept_levels.has(dept_id):
			dept_levels[dept_id] = 1 if int(dd.get("unlock_cost", 0)) <= 0 else 0
	_sync_patients()
	_cache_dirty = true   # 科室等级可能被旧档兼容改写，置脏重建索引缓存

# ============ 配置快捷读 ============
func _cfg() -> Dictionary:
	return g._clinic_configs

func _st() -> Dictionary:
	return _cfg().get("settings", {})

# ============ 收益罐（医术先入罐，点领取入账；评分不进罐，直接进病症池） ============
func get_jar_total() -> Dictionary:
	return {"yishu": jar_yishu}

func has_jar() -> bool:
	return jar_yishu > 0

# 领取收益罐：医术入账并清零，返回本次领取量
func collect_jar() -> Dictionary:
	var r := {"yishu": jar_yishu}
	yishu += jar_yishu
	jar_yishu = 0
	return r

# ============ 病人队列（体力池）：按时间差离线补发，封顶上限；道具加人不封顶 ============
func _sync_patients():
	var now: int = int(Time.get_unix_time_from_system())
	var gained: int = int((now - patient_time) / float(_st().get("patient_interval", 1200)))
	if gained > 0:
		patients = min(int(_st().get("patient_cap", 60)), patients + gained)
		patient_time += gained * int(_st().get("patient_interval", 1200))

func get_patient_count() -> int:
	_sync_patients()
	return patients

func get_patient_cap() -> int:
	return int(_st().get("patient_cap", 60))

# 距下一个病人恢复的秒数（队列满返回0）
func get_next_patient_seconds() -> int:
	_sync_patients()
	if patients >= get_patient_cap():
		return 0
	return int(int(_st().get("patient_interval", 1200)) - (Time.get_unix_time_from_system() - patient_time))

# 道具途径加病人：不受上限限制（上限只管自然恢复），允许超出排队
func add_patients(n: int):
	_sync_patients()
	patients += n

# 已解锁病人池（医术达到阈值）
func get_unlocked_patients() -> Array:
	var pool := []
	for p in _cfg().get("patients", []):
		if yishu >= int(p.get("need_yishu", 0)):
			pool.append(p)
	return pool

# 全量病人表（UI 解锁进度展示用）
func get_patient_unlock_info() -> Array:
	return _cfg().get("patients", [])

# ============ 接诊队列：转入（接诊/一键接诊只做搬运，纯改数字永不卡） ============
func get_treat_queue() -> int:
	return treat_queue

# 接诊：1 人转入接诊队列
func admit_one() -> Dictionary:
	_sync_patients()
	if patients <= 0:
		return {"ok": false, "msg": "暂无病人，稍后再来"}
	patients -= 1
	treat_queue += 1
	return {"ok": true}

# 一键接诊：全部转入接诊队列（体力池立刻恢复计数，不受治疗进度影响）
func admit_all() -> Dictionary:
	_sync_patients()
	if patients <= 0:
		return {"ok": false, "msg": "暂无病人，稍后再来"}
	var n := patients
	treat_queue += n
	patients = 0
	patient_time = int(Time.get_unix_time_from_system())   # 清零后重起自然恢复计时
	return {"ok": true, "count": n}

# 治疗批处理：视图定时器以【时间盒 4ms/0.05s】驱动（约5000+/秒，帧压力恒定）
# 每治一个实时入账；队列治完自然停止，无需汇总
func process_treat_queue(budget_ms: int = 4) -> Dictionary:
	if treat_queue <= 0:
		return {"ok": true, "done": true}
	if get_unlocked_illnesses().is_empty() or get_unlocked_patients().is_empty():
		return {"ok": false, "msg": "暂无可诊治病症/病人，队列暂停"}
	var t0: int = Time.get_ticks_msec()
	while treat_queue > 0 and Time.get_ticks_msec() - t0 < budget_ms:
		_treat_one()
	if treat_queue <= 0:
		return {"ok": true, "done": true}
	return {"ok": true, "done": false, "left": treat_queue}

# 治疗单个（内部）：随机已解锁病人+随机已解锁病症，走科室链结算
func _treat_one():
	var pool := get_unlocked_patients()
	var patient: Dictionary = pool[randi() % pool.size()]
	var illnesses := get_unlocked_illnesses()
	var illness_id: String = illnesses[randi() % illnesses.size()]
	var preview := get_illness_preview(illness_id)
	var bonus: float = float(patient.get("bonus", 0))
	var score_gain := int(floor(preview["score"] * (1.0 + bonus)))
	jar_yishu += int(preview["yishu"])
	illness_scores[illness_id] = get_illness_score(illness_id) + score_gain
	treat_queue -= 1
	# 25% 概率掉 1 个科室图纸
	if randf() < float(_st().get("blueprint_drop_pct", 0.25)):
		var item: String = _st().get("blueprint_item", "ke_shi_tu_zhi")
		g.items[item] = int(g.items.get(item, 0)) + 1

# ============ 科室 ============
# 科室是否已新增（药房初始已建；unlock_cost>0 的科室需消耗图纸新增）
func is_dept_unlocked(dept_id: String) -> bool:
	return get_dept_level(dept_id) > 0

func get_dept_level(dept_id: String) -> int:
	return int(dept_levels.get(dept_id, 0))

func get_dept_unlock_cost(dept_id: String) -> int:
	var d: Dictionary = _cfg().get("departments", {}).get(dept_id, {})
	return int(d.get("unlock_cost", 0))

func can_unlock_dept(dept_id: String) -> Dictionary:
	if is_dept_unlocked(dept_id):
		return {"ok": false, "msg": "科室已存在"}
	var item: String = _st().get("blueprint_item", "ke_shi_tu_zhi")
	if int(g.items.get(item, 0)) < get_dept_unlock_cost(dept_id):
		return {"ok": false, "msg": "科室图纸不足"}
	return {"ok": true}

# 新增科室：消耗图纸（unlock_cost），建成后 1 级
func unlock_dept(dept_id: String) -> Dictionary:
	var chk := can_unlock_dept(dept_id)
	if not chk.get("ok", false):
		return chk
	var item: String = _st().get("blueprint_item", "ke_shi_tu_zhi")
	g.items[item] = int(g.items.get(item, 0)) - get_dept_unlock_cost(dept_id)
	dept_levels[dept_id] = 1
	_cache_dirty = true   # 新科室可能解锁新病症，置脏重建缓存
	return {"ok": true}

func get_dept_yishu(dept_id: String) -> int:
	if not is_dept_unlocked(dept_id):
		return 0
	var d: Dictionary = _cfg().get("departments", {}).get(dept_id, {})
	return int(d.get("yishu0", 98)) + int(d.get("yishu_per", 10)) * (get_dept_level(dept_id) - 1)

func get_dept_score(dept_id: String) -> int:
	if not is_dept_unlocked(dept_id):
		return 0
	var d: Dictionary = _cfg().get("departments", {}).get(dept_id, {})
	return int(d.get("score0", 0)) + int(d.get("score_per", 0)) * (get_dept_level(dept_id) - 1)

# 科室升级消耗：1~20级 round(基数×级^1.5)；21级起固定值（600~900，各科室不同）
func get_dept_upgrade_cost(dept_id: String) -> int:
	var d: Dictionary = _cfg().get("departments", {}).get(dept_id, {})
	var lv := get_dept_level(dept_id)
	if lv <= 20:
		return int(round(float(d.get("cost_base", 3)) * pow(lv, 1.5)))
	return int(d.get("cost_fixed", 600))

func can_upgrade_dept(dept_id: String) -> Dictionary:
	if not is_dept_unlocked(dept_id):
		return {"ok": false, "msg": "请先新增科室"}
	var item: String = _st().get("blueprint_item", "ke_shi_tu_zhi")
	if int(g.items.get(item, 0)) < get_dept_upgrade_cost(dept_id):
		return {"ok": false, "msg": "科室图纸不足"}
	return {"ok": true}

func upgrade_dept(dept_id: String) -> Dictionary:
	var chk := can_upgrade_dept(dept_id)
	if not chk.get("ok", false):
		return chk
	var item: String = _st().get("blueprint_item", "ke_shi_tu_zhi")
	g.items[item] = int(g.items.get(item, 0)) - get_dept_upgrade_cost(dept_id)
	dept_levels[dept_id] = get_dept_level(dept_id) + 1
	_cache_dirty = true   # 升级可能解锁新病症，置脏重建缓存
	return {"ok": true}

# ============ 病症 ============
# 查病症配置：O(1) 直达索引（原实现为 80 项循环查找）
func get_illness_cfg(illness_id: String) -> Dictionary:
	_ensure_index()
	return _illness_index.get(illness_id, {})

# 病症是否解锁（主科室已新增且等级达到解锁等级）
func is_illness_unlocked(illness_id: String) -> bool:
	var info := get_illness_cfg(illness_id)
	if info.is_empty():
		return false
	return get_dept_level(str(info.get("dept", ""))) >= int(info["cfg"].get("unlock_level", 1))

# 病症经过的科室链 = [主科室] + 额外科室（去重保序）
func get_illness_departments(illness_id: String) -> Array:
	var info := get_illness_cfg(illness_id)
	if info.is_empty():
		return []
	var chain: Array = [str(info.get("dept", ""))]
	for e in info["cfg"].get("extra", []):
		if not chain.has(e):
			chain.append(e)
	return chain

# 接诊收益预览：按当前科室等级算走一遍科室链可得多少医术/评分（不含病人加成）
func get_illness_preview(illness_id: String) -> Dictionary:
	var yishu_sum := 0
	var score_sum := 0
	for dept_id in get_illness_departments(illness_id):
		yishu_sum += get_dept_yishu(str(dept_id))
		score_sum += get_dept_score(str(dept_id))
	return {"yishu": yishu_sum, "score": score_sum}

# 已解锁病症列表：读缓存（脏时重建）；返回只读引用，外部勿修改
func get_unlocked_illnesses() -> Array:
	_ensure_index()
	return _unlocked_cache

func get_illness_level(illness_id: String) -> int:
	return int(illness_levels.get(illness_id, 0))

# 该病症独立评分池余额
func get_illness_score(illness_id: String) -> int:
	return int(illness_scores.get(illness_id, 0))

# 单个病症当前店铺赚速加成（初始30% + 5%×图鉴等级）
func get_illness_pct(illness_id: String) -> float:
	if not is_illness_unlocked(illness_id):
		return 0.0
	return float(_st().get("illness_init_pct", 0.30)) + float(_st().get("illness_pct_per_level", 0.05)) * get_illness_level(illness_id)

# 某职业店铺赚速加成（读取式，shop_system 收入公式接入）：
# Σ 已解锁病症（初始30% + 5%×图鉴等级），该病症所属科室的加成对象职业匹配才计入
func get_category_bonus(category: String) -> float:
	var total := 0.0
	for dept_id in _cfg().get("departments", {}):
		var d: Dictionary = _cfg().get("departments", {})[dept_id]
		if str(d.get("category", "")) != category:
			continue
		for iid in d.get("illnesses", {}):
			total += get_illness_pct(iid)
	return total

# 图鉴升第n级消耗评分 = 100×经过科室数×(1+2+…+n)（等差累加；1→2级=100×1×科室数）
# 扣该病症自己的评分池
func get_illness_upgrade_cost(illness_id: String) -> int:
	var n := get_illness_level(illness_id) + 1
	var base: int = int(_st().get("illness_cost_base", 100))
	return int(base * get_illness_departments(illness_id).size() * n * (n + 1) / 2.0)

func can_upgrade_illness(illness_id: String) -> Dictionary:
	if not is_illness_unlocked(illness_id):
		return {"ok": false, "msg": "病症未解锁"}
	if get_illness_score(illness_id) < get_illness_upgrade_cost(illness_id):
		return {"ok": false, "msg": "该病症评分不足"}
	return {"ok": true}

func upgrade_illness(illness_id: String) -> Dictionary:
	var chk := can_upgrade_illness(illness_id)
	if not chk.get("ok", false):
		return chk
	illness_scores[illness_id] = get_illness_score(illness_id) - get_illness_upgrade_cost(illness_id)
	illness_levels[illness_id] = get_illness_level(illness_id) + 1
	return {"ok": true}
