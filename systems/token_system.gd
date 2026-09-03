# ============================================================
# 信物系统：特殊门客晋升传奇时获得专属信物（李白→青锋剑·雷霆净世）
# 信物技能等级 = 信物等级：每级固定消耗专属道具，给信物主人和
# 已绑定羁绊门客各加 aptitude_per_level 资质（无上限）
# 羁绊绑定：bind_unlock_levels[0] 级绑第1个，[1] 级绑第2个（上限2个）
#   绑定后：该门客赚钱 +bind_income_pct；主人资质 += 绑定门客总资质 × owner_aptitude_share（每个各算）
# 纯逻辑模块：状态经 g 共享中枢；配置在 res://data/tokens.json（按 hero_id 索引）
# ============================================================
class_name TokenSystem
extends RefCounted

var g   # GameData 中枢引用（不标类型避免循环引用）

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 信物存档：{hero_id: {"level": 技能等级, "binds": [羁绊门客id, 羁绊门客id]}}
func get_save_data() -> Dictionary:
	return {"hero_tokens": g.hero_tokens}

func load_save_data(s: Dictionary):
	# 类型防御：旧档/异常档缺字段或为 null 时保持初始空表
	if s.has("hero_tokens") and s.hero_tokens is Dictionary:
		g.hero_tokens = s.hero_tokens.duplicate(true)

# ============ 配置查询 ============
# 某门客的信物配置（无则空字典；tokens.json 顶层 "tokens" 段按 hero_id 索引）
func get_token_cfg(hero_id: String) -> Dictionary:
	return g._token_configs.get("tokens", {}).get(hero_id, {})

# ============ 拥有判定 ============
# 是否已获得信物：配置了信物 且 门客品质达到获得线（grant_quality，1=传奇）
# （李白赋诗 tiers threshold 5 → quality 1，即赋诗5级晋升传奇时获得）
func has_token(hero_id: String) -> bool:
	var cfg = get_token_cfg(hero_id)
	if cfg.is_empty() or not g.heroes.has(hero_id): return false
	return int(g.heroes[hero_id].get("quality", 0)) >= int(cfg.get("grant_quality", 1))

# ============ 状态 ============
# 取信物状态（等级/绑定），无记录则惰性初始化（条目仅在升级/绑定时实质写入存档）
func _get_state(hero_id: String) -> Dictionary:
	if not g.hero_tokens.has(hero_id):
		g.hero_tokens[hero_id] = {"level": 0, "binds": ["", ""]}
	return g.hero_tokens[hero_id]

# 信物技能当前等级（= 信物等级）
func get_level(hero_id: String) -> int:
	return int(_get_state(hero_id).get("level", 0))

# 第 idx 个绑定格是否已解锁（技能等级达到配置门槛）
func is_bind_unlocked(hero_id: String, idx: int) -> bool:
	var unlocks: Array = get_token_cfg(hero_id).get("bind_unlock_levels", [0])
	if idx < 0 or idx >= unlocks.size(): return false
	return get_level(hero_id) >= int(unlocks[idx])

# 绑定列表 ["", ""]（空串=该格未绑定）
func get_binds(hero_id: String) -> Array:
	return _get_state(hero_id).get("binds", ["", ""])

# ============ 升级（信物技能） ============
# 升级信物技能：每级固定消耗 cost_per_level 个专属道具，无上限
# batch=true 十连；道具不足时按实际可升级数结算，返回实际升级级数
func upgrade(hero_id: String, batch: bool = false) -> int:
	var cfg = get_token_cfg(hero_id)
	if cfg.is_empty(): return 0
	var cost_per = int(cfg.get("cost_per_level", 600))
	var item_id: String = cfg.get("cost_item", "")
	var times = 10 if batch else 1
	var have = g.items.get(item_id, 0)
	var can = min(times, int(have / cost_per))   # 无上限，能升多少升多少
	if can <= 0: return 0
	g.items[item_id] = have - can * cost_per
	var state = _get_state(hero_id)
	state.level = int(state.get("level", 0)) + can
	return can

# 升级按钮文本：单级/十连理论消耗（与实际扣费同口径）
func get_upgrade_btn_text(hero_id: String, batch: bool) -> String:
	var cost_per = int(get_token_cfg(hero_id).get("cost_per_level", 600))
	if batch:
		return "十连\n%d" % (cost_per * 10)
	return "升级\n%d" % cost_per

# ============ 羁绊绑定 ============
# 绑定羁绊门客到第 idx 格：不能绑自己 / 未拥有 / 已在其他格绑定
func bind_hero(hero_id: String, idx: int, target: String) -> Dictionary:
	if not has_token(hero_id): return {"ok": false, "msg": "未获得信物"}
	if not is_bind_unlocked(hero_id, idx): return {"ok": false, "msg": "绑定格未解锁"}
	if target == hero_id: return {"ok": false, "msg": "不能绑定自己"}
	if not g.heroes.has(target): return {"ok": false, "msg": "门客不存在"}
	if get_binds(hero_id).has(target): return {"ok": false, "msg": "该门客已绑定"}
	_get_state(hero_id).binds[idx] = target
	return {"ok": true}

# 解绑第 idx 格（免费无消耗）
func unbind(hero_id: String, idx: int):
	var state = _get_state(hero_id)
	if idx >= 0 and idx < state.binds.size():
		state.binds[idx] = ""

# 可绑定的门客 id 列表：已拥有、非自己、未被本信物其他格绑定（选择器用）
func get_bindable_heroes(hero_id: String) -> Array:
	var result = []
	var binds = get_binds(hero_id)
	for hid in g.heroes.keys():
		if hid == hero_id or binds.has(hid): continue
		result.append(hid)
	return result

# ============ 加成计算（HeroData 聚合唯一入口调用） ============
# 信物主人资质加成 = 技能等级×每级资质 + Σ(每个绑定门客总资质 × owner_aptitude_share)
# 【注意】这里反查绑定门客的总资质会回调 HeroData.get_total_aptitude，深度恒为1
# （普通门客无信物递归项）。将来若新增第二个信物门客，严禁两个信物门客互绑，否则死循环
func get_owner_aptitude(hero_id: String) -> int:
	if not has_token(hero_id): return 0
	var cfg = get_token_cfg(hero_id)
	var apt = get_level(hero_id) * int(cfg.get("aptitude_per_level", 3))
	var share = float(cfg.get("owner_aptitude_share", 0.01))
	for target in get_binds(hero_id):
		if target != "" and g.heroes.has(target):
			apt += int(HeroData.get_total_aptitude(g, target) * share)
	return apt

# 门客作为"被绑定者"获得的资质 = 主人的信物等级 × 每级资质
func get_bound_aptitude(hero_id: String) -> int:
	for owner_id in g.hero_tokens.keys():
		if not has_token(owner_id): continue
		var cfg = get_token_cfg(owner_id)
		if cfg.is_empty(): continue
		if get_binds(owner_id).has(hero_id):
			return get_level(owner_id) * int(cfg.get("aptitude_per_level", 3))
	return 0

# 门客作为"被绑定者"获得的赚钱百分比（固定 bind_income_pct）
func get_bound_income_pct(hero_id: String) -> float:
	for owner_id in g.hero_tokens.keys():
		if not has_token(owner_id): continue
		var cfg = get_token_cfg(owner_id)
		if cfg.is_empty(): continue
		if get_binds(owner_id).has(hero_id):
			return float(cfg.get("bind_income_pct", 0.10))
	return 0.0
