# ============================================================
# 招商系统（2026-10-04 批次①：本地全链路）
# 三页签：承包项目（自己立项）/ 项目招商（批次①=人机兜底，真人 Worker 批次②）/ 名流榜（批次①本地记账+空态 UI）
# 结算公式唯一入口在本文件：每分钟资历 = 基础(60) × 身份倍数 × (1 + 称号0%) × (1 + c203 每星2%)
#   承包资历 = 每分钟 × 份数 × 180（承包时刻锁定"预计资历"，身份/藏品中途变化不影响在途项目）
#   加入资历 = 自己每分钟 × 剩余分钟（加入时刻锁定）
# 资历=全局五池（仕途/农事/匠造/行商/军事），副业第六技能的消耗口走 side_skill_system（函数住机制的家）
# ============================================================
class_name ZhaoshangSystem
extends RefCounted

var g

func _init(p_g):
	g = p_g

# ============ 存档 ============
var active_projects: Array = []    # 自己承包的进行中 [{type,copies,start_ts,end_ts,merit}]
var joined_projects: Array = []    # 自己加入的进行中 [{id,owner_name,type,end_ts,merit,is_ai}]
var pending_projects: Array = []   # Worker 补报队列（批次②真同步才写入，批次①恒空）
var weekly_merit: Dictionary = {}  # {merit_key: 本周资历}（名流榜批次③上报，批次①先本地记账）
var weekly_key: String = ""        # 当前周键（周一 0 点 UTC+8 界，见 _week_key）
var daily_publish: int = 0         # 今日已立项次数（每日 0 点重置，UTC+8；上限=基础1+藏品岱宗+雷恩天狼刃）
var daily_reset_ts: int = 0
var liked_week: String = ""        # 本周已点赞的周键（赞一次后本周不再渲染赞钮，409 双重点击在客户端堵掉）

var offline_notice: Array = []     # 读档离线补算摘要（进招商页弹一次即清，不落盘）
# 批次②：真机项目拉取缓存（不落盘，每次进页拉新）+ 补报/发布失败透传
var net = null   # NetSystem 由 controller _ready 注入（网络层住 controller 是全局先例，系统不直连）
var real_projects: Array = []        # Worker 返回的进行中且有空位、排除自己的项目
var real_projects_failed: bool = false   # 拉取失败=true（断网/Worker 挂），UI 显示重试钮
var _fetching_projects: bool = false

func get_save_data() -> Dictionary:
	return {"zs_active": active_projects, "zs_joined": joined_projects,
		"zs_pending": pending_projects, "zs_weekly": weekly_merit, "zs_weekly_key": weekly_key,
		"zs_daily_pub": daily_publish, "zs_daily_reset": daily_reset_ts, "zs_ai": ai_cache, "zs_liked": liked_week}

func load_save_data(s: Dictionary):
	if s.has("zs_active") and s.zs_active is Array: active_projects = s.zs_active
	if s.has("zs_joined") and s.zs_joined is Array: joined_projects = s.zs_joined
	if s.has("zs_pending") and s.zs_pending is Array: pending_projects = s.zs_pending
	if s.has("zs_weekly") and s.zs_weekly is Dictionary: weekly_merit = s.zs_weekly
	if s.has("zs_weekly_key"): weekly_key = str(s.zs_weekly_key)
	if s.has("zs_daily_pub"): daily_publish = int(s.zs_daily_pub)
	if s.has("zs_daily_reset"): daily_reset_ts = int(s.zs_daily_reset)
	if s.has("zs_liked"): liked_week = str(s.zs_liked)
	if s.has("zs_ai") and s.zs_ai is Array: ai_cache = s.zs_ai   # 人机项目落盘：重登后名字/倒计时稳定（否则重roll会误导玩家"项目变了"）
	check_week_reset()
	# 离线补算：过期项目直接结算（医馆离线续算同款），摘要暂存供招商页弹出
	var settled: Array = _settle_expired()
	if settled.size() > 0:
		offline_notice = settled

