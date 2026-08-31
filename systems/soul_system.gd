# ============================================================
# 兽魂系统（2026-08-30 新增：珍兽魂盘 + 魂石镶嵌）
# 纯逻辑模块：魂石仓库统一存 GameData 中枢（g.soul_stones），魂盘数据存珍兽实例 instance["soul"]
# 配置外置 res://data/soulstones.json（g._soul_configs）
# 规则要点：
#   魂盘5×5共25格，初始解锁正中3×3；额格外解锁消耗五色石=当前魂盘等级×5
#   魂盘等级按已解锁格数阶梯（10格2级/13格3级/18格4级/25格5级）；容量=3+(等级-1)块
#   魂石4品质：优秀1格/卓越2格/传奇3格/无双4格；形状生成时随机，放置不旋转/不重叠/限已解锁格
#   每格随机颜色（士/农/工/商/侠）+ 词条资质（优秀1-10/卓越5-15/传奇10-20/无双15-25）
#   激发：格颜色==该兽装备门客的职业 → 该格 赚钱+（按魂盘等级3/5/10/15/20%）+ 词条资质生效；不激发只占位
#   重置：取下全部魂石回仓库、额格外上锁、按 spent 全退五色石
#   重塑：同品质2块 → 概率升品（优秀40%/卓越20%/传奇10%），失败同品质全重随；无双不可重塑
# ============================================================
class_name SoulSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免循环引用）
var g

# 五种职业色（显示色值在 soulstones.json 的 colors 段）
const COLORS = ["士", "农", "工", "商", "侠"]

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
func get_save_data() -> Dictionary:
	return {
		"soul_stones": g.soul_stones,         # 魂石仓库 {uid: {uid, quality, shape, cells:[{color,apt}]}}
		"soul_stone_seq": g.soul_stone_seq,   # 魂石uid自增序号
	}

# 从存档认领（老存档缺字段保持初始值，魂盘在 beasts 实例里由 beast_system 存档天然覆盖）
func load_save_data(s: Dictionary):
	if s.has("soul_stones"): g.soul_stones = s.soul_stones.duplicate(true)
	if s.has("soul_stone_seq"): g.soul_stone_seq = int(s.soul_stone_seq)

# ============ 配置读取 ============
func _settings() -> Dictionary:
	return g._soul_configs.get("settings", {})

# 品质对应形状库
func _shapes(quality: String) -> Array:
	return g._soul_configs.get("shapes", {}).get(quality, [[[0, 0]]])

# ============ 魂石生成 / 宝箱 ============
# 生成一块魂石入仓库：形状随机（不旋转）；每格颜色随机（same_color时全格同色，无双魂石箱用）；词条按品质范围随机
func gen_stone(quality: String, same_color: bool = false) -> Dictionary:
	var pool = _shapes(quality)
	var shape = pool[randi() % pool.size()]
	var rng: Array = _settings().get("apt_range", {}).get(quality, [1, 10])
	var fixed_color = COLORS[randi() % COLORS.size()]
	var cells = []
	for off in shape:
		var color = fixed_color if same_color else COLORS[randi() % COLORS.size()]
		cells.append({"color": color, "apt": randi_range(int(rng[0]), int(rng[1]))})
	g.soul_stone_seq += 1
	var uid = "ss%d" % g.soul_stone_seq
	g.soul_stones[uid] = {"uid": uid, "quality": quality, "shape": shape, "cells": cells}
	return g.soul_stones[uid]

# 开启宝箱：normal=魂石宝箱(随机优秀) / wushuang=无双魂石箱(四格同色无双)
func open_box(kind: String) -> Dictionary:
	if kind == "wushuang":
		return {"ok": true, "stone": gen_stone("无双", true)}
	return {"ok": true, "stone": gen_stone("优秀")}

