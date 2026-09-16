# ============================================================
# 药铺玩法系统（商铺地图 药铺「▶」入口全屏页；2026-09-16 按药铺设计方案 v1.3 定稿）
# 双队列模型（2026-09-16 用户拍板，同医馆队列化范式）：
#   病人池（开发口径"体力"）：40分钟/个自然恢复，上限30，离线照涨；恢复与收益结算完全解耦（只恢复病人，不计算收益）
#   计算队列：点【营业】立即结算1个（不入队）/ 勾选【一键接待】后点【营业】把当前病人全部转入队列
#             （勾选本身不消耗病人，【改】2026-09-16 用户拍板）；队列由 game_controller 每秒节拍 +
#             页面定时器以【时间盒】批处理，不影响性能；队列进存档，离线暂停不假结算，上线接着排队
# 接待结算（每个病人）：均匀随机已解锁药方 → 售价=round(基础售价×1.04^(lv-1)) 进收益罐；
#   药铺经验/次 + 熟练度+100/次 进收益罐；领取时统一入账（铜板→货币/经验→勋章累计【只增不减】/熟练度→药方池）
# 三货币线：铜板升工艺（7项，固定值层伙计赚速）｜熟练度升药方（29张，15级满）｜累计经验升勋章（15级手动）
# 加成接线：勋章全体商铺赚速%（shop_system 百分比层）+ 工艺伙计赚速固定值（shop_system 店员层）
# 精进上限：勋章 refine_cap 差值写入天赋解锁技能 max_level（写入式，升级判定/UI 显示零改动）
# 状态内部持有随 get_save_data 落盘（game_data 只注册系统+加载配置，零新字段，同 clinic/war 惯例）
# ============================================================
class_name DrugshopSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有） ----------
var stamina: int = 0                 # 病人池（开发口径"体力"，待接待病人数）：自然恢复，上限 settings.stamina_cap
var stamina_ts: int = 0              # 上次病人恢复结算时间戳（离线补发基准）
var auto_settle: bool = false        # 一键接待模式开关：勾选后营业=全部转入队列（勾选本身不消耗，点营业才消耗）
var settle_queue: int = 0            # 计算队列：已入队待结算（进存档，离线暂停，上线续算）
var coins: int = 0                   # 铜板（药铺独立货币，收益罐领取入账，仅用于工艺升级）
var exp_total: int = 0               # 累计药铺经验（只增不减：勋章升级进度 + 药方解锁条件）
var medal_lv: int = 1                # 勋章等级（1~15，初始1级）
var pot: Dictionary = {"coins": 0, "exp": 0, "prof": {}}   # 收益罐：待领取 铜板/药铺经验/熟练度{rid:值}
var crafts: Dictionary = {}          # craft_id: 工艺等级（0起）
var recipes: Dictionary = {}         # rid: {lv, prof, unlocked}
var ach: Dictionary = {}             # 成就线id: 已领取档数
var patients_total: int = 0          # 累计接待病人（成就进度，结算即计，不等到领取）

func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {"drugshop": {
		"stamina": stamina, "stamina_ts": stamina_ts, "auto_settle": auto_settle,
		"settle_queue": settle_queue,
		"coins": coins, "exp_total": exp_total, "medal_lv": medal_lv,
		"pot": pot, "crafts": crafts, "recipes": recipes,
		"ach": ach, "patients_total": patients_total}}

# 从扁平存档表认领本系统字段（旧档缺字段保持初始值；时间戳缺失从当前起算）
# 离线口径（用户拍板）：只补算体力恢复，不补算收益；计算队列原样保留，上线由后台节拍续算
func load_save_data(s: Dictionary):
	if not s.has("drugshop") or not (s.drugshop is Dictionary):
		_init_state()
		return
	var d: Dictionary = s.drugshop
	stamina = int(d.get("stamina", 0))
	stamina_ts = int(d.get("stamina_ts", 0))
	auto_settle = bool(d.get("auto_settle", false))
	settle_queue = int(d.get("settle_queue", 0))
	coins = int(d.get("coins", 0))
	exp_total = int(d.get("exp_total", 0))
	medal_lv = clampi(int(d.get("medal_lv", 1)), 1, get_medal_count())
	pot = d.get("pot", {"coins": 0, "exp": 0, "prof": {}})
	if not (pot is Dictionary):
		pot = {"coins": 0, "exp": 0, "prof": {}}
	pot["coins"] = int(pot.get("coins", 0))
	pot["exp"] = int(pot.get("exp", 0))
	if not (pot.get("prof", {}) is Dictionary):
		pot["prof"] = {}
	crafts = d.get("crafts", {})
	recipes = d.get("recipes", {})
	ach = d.get("ach", {})
	patients_total = int(d.get("patients_total", 0))
	if stamina_ts <= 0:
		stamina_ts = int(Time.get_unix_time_from_system())   # get_unix_time 返回 float，显式转 int 消窄化警告
	_init_state()
	_sync_stamina()