# ============ 配置读取（zhaoshang.json，代码默认值兜底） ============
func _st() -> Dictionary:
	return g._zhaoshang_configs.get("settings", {})

# 点赞奖励（五种资历各+X；名流榜页签显示用）
func get_like_merit() -> int:
	return int(_st().get("like_merit", 10000))

# 单份批文分钟数 / 单次最大份数（签订弹窗 UI 用）
func get_minutes_per_copy() -> int:
	return int(_st().get("minutes_per_copy", 180))

# 单次立项可消耗批文份数上限 = VIP 表（0~16 级：2~9 份；设计本意，用户 2026-10-04 拍板还原）
func get_max_copies() -> int:
	var arr: Array = _st().get("vip_publish_counts", [])
	var lv: int = clampi(int(g.vip_level), 0, maxi(0, arr.size() - 1))
	return int(arr[lv])

func get_projects() -> Dictionary:
	return g._zhaoshang_configs.get("projects", {})

func get_project_cfg(p_type: String) -> Dictionary:
	var ps: Dictionary = get_projects()
	return ps.get(p_type, {})

func get_merit_names() -> Dictionary:
	return g._zhaoshang_configs.get("merit_names", {})

func merit_name(key: String) -> String:
	var names: Dictionary = get_merit_names()
	return str(names.get(key, key))

# 门客职业→对应项目类型（副业第六技能的技能名/消耗资历都从这里映射）
func get_career_project(career: String) -> String:
	var m: Dictionary = g._zhaoshang_configs.get("career_project", {})
	return str(m.get(career, ""))

# 门客职业→对应资历键（side_skill_system "merit" 货币分支用）
func get_career_merit(career: String) -> String:
	var p_type: String = get_career_project(career)
	return str(get_project_cfg(p_type).get("merit", ""))

# 副业第六技能升级消耗曲线（表驱动，zhaoshang.json merit_upgrade_costs 200 项，第 k 项=100×k^1.887）
# level=当前等级（0~199）：0→1 吃表第 1 项（k=1=100），199→200 吃表第 200 项（k=200 兜底外推）
func get_merit_upgrade_cost(level: int) -> int:
	var arr: Array = _st().get("merit_upgrade_costs", [])
	if level >= 0 and level < arr.size():
		return int(arr[level])
	return 0

# ============ 结算公式（唯一入口） ============
func _now() -> int:
	return int(Time.get_unix_time_from_system())

