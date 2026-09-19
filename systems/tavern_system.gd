# ============================================================
# 酒肆玩法系统（档案四十二节；2026-09-16 批1交付，批3增补 get_facility_preview）
# 模型对照（全部复用已验证先例，不另造轮子）：
#   叫号体力   ← 医馆病人队列（时间恢复/离线补发封顶/道具超上限/队列批处理）
#   收益罐     ← 客栈 pending/claim（银条先入罐，点领取入账）
#   银条       ← 客栈交子同款独立货币（不与铜钱/交子互通，内循环）
#   友好/才华  ← 藏品二批写入式 + 累计值解锁补发（granted 计数器，friend_system 挂钩补发）
# 接待结算（队列批处理防卡顿，每客实时入账）：
#   每客：银条（接待客人收益=全设施银条收益之和）入【收益罐】；
#         二选一随机（serve_exp_pct）——百业经验→随机已拥有门客入钱庄个人池 /
#         才艺经验→随机已拥有挚友入本系统才艺池（本轮只累积不接消耗端）
# 设施三属性（等级 L，上限200）：
#   知名度 = fame0 + fame_per×(L-1)；银条收益 = income0 + income_per×(L-1)
#   餐饮区→该类挚友友好 = friendly0 + friendly_per×(L-1)（写入式+累计补发）
#   娱乐区→该类挚友才华 = talent0  + talent_per×(L-1)（写入式+累计补发）
# 升级消耗 = min(拟合线, 前期爬坡曲线)，两线在 L21~22 处自然相交衔接，全程单调递增
#   拟合线 = cost_base(每设施独立,24级以上原游戏截图实测锚点,勿动) + cost_per_level×当前等级
#   前期爬坡 = early_cost_base × early_cost_growth^当前等级（1~23级原游戏无截图数据,按"满管叫号≈1次升级"补）
# 设施解锁 = 知名度达 200×全局序号(order,第69个=1.38万拉满) + 银条开价(=0→1级消耗)
# 酒肆升级 = 知名度达 5000×1.2^当前等级，免费直升（不耗资源），上限100
# 状态内部持有随 get_save_data 落盘（game_data 只注册系统+加载配置，同 inn/clinic 惯例）
# ============================================================
class_name TavernSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有） ----------
var sign_name: String = ""            # 招牌（空=用配置默认"红尘酒楼"，改名免费限8字）
var level: int = 1                    # 酒肆等级（1~100）
var yintiao: int = 0                  # 银条（已领取；设施升级/解锁消耗）
var jar_yintiao: int = 0              # 收益罐：待领取银条
var jiaohao: int = 0                  # 叫号（体力池：20分钟/点自然恢复，上限50）
var jiaohao_time: int = 0             # 上次叫号结算时间戳（离线补发基准）
var serve_queue: int = 0              # 接待队列：一键叫号转入，视图定时器时间盒批处理（进存档，离线不做假结算）
var facility_levels: Dictionary = {}  # facility_id: 等级（>=1=已解锁；缺省=未解锁）
var granted: Dictionary = {"friendly": {}, "talent": {}}  # 每类挚友累计已发友好/才华（新挚友解锁时一次性补发）
var caiyi: Dictionary = {}            # 才艺经验池 {friend_id: 数量}（本轮只累积，消耗端待挚友技能系统）

# 挚友存档键映射（同藏品 FRIEND_STAT_KEYS 教训：显式建表，禁止拿显示名当字段名）
const FRIEND_STAT_KEYS := {"friendly": "friendly", "talent": "talent"}

func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {"tavern": {
		"sign_name": sign_name, "level": level,
		"yintiao": yintiao, "jar_yintiao": jar_yintiao,
		"jiaohao": jiaohao, "jiaohao_time": jiaohao_time,
		"serve_queue": serve_queue,   # 接待队列持久化：离线不做假结算，读档后接着接待
		"facility_levels": facility_levels,
		"granted": granted, "caiyi": caiyi}}

