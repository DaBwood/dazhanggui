# ============================================================
# 商会系统（第一期：人机/议事厅/建设/等级/商店）
# 纯逻辑模块：自己的存档字段自己认领（GameData 零字段改动）
# 共享记录（财富/经验/等级/成员/议事厅）存 Cloudflare Worker guilds 表；
# 网络读写由 guild_view 驱动（本类不碰 net），操作为：set_record → ensure_fresh → 操作 → 取 cache 回写
# 人机=确定性模拟：成员列表只占 {bot,name,seed}，数值人人现算一致；
# 人机建设=惰性补结算：任何人打开商会按"上次结算日"补齐，幂等不重复
# ============================================================
class_name GuildSystem
extends RefCounted

var g

# ===== 自有存档字段 =====
var guild_id: String = ""            # 所属商会ID（空=未入会）
var guild_contribution: int = 0      # 个人贡献（商店货币）
var guild_build: Dictionary = {}     # 建设日计数 {"date","primary","middle","high","item"}
var guild_council_hero: String = ""  # 我委任到议事厅的门客id
var guild_buys: Dictionary = {}      # 限购记录 {row: {"day","n","month","m"}}

# 商会共享记录缓存（guild_view 拉取后注入）
var cache: Dictionary = {}
var my_user: String = ""             # 当前账号名（guild_view 注入，用于职位判断）

func _init(p_g):
	g = p_g

# ============ 存档 ============
func get_save_data() -> Dictionary:
	return {
		"guild_id": guild_id,
		"guild_contribution": guild_contribution,
		"guild_build": guild_build,
		"guild_council_hero": guild_council_hero,
		"guild_buys": guild_buys,
	}

func load_save_data(s: Dictionary):
	if s.has("guild_id"): guild_id = str(s.guild_id)
	if s.has("guild_contribution"): guild_contribution = int(s.guild_contribution)
	if s.has("guild_build") and s.guild_build is Dictionary: guild_build = s.guild_build.duplicate(true)
	if s.has("guild_council_hero"): guild_council_hero = str(s.guild_council_hero)
	if s.has("guild_buys") and s.guild_buys is Dictionary: guild_buys = s.guild_buys.duplicate(true)

# ============ 配置 ============
func get_settings() -> Dictionary:
	return g._guild_configs.get("settings", {})

func get_build_conf(kind: String) -> Dictionary:
	return g._guild_configs.get("builds", {}).get(kind, {})

func get_shop_daily() -> Array:
	return g._guild_configs.get("shop_daily", [])

func get_shop_monthly() -> Array:
	return g._guild_configs.get("shop_monthly", [])

func get_trade_list() -> Array:   # 二期商贸用
	return g._guild_configs.get("trades", [])

# ============ 等级与人数 ============
func get_member_cap(level: int) -> int:
	return int(get_settings().get("member_base", 22)) + int(get_settings().get("member_per_level", 2)) * (level - 1)

# level → level+1 所需经验（表第 level-1 项）
func get_level_exp(level: int) -> int:
	var arr: Array = get_settings().get("level_exp", [])
	if level >= 1 and level <= arr.size():
		return int(arr[level - 1])
	return 999999999

func get_max_level() -> int:
	return int(get_settings().get("max_level", 9))

# 给商会加经验并自动升级（直接改 record）
func _apply_exp(record: Dictionary, amount: float) -> void:
	record["exp"] = float(record.get("exp", 0)) + amount
	var lv = int(record.get("level", 1))
	while lv < get_max_level() and record["exp"] >= get_level_exp(lv):
		record["exp"] -= get_level_exp(lv)
		lv += 1
	record["level"] = lv

# ============ 网络注入/补结算 ============
func set_record(record: Dictionary, username: String) -> void:
	cache = record
	my_user = username
	_bot_catchup(cache)

func get_record() -> Dictionary:
	return cache

# 确保人机建设已补结算到今日（幂等）
func ensure_fresh() -> Dictionary:
	if cache.is_empty(): return {}
	_bot_catchup(cache)
	_trade_daily_reset(cache)   # 【新增】商贸：跨天清空中途路线（用户拍板：今天开第二天没走完也刷新）
	return cache

