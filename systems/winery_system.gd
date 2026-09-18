# ============================================================
# 酒坊玩法系统（商铺地图 酒坊「▶」入口全屏页；2026-09-18 按酒坊设计方案 v1.0 定稿实现）
# 核心循环：三作坊五流程升级（耗酒艺值）→ 消耗材料酿造（产酒+酒香+酒艺）→ 酒香升勋章（全体商铺赚速）
#         → 名酒记养成（累计酿造瓶数升级，门客赚钱）→ 品酒（百业经验/交情/满意值→门客帖）→ 酒客故事交情领奖
# 即时结算制（同钱庄/促织，非队列制）：酿造/升级/品酒全部当场出结果，无后台节拍
# 货币线：酒艺值（酿造产出，升流程）｜酒香值（酿造产出，累计升勋章 15 级，只增不减）｜元宝（采买材料）
# 加成接线：①勋章全部商铺赚速%（shop_system 百分比层，同药铺勋章挂点）
#           ②流程对应职业商铺赚速+10%×级（读取式，shop_system 百分比层追加）
# 待接入（方案 §8 挂标记，勿动）：勋章 refine_cap 写入天赋 / 藏品对酒香加成 / 家具币挂点 / 6 种新道具效果
# 状态内部持有随 get_save_data 落盘（game_data 只注册系统+加载配置，零新字段，同 drugshop 惯例）
# ============================================================
class_name WinerySystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# ---------- 存档字段（内部持有） ----------
# 【改】2026-09-18 材料库存并入物品表 g.items（背包即库存；采买/初始赠送/酿造消耗/活动奖励统一走物品表）
var buy_ts: int = 0                # 本周周一 0 点时间戳（每周限购刷新基准）
var buys: Dictionary = {}          # material_id: 本周已购数量
var ws: Dictionary = {}            # workshop_id: {process_id: 等级}（五流程，初始全 1 级）
var jiuyi: int = 0                 # 酒艺值：酿造产出，升流程消耗（方案存档字段未列，【新增】补池）
var jiuxiang: int = 0              # 累计酒香值（只增不减：勋章升级进度，同药铺 exp_total）
var medal_lv: int = 1              # 勋章等级（1~15，初始 1 级）
var wines: Dictionary = {}         # wine_id: {lv, brewed, cnt}（lv=名酒记等级/brewed=累计酿造瓶数/cnt=当前瓶数【新增】）
var bonds: Dictionary = {}         # hero_id: {exp, claimed, satis}（交情累计/已领档/满意值）
var invited: String = ""           # 品酒邀请的门客 id（空=未邀请）
var auto_drink: bool = false       # 自动饮酒开关（按品质高→低喝光库存）

func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	# mat_migrated=旧档材料迁移标记（防读档重复叠加进物品表）
	return {"winery": {
		"mat_migrated": true, "buy_ts": buy_ts, "buys": buys,
		"ws": ws, "jiuyi": jiuyi, "jiuxiang": jiuxiang, "medal_lv": medal_lv,
		"wines": wines, "bonds": bonds, "invited": invited, "auto_drink": auto_drink}}

# 从扁平存档表认领本系统字段（旧档缺字段保持初始值）
# 新档（无 winery 段）：材料按 settings.init_materials 各送（方案 §3）
func load_save_data(s: Dictionary):
	var fresh: bool = not s.has("winery") or not (s.winery is Dictionary)
	if fresh:
		_init_state(true)
		return
	var d: Dictionary = s.winery
	# 旧档一次性迁移：winery.materials → g.items（items 先于系统读档，game_data 惯例成立）
	if d.has("materials") and not bool(d.get("mat_migrated", false)):
		var old_m: Dictionary = d.get("materials", {})
		for m in _cfg().get("materials", []):
			var mid: String = str(m.get("id", ""))
			if old_m.has(mid):
				g.items[mid] = int(g.items.get(mid, 0)) + int(old_m[mid])
	buy_ts = int(d.get("buy_ts", 0))
	buys = d.get("buys", {})
	if not (buys is Dictionary):
		buys = {}
	ws = d.get("ws", {})
	if not (ws is Dictionary):
		ws = {}
	jiuyi = int(d.get("jiuyi", 0))
	jiuxiang = int(d.get("jiuxiang", 0))
	medal_lv = clampi(int(d.get("medal_lv", 1)), 1, get_medal_count())
	wines = d.get("wines", {})
	if not (wines is Dictionary):
		wines = {}
	bonds = d.get("bonds", {})
	if not (bonds is Dictionary):
		bonds = {}
	invited = str(d.get("invited", ""))
	auto_drink = bool(d.get("auto_drink", false))
	_sync_buy()   # 上线先校准周限购（跨周直接重置）
	_init_state(false)