# ============ 重塑 ============
# 同品质2块重塑：按 recast_up 概率升品，失败则同品质全重随（形状/颜色/词条）；盘中魂石不可重塑
func recast(uid1: String, uid2: String) -> Dictionary:
	if uid1 == uid2:
		return {"ok": false, "reason": "不能选同一块魂石"}
	if not g.soul_stones.has(uid1) or not g.soul_stones.has(uid2):
		return {"ok": false, "reason": "魂石不存在"}
	var q1: String = g.soul_stones[uid1].get("quality", "")
	if q1 != g.soul_stones[uid2].get("quality", ""):
		return {"ok": false, "reason": "品质不同不能重塑"}
	if q1 == "无双":
		return {"ok": false, "reason": "无双魂石不可重塑"}
	if _is_placed(uid1) or _is_placed(uid2):
		return {"ok": false, "reason": "请先把魂盘上的魂石取下"}
	var up_chance = float(_settings().get("recast_up", {}).get(q1, 0.0))
	var up_map = {"优秀": "卓越", "卓越": "传奇", "传奇": "无双"}
	var upgraded = randf() < up_chance
	var new_q: String = up_map[q1] if upgraded else q1
	g.soul_stones.erase(uid1)
	g.soul_stones.erase(uid2)
	var st = gen_stone(new_q, false)
	return {"ok": true, "upgraded": upgraded, "stone": st}

# ============ 魂盘（数据存珍兽实例 instance["soul"]） ============
# 取魂盘数据（首次访问自动初始化：unlocked=额外界格 / spent=已花五色石 / stones={uid:锚点格}）
func _get_board(beast_id: String, instance_index: int = 0) -> Dictionary:
	var inst = g.beast_system.get_beast_instance(beast_id, instance_index)
	if inst == null:
		return {}
	if not inst.has("soul") or not (inst["soul"] is Dictionary):
		inst["soul"] = {"unlocked": [], "spent": 0, "stones": {}}
	var soul: Dictionary = inst["soul"]
	if not soul.has("unlocked"): soul["unlocked"] = []
	if not soul.has("spent"): soul["spent"] = 0
	if not soul.has("stones"): soul["stones"] = {}
	return soul

# 全部已解锁格序号（初始正中3×3 + 额外界格）
func get_unlocked_cells(beast_id: String, instance_index: int = 0) -> Array:
	var cells: Array = []
	for ci in _settings().get("initial_cells", [6, 7, 8, 11, 12, 13, 16, 17, 18]):
		cells.append(int(ci))
	for ci in _get_board(beast_id, instance_index).get("unlocked", []):
		if not cells.has(int(ci)):
			cells.append(int(ci))
	return cells

# 魂盘等级：按已解锁格数查阶梯（10格2级/13格3级/18格4级/25格5级，否则1级）
func get_board_level(beast_id: String, instance_index: int = 0) -> int:
	var count = get_unlocked_cells(beast_id, instance_index).size()
	var lv = 1
	for k in _settings().get("level_thresholds", {"10": 2, "13": 3, "18": 4, "25": 5}).keys():
		if count >= int(k):
			lv = max(lv, int(_settings().level_thresholds[k]))
	return lv

# 可放置魂石数：3 + (等级-1)
func get_capacity(beast_id: String, instance_index: int = 0) -> int:
	return int(_settings().get("base_capacity", 3)) + get_board_level(beast_id, instance_index) - 1


# 【新增】满盘进度：covered=已放置魂石占用的格数，total=已解锁格数
# 放置校验保证不重叠且限已解锁格，故 covered 永远 ≤ total，covered==total 即填满
func get_fill_progress(beast_id: String, instance_index: int = 0) -> Dictionary:
	var total = get_unlocked_cells(beast_id, instance_index).size()
	var covered = 0
	for uid in _get_board(beast_id, instance_index).get("stones", {}).keys():
		covered += g.soul_stones.get(uid, {}).get("cells", []).size()
	return {"covered": covered, "total": total}