# 旧档/异常档缺 drugshop 段时的初始状态（第1张药方初始解锁）
func _init_state():
	for r in _cfg().get("recipes", []):
		var rid: String = str(r.get("id", ""))
		if rid == "":
			continue
		if not recipes.has(rid):
			recipes[rid] = {"lv": 1, "prof": 0, "unlocked": rid == "r01"}
		else:
			var e: Dictionary = recipes[rid]
			e["lv"] = clampi(int(e.get("lv", 1)), 1, get_recipe_max_level())
			e["prof"] = int(e.get("prof", 0))
			e["unlocked"] = bool(e.get("unlocked", false))
	for c in _cfg().get("crafts", []):
		var cid: String = str(c.get("id", ""))
		if cid != "" and not crafts.has(cid):
			crafts[cid] = 0
	for line in _cfg().get("achievements", []):
		var lid: String = str(line.get("id", ""))
		if lid != "" and not ach.has(lid):
			ach[lid] = 0

# ============ 配置快捷读 ============
func _cfg() -> Dictionary:
	return g._drugshop_configs

func _st() -> Dictionary:
	return _cfg().get("settings", {})

func get_recipe_cfg(rid: String) -> Dictionary:
	for r in _cfg().get("recipes", []):
		if str(r.get("id", "")) == rid:
			return r
	return {}

func get_recipe_max_level() -> int:
	return int(_st().get("recipe_max_level", 15))

func get_medal_count() -> int:
	return _cfg().get("medals", []).size()

# ============ 体力池（与收益结算解耦：只恢复体力，不计算收益） ============
func _sync_stamina():
	var now: int = int(Time.get_unix_time_from_system())
	var gained: int = int((now - stamina_ts) / float(_st().get("stamina_interval", 2400)))
	if gained > 0:
		stamina = min(int(_st().get("stamina_cap", 30)), stamina + gained)
		stamina_ts += gained * int(_st().get("stamina_interval", 2400))

func get_stamina() -> int:
	_sync_stamina()
	return stamina

func get_stamina_cap() -> int:
	return int(_st().get("stamina_cap", 30))

# 距下一点体力恢复的秒数（满返回0）
func get_next_stamina_seconds() -> int:
	_sync_stamina()
	if stamina >= get_stamina_cap():
		return 0
	return int(int(_st().get("stamina_interval", 2400)) - (Time.get_unix_time_from_system() - stamina_ts))

# ============ 一键接待开关 ============
# 【改】2026-09-16 用户拍板：勾选只切换营业按钮模式，不消耗病人；点【营业】才把病人转入队列
func get_auto_settle() -> bool:
	return auto_settle

# 勾选一键接待：仅记录模式开关（营业=单个接待 / 营业=全部转入队列），本身不消耗病人
func set_auto_settle(on: bool) -> Dictionary:
	auto_settle = on
	return {"ok": true}

# 一键接待模式：当前全部病人转入计算队列（后台批处理结算，体力恢复照常互不阻塞）
func settle_all() -> Dictionary:
	_sync_stamina()
	if stamina <= 0:
		return {"ok": false, "msg": "病人不足，稍后再来"}
	var n: int = stamina
	settle_queue += n
	stamina = 0
	stamina_ts = int(Time.get_unix_time_from_system())   # 清零后重起自然恢复计时
	return {"ok": true, "n": n}

# ============ 后台节拍（game_controller 每秒 + 页面定时器共用入口） ============
# 时间盒批处理：只推进队列结算，不自动搬运病人（搬运唯一入口=营业按钮，【改】2026-09-16）
func background_tick(budget_ms: int = 2) -> Dictionary:
	_sync_stamina()
	return process_queue(budget_ms)

func get_settle_queue() -> int:
	return settle_queue