# ============ 日期工具 ============
func _today() -> String:
	return Time.get_date_string_from_system()

func _date_of(ts: int) -> String:
	var dt = Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

func _date_to_unix(d: String) -> int:
	var p = d.split("-")
	return Time.get_unix_time_from_datetime_dict({"year": int(p[0]), "month": int(p[1]), "day": int(p[2]), "hour": 0, "minute": 0, "second": 0})

func _next_date(d: String) -> String:
	return _date_of(_date_to_unix(d) + 86400)

# ============ 人机玩家（确定性模拟） ============
const BOT_SURNAMES := ["沈","顾","陆","崔","卢","郑","秦","许","潘","杜","钟","任","姜","戚","邹"]
const BOT_SHOPS := ["恒发","永盛","隆昌","泰和","万丰","瑞庆","聚源","德馨","同福","广益"]

func get_careers() -> Array:
	return ["士", "农", "工", "商", "侠"]

func _gen_bot_name(record: Dictionary) -> String:
	var used := {}
	for m in record.get("members", []):
		used[m.get("name", "")] = true
	for i in range(200):
		var nm = BOT_SURNAMES[randi() % BOT_SURNAMES.size()] + BOT_SHOPS[randi() % BOT_SHOPS.size()] + "商行"
		if not used.has(nm):
			return nm
	return "无名商号" + str(randi() % 1000)

func get_bot_count(record: Dictionary) -> int:
	var n = 0
	for m in record.get("members", []):
		if m.get("bot", false): n += 1
	return n

# 人机议事厅职业：种子定死，全员看到一致
# 【修】参数名 p_seed：原名 seed 与 Godot 全局函数 seed() 重名（编辑器警告 SHADOWED_GLOBAL_IDENTIFIER）
func get_bot_career(p_seed: int) -> String:
	return get_careers()[abs(p_seed) % 5]

# 人机议事厅店铺技能加成：30% 起，每商会日 +2%，封 200%（只作真人加成来源，人机自身不需要真生效）
# 【修】参数 _seed 下划线前缀：本函数只随商会天数成长，不用种子（消除 UNUSED_PARAMETER 警告）
func get_bot_skill_pct(_seed: int, record: Dictionary) -> float:
	var days = maxf(0.0, (Time.get_unix_time_from_system() - int(record.get("created", 0))) / 86400.0)
	return minf(float(get_settings().get("bot_skill_base", 0.3)) + days * float(get_settings().get("bot_skill_per_day", 0.02)), float(get_settings().get("bot_skill_cap", 2.0)))

# 人机建设惰性补结算：把上次结算日至今的财富/经验一次补齐（幂等）
func _bot_catchup(record: Dictionary) -> void:
	var bots = get_bot_count(record)
	if bots <= 0:
		record["bot_settle"] = _today()
		return
	var last: String = record.get("bot_settle", "")
	if last == "":
		last = _date_of(int(record.get("created", int(Time.get_unix_time_from_system()))))
	var today = _today()
	if last >= today:
		return
	var days = 0
	var d = last
	while d < today and days < 4000:
		d = _next_date(d)
		days += 1
	record["wealth"] = float(record.get("wealth", 0)) + float(get_settings().get("bot_daily_wealth", 600)) * bots * days
	_apply_exp(record, float(get_settings().get("bot_daily_exp", 600)) * bots * days)
	record["bot_settle"] = today

# 招募人机填满空位（仅会长/副会长）
func recruit_bots() -> Dictionary:
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载"}
	if not is_officer(record): return {"ok": false, "reason": "只有会长/副会长可以招募"}
	var room = get_member_cap(int(record.get("level", 1))) - record.get("members", []).size()
	if room <= 0: return {"ok": false, "reason": "商会已满员"}
	for i in range(room):
		record["members"].append({"bot": true, "name": _gen_bot_name(record), "seed": randi(), "joined": int(Time.get_unix_time_from_system())})
	return {"ok": true, "count": room}