# 缺段/缺项补初始值：新档送初始材料；流程全 1 级；每酒初始 Lv.1/0 瓶
func _init_state(fresh: bool):
	if fresh:
		# 新档初始材料直接入物品表
		var init_n: int = int(_st().get("init_materials", 10))
		for m in _cfg().get("materials", []):
			var mid: String = str(m.get("id", ""))
			if mid != "" and int(g.items.get(mid, 0)) <= 0:
				g.items[mid] = init_n
	for w in _cfg().get("workshops", []):
		var wid: String = str(w.get("id", ""))
		if wid == "":
			continue
		if not ws.has(wid) or not (ws[wid] is Dictionary):
			ws[wid] = {}
		for p in w.get("processes", []):
			var pid: String = str(p.get("id", ""))
			if pid == "":
				continue
			ws[wid][pid] = clampi(int(ws[wid].get(pid, 1)), 1, get_process_max_lv())
	for wcfg in _cfg().get("wines", []):
		var wname: String = str(wcfg.get("id", ""))
		if wname == "":
			continue
		if not wines.has(wname) or not (wines[wname] is Dictionary):
			wines[wname] = {"lv": 1, "brewed": 0, "cnt": 0}
		else:
			var e: Dictionary = wines[wname]
			e["lv"] = clampi(int(e.get("lv", 1)), 1, int(_st().get("wine_max_lv", 100)))
			e["brewed"] = int(e.get("brewed", 0))
			e["cnt"] = int(e.get("cnt", 0))
			# spent 记账（2026-09-18 每级瓶数口径新增）；旧档无 spent：按"已酿即已耗"迁移，不多扣不重领
			if e.has("spent"):
				e["spent"] = int(e["spent"])
			else:
				e["spent"] = int(e["brewed"])

# ============ 配置快捷读 ============
func _cfg() -> Dictionary:
	return g._winery_configs

func _st() -> Dictionary:
	return _cfg().get("settings", {})

func get_process_max_lv() -> int:
	return int(_st().get("process_max_lv", 9))

func get_medal_count() -> int:
	return _cfg().get("medals", []).size()

# ============ 材料与采买（100 元宝/个，每种每周限购 15，每周一刷新） ============
# 材料合法性校验（对配置表，不再依赖内部库存字典）
func _is_material(mid: String) -> bool:
	for m in _cfg().get("materials", []):
		if str(m.get("id", "")) == mid:
			return true
	return false

func get_materials() -> Dictionary:
	var d := {}
	for m in _cfg().get("materials", []):
		var mid: String = str(m.get("id", ""))
		d[mid] = int(g.items.get(mid, 0))
	return d

func get_material(mid: String) -> int:
	return int(g.items.get(mid, 0))

# 本周周一 0 点时间戳（UTC+8 口径，同档案踩坑 25 手动 +8×3600）
func _cur_week_monday() -> int:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var midnight: int = int(Time.get_unix_time_from_system()) + 8 * 3600
	midnight -= int(dt.get("hour", 0)) * 3600 + int(dt.get("minute", 0)) * 60 + int(dt.get("second", 0))
	var dow: int = int(dt.get("weekday", 1))   # 0=周日 1=周一 … 6=周六
	var since_monday: int = (dow + 6) % 7
	return midnight - since_monday * 86400 - 8 * 3600