# 从扁平存档表认领本系统字段（旧档/新档缺字段保持初始值；时间戳缺失从当前起算）
func load_save_data(s: Dictionary):
	if not s.has("tavern") or not s.tavern is Dictionary:
		_init_defaults()   # 新档/旧档无酒肆段：走初始设施装配（只跑一次，见函数注释）
		return
	var d: Dictionary = s.tavern
	sign_name = str(d.get("sign_name", ""))
	level = int(d.get("level", 1))
	yintiao = int(d.get("yintiao", 0))
	jar_yintiao = int(d.get("jar_yintiao", 0))
	jiaohao = int(d.get("jiaohao", 0))
	jiaohao_time = int(d.get("jiaohao_time", 0))
	serve_queue = int(d.get("serve_queue", 0))
	if d.has("facility_levels") and d.facility_levels is Dictionary:
		facility_levels = d.facility_levels
	else:
		_init_facilities_only()
	# 【新增】2026-09-19 空设施表自愈：旧档 bug 会把空表 {} 存进存档（初始装配空跑过），
	# "is Dictionary" 分支照样采纳空表 → 无设施 → 每客银条恒 0（收入=get_income_per_guest 按已解锁设施求和）。
	# 空表=从未装配成功=羁绊也没发过 → _init_defaults 整体重来安全（granted 不防重复，故只在空表时触发这一次）
	if facility_levels.is_empty():
		_init_defaults()   # 有酒肆段但无设施表：补初始设施（不发友好/才华，累计值从零起）
	if d.has("granted") and d.granted is Dictionary:
		granted = d.granted
	if d.has("caiyi") and d.caiyi is Dictionary:
		caiyi = d.caiyi
	if sign_name == "":
		sign_name = str(_st().get("default_name", "红尘酒楼"))
	if jiaohao_time <= 0:
		jiaohao_time = int(Time.get_unix_time_from_system())   # get_unix_time 返回 float，显式转 int 消窄化警告
	_sync_jiaohao()

# 新档默认装配：解锁配置中 initial=true 的设施（1级），并按1级属性给已拥有挚友发放友好/才华
# 幂等保障：仅"存档里没有 tavern 段"时调用；facility_levels 落盘后后续读档不再进此分支
func _init_defaults():
	_init_facilities_only()
	for fid in facility_levels.keys():
		_grant_bond(get_facility_cfg(str(fid)))

# 仅解锁初始设施（不发友好/才华）；供"有酒肆段但缺设施表"的补档场景复用
func _init_facilities_only():
	facility_levels = {}
	for f in get_facility_list():
		if f.get("initial", false):
			facility_levels[str(f.get("id", ""))] = 1

# ============ 配置快捷读 ============
func _cfg() -> Dictionary:
	return g._tavern_configs

func _st() -> Dictionary:
	return _cfg().get("settings", {})

# 全量设施表（按全局解锁序号 order 排列）
func get_facility_list() -> Array:
	return _cfg().get("facilities", [])

# 查设施配置：懒建索引 O(1)（69 设施防每次线性扫）
var _fac_index: Dictionary = {}
var _fac_index_built: bool = false

func get_facility_cfg(fid: String) -> Dictionary:
	if not _fac_index_built:
		for f in get_facility_list():
			_fac_index[str(f.get("id", ""))] = f
		_fac_index_built = true
	return _fac_index.get(fid, {})

# 某区域（餐饮/娱乐）的项目（页签）名列表，按配置顺序去重
func get_projects(area: String) -> Array:
	var out := []
	for f in get_facility_list():
		if str(f.get("area", "")) == area and not out.has(str(f.get("project", ""))):
			out.append(str(f.get("project", "")))
	return out

# 某项目下的设施列表（按 order 升序）
func get_project_facilities(project: String) -> Array:
	var out := []
	for f in get_facility_list():
		if str(f.get("project", "")) == project:
			out.append(f)
	return out

# ============ 叫号体力（医馆病人队列同款：时间恢复/离线补发/道具超上限） ============
func _sync_jiaohao():
	var now: int = int(Time.get_unix_time_from_system())
	var gained: int = int((now - jiaohao_time) / float(_st().get("jiaohao_interval", 1200)))
	if gained > 0:
		jiaohao = min(int(_st().get("jiaohao_cap", 50)), jiaohao + gained)
		jiaohao_time += gained * int(_st().get("jiaohao_interval", 1200))

func get_jiaohao() -> int:
	_sync_jiaohao()
	return jiaohao