# ============ 职位 ============
# 真人成员条目：{"user":账号名, "name":显示名, "role":"owner"/"vice"/""}
func is_officer(record: Dictionary) -> bool:
	if my_user == "": return false
	if record.get("owner", "") == my_user: return true
	for m in record.get("members", []):
		if not m.get("bot", false) and m.get("user", "") == my_user and m.get("role", "") == "vice":
			return true
	return false

# ============ 议事厅 ============
# 门客店铺技能总加成（1.0=100%）：直接汇总门客 shop_skills（与 hero_data.get_shop_bonus 同一算法，
# 但议事厅不要求门客已派遣店铺——照抄其加总逻辑，去掉 assigned_shop 限制）
func get_hero_shop_pct(hero_id: String) -> float:
	var hero = g.heroes.get(hero_id, {})
	var total = 0.0
	for skill in hero.get("shop_skills", []):
		total += float(skill.get("base_percent", 0)) + (int(skill.get("level", 1)) - 1) * float(skill.get("percent_per_level", 0))
		# 钱庄「财源广进」是独立店铺技能，在此自然计入（议事厅=门客委任+财源广进 两技能相加）
	return total

# 委任门客进议事厅（快照职业+加成%，写进共享记录全员可见；空串=撤回）
func set_council_hero(hero_id: String) -> Dictionary:
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载"}
	if my_user == "": return {"ok": false, "reason": "请先登录账号"}
	if hero_id != "" and not g.heroes.has(hero_id):
		return {"ok": false, "reason": "未拥有该门客"}
	var council: Dictionary = record.get("council", {})
	if hero_id == "":
		council.erase(my_user)
	else:
		var cfg = g.get_hero_config(hero_id)
		council[my_user] = {"hero": hero_id, "hero_name": cfg.get("name", hero_id), "career": str(cfg.get("career", "")), "pct": get_hero_shop_pct(hero_id)}
	record["council"] = council
	guild_council_hero = hero_id
	return {"ok": true}

# 某职业议事厅总加成（真人+人机）——shop_system 加法链接入用
func get_career_bonus(career: String) -> float:
	if career == "" or cache.is_empty(): return 0.0
	var total = 0.0
	for u in cache.get("council", {}).keys():
		var e = cache["council"][u]
		if e.get("career", "") == career:
			total += float(e.get("pct", 0.0))
	for m in cache.get("members", []):
		if m.get("bot", false) and get_bot_career(int(m.get("seed", 0))) == career:
			total += get_bot_skill_pct(int(m.get("seed", 0)), cache)
	return total

# ============ 建设 ============
func get_build_used(kind: String) -> int:
	if str(guild_build.get("date", "")) != _today():
		return 0
	return int(guild_build.get(kind, 0))

# 建设一次：财富/经验进共享记录，贡献进自己存档；返回 {"ok", "conf", "record"}
func build(kind: String) -> Dictionary:
	var conf = get_build_conf(kind)
	if conf.is_empty(): return {"ok": false, "reason": "未知建设类型"}
	if get_build_used(kind) >= int(conf.get("daily", 0)):
		return {"ok": false, "reason": "今日次数已用完"}
	var yb = int(conf.get("yuanbao", 0))
	if yb > 0 and g.yuanbao < yb:
		return {"ok": false, "reason": "元宝不足（需要%d）" % yb}
	var item_id = str(conf.get("item", ""))
	if item_id != "" and g.items.get(item_id, 0) < int(conf.get("item_count", 1)):
		return {"ok": false, "reason": "道具不足（%s）" % g.ITEM_CONFIG.get(item_id, {}).get("name", item_id)}
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载，请稍后重试"}
	if yb > 0: g.yuanbao -= yb
	if item_id != "": g.items[item_id] = g.items.get(item_id, 0) - int(conf.get("item_count", 1))
	guild_contribution += int(conf.get("contribution", 0))
	record["wealth"] = float(record.get("wealth", 0)) + float(conf.get("wealth", 0))
	_apply_exp(record, float(conf.get("exp", 0)))
	if str(guild_build.get("date", "")) != _today():
		guild_build = {"date": _today(), "primary": 0, "middle": 0, "high": 0, "item": 0}
	guild_build[kind] = int(guild_build.get(kind, 0)) + 1
	g.save_game()
	return {"ok": true, "conf": conf, "record": record}