# 上线/购买前校准：跨周清空本周已购
func _sync_buy():
	var cur: int = _cur_week_monday()
	if buy_ts < cur:
		buy_ts = cur
		buys = {}

func get_buy_left(mid: String) -> int:
	_sync_buy()
	return max(0, int(_st().get("buy_weekly_limit", 15)) - int(buys.get(mid, 0)))

# 采买：扣元宝入库存，受每周限购约束
func buy_material(mid: String, n: int = 1) -> Dictionary:
	_sync_buy()
	if not _is_material(mid):
		return {"ok": false, "msg": "材料不存在"}
	if n <= 0:
		return {"ok": false, "msg": "数量非法"}
	if n > get_buy_left(mid):
		return {"ok": false, "msg": "本周限购已达上限"}
	var cost: int = int(_st().get("buy_price", 100)) * n
	if g.yuanbao < cost:
		return {"ok": false, "msg": "元宝不足"}
	g.yuanbao -= cost
	g.items[mid] = get_material(mid) + n
	buys[mid] = int(buys.get(mid, 0)) + n
	return {"ok": true, "cost": cost}

# ============ 三作坊五流程（耗酒艺值升级；同步升级=一键拉平） ============
func get_workshop_list() -> Array:
	return _cfg().get("workshops", [])

func get_workshop_cfg(wid: String) -> Dictionary:
	for w in _cfg().get("workshops", []):
		if str(w.get("id", "")) == wid:
			return w
	return {}

func get_process_lv(wid: String, pid: String) -> int:
	if not ws.has(wid):
		return 1
	return clampi(int(ws[wid].get(pid, 1)), 1, get_process_max_lv())

# 该坊五流程等级之和 S（品质概率与产出的基数）
func get_workshop_S(wid: String) -> int:
	var total := 0
	var wcfg: Dictionary = get_workshop_cfg(wid)
	for p in wcfg.get("processes", []):
		total += get_process_lv(wid, str(p.get("id", "")))
	return total

# 升级消耗（酒艺值）：500 + 250×k×(k-1)，k=当前级（1→2=500 / 2→3=1000 / 3→4=2000 / 4→5=3500 / 5→6=5500 / 6→7=8000，逐档递增无上限；2026-09-18 用户拍板）
func get_process_cost(k: int) -> int:
	return int(_st().get("process_cost_base", 500)) + int(_st().get("process_cost_step", 250)) * k * (k - 1)

func get_process_upgrade_cost(wid: String, pid: String) -> int:
	if get_process_lv(wid, pid) >= get_process_max_lv():
		return 0
	return get_process_cost(get_process_lv(wid, pid))

func can_upgrade_process(wid: String, pid: String) -> Dictionary:
	if get_process_lv(wid, pid) >= get_process_max_lv():
		return {"ok": false, "msg": "已满级"}
	if jiuyi < get_process_upgrade_cost(wid, pid):
		return {"ok": false, "msg": "酒艺值不足"}
	return {"ok": true}

func upgrade_process(wid: String, pid: String) -> Dictionary:
	var chk := can_upgrade_process(wid, pid)
	if not chk.get("ok", false):
		return chk
	jiuyi -= get_process_upgrade_cost(wid, pid)
	ws[wid][pid] = get_process_lv(wid, pid) + 1
	return {"ok": true}

# 【同步升级】勾选：五流程一键拉平（每项各升 1 级循环，直到酒艺不足或全满）
func sync_upgrade_workshop(wid: String) -> Dictionary:
	var up := 0
	while true:
		var best_pid: String = ""
		var best_cost: int = -1
		for p in get_workshop_cfg(wid).get("processes", []):
			var pid: String = str(p.get("id", ""))
			if get_process_lv(wid, pid) >= get_process_max_lv():
				continue
			var c: int = get_process_upgrade_cost(wid, pid)
			if c <= jiuyi and (best_cost < 0 or c < best_cost):
				best_cost = c
				best_pid = pid
		if best_pid == "":
			break
		jiuyi -= best_cost
		ws[wid][best_pid] = get_process_lv(wid, best_pid) + 1
		up += 1
	if up <= 0:
		return {"ok": false, "msg": "酒艺值不足"}
	return {"ok": true, "up": up}