# UTC+8 日期串（教训34：get_datetime_string 的 true 是 use_space 不是时区，UTC 要手动 +8×3600）
func _date_str(ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(ts + 8 * 3600, true).substr(0, 10)

# 周键 = 本周一 0 点（UTC+8）日期串；周一 0 点重置口径
func _week_key() -> String:
	var local: int = _now() + 8 * 3600
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(local)
	var days_since_monday: int = (int(d.get("weekday", 1)) + 6) % 7
	var monday_local: int = local - days_since_monday * 86400 - int(d.get("hour", 0)) * 3600 - int(d.get("minute", 0)) * 60 - int(d.get("second", 0))
	return Time.get_datetime_string_from_unix_time(monday_local, true).substr(0, 10)

func check_daily_reset():
	var now: int = _now()
	if _date_str(now) != _date_str(daily_reset_ts):
		daily_publish = 0
		daily_reset_ts = now

func check_week_reset():
	var k: String = _week_key()
	if weekly_key != k:
		weekly_key = k
		weekly_merit = {}

# 身份倍数（表驱动 1~60 级；identity_multipliers[lv-1]，越界钳表端）
func get_identity_multiplier() -> float:
	var arr: Array = _st().get("identity_multipliers", [])
	var lv: int = clampi(int(g.identity_level), 1, maxi(1, arr.size()))
	return float(arr[lv - 1])

# c203 锦簇画屏：立项/加入资历产出每星+2%（读取式乘区；get_special_star_pct 未拥有返 0）
func get_collection_merit_pct() -> float:
	return g.collection_system.get_special_star_pct("c203", 0.02)

# 自己每分钟资历（含身份倍数与藏品乘区；低基数百分比必须 round，int 取整会吞加成）
func get_merit_per_min() -> int:
	var base: int = int(_st().get("base_merit_per_min", 60))
	return int(round(base * get_identity_multiplier() * (1.0 + get_collection_merit_pct())))

# ============ 资历池（全局五池） ============
func get_merit(key: String) -> int:
	return int(weekly_merit.get(key, 0))

# 结算入账（承包到期/参与到期/点赞都走这里；周一重置在周键变更时自然清账）
# 在线时增量上报 Worker 周榜（服务端累加纯存储）；离线单机赚的资历只进本地账
func add_merit(key: String, amount: int):
	if amount <= 0: return
	check_week_reset()
	weekly_merit[key] = get_merit(key) + amount
	if net != null and net.token != "":
		net.zs_merit({key: amount}, net.username, weekly_key, func(_code: int, _d: Dictionary): pass)

# 资历消耗口（side_skill_system 第六技能升级扣对应职业资历；余额不足返回 false 不扣）
func spend_merit(key: String, amount: int) -> bool:
	if key == "" or amount <= 0: return false
	check_week_reset()
	if get_merit(key) < amount: return false
	weekly_merit[key] = get_merit(key) - amount
	return true

# ============ 槽位与次数 ============
# 每日可立项次数 = 基础1（project_slot_base 配置项）+ c193岱宗（拥有即+1，不叠星）+ 雷恩·天狼刃（zhaoshang_extra cond=project）
# 设计本意（2026-10-04 用户拍板还原）：每日次数=1+藏品+雷恩；VIP 表是单次立项可消耗批文份数上限（见 get_max_copies）
func get_today_publish_limit() -> int:
	var total: int = int(_st().get("project_slot_base", 1))
	if g.collection_system.is_owned("c193"):
		total += 1
	total += g.talent_system.get_zhaoshang_extra("project")
	return total

func get_today_publish_left() -> int:
	check_daily_reset()
	return maxi(0, get_today_publish_limit() - daily_publish)

# 加入槽位 = 基础2 + 雷恩·北斗七星（zhaoshang_extra cond=join）
func get_join_slot_total() -> int:
	return int(_st().get("join_slot_base", 2)) + g.talent_system.get_zhaoshang_extra("join")

# ============ 承包（页签一） ============
func get_contract_check(p_type: String, copies: int) -> Dictionary:
	var conf: Dictionary = get_project_cfg(p_type)
	if conf.is_empty(): return {"ok": false, "reason": "项目不存在"}
	var have: int = int(g.items.get(str(conf.get("piwen", "")), 0))
	if have < copies: return {"ok": false, "reason": "%s不足（拥有%d/%d）" % [str(conf.get("piwen_name", "批文")), have, copies]}
	if get_today_publish_left() < 1: return {"ok": false, "reason": "今日立项次数已用完（基础1+藏品+雷恩）"}
	return {"ok": true, "reason": ""}

func contract(p_type: String, copies: int) -> Dictionary:
	var check: Dictionary = get_contract_check(p_type, copies)
	if not bool(check.get("ok", false)):
		return {"ok": false, "msg": str(check.get("reason", "无法承包"))}
	var conf: Dictionary = get_project_cfg(p_type)
	var piwen: String = str(conf.get("piwen", ""))
	g.items[piwen] = int(g.items.get(piwen, 0)) - copies
	var minutes: int = int(_st().get("minutes_per_copy", 180))
	var now: int = _now()
	# 预计资历锁定在承包时刻（每分钟资历×份数×单份分钟）
	var merit: int = get_merit_per_min() * copies * minutes
	# id 客户端生成且带时间戳：服务端 ON CONFLICT upsert，补报重试幂等安全
	var pid: String = "p_%d_%d" % [now, randi() % 100000]
	var proj: Dictionary = {"id": pid, "type": p_type, "copies": copies,
		"start_ts": now, "end_ts": now + copies * minutes * 60, "merit": merit}
	active_projects.append(proj)
	daily_publish += 1
	return {"ok": true, "msg": "%s ×%d 已立项" % [str(conf.get("name", p_type)), copies], "merit": merit, "project": proj}

# ============ 项目招商（批次①=人机兜底） ============
# 人机项目：5 个、每种项目 1 个常驻（2~6 小时随机）；内存缓存——页内重建不重roll（owner/倒计时不闪），全过期才重新生成
var ai_cache: Array = []

func get_ai_projects() -> Array:
	var now: int = _now()
	var alive: Array = []
	for p in ai_cache:
		if int(p.get("end_ts", 0)) > now:
			alive.append(p)
	if alive.is_empty():
		alive = _gen_ai_projects(now)
	ai_cache = alive   # 顺带清掉过期项
	return alive

func _gen_ai_projects(now: int) -> Array:
	var names: Array = g._zhaoshang_configs.get("ai_names", [])
	var span: int = maxi(1, int(_st().get("ai_duration_max", 21600)) - int(_st().get("ai_duration_min", 7200)))
	var out: Array = []
	for p_type in get_projects().keys():
		var end_ts: int = now + int(_st().get("ai_duration_min", 7200)) + randi() % span
		var nm: String = str(names[randi() % names.size()]) if names.size() > 0 else "神秘商贾"
		out.append({"id": "ai_" + p_type, "is_ai": true, "type": p_type,
			"owner_name": nm, "end_ts": end_ts, "slots": 4})
	return out

func has_joined(p_id: String) -> bool:
	for p in joined_projects:
		if str(p.get("id", "")) == p_id: return true
	return false

func get_join_check(p: Dictionary) -> Dictionary:
	var now: int = _now()
	if int(p.get("end_ts", 0)) <= now: return {"ok": false, "reason": "项目已结束"}
	if int(p.get("joined", 0)) >= int(p.get("slots", 5)): return {"ok": false, "reason": "项目已满员"}
	if has_joined(str(p.get("id", ""))): return {"ok": false, "reason": "已加入该项目"}
	if joined_projects.size() >= get_join_slot_total(): return {"ok": false, "reason": "参与项目已满（%d/%d）" % [joined_projects.size(), get_join_slot_total()]}
	return {"ok": true, "reason": ""}

# 加入结算口径：自己每分钟资历 × 剩余分钟（加入时刻锁定）
func join_project(p: Dictionary) -> Dictionary:
	var check: Dictionary = get_join_check(p)
	if not bool(check.get("ok", false)):
		return {"ok": false, "msg": str(check.get("reason", "无法加入"))}
	var now: int = _now()
	var remain_min: int = maxi(1, int(floor((int(p.get("end_ts", now)) - now) / 60.0)))
	var merit: int = get_merit_per_min() * remain_min
	var conf: Dictionary = get_project_cfg(str(p.get("type", "")))
	joined_projects.append({"id": str(p.get("id", "")), "owner_name": str(p.get("owner_name", "")),
		"type": str(p.get("type", "")), "end_ts": int(p.get("end_ts", 0)), "merit": merit,
		"is_ai": bool(p.get("is_ai", false))})
	return {"ok": true, "msg": "成功加入【%s】" % str(conf.get("name", "项目")), "merit": merit}

# ============ 批次②：Worker 真同步（发布/加入/拉取/补报） ============
# 未登录（token 空）= 单机玩法：不进招商池也不补报；发布失败两口径按 code 区分——
#   code==-1（断网/Worker 挂）→ 本地照玩 + 进补报队列，恢复后补报；
#   4xx/5xx（Worker 明确拒绝）→ 回滚批文并摘项目，on_fail 红字透传（拍板"发布失败→批文回滚+红字"）
func publish_project(p: Dictionary, on_fail: Callable):
	if net == null or net.token == "": return
	net.zs_publish({"id": str(p.get("id", "")), "owner_name": net.username,
		"type": str(p.get("type", "")), "copies": int(p.get("copies", 1)),
		"start_ts": int(p.get("start_ts", 0)), "end_ts": int(p.get("end_ts", 0))},
		func(code: int, d: Dictionary):
			if code == 200 and bool(d.get("ok", false)):
				return
			if code == -1:
				pending_projects.append(p)
				on_fail.call("网络异常，项目暂存本地，恢复后自动补报")
			else:
				_rollback_project(p)
				on_fail.call("立项被拒（%s），批文已退回" % str(d.get("msg", "服务器错误"))))

# Worker 拒绝发布时的回滚：摘项目 + 退批文（资历未结算无账可冲）
func _rollback_project(p: Dictionary):
	for i in range(active_projects.size()):
		if str(active_projects[i].get("id", "")) == str(p.get("id", "")):
			active_projects.remove_at(i)
			break
	var conf: Dictionary = get_project_cfg(str(p.get("type", "")))
	var piwen: String = str(conf.get("piwen", ""))
	if piwen != "":
		g.items[piwen] = int(g.items.get(piwen, 0)) + int(p.get("copies", 1))

# 加入真机项目：先本地校验（不占槽），服务器确认成功才入 joined_projects（失败不占槽位，拍板口径）
# cb(ok: bool, msg: String)；资历按服务器返回 end_ts 锁定剩余分钟（客户端时钟不可信，以服务器为准）
func join_real(p: Dictionary, cb: Callable):
	var check: Dictionary = get_join_check(p)
	if not bool(check.get("ok", false)):
		cb.call(false, str(check.get("reason", "无法加入")))
		return
	net.zs_join(str(p.get("id", "")), net.username,
		func(code: int, d: Dictionary):
			if code == 200 and bool(d.get("ok", false)):
				var end_ts: int = int(d.get("end_ts", p.get("end_ts", 0)))
				var now: int = _now()
				var remain_min: int = maxi(1, int(floor((end_ts - now) / 60.0)))
				var merit: int = get_merit_per_min() * remain_min
				joined_projects.append({"id": str(p.get("id", "")), "owner_name": str(p.get("owner_name", "")),
					"type": str(p.get("type", "")), "end_ts": end_ts, "merit": merit, "is_ai": false})
				cb.call(true, "成功加入")
			elif code == -1:
				cb.call(false, "网络异常，请重试")
			else:
				cb.call(false, str(d.get("msg", "加入失败"))))

# 拉取真机项目列表（进项目招商页触发；并发守卫防重复请求）；ok=false=断网/Worker 挂，UI 走人机兜底+重试钮
func fetch_real_projects(cb: Callable):
	if _fetching_projects: return
	_fetching_projects = true
	net.zs_projects(func(code: int, d: Dictionary):
		_fetching_projects = false
		if code == 200 and bool(d.get("ok", false)):
			real_projects = d.get("projects", [])
			real_projects_failed = false
			cb.call(true)
		else:
			real_projects = []
			real_projects_failed = true
			cb.call(false))

# 补报队列：进招商页时清一次；补报用同一幂等 id 重发，成功即从队列摘除
func flush_pending():
	if net == null or pending_projects.is_empty() or net.token == "": return
	var queue: Array = pending_projects.duplicate()
	for p in queue:
		# 回调按值捕获项目：循环变量按引用捕获会让所有回调看到最后一项（GDScript 闭包坑）
		var cb: Callable = func(code: int, d: Dictionary, q: Dictionary):
			if code == 200 and bool(d.get("ok", false)):
				for i in range(pending_projects.size()):
					if str(pending_projects[i].get("id", "")) == str(q.get("id", "")):
						pending_projects.remove_at(i)
						break
		net.zs_publish({"id": str(p.get("id", "")), "owner_name": net.username,
			"type": str(p.get("type", "")), "copies": int(p.get("copies", 1)),
			"start_ts": int(p.get("start_ts", 0)), "end_ts": int(p.get("end_ts", 0))},
			cb.bind(p.duplicate()))

# ============ 批次③：周榜上报后的真榜与点赞 ============
# 分榜缓存：{merit_key: Array}，当前周键内有效；换周/换榜重新拉
var lb_cache: Dictionary = {}
var lb_week: String = ""
var lb_failed: bool = false
var _fetching_lb: bool = false

func fetch_leaderboard(merit: String, cb: Callable):
	check_week_reset()
	if lb_week != weekly_key:   # 换周自然失效
		lb_cache = {}
		lb_week = weekly_key
	if _fetching_lb: return
	_fetching_lb = true
	net.zs_leaderboard(merit, weekly_key, func(code: int, d: Dictionary):
		_fetching_lb = false
		if code == 200 and bool(d.get("ok", false)):
			lb_cache[merit] = d.get("list", [])
			lb_failed = false
			cb.call(true)
		else:
			lb_failed = true
			cb.call(false))

# 本周是否已点赞（名流榜页签据此不渲染赞钮）
func get_liked_this_week() -> bool:
	check_week_reset()
	return liked_week == weekly_key and weekly_key != ""

# 点赞另一个玩家：服务端唯一约束挡本周重复；成功后五种资历各+10000（经 add_merit 入账并顺带上报）
func like_player(target: String, cb: Callable):
	if net == null or net.token == "":
		cb.call(false, "未登录，无法点赞")
		return
	check_week_reset()
	net.zs_like(target, weekly_key, func(code: int, d: Dictionary):
		if code == 200 and bool(d.get("ok", false)):
			var names: Dictionary = get_merit_names()
			for key in names.keys():
				add_merit(str(key), int(_st().get("like_merit", 10000)))
			liked_week = weekly_key   # 本周已赞：客户端不再渲染赞钮（服务端 409 双保险）
			cb.call(true, "")
		elif code == -1:
			cb.call(false, "网络异常，请重试")
		else:
			cb.call(false, str(d.get("msg", "点赞失败"))))

# ============ 结算节拍（controller on_auto_earn 每秒调用） ============
func tick() -> Array:
	check_daily_reset()
	check_week_reset()
	return _settle_expired()

# 过期项目结算：承包按锁定预计资历、加入按锁定剩余分钟资历；返回结算摘要 [{type,merit}]
func _settle_expired() -> Array:
	var now: int = _now()
	var settled: Array = []
	var still_active: Array = []
	for p in active_projects:
		if int(p.get("end_ts", 0)) <= now:
			var m1: int = int(p.get("merit", 0))
			add_merit(str(get_project_cfg(str(p.get("type", ""))).get("merit", "")), m1)
			settled.append({"type": str(p.get("type", "")), "merit": m1, "kind": "contract"})
		else:
			still_active.append(p)
	active_projects = still_active
	var still_joined: Array = []
	for p in joined_projects:
		if int(p.get("end_ts", 0)) <= now:
			var m2: int = int(p.get("merit", 0))
			add_merit(str(get_project_cfg(str(p.get("type", ""))).get("merit", "")), m2)
			settled.append({"type": str(p.get("type", "")), "merit": m2, "kind": "join"})
		else:
			still_joined.append(p)
	joined_projects = still_joined
	return settled

# 读档/节拍结算后的统一文案（成功弹窗用）：【项目名】资历+xxx
func settle_text(s: Dictionary) -> String:
	var conf: Dictionary = get_project_cfg(str(s.get("type", "")))
	return "【%s】%s+%d" % [str(conf.get("name", "项目")), merit_name(str(conf.get("merit", ""))), int(s.get("merit", 0))]