# ============ 商店 ============
func _find_shop_row(row_id: String) -> Dictionary:
	for e in get_shop_daily() + get_shop_monthly():
		if e.get("row", "") == row_id: return e
	return {}

func _buy_used(row_id: String, entry: Dictionary) -> int:
	var rec = guild_buys.get(row_id, {})
	if str(entry.get("period", "day")) == "month":
		return int(rec.get("m", 0)) if str(rec.get("month", "")) == _today().substr(0, 7) else 0
	return int(rec.get("n", 0)) if str(rec.get("day", "")) == _today() else 0

func _record_buy(row_id: String, entry: Dictionary) -> void:
	var rec = guild_buys.get(row_id, {})
	if str(entry.get("period", "day")) == "month":
		if str(rec.get("month", "")) != _today().substr(0, 7): rec = {"month": _today().substr(0, 7), "m": 0}
		rec["m"] = int(rec.get("m", 0)) + 1
	else:
		if str(rec.get("day", "")) != _today(): rec = {"day": _today(), "n": 0}
		rec["n"] = int(rec.get("n", 0)) + 1
	guild_buys[row_id] = rec

# 购买：珍兽直发珍兽，其余进背包；限购按 period 日/月
func buy(row_id: String) -> Dictionary:
	var entry = _find_shop_row(row_id)
	if entry.is_empty(): return {"ok": false, "reason": "商品不存在"}
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载"}
	if int(record.get("level", 1)) < int(entry.get("level", 1)):
		return {"ok": false, "reason": "商会等级不足（需要%d级）" % int(entry.level)}
	if _buy_used(row_id, entry) >= int(entry.get("limit", 0)):
		return {"ok": false, "reason": "已达限购上限"}
	if guild_contribution < int(entry.get("cost", 0)):
		return {"ok": false, "reason": "个人贡献不足（需要%d）" % int(entry.cost)}
	guild_contribution -= int(entry.cost)
	if str(entry.get("beast", "")) != "":
		g.add_beast(str(entry.beast))
	else:
		var item_id = str(entry.get("item", ""))
		g.items[item_id] = g.items.get(item_id, 0) + 1
	_record_buy(row_id, entry)
	g.save_game()
	return {"ok": true, "entry": entry}


# ============================================================
# 商贸（2026-09-10 商会第二批，用户拍板规则）
# 流程：会长/副会长耗财富开启 → 成员委任门客（可多条路线、可多个门客，门客不锁定）
#       → 全队委任赚速总和≥要求即锁定（不可撤回、不再复查）→ 倒计时结束
#       → 任何人打开商会时惰性结算：参与成员各收一封邮件（固定贡献按占比分+随机池人人平等抽）
# 每天刷新：今天开启的路线第二天未完成也清空（set_record/ensure_fresh 时按日期判）
# 商会经验全入共享记录（exp_done 标记防重）；个人贡献在发自己邮件时入自己存档
# 数据全在共享 record["trades"]（旧存档无该字段，读时全走默认值零迁移）：
#   trades = {"date": "2026-09-10", "active": {trade_id: {
#     "opened_by", "opened_ts", "assigns": {user: {"heroes": {hero_id: 赚速快照}, "total": 总和}},
#     "locked", "lock_ts", "end_ts", "plan": {user: 贡献份额}, "exp_done"}}}
# ============================================================

# 取单条路线配置
func get_trade_conf(trade_id: String) -> Dictionary:
	for e in get_trade_list():
		if str(e.get("id", "")) == trade_id:
			return e
	return {}