func get_jiaohao_cap() -> int:
	return int(_st().get("jiaohao_cap", 50))

# 距下一点叫号恢复的秒数（满上限返回0）
func get_next_jiaohao_seconds() -> int:
	_sync_jiaohao()
	if jiaohao >= get_jiaohao_cap():
		return 0
	return maxi(0, int(_st().get("jiaohao_interval", 1200)) - (int(Time.get_unix_time_from_system()) - jiaohao_time))

# 道具途径加叫号（佳酿+2/个）：不受上限限制（上限只管自然恢复）
func add_jiaohao(n: int):
	_sync_jiaohao()
	jiaohao += n

# ============ 接待队列（叫号只做搬运纯改数字永不卡；视图定时器时间盒批处理） ============
func get_serve_queue() -> int:
	return serve_queue

# 叫号1位客人转入接待队列
func call_one() -> Dictionary:
	_sync_jiaohao()
	if jiaohao <= 0:
		return {"ok": false, "msg": "暂无叫号，稍后再来"}
	jiaohao -= 1
	serve_queue += 1
	return {"ok": true}

# 一键叫号：全部转入接待队列（体力池立刻清零重起自然恢复计时）
func call_all() -> Dictionary:
	_sync_jiaohao()
	if jiaohao <= 0:
		return {"ok": false, "msg": "暂无叫号，稍后再来"}
	var n: int = jiaohao
	serve_queue += n
	jiaohao = 0
	jiaohao_time = int(Time.get_unix_time_from_system())
	return {"ok": true, "count": n}

# 接待批处理：视图定时器以【时间盒 4ms/0.05s】驱动（约5000+/秒，帧压力恒定）
# 每接待一位实时入账；队列接待完自然停止，无需汇总
func process_serve_queue(budget_ms: int = 4) -> Dictionary:
	if serve_queue <= 0:
		return {"ok": true, "done": true}
	var t0: int = Time.get_ticks_msec()
	while serve_queue > 0 and Time.get_ticks_msec() - t0 < budget_ms:
		_serve_one()
	if serve_queue <= 0:
		return {"ok": true, "done": true}
	return {"ok": true, "done": false, "left": serve_queue}

# 接待单个（内部）：银条入罐 + 百业/才艺经验二选一随机（纯随机不按资质权重）
func _serve_one():
	jar_yintiao += get_income_per_guest()
	if randf() < float(_st().get("serve_exp_pct", 0.5)):
		var hero_ids: Array = g.heroes.keys()
		if not hero_ids.is_empty():
			g.hero_system.add_baiye(str(hero_ids[randi() % hero_ids.size()]), get_baiye_per_guest())
	else:
		var friend_ids: Array = g.friends.keys()
		if not friend_ids.is_empty():
			var fid: String = str(friend_ids[randi() % friend_ids.size()])
			caiyi[fid] = int(caiyi.get(fid, 0)) + get_caiyi_per_guest()
	serve_queue -= 1

# ============ 收益罐（银条先入罐，点领取入账；无容量上限） ============
func get_jar() -> int:
	return jar_yintiao

func has_jar() -> bool:
	return jar_yintiao > 0

# 领取收益罐：银条入账并清零，返回本次领取量
func collect_jar() -> int:
	var r: int = jar_yintiao
	yintiao += jar_yintiao
	jar_yintiao = 0
	return r

func get_yintiao() -> int:
	return yintiao

# 扣银条（内部统一出口；余额不足返回 false）
func _spend_yintiao(n: int) -> bool:
	if yintiao < n:
		return false
	yintiao -= n
	return true

# ============ 招牌与酒肆等级 ============
func get_sign_name() -> String:
	if sign_name == "":
		sign_name = str(_st().get("default_name", "红尘酒楼"))
	return sign_name

# 改名：免费，限8个中文字（去首尾空格后校验长度）
func rename_sign(p_name: String) -> Dictionary:
	var n: String = p_name.strip_edges()
	if n == "":
		return {"ok": false, "msg": "名字不能为空"}
	if n.length() > int(_st().get("max_name_len", 8)):
		return {"ok": false, "msg": "最多%d个字" % int(_st().get("max_name_len", 8))}
	sign_name = n
	return {"ok": true}