# 【新增】魂盘是否填满：所有已解锁格都被魂石占住（不要求颜色激发，占满即算）
func is_board_full(beast_id: String, instance_index: int = 0) -> bool:
	var p = get_fill_progress(beast_id, instance_index)
	return int(p.total) > 0 and int(p.covered) >= int(p.total)


# 解锁下一格的消耗：当前魂盘等级 × 5
func get_unlock_cost(beast_id: String, instance_index: int = 0) -> int:
	return get_board_level(beast_id, instance_index) * int(_settings().get("unlock_cost_per_level", 5))

# 解锁一格：扣五色石并累计 spent（重置时按此退还）
func unlock_cell(beast_id: String, instance_index: int, cell: int) -> Dictionary:
	if cell < 0 or cell >= 25:
		return {"ok": false, "reason": "格子无效"}
	if get_unlocked_cells(beast_id, instance_index).has(cell):
		return {"ok": false, "reason": "该格已解锁"}
	var cost = get_unlock_cost(beast_id, instance_index)
	if int(g.items.get("wuse_shi", 0)) < cost:
		return {"ok": false, "reason": "五色石不足（需要%d）" % cost}
	g.items["wuse_shi"] = int(g.items.get("wuse_shi", 0)) - cost
	var soul = _get_board(beast_id, instance_index)
	soul["unlocked"].append(cell)
	soul["spent"] = int(soul.get("spent", 0)) + cost
	return {"ok": true, "level": get_board_level(beast_id, instance_index)}

# 重置魂盘：取下全部魂石（只清放置，石头本体留仓库）、额外界格上锁、按 spent 全退五色石
func reset_board(beast_id: String, instance_index: int) -> Dictionary:
	var soul = _get_board(beast_id, instance_index)
	var refund = int(soul.get("spent", 0))
	soul["unlocked"] = []
	soul["spent"] = 0
	soul["stones"] = {}
	if refund > 0:
		g.items["wuse_shi"] = int(g.items.get("wuse_shi", 0)) + refund
	return {"ok": true, "refund": refund}

# ============ 放置 / 取下 ============
# 魂石锚定在 anchor 后的绝对格序号数组；出界返回空数组（非法）
func _stone_cells(stone: Dictionary, anchor: int) -> Array:
	var ax = anchor % 5
	@warning_ignore("integer_division")   # 【修】故意向下取整算行号，压制整数除法警告
	var ay = int(anchor / 5)
	var out = []
	for off in stone.get("shape", []):
		var x = ax + int(off[0])
		var y = ay + int(off[1])
		if x < 0 or x >= 5 or y < 0 or y >= 5:
			return []
		out.append(y * 5 + x)
	return out

# 某格被哪块魂石占着（返回uid，空格返回""）
func get_cell_stone(beast_id: String, instance_index: int, cell: int) -> String:
	var stones: Dictionary = _get_board(beast_id, instance_index).get("stones", {})
	for uid in stones.keys():
		if _stone_cells(g.soul_stones.get(uid, {}), int(stones[uid])).has(cell):
			return uid
	return ""

# 【新增】纯校验：该魂石以 anchor 放置是否合法（未在盘/容量/出界/未解锁/重叠），不改动数据
# 供界面拖放悬停/标绿实时查询；place_stone 内部也走它，保证两处判定永远一致
func can_place_stone(beast_id: String, instance_index: int, uid: String, anchor: int) -> Dictionary:
	if not g.soul_stones.has(uid):
		return {"ok": false, "reason": "魂石不存在"}
	if _is_placed(uid):
		return {"ok": false, "reason": "该魂石已在魂盘上"}
	var soul = _get_board(beast_id, instance_index)
	var stones: Dictionary = soul.get("stones", {})
	if stones.size() >= get_capacity(beast_id, instance_index):
		return {"ok": false, "reason": "魂石数量已达上限"}
	var cells = _stone_cells(g.soul_stones[uid], anchor)
	if cells.is_empty():
		return {"ok": false, "reason": "放不下（超出盘外）"}
	var unlocked = get_unlocked_cells(beast_id, instance_index)
	for ci in cells:
		if not unlocked.has(ci):
			return {"ok": false, "reason": "放不下（格子未解锁）"}
		if get_cell_stone(beast_id, instance_index, ci) != "":
			return {"ok": false, "reason": "放不下（与其他魂石重叠）"}
	return {"ok": true}