func _trades_of(record: Dictionary) -> Dictionary:
	var t: Dictionary = record.get("trades", {})
	if not (t is Dictionary):
		t = {}
	if not t.has("active") or not (t["active"] is Dictionary):
		t["active"] = {}
	return t

# 每日刷新：日期变了清空全部进行中（不补发、不结算，用户拍板）
func _trade_daily_reset(record: Dictionary) -> void:
	var t = _trades_of(record)
	if str(t.get("date", "")) != _today():
		record["trades"] = {"date": _today(), "active": {}}

# 路线状态：closed=未开启 assigning=委任中 running=已锁定倒计时 done=到期待结算
func get_trade_status(trade_id: String) -> String:
	if cache.is_empty(): return "closed"
	var active: Dictionary = _trades_of(cache).get("active", {})
	if not active.has(trade_id): return "closed"
	var t: Dictionary = active[trade_id]
	if not bool(t.get("locked", false)): return "assigning"
	if int(t.get("end_ts", 0)) > Time.get_unix_time_from_system(): return "running"
	return "done"

# 是否商会成员（members 含会长本人；人机有 bot 标记）
func _is_member(record: Dictionary, user: String) -> bool:
	for m in record.get("members", []):
		if bool(m.get("bot", false)):
			continue
		if str(m.get("user", "")) == user:
			return true
	return false

# ---------- 开启路线（会长/副会长，耗财富） ----------
func open_trade(trade_id: String) -> Dictionary:
	var conf = get_trade_conf(trade_id)
	if conf.is_empty(): return {"ok": false, "reason": "路线不存在"}
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载"}
	if not is_officer(record): return {"ok": false, "reason": "只有会长/副会长可以开启"}
	if int(record.get("level", 1)) < int(conf.get("level", 1)):
		return {"ok": false, "reason": "商会%d级解锁该路线" % int(conf.level)}
	var trades = _trades_of(record)
	if trades["active"].has(trade_id):
		return {"ok": false, "reason": "该路线已在进行中"}
	var cost = float(conf.get("cost", 0))
	if float(record.get("wealth", 0)) < cost:
		return {"ok": false, "reason": "商会财富不足（需要%d）" % int(cost)}
	record["wealth"] = float(record.get("wealth", 0)) - cost
	trades["active"][trade_id] = {
		"opened_by": my_user,
		"opened_ts": Time.get_unix_time_from_system(),
		"assigns": {},
		"locked": false, "lock_ts": 0, "end_ts": 0,
		"plan": {}, "exp_done": false,
	}
	return {"ok": true, "conf": conf}

# ---------- 委任门客（整体替换我的委任；提交时算赚速快照，达标即锁） ----------
func assign_trade(trade_id: String, hero_ids: Array) -> Dictionary:
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载"}
	if my_user == "": return {"ok": false, "reason": "请先登录账号"}
	if not _is_member(record, my_user): return {"ok": false, "reason": "不是商会成员"}
	var trades = _trades_of(record)
	if not trades["active"].has(trade_id): return {"ok": false, "reason": "该路线未开启"}
	var t: Dictionary = trades["active"][trade_id]
	if bool(t.get("locked", false)): return {"ok": false, "reason": "路线已锁定，无法委任"}
	var heroes := {}
	var total := 0.0
	for hid in hero_ids:
		var s := str(hid)
		if heroes.has(s): continue   # 去重
		if not g.heroes.has(s): return {"ok": false, "reason": "未拥有门客，请刷新后重试"}
		var inc := float(HeroData.get_income(g, s))   # 赚速快照（提交时刻）
		heroes[s] = inc
		total += inc
	t["assigns"][my_user] = {"heroes": heroes, "total": total}
	_try_lock(record, trade_id)
	return {"ok": true, "total": total, "locked": bool(t.get("locked", false))}

# 撤回我的委任（仅锁定前）
func withdraw_trade(trade_id: String) -> Dictionary:
	var record = ensure_fresh()
	if record.is_empty(): return {"ok": false, "reason": "商会数据未加载"}
	var trades = _trades_of(record)
	if not trades["active"].has(trade_id): return {"ok": false, "reason": "该路线未开启"}
	var t: Dictionary = trades["active"][trade_id]
	if bool(t.get("locked", false)): return {"ok": false, "reason": "路线已锁定，不可撤回"}
	t["assigns"].erase(my_user)
	return {"ok": true}