# 队列批处理：每结算1个=随机已解锁药方→收益入罐；治完自然停止
func process_queue(budget_ms: int = 2) -> Dictionary:
	if settle_queue <= 0:
		return {"ok": true, "done": true}
	if get_unlocked_recipes().is_empty():
		return {"ok": false, "msg": "暂无已解锁药方，队列暂停"}
	var t0: int = Time.get_ticks_msec()
	while settle_queue > 0 and Time.get_ticks_msec() - t0 < budget_ms:
		_settle_one()
	if settle_queue <= 0:
		return {"ok": true, "done": true}
	return {"ok": true, "done": false, "left": settle_queue}

# 结算单个病人（内部）：均匀随机已解锁药方；售价/经验/熟练度全部进收益罐
func _settle_one():
	var pool := get_unlocked_recipes()
	var rc: Dictionary = pool[randi() % pool.size()]
	var rid: String = str(rc.get("id", ""))
	var lv := get_recipe_level(rid)
	pot["coins"] = int(pot.get("coins", 0)) + get_recipe_price(rid)
	pot["exp"] = int(pot.get("exp", 0)) + int(rc.get("exp", 0))
	var profs: Dictionary = pot.get("prof", {})
	profs[rid] = int(profs.get(rid, 0)) + int(_st().get("prof_per_serve", 100))
	pot["prof"] = profs
	patients_total += 1
	settle_queue -= 1

# 营业：消耗1点立即结算1个病人（手动接待不入队，即时出结果）
func serve_one() -> Dictionary:
	_sync_stamina()
	if stamina <= 0:
		return {"ok": false, "msg": "病人不足，稍后再来"}   # 【改】体力→病人（开发口径体力，玩家口径病人）
	if get_unlocked_recipes().is_empty():
		return {"ok": false, "msg": "暂无已解锁药方"}
	stamina -= 1
	# 直接复用队列结算单元：临时入队→结算→出队
	settle_queue += 1
	_settle_one()
	var r: Dictionary = {"ok": true,
		"coins": int(pot.get("coins", 0)), "exp": int(pot.get("exp", 0))}
	return r

# 【新增】2026-09-16 药铺招牌：道具恢复病人，不受自然上限限制（同医馆病人手册/精力丹口径）
func add_stamina(n: int):
	stamina += n

# ============ 收益罐（无上限，手动领取统一入账） ============
func get_pot() -> Dictionary:
	return pot

func has_pot() -> bool:
	if int(pot.get("coins", 0)) > 0 or int(pot.get("exp", 0)) > 0:
		return true
	for rid in pot.get("prof", {}):
		if int(pot["prof"][rid]) > 0:
			return true
	return false

# 领取收益罐：铜板→货币；药铺经验→勋章累计（只增不减）；熟练度→对应药方池
func collect_pot() -> Dictionary:
	var r := {"coins": int(pot.get("coins", 0)), "exp": int(pot.get("exp", 0)),
		"prof": (pot.get("prof", {}) as Dictionary).duplicate()}
	coins += r["coins"]
	exp_total += r["exp"]   # 累计进度独立记账：只加不减，不扣消耗池
	for rid in r["prof"]:
		if recipes.has(rid):
			recipes[rid]["prof"] = get_recipe_prof(rid) + int(r["prof"][rid])
	pot = {"coins": 0, "exp": 0, "prof": {}}
	return r

# ============ 药方 ============
func get_recipe_level(rid: String) -> int:
	if not recipes.has(rid):
		return 1
	return clampi(int(recipes[rid].get("lv", 1)), 1, get_recipe_max_level())

# 药方自有熟练度池（领取收益罐后入账的部分）
func get_recipe_prof(rid: String) -> int:
	if not recipes.has(rid):
		return 0
	return int(recipes[rid].get("prof", 0))

func is_recipe_unlocked(rid: String) -> bool:
	if not recipes.has(rid):
		return false
	return bool(recipes[rid].get("unlocked", false))

# 第k张药方解锁需累计药铺经验 ≥ 3000×(k-1)²（按配置顺序，k=1初始解锁）
func get_recipe_unlock_need(rid: String) -> int:
	var idx := 0
	for r in _cfg().get("recipes", []):
		idx += 1
		if str(r.get("id", "")) == rid:
			break
	var base: int = int(_st().get("unlock_exp_base", 3000))
	return base * (idx - 1) * (idx - 1)