# 单次酿造产出：五流程 Σ（每级每流程 酒香/酒艺 各 +5×级）
func get_brew_output(wid: String) -> int:
	var per: int = int(_st().get("brew_output_per_lv", 5))
	var total := 0
	var wcfg: Dictionary = get_workshop_cfg(wid)
	for p in wcfg.get("processes", []):
		total += per * get_process_lv(wid, str(p.get("id", "")))
	return total

# 某职业商铺赚速加成（小数制）：全部作坊中该职业流程 Σ 等级 × 10%/级（读取式，配置为准）
func get_workshop_career_pct(career: String) -> float:
	var per: float = float(_st().get("career_pct_per_lv", 0.10))
	var total := 0.0
	for w in _cfg().get("workshops", []):
		var wid: String = str(w.get("id", ""))
		for p in w.get("processes", []):
			if str(p.get("career", "")) != career:
				continue
			total += per * get_process_lv(wid, str(p.get("id", "")))
	return total

# ============ 品质概率（锚点 S=45；S 每 +1 按 delta 平移，clamp≥0 归一化） ============
# 返回 5 档归一化权重数组 [普通,优秀,卓越,传奇,无双]
func get_quality_weights(wid: String) -> Array:
	var qa: Dictionary = _cfg().get("quality_anchor", {})
	var S: int = get_workshop_S(wid)
	var diff: int = S - int(qa.get("anchor_S", 45))
	var weights := []
	for q in range(1, 6):
		var base: float = float(qa.get("table", {}).get(str(q), 0.0))
		base += float(qa.get("delta", {}).get(str(q), 0.0)) * diff
		weights.append(max(0.0, base))
	var sum := 0.0
	for x in weights:
		sum += x
	if sum <= 0.0:
		return [1.0, 0.0, 0.0, 0.0, 0.0]
	for i in weights.size():
		weights[i] = weights[i] / sum
	return weights

# 按权重 roll 一档品质（1~5），返回品质序
func _roll_quality(wid: String) -> int:
	var weights: Array = get_quality_weights(wid)
	var r: float = randf()
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if r < acc:
			return i + 1
	return 1

# ============ 酿酒（1 材料=1 次；即时结算无动画；滑杆批量 1~库存） ============
# 产出：按对应坊概率出 1 瓶酒（该材料对应 5 酒中匹配品质的一瓶）+ 酒香/酒艺（=该坊五流程产出和）
func brew(mid: String, n: int = 1) -> Dictionary:
	if not _is_material(mid):
		return {"ok": false, "msg": "材料不存在"}
	if n <= 0:
		return {"ok": false, "msg": "数量非法"}
	n = min(n, get_material(mid))
	if n <= 0:
		return {"ok": false, "msg": "材料不足"}
	# 材料所属作坊（materials 配置 id 与作坊 id 同构）
	var wid: String = mid
	var wcfg: Dictionary = get_workshop_cfg(wid)
	if wcfg.is_empty():
		return {"ok": false, "msg": "作坊不存在"}
	var output: int = get_brew_output(wid)
	var got: Dictionary = {}   # 品质序: 瓶数
	for i in n:
		var q: int = _roll_quality(wid)
		got[q] = int(got.get(q, 0)) + 1
		# 该材料该品质的酒入库存（wines 表 15 酒按 material+quality 唯一对应）
		for wc in _cfg().get("wines", []):
			if str(wc.get("material", "")) == mid and int(wc.get("quality", 0)) == q:
				var wid2: String = str(wc.get("id", ""))
				wines[wid2]["cnt"] = int(wines[wid2].get("cnt", 0)) + 1
				wines[wid2]["brewed"] = int(wines[wid2].get("brewed", 0)) + 1
				break
	g.items[mid] = get_material(mid) - n   # 消耗走物品表
	jiuxiang += output * n   # 累计酒香（勋章进度，只增不减）
	jiuyi += output * n      # 酒艺值入池（升流程）
	return {"ok": true, "n": n, "got": got, "jiuxiang": output * n, "jiuyi": output * n}