func get_level() -> int:
	return level

func get_max_level() -> int:
	return int(_st().get("max_level", 100))

# 升下一级所需知名度阈值 = 5000 × 1.2^当前等级
func get_fame_threshold() -> int:
	return int(float(_st().get("fame_threshold_base", 5000)) * pow(float(_st().get("fame_threshold_pow", 1.2)), level))

func can_level_up() -> Dictionary:
	if level >= get_max_level():
		return {"ok": false, "msg": "酒肆已满级"}
	if get_fame_total() < get_fame_threshold():
		return {"ok": false, "msg": "知名度不足"}
	return {"ok": true}

# 酒肆升级：不消耗任何资源，知名度达阈值即升
func level_up() -> Dictionary:
	var chk := can_level_up()
	if not chk.get("ok", false):
		return chk
	level += 1
	return {"ok": true}

# ============ 设施查询 ============
func get_facility_level(fid: String) -> int:
	return int(facility_levels.get(fid, 0))

func is_facility_unlocked(fid: String) -> bool:
	return get_facility_level(fid) > 0

# 设施当前三属性（按等级公式；未解锁按1级预览，调用方自行判断显隐）
func get_facility_fame(fcfg: Dictionary) -> int:
	var lv: int = maxi(1, get_facility_level(str(fcfg.get("id", ""))))
	return int(_st().get("fame0", 50)) + int(_st().get("fame_per", 25)) * (lv - 1)

func get_facility_income(fcfg: Dictionary) -> int:
	var lv: int = maxi(1, get_facility_level(str(fcfg.get("id", ""))))
	return int(_st().get("income0", 50)) + int(_st().get("income_per", 2)) * (lv - 1)

# 设施羁绊属性类型：餐饮区→friendly（友好），娱乐区→talent（才华）
func get_facility_stat(fcfg: Dictionary) -> String:
	return "friendly" if str(fcfg.get("area", "")) == "餐饮" else "talent"

# 设施羁绊值：友好 = 2+2(L-1)；才华 = 4+4(L-1)
func get_facility_bond(fcfg: Dictionary) -> int:
	var lv: int = maxi(1, get_facility_level(str(fcfg.get("id", ""))))
	if get_facility_stat(fcfg) == "friendly":
		return int(_st().get("friendly0", 2)) + int(_st().get("friendly_per", 2)) * (lv - 1)
	return int(_st().get("talent0", 4)) + int(_st().get("talent_per", 4)) * (lv - 1)

# 全设施知名度之和（小喇叭；酒肆升级门槛判定）
func get_fame_total() -> int:
	var total := 0
	for f in get_facility_list():
		if is_facility_unlocked(str(f.get("id", ""))):
			total += get_facility_fame(f)
	return total

# 接待客人收益 = 所有已解锁设施银条收益之和
func get_income_per_guest() -> int:
	var total := 0
	for f in get_facility_list():
		if is_facility_unlocked(str(f.get("id", ""))):
			total += get_facility_income(f)
	# 【新增】2026-09-19 藏品「招财进宝」酒肆银条收益+2%（固定值，合成即生效升星不叠加；round 防低基数取整吞加成）
	return int(round(total * (1.0 + g.collection_system.get_special_pct("c187", 0.02))))

# 每客百业经验 = 20 + 酒肆等级×1
func get_baiye_per_guest() -> int:
	return int(_st().get("baiye_base", 20)) + int(_st().get("baiye_per_level", 1)) * level

# 每客才艺经验 = 200 + 酒肆等级×10
func get_caiyi_per_guest() -> int:
	return int(_st().get("caiyi_base", 200)) + int(_st().get("caiyi_per_level", 10)) * level

# ============ 设施解锁（知名度门槛 + 银条开价） ============
# 解锁所需知名度 = 500 × 全局解锁序号(order)
func get_unlock_fame(fcfg: Dictionary) -> int:
	return int(_st().get("unlock_fame_per", 500)) * int(fcfg.get("order", 0))

# 解锁开价 = 该设施 0级→1级 的升级消耗（用户拍板：开价=0→1级消耗）
func get_unlock_cost(fcfg: Dictionary) -> int:
	return _cost_at_level(fcfg, 0)