func can_unlock_recipe(rid: String) -> Dictionary:
	if is_recipe_unlocked(rid):
		return {"ok": false, "msg": "药方已解锁"}
	if exp_total < get_recipe_unlock_need(rid):
		return {"ok": false, "msg": "累计药铺经验不足"}
	return {"ok": true}

# 手动点击解锁（不消耗经验）
func unlock_recipe(rid: String) -> Dictionary:
	var chk := can_unlock_recipe(rid)
	if not chk.get("ok", false):
		return chk
	if not recipes.has(rid):
		recipes[rid] = {"lv": 1, "prof": 0, "unlocked": true}
	else:
		recipes[rid]["unlocked"] = true
	return {"ok": true}

# 已解锁药方池（接待均匀随机从这里抽）
func get_unlocked_recipes() -> Array:
	var pool := []
	for r in _cfg().get("recipes", []):
		if is_recipe_unlocked(str(r.get("id", ""))):
			pool.append(r)
	return pool

# 全部药方（UI 列表，配置顺序=解锁顺序）
func get_recipe_list() -> Array:
	return _cfg().get("recipes", [])

# 售价(lv) = round(基础售价 × 1.04^(lv-1))，四舍五入
func get_recipe_price(rid: String) -> int:
	var rc := get_recipe_cfg(rid)
	if rc.is_empty():
		return 0
	return int(round(float(rc.get("base_price", 0)) * pow(1.04, get_recipe_level(rid) - 1)))

# 药方升级消耗熟练度：cost(lv) = 500×lv²（lv=当前等级；满级不可升）
func get_recipe_upgrade_cost(rid: String) -> int:
	var lv := get_recipe_level(rid)
	if lv >= get_recipe_max_level():
		return 0
	return int(500 * lv * lv)

func upgrade_recipe(rid: String, batch: bool = false) -> Dictionary:
	if not is_recipe_unlocked(rid):
		return {"ok": false, "msg": "药方未解锁"}
	if not recipes.has(rid):
		recipes[rid] = {"lv": 1, "prof": 0, "unlocked": true}
	var up := 0
	while get_recipe_level(rid) < get_recipe_max_level() and get_recipe_prof(rid) >= get_recipe_upgrade_cost(rid):
		recipes[rid]["prof"] = get_recipe_prof(rid) - get_recipe_upgrade_cost(rid)
		recipes[rid]["lv"] = get_recipe_level(rid) + 1
		up += 1
		if not batch:
			break
	if up <= 0:
		return {"ok": false, "msg": "熟练度不足"}
	return {"ok": true, "up": up}

# ============ 工艺（铜板升级；固定值层伙计赚速，shop_system 店员层接入） ============
func get_craft_level(cid: String) -> int:
	return int(crafts.get(cid, 0))

# 升级消耗（铜板）：2500×(⌊当前等级/10⌋+1)，每10级一档（当前0~9级→2500，10~19→5000……）
func get_craft_cost(cid: String) -> int:
	var base: int = int(_st().get("craft_cost_base", 2500))
	var per: int = int(_st().get("craft_cost_per_tier", 10))
	return base * (floori(float(get_craft_level(cid)) / per) + 1)

func can_upgrade_craft(cid: String) -> Dictionary:
	if coins < get_craft_cost(cid):
		return {"ok": false, "msg": "铜板不足"}
	return {"ok": true}

func upgrade_craft(cid: String) -> Dictionary:
	var chk := can_upgrade_craft(cid)
	if not chk.get("ok", false):
		return chk
	coins -= get_craft_cost(cid)
	crafts[cid] = get_craft_level(cid) + 1
	return {"ok": true}

# 全部升级：7项工艺各升1级，铜板不足的项跳过；返回成功项数
func upgrade_all_crafts() -> Dictionary:
	var up := 0
	for c in _cfg().get("crafts", []):
		var cid: String = str(c.get("id", ""))
		if cid == "":
			continue
		if upgrade_craft(cid).get("ok", false):
			up += 1
	return {"ok": true, "up": up}

func get_craft_list() -> Array:
	return _cfg().get("crafts", [])

# 工艺总等级（成就进度用）
func get_craft_total_level() -> int:
	var total := 0
	for cid in crafts:
		total += int(crafts[cid])
	return total

# 某店铺类目（士/农/工/商/侠）的伙计赚速固定加成：
# 洗药/晒药（全体）每级+per_level，对应职业工艺每级+per_level；全部固定值相加
func get_craft_staff_bonus(category: String) -> float:
	var total := 0.0
	for c in _cfg().get("crafts", []):
		var target: String = str(c.get("target", ""))
		if target != "all" and target != category:
			continue
		total += float(c.get("per_level", 0.0)) * get_craft_level(str(c.get("id", "")))
	return total