# 有可酿材料（地图/主页红点用；库存读物品表）
func has_brewable() -> bool:
	for m in _cfg().get("materials", []):
		if int(g.items.get(str(m.get("id", "")), 0)) > 0:
			return true
	return false

# ============ 勋章（15 级手动升级；累计酒香只作门槛不消耗，同药铺勋章范式） ============
func get_medal_lv() -> int:
	return medal_lv

func get_jiuxiang() -> int:
	return jiuxiang

func _medal_cfg(lv: int) -> Dictionary:
	var arr: Array = _cfg().get("medals", [])
	if lv < 1 or lv > arr.size():
		return {}
	return arr[lv - 1]

# 当前勋章全体商铺赚速加成（小数制：+100%=1.0）
func get_medal_shop_pct() -> float:
	return float(_medal_cfg(medal_lv).get("shop_pct", 0.0))

# 下一级勋章所需累计酒香（满级返回 -1）
func get_next_medal_need() -> int:
	var nxt: Dictionary = _medal_cfg(medal_lv + 1)
	if nxt.is_empty():
		return -1
	return int(nxt.get("need_jiuxiang", 0))

func can_upgrade_medal() -> Dictionary:
	if get_next_medal_need() < 0:
		return {"ok": false, "msg": "已达满级"}
	if jiuxiang < get_next_medal_need():
		return {"ok": false, "msg": "累计酒香不足"}
	return {"ok": true}

# 手动升级勋章；refine_cap 待接入（方案 §8 挂标记：等用户完善门客系统时仿 drugshop apply_skill_cap_delta 补）
func upgrade_medal() -> Dictionary:
	var chk := can_upgrade_medal()
	if not chk.get("ok", false):
		return chk
	medal_lv += 1
	return {"ok": true}

# ============ 名酒记（15 酒；升级消耗=累计酿造瓶数；门客赚钱公式见 get_wine_income） ============
func get_wine_list() -> Array:
	return _cfg().get("wines", [])

func get_wine_cfg(wine_id: String) -> Dictionary:
	for w in _cfg().get("wines", []):
		if str(w.get("id", "")) == wine_id:
			return w
	return {}

func _wine_entry(wine_id: String) -> Dictionary:
	if not wines.has(wine_id):
		wines[wine_id] = {"lv": 1, "brewed": 0, "cnt": 0}
	return wines[wine_id]

func get_wine_lv(wine_id: String) -> int:
	return clampi(int(_wine_entry(wine_id).get("lv", 1)), 1, int(_st().get("wine_max_lv", 100)))

func get_wine_cnt(wine_id: String) -> int:
	return int(_wine_entry(wine_id).get("cnt", 0))

func get_wine_brewed(wine_id: String) -> int:
	return int(_wine_entry(wine_id).get("brewed", 0))

# 本级升级所需瓶数（每级瓶数 = B×(1+floor((级-1)/36))，B=品质档倍率 无双1/传奇2/卓越3/优秀5/普通10）
# 【改】2026-09-18 用户拍板：增量口径（普通酒 1→2 级 10 瓶）；旧档已升过的级用 spent 补齐记账，不多扣
func get_wine_level_cost(wine_id: String) -> int:
	# 【修】Godot JSON 数字一律 float：str(5.0)="5.0" 会 miss 字符串键，必须 int() 归一再 str
	var B: int = int(_cfg().get("wine_quality_mult", {}).get(str(int(get_wine_cfg(wine_id).get("quality", 1))), 10))
	var div: int = int(_st().get("brew_step_div", 36))
	return B * (1 + int(floor(float(get_wine_lv(wine_id) - 1) / div)))