# 放置魂石：校验走 can_place_stone，通过后落子
func place_stone(beast_id: String, instance_index: int, uid: String, anchor: int) -> Dictionary:
	var chk = can_place_stone(beast_id, instance_index, uid, anchor)
	if not chk.get("ok", false):
		return chk
	_get_board(beast_id, instance_index).get("stones", {})[uid] = anchor
	return {"ok": true}

# 取下魂石（免费，石头回仓库）
func remove_stone(beast_id: String, instance_index: int, uid: String) -> Dictionary:
	_get_board(beast_id, instance_index).get("stones", {}).erase(uid)
	return {"ok": true}

# 魂石是否已放在某个魂盘上（扫全部珍兽实例）
func _is_placed(uid: String) -> bool:
	for bid in g.beasts.keys():
		var d = g.beasts[bid]
		var instances = d if d is Array else [d]
		for inst in instances:
			var soul = inst.get("soul", {})
			if soul is Dictionary and soul.get("stones", {}).has(uid):
				return true
	return false

# ============ 加成计算（供 HeroData 聚合，经 GameData 转发） ============
# 魂盘总加成：逐格检查激发（颜色==装备门客职业）；激发格 赚钱+按魂盘等级% + 词条资质
func get_board_bonus(beast_id: String, instance_index: int = 0) -> Dictionary:
	var res = {"percent": 0.0, "apt": 0, "inspired": 0}
	var inst = g.beast_system.get_beast_instance(beast_id, instance_index)
	if inst == null:
		return res
	var hero_id: String = inst.get("equipped_hero", "")
	if hero_id == "" or not g.heroes.has(hero_id):
		return res
	var category: String = g.get_hero_config(hero_id).get("category", "")
	if category == "":
		return res
	var lv = get_board_level(beast_id, instance_index)
	var pct = float(_settings().get("inspire_pct", {}).get(str(lv), 0.03))
	var stones: Dictionary = _get_board(beast_id, instance_index).get("stones", {})
	for uid in stones.keys():
		var cells_cfg: Array = g.soul_stones.get(uid, {}).get("cells", [])
		for cell in cells_cfg:
			if cell.get("color", "") != category:
				continue   # 颜色不匹配：只占位不生效
			res.percent += pct
			res.apt += int(cell.get("apt", 0))
			res.inspired += 1
	# 【新增】满盘光环：已解锁格被魂石全部填满时，按魂盘等级追加赚钱百分比
	# （配置 full_pct：1级5%/2级10%/3级15%/4级20%/5级30%，直接并入 percent）
	if is_board_full(beast_id, instance_index):
		res.percent += float(_settings().get("full_pct", {}).get(str(lv), 0.0))
	return res

# 门客维度的魂魂加成（找该门客装备的珍兽 → 其魂盘）
func get_hero_soul_percent(hero_id: String) -> float:
	if not g.heroes.has(hero_id): return 0.0
	var h = g.heroes[hero_id]
	var bid: String = h.get("equipped_beast", "")
	if bid == "": return 0.0
	return get_board_bonus(bid, int(h.get("equipped_beast_index", 0))).percent

func get_hero_soul_aptitude(hero_id: String) -> int:
	if not g.heroes.has(hero_id): return 0
	var h = g.heroes[hero_id]
	var bid: String = h.get("equipped_beast", "")
	if bid == "": return 0
	return int(get_board_bonus(bid, int(h.get("equipped_beast_index", 0))).apt)