func can_unlock_facility(fid: String) -> Dictionary:
	var fcfg := get_facility_cfg(fid)
	if fcfg.is_empty():
		return {"ok": false, "msg": "设施不存在"}
	if is_facility_unlocked(fid):
		return {"ok": false, "msg": "设施已解锁"}
	if get_fame_total() < get_unlock_fame(fcfg):
		return {"ok": false, "msg": "知名度不足"}
	if yintiao < get_unlock_cost(fcfg):
		return {"ok": false, "msg": "银条不足"}
	return {"ok": true}

# 解锁设施：扣开价→1级→给该类已拥有挚友发放1级友好/才华并入累计值
func unlock_facility(fid: String) -> Dictionary:
	var chk := can_unlock_facility(fid)
	if not chk.get("ok", false):
		return chk
	_spend_yintiao(get_unlock_cost(get_facility_cfg(fid)))
	facility_levels[fid] = 1
	_grant_bond(get_facility_cfg(fid))
	return {"ok": true}

# ============ 设施升级（消耗银条；同步升级=同项目全部+1） ============
# L→L+1 消耗 = _cost_at_level(fcfg, 当前等级)（解锁开价=同一公式在 0 级求值）
func get_upgrade_cost(fid: String) -> int:
	return _cost_at_level(get_facility_cfg(fid), get_facility_level(fid))

# 消耗核心：拟合线(高等级实测锚点) 与 前期等比爬坡 取小
# 低等级段爬坡线远低于拟合线 → 前期可玩；L21~22 两线相交 → 高等级段锚点原样保留
func _cost_at_level(fcfg: Dictionary, lv: int) -> int:
	var fitted: int = int(fcfg.get("cost_base", 0)) + int(_st().get("cost_per_level", 1300)) * lv
	var early: int = int(float(_st().get("early_cost_base", 3000)) * pow(float(_st().get("early_cost_growth", 1.2)), lv))
	return mini(fitted, early)

func get_facility_max_level() -> int:
	return int(_st().get("facility_max_level", 200))

func can_upgrade_facility(fid: String) -> Dictionary:
	if not is_facility_unlocked(fid):
		return {"ok": false, "msg": "请先解锁设施"}
	if get_facility_level(fid) >= get_facility_max_level():
		return {"ok": false, "msg": "设施已满级"}
	if yintiao < get_upgrade_cost(fid):
		return {"ok": false, "msg": "银条不足"}
	return {"ok": true}

# 升级设施：扣银条→等级+1→给该类已拥有挚友发放本级友好/才华并入累计值
func upgrade_facility(fid: String) -> Dictionary:
	var chk := can_upgrade_facility(fid)
	if not chk.get("ok", false):
		return chk
	_spend_yintiao(get_upgrade_cost(fid))
	facility_levels[fid] = get_facility_level(fid) + 1
	_grant_bond(get_facility_cfg(fid))
	return {"ok": true}

# 项目内可升级设施数（同步升级前预览/红点口径）
func get_project_upgradable_count(project: String) -> int:
	var n := 0
	for f in get_project_facilities(project):
		if can_upgrade_facility(str(f.get("id", ""))).get("ok", false):
			n += 1
	return n

# 同步升级：同项目所有已解锁设施各升一级（逐个校验，银条不足者跳过）
func upgrade_project(project: String) -> Dictionary:
	var up := 0
	for f in get_project_facilities(project):
		var fid := str(f.get("id", ""))
		if can_upgrade_facility(fid).get("ok", false):
			upgrade_facility(fid)
			up += 1
	if up <= 0:
		return {"ok": false, "msg": "银条不足或设施已满级"}
	return {"ok": true, "count": up}

# 设施升级红点口径（建筑小按钮红点）
func has_upgradeable_facility() -> bool:
	for f in get_facility_list():
		if can_upgrade_facility(str(f.get("id", ""))).get("ok", false):
			return true
	return false

# 设施解锁红点口径（知名度+银条双达标）
func has_unlockable_facility() -> bool:
	for f in get_facility_list():
		if can_unlock_facility(str(f.get("id", ""))).get("ok", false):
			return true
	return false