# 本级已积累瓶数（累计酿造 − 已消耗），绿字"还需酿造 X/Y 瓶"的 X
func get_wine_overplus(wine_id: String) -> int:
	return get_wine_brewed(wine_id) - int(_wine_entry(wine_id).get("spent", 0))

# 酒品信息绿字"还需酿造 X/Y 瓶"：Y=本级升级所需瓶数（满级 -1）
func get_wine_next_need(wine_id: String) -> int:
	if get_wine_lv(wine_id) >= int(_st().get("wine_max_lv", 100)):
		return -1
	return get_wine_level_cost(wine_id)

# 门客赚钱（方案 §5 截图公式）：品质序×10000 + 品质序×5000×(级−1)；接入 HeroData 方式待 batch3 定（写入式/读取式）
func get_wine_income(wine_id: String) -> int:
	var q: int = int(get_wine_cfg(wine_id).get("quality", 1))
	return q * int(_st().get("wine_income_base", 10000)) + q * int(_st().get("wine_income_per_lv", 5000)) * (get_wine_lv(wine_id) - 1)

func can_upgrade_wine(wine_id: String) -> Dictionary:
	if get_wine_lv(wine_id) >= int(_st().get("wine_max_lv", 100)):
		return {"ok": false, "msg": "已达满级"}
	if get_wine_overplus(wine_id) < get_wine_level_cost(wine_id):
		return {"ok": false, "msg": "酿造瓶数不足"}
	return {"ok": true}

# 升级名酒：消耗本级所需瓶数（spent 记账），不耗库存瓶数；batch=true 一键升满可升范围
func upgrade_wine(wine_id: String, batch: bool = false) -> Dictionary:
	var up := 0
	while can_upgrade_wine(wine_id).get("ok", false):
		var e: Dictionary = _wine_entry(wine_id)
		e["spent"] = int(e.get("spent", 0)) + get_wine_level_cost(wine_id)
		e["lv"] = get_wine_lv(wine_id) + 1
		up += 1
		if not batch:
			break
	if up <= 0:
		return {"ok": false, "msg": "酿造瓶数不足"}
	return {"ok": true, "up": up}

# ============ 品酒（消耗 1 瓶 → 百业经验×交情加成 / 交情 / 满意值） ============
func get_invited() -> String:
	return invited

func set_invited(hero_id: String) -> Dictionary:
	invited = hero_id
	return {"ok": true}

func get_auto_drink() -> bool:
	return auto_drink

func set_auto_drink(on: bool) -> Dictionary:
	auto_drink = on
	return {"ok": true}

# 门客交情条目（按需建档，空值合法）
func get_bond(hero_id: String) -> Dictionary:
	if not bonds.has(hero_id) or not (bonds[hero_id] is Dictionary):
		bonds[hero_id] = {"exp": 0, "claimed": 0, "satis": 0}
	return bonds[hero_id]

func get_bond_exp(hero_id: String) -> int:
	return int(get_bond(hero_id).get("exp", 0))

func get_bond_claimed(hero_id: String) -> int:
	return int(get_bond(hero_id).get("claimed", 0))

func get_bond_satis(hero_id: String) -> int:
	return int(get_bond(hero_id).get("satis", 0))

# 交情加成：百业经验收益 +min(交情×0.03%, 25%)（小数制）
func get_bond_bonus_pct(hero_id: String) -> float:
	var per: float = float(_st().get("bond_bonus_per_point", 0.0003))
	var cap: float = float(_st().get("bond_bonus_cap", 0.25))
	return min(get_bond_exp(hero_id) * per, cap)