# 达标判定与锁定：全队委任赚速总和≥require → 锁死+算分配方案
func _try_lock(record: Dictionary, trade_id: String) -> void:
	var trades = _trades_of(record)
	if not trades["active"].has(trade_id): return
	var t: Dictionary = trades["active"][trade_id]
	if bool(t.get("locked", false)): return
	var conf = get_trade_conf(trade_id)
	var total := 0.0
	for u in t["assigns"].keys():
		total += float(t["assigns"][u].get("total", 0))
	if total < float(conf.get("require", 0)):
		return
	t["locked"] = true
	t["lock_ts"] = Time.get_unix_time_from_system()
	t["end_ts"] = int(t["lock_ts"]) + int(float(conf.get("hours", 0)) * 3600)
	# 分配方案：贡献按委任赚速占比分，除不尽余数给占比最大者
	var plan := {}
	var contrib := int(conf.get("contrib", 0))
	var given := 0
	var best_u := ""
	var best_t := -1.0
	for u in t["assigns"].keys():
		var share := int(contrib * float(t["assigns"][u].get("total", 0)) / total)
		plan[u] = share
		given += share
		if float(t["assigns"][u].get("total", 0)) > best_t:
			best_t = float(t["assigns"][u].get("total", 0))
			best_u = str(u)
	if best_u != "" and given < contrib:
		plan[best_u] = int(plan[best_u]) + (contrib - given)
	t["plan"] = plan

# ---------- 惰性结算：到期路线发邮件（在 guild_view 拉取后调用，随后 guild_save 回写共享记录） ----------
# 只结算"我自己"那份（邮件本地）；商会经验全入共享记录一次（exp_done）
# 幂等：邮件 id = guild_trade_路线id_日期，本地已存在则跳过（防重领奖）
func settle_due_trades() -> Dictionary:
	var record = cache
	if record.is_empty(): return {"ok": false, "reason": "无缓存"}
	var trades = _trades_of(record)
	var now := Time.get_unix_time_from_system()
	var settled: Array = []
	for trade_id in trades["active"].keys():
		var t: Dictionary = trades["active"][trade_id]
		if not bool(t.get("locked", false)): continue
		if int(t.get("end_ts", 0)) > now: continue
		var conf = get_trade_conf(trade_id)
		# 商会经验：全入（共享标记防重，任一成员打开都会补）
		if not bool(t.get("exp_done", false)):
			_apply_exp(record, float(conf.get("exp", 0)))
			t["exp_done"] = true
		# 我的邮件：固定贡献按方案 + 随机池人人平等抽（次数=耗时÷0.5h）
		if my_user != "" and t["assigns"].has(my_user):
			var date_str := str(trades.get("date", ""))
			var mail_id := "guild_trade_%s_%s" % [trade_id, date_str]
			if not g.mail_system.has_mail(mail_id):
				var draws := {}
				var pool: Array = g._guild_configs.get("trade_random_pool", [])
				var draw_hours := float(get_settings().get("trade_draw_hours", 0.5))
				var n := 0
				if draw_hours > 0:
					n = int(float(conf.get("hours", 0)) / draw_hours)
				for i in n:
					if pool.is_empty(): break
					var it := str(pool[randi() % pool.size()])
					draws[it] = draws.get(it, 0) + 1
				var my_share := int(t.get("plan", {}).get(my_user, 0))
				if my_share > 0:
					guild_contribution += my_share
				g.mail_system.add_mail(
					mail_id,
					"商贸完成·%s" % str(conf.get("name", trade_id)),
					"路线【%s】贸易完成，个人贡献 +%d（已入账），随机货品见附件。" % [str(conf.get("name", trade_id)), my_share],
					draws)
				settled.append(trade_id)
	return {"ok": true, "settled": settled}