# ============ 勋章（15级手动升级；累计药铺经验只作门槛不消耗） ============
func get_medal_lv() -> int:
	return medal_lv

func _medal_cfg(lv: int) -> Dictionary:
	var arr: Array = _cfg().get("medals", [])
	if lv < 1 or lv > arr.size():
		return {}
	return arr[lv - 1]

func get_medal_name() -> String:
	return str(_medal_cfg(medal_lv).get("name", ""))

# 当前勋章全体商铺赚速加成（小数制：+100%=1.0）
func get_medal_shop_pct() -> float:
	return float(_medal_cfg(medal_lv).get("shop_pct", 0.0))

# 当前勋章精进技能等级上限加成（写入天赋解锁技能 max_level）
func get_refine_cap_bonus() -> int:
	return int(_medal_cfg(medal_lv).get("refine_cap", 0))

# 下一级勋章配置（满级返回空字典）
func get_next_medal_cfg() -> Dictionary:
	return _medal_cfg(medal_lv + 1)

func can_upgrade_medal() -> Dictionary:
	var nxt := get_next_medal_cfg()
	if nxt.is_empty():
		return {"ok": false, "msg": "已达满级"}
	if exp_total < int(nxt.get("need_exp", 0)):
		return {"ok": false, "msg": "累计药铺经验不足"}
	return {"ok": true}

# 手动升级勋章：校验累计经验达标（不消耗经验），精进上限差值写入天赋解锁技能
func upgrade_medal() -> Dictionary:
	var chk := can_upgrade_medal()
	if not chk.get("ok", false):
		return chk
	var old_cap := get_refine_cap_bonus()
	medal_lv += 1
	var new_cap := get_refine_cap_bonus()
	# 差值写入天赋解锁技能等级上限（写入式：升级判定/UI 显示读 sk.max_level 自动生效）
	if g.talent_system != null and new_cap > old_cap:
		g.talent_system.apply_skill_cap_delta(new_cap - old_cap)
	return {"ok": true}

# ============ 药铺成就（3条线 × 4档） ============
# 各线当前进度值
func get_ach_progress(line_id: String) -> int:
	match line_id:
		"formula_lv":
			var total := 0
			for rid in recipes:
				total += get_recipe_level(rid)
			return total
		"craft_lv":
			return get_craft_total_level()
		"patients":
			return patients_total
	return 0

func get_ach_list() -> Array:
	return _cfg().get("achievements", [])

func get_ach_claimed(line_id: String) -> int:
	return int(ach.get(line_id, 0))

# 该档是否可领取（进度达标且未领取过）
func can_claim_ach(line_id: String, tier_idx: int) -> bool:
	if tier_idx < get_ach_claimed(line_id):
		return false
	for line in get_ach_list():
		if str(line.get("id", "")) != line_id:
			continue
		var tiers: Array = line.get("tiers", [])
		if tier_idx >= tiers.size():
			return false
		return get_ach_progress(line_id) >= int(tiers[tier_idx].get("need", 0))
	return false

# 领取成就档奖励：道具走背包入账通道，按档幂等（已领取的档跳过）
func claim_ach(line_id: String, tier_idx: int) -> Dictionary:
	if not can_claim_ach(line_id, tier_idx):
		return {"ok": false, "msg": "未达到领取条件"}
	for line in get_ach_list():
		if str(line.get("id", "")) != line_id:
			continue
		var tiers: Array = line.get("tiers", [])
		if tier_idx >= tiers.size():
			return {"ok": false, "msg": "奖励不存在"}
		var rewards: Array = tiers[tier_idx].get("rewards", [])
		var parts := []
		for r in rewards:
			var iid: String = str(r.get("item", ""))
			var n: int = int(r.get("count", 0))
			if iid == "" or n <= 0:
				continue
			g.items[iid] = int(g.items.get(iid, 0)) + n
			var iname: String = g.ITEM_CONFIG.get(iid, {}).get("name", iid)
			parts.append("%s×%d" % [iname, n])
		ach[line_id] = max(get_ach_claimed(line_id), tier_idx + 1)
		return {"ok": true, "rewards": "、".join(parts)}
	return {"ok": false, "msg": "奖励不存在"}