# ============ 友好/才华发放（写入式 + 累计值 + 解锁补发，仿藏品二批） ============
# 设施每升1级调用一次：给"该设施绑定类别"的全部已拥有挚友写入本级增量
# （友好+2/级、才华+4/级），并把本级增量累进 granted 计数器（新挚友解锁补发用）
func _grant_bond(fcfg: Dictionary):
	var cat := str(fcfg.get("category", ""))
	if cat == "":
		return
	var stat := get_facility_stat(fcfg)
	var per: int = int(_st().get("friendly_per" if stat == "friendly" else "talent_per", 2))
	var key: String = FRIEND_STAT_KEYS[stat]
	for fid in g.friends.keys():
		if str(g.friends[fid].get("category", "")) != cat:
			continue
		g.friends[fid][key] = int(g.friends[fid].get(key, 0)) + per
	var bucket: Dictionary = granted.get(stat, {})
	bucket[cat] = int(bucket.get(cat, 0)) + per
	granted[stat] = bucket

# 新挚友解锁补发：把该类累计已发的友好/才华一次性写入（friend_system.unlock_friend 挂钩调用）
# 新挚友 granted 从零起，补发全量累计值；幂等（只在解锁瞬间调用一次）
func apply_friend_unlock_bonus(fid: String):
	if not g.friends.has(fid):
		return
	var cat := str(g.friends[fid].get("category", ""))
	var f_add: int = int(granted.get("friendly", {}).get(cat, 0))
	var t_add: int = int(granted.get("talent", {}).get(cat, 0))
	if f_add > 0:
		g.friends[fid]["friendly"] = int(g.friends[fid].get("friendly", 0)) + f_add
	if t_add > 0:
		g.friends[fid]["talent"] = int(g.friends[fid].get("talent", 0)) + t_add

# ============ 才艺经验池（本轮只累积不接消耗端） ============
func get_caiyi(fid: String) -> int:
	return int(caiyi.get(fid, 0))

# 【新增】消耗才艺经验（挚友才艺技能升级用）；余额不足返回 false 不扣
func spend_caiyi(fid: String, amount: int) -> bool:
	if get_caiyi(fid) < amount: return false
	caiyi[fid] = get_caiyi(fid) - amount
	return true

func get_caiyi_total() -> int:
	var total := 0
	for k in caiyi.keys():
		total += int(caiyi[k])
	return total

# 才艺经验入账（内部；当前仅 _serve_one 调用，预留外部途径口子）
func add_caiyi(fid: String, n: int):
	caiyi[fid] = int(caiyi.get(fid, 0)) + n

# ============ 设施升级预览（批3新增：弹窗"当前→下级"三属性展示） ============
# 仅对已解锁设施有效（lv>=1）；maxed=true 表示已满级（下级值保持与当前相同，调用方隐藏箭头）
func get_facility_preview(fid: String) -> Dictionary:
	var fcfg := get_facility_cfg(fid)
	var out := {"stat": "friendly", "cat": "", "fame": 0, "income": 0, "bond": 0,
		"next_fame": 0, "next_income": 0, "next_bond": 0, "cost": 0, "maxed": true}
	if fcfg.is_empty():
		return out
	var lv: int = maxi(1, get_facility_level(fid))
	var stat := get_facility_stat(fcfg)
	var fame_per: int = int(_st().get("fame_per", 25))
	var income_per: int = int(_st().get("income_per", 2))
	var bond_per: int = int(_st().get("friendly_per", 2) if stat == "friendly" else _st().get("talent_per", 4))
	out.stat = stat
	out.cat = str(fcfg.get("category", ""))
	out.fame = int(_st().get("fame0", 50)) + fame_per * (lv - 1)
	out.income = int(_st().get("income0", 50)) + income_per * (lv - 1)
	out.bond = (int(_st().get("friendly0", 2)) if stat == "friendly" else int(_st().get("talent0", 4))) + bond_per * (lv - 1)
	out.cost = get_upgrade_cost(fid)
	out.maxed = lv >= get_facility_max_level()
	if not out.maxed:
		out.next_fame = out.fame + fame_per
		out.next_income = out.income + income_per
		out.next_bond = out.bond + bond_per
	else:
		out.next_fame = out.fame
		out.next_income = out.income
		out.next_bond = out.bond
	return out