# 点酒共饮：消耗 n 瓶 → 百业经验（吃交情加成，走 bank 入账口）/交情/满意值（满 1000 送门客帖循环）
func drink(hero_id: String, wine_id: String, n: int = 1) -> Dictionary:
	if invited == "" or invited != hero_id:
		return {"ok": false, "msg": "请先邀请门客"}
	var wc: Dictionary = get_wine_cfg(wine_id)
	if wc.is_empty():
		return {"ok": false, "msg": "酒不存在"}
	if n <= 0:
		return {"ok": false, "msg": "数量非法"}
	n = min(n, get_wine_cnt(wine_id))
	if n <= 0:
		return {"ok": false, "msg": "库存不足"}
	_wine_entry(wine_id)["cnt"] = get_wine_cnt(wine_id) - n
	var bonus: float = get_bond_bonus_pct(hero_id)
	var baiye_gain: int = int(round(float(wc.get("baiye", 0)) * (1.0 + bonus))) * n
	g.bank_system.add_baiye(hero_id, baiye_gain)
	var b: Dictionary = get_bond(hero_id)
	b["exp"] = get_bond_exp(hero_id) + int(wc.get("bond", 0)) * n
	b["satis"] = get_bond_satis(hero_id) + int(wc.get("satis", 0)) * n
	# 满意值满 1000 送 1 张门客帖并循环，不清门客（方案 §6）
	var loop: int = int(_st().get("satis_loop", 1000))
	var tokens: int = int(floor(float(b["satis"]) / loop))
	if tokens > 0:
		g.items["hero_token"] = int(g.items.get("hero_token", 0)) + tokens
		b["satis"] = int(b["satis"]) - tokens * loop
	return {"ok": true, "n": n, "baiye": baiye_gain,
		"bond": int(wc.get("bond", 0)) * n, "satis": int(wc.get("satis", 0)) * n, "tokens": tokens}

# 【自动饮酒】按列表顺序（品质高→低）自动喝光全部库存（暂定口径）
func auto_drink_all(hero_id: String) -> Dictionary:
	if invited == "":
		return {"ok": false, "msg": "请先邀请门客"}
	var order := []
	for wc in _cfg().get("wines", []):
		var wid3: String = str(wc.get("id", ""))
		if get_wine_cnt(wid3) > 0:
			order.append({"id": wid3, "q": int(wc.get("quality", 1))})
	order.sort_custom(func(a, b): return int(a["q"]) > int(b["q"]))
	var total := {"baiye": 0, "bond": 0, "satis": 0, "tokens": 0, "n": 0}
	for e in order:
		var r: Dictionary = drink(hero_id, str(e["id"]), get_wine_cnt(str(e["id"])))
		if r.get("ok", false):
			total["n"] += int(r.get("n", 0))
			for k in ["baiye", "bond", "satis", "tokens"]:
				total[k] = int(total[k]) + int(r.get(k, 0))
	if int(total["n"]) <= 0:
		return {"ok": false, "msg": "库存不足"}
	total["ok"] = true
	return total

# ============ 酒客故事（交情 ladder：全部已拥有门客独立进度，满 50 级） ============
# 等级成本（交情累计阈值）：1-5级 200/级；6-10级 400/级；≥11级 120×级−195/级（方案 §7 拟合）
func get_bond_threshold(lv: int) -> int:
	var total := 0
	for k in range(1, lv + 1):
		if k <= int(_st().get("bond_cost_early_lv", 5)):
			total += int(_st().get("bond_cost_early", 200))
		elif k <= int(_st().get("bond_cost_mid_lv", 10)):
			total += int(_st().get("bond_cost_mid", 400))
		else:
			total += int(_st().get("bond_cost_late_base", 120)) * k - int(_st().get("bond_cost_late_offset", 195))
	return total

# 由交情累计值反推当前等级（满级 50）
func get_bond_level(hero_id: String) -> int:
	# 【修】变量名 exp 撞内置函数 exp()（SHADOWED_GLOBAL_IDENTIFIER 警告），改名 bond_exp
	var bond_exp: int = get_bond_exp(hero_id)
	var lv := 0
	for k in range(1, int(_st().get("bond_max_lv", 50)) + 1):
		if bond_exp >= get_bond_threshold(k):
			lv = k
	return lv

# 档位名（方案 §7：不期而遇0-3/泛泛之交4-7/…/死生契阔39-50）
func get_bond_tier_name(hero_id: String) -> String:
	var lv: int = get_bond_level(hero_id)
	var name: String = ""
	for t in _cfg().get("bond_tier_names", []):
		if lv >= int(t.get("lv", 0)):
			name = str(t.get("name", ""))
	return name

# 下一级可领判定：已领档+1 的累计阈值达标
func can_claim_bond(hero_id: String) -> Dictionary:
	var next_lv: int = get_bond_claimed(hero_id) + 1
	if next_lv > int(_st().get("bond_max_lv", 50)):
		return {"ok": false, "msg": "奖励已全部领取"}
	if get_bond_exp(hero_id) < get_bond_threshold(next_lv):
		return {"ok": false, "msg": "交情不足"}
	return {"ok": true, "lv": next_lv}

# 发放一组奖励入背包，返回拼接文案（同药铺 _grant_rewards 范式；新道具占位期按 id 显名）
func _grant_rewards(rewards: Array) -> String:
	var parts := []
	for r in rewards:
		var iid: String = str(r.get("item", ""))
		var n: int = int(r.get("count", 0))
		if iid == "" or n <= 0:
			continue
		g.items[iid] = int(g.items.get(iid, 0)) + n
		var iname: String = g.ITEM_CONFIG.get(iid, {}).get("name", iid)
		parts.append("%s×%d" % [iname, n])
	return "、".join(parts)

# 领取该门客下一档奖励：1-2 件道具 + 声望卡（30 级起高级）+ 每 5 级家具币
func claim_bond(hero_id: String) -> Dictionary:
	var chk := can_claim_bond(hero_id)
	if not chk.get("ok", false):
		return chk
	var lv: int = int(chk.get("lv", 0))
	var rewards: Array = _cfg().get("bond_rewards", [])
	if lv < 1 or lv > rewards.size():
		return {"ok": false, "msg": "奖励不存在"}
	var rc: Dictionary = rewards[lv - 1]
	var b: Dictionary = get_bond(hero_id)
	b["claimed"] = lv
	var got: Array = []
	var items_txt: String = _grant_rewards(rc.get("items", []))
	if items_txt != "":
		got.append(items_txt)
	var rep_n: int = int(rc.get("rep", 0))
	if rep_n > 0:
		var rep_id: String = "reputation_card_adv" if bool(rc.get("rep_adv", false)) else "reputation_card"
		g.items[rep_id] = int(g.items.get(rep_id, 0)) + rep_n
		got.append("%s×%d" % [g.ITEM_CONFIG.get(rep_id, {}).get("name", rep_id), rep_n])
	var fur_n: int = int(rc.get("furniture", 0))
	if fur_n > 0:
		g.items["jiajibi"] = int(g.items.get("jiajibi", 0)) + fur_n
		got.append("家具币×%d" % fur_n)
	return {"ok": true, "lv": lv, "rewards": "、".join(got)}

# ============ 红点判定 ============
# 有任意流程可升（酒艺值够任意一流程下级）
func has_upgradeable_process() -> bool:
	for w in _cfg().get("workshops", []):
		var wid: String = str(w.get("id", ""))
		for p in w.get("processes", []):
			if can_upgrade_process(wid, str(p.get("id", ""))).get("ok", false):
				return true
	return false

# 有门客可领交情奖励
func has_claimable_bond() -> bool:
	for hid in g.heroes:
		if can_claim_bond(str(hid)).get("ok", false):
			return true
	return false

# 有可领门客帖的满档满意值（品酒入口提示）
func has_satis_loop_ready() -> bool:
	for hid in bonds:
		if get_bond_satis(str(hid)) >= int(_st().get("satis_loop", 1000)):
			return true
	return false

# 某职业门客的名酒记固定赚速：该职业绑定酒的 Σ（品质序×10000 + 品质序×5000×(级-1)）
# 读取式（hero_data.get_extra_income 职业行挂点，同客栈菜谱/促织培育范式；2026-09-18 用户拍板按职业接入）
func get_career_wine_income(career: String) -> int:
	var total := 0
	for wc in _cfg().get("wines", []):
		if str(wc.get("career", "")) != career:
			continue
		total += get_wine_income(str(wc.get("id", "")))
	return total
