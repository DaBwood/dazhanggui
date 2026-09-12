# ============================================================
# 客栈玩法系统（商铺地图化批次3：营业 / 菜谱 / 庖丁解牛 / 兑换商店）
# 纯逻辑模块：状态内部持有，经 get_save_data/load_save_data 落盘（game_data 只接线）
# 规则（档案三十六节② + 2026-09-12 用户拍板）：
#   营业：1 个灶位；【开始营业】→ 选门客（职业决定菜品）→ 选食材包+数量 →【烹饪】，每次消耗 1 个食材包
#         时长两两分组 300/480/600/780/900 秒；懒结算离线照走，完成收益进「收益罐」（厨艺值+交子+烹饪次数），点领取入账
#         轮班加成=当日职业收益×2（周一士~周五侠，周末全职业）
#   菜谱：每道菜（食材包×职业，共50道）独立等级，用烹饪次数升级
#         L→L+1 需 ceil(L/10) 次（1~10级每级1次，每10级+1次需求）
#         每级给同职业门客固定赚钱 500×本次升级所需烹饪次数（累加制）
#   厨艺值：产出后存本系统；由 side_skill_system 副业「庖丁解牛」消耗（每门客独立等级，上限300）
#   兑换商店：交子货币、无限购；碎片类可合成（残帖10合1门客帖 / 印碎片20合1令）
# ============================================================
class_name InnSystem
extends RefCounted

# GameData 中枢引用（不标类型，避免类之间循环引用导致解析失败）
var g

func _init(p_g):
	g = p_g

# ============ 存档（本系统持有的字段） ============
var cooking: Dictionary = {}     # 灶位 {pack_id, career, hero_id, count, start_time}（count=剩余次数）
var cuisine: int = 0             # 厨艺值（已领取；side_skill_system「庖丁解牛」升级货币，全局池）
var jiaozi: int = 0              # 交子（已领取；兑换商店货币）
var pending: Dictionary = {"cuisine": 0, "jiao": 0, "cooks": {}}   # 收益罐：待领取（厨艺/交子/烹饪次数{"pack_id|职业": n}）
var dish_cooks: Dictionary = {}  # 每道菜累计烹饪次数 {"pack_id|职业": n}

func get_save_data() -> Dictionary:
	return {
		"inn_cooking": cooking,
		"inn_cuisine": cuisine,
		"inn_jiaozi": jiaozi,
		"inn_pending": pending,
		"inn_dish_cooks": dish_cooks,
	}

# 从扁平存档表认领本系统字段（老档缺字段保持初始值，类型防御防一处崩整轮）
func load_save_data(s: Dictionary):
	if s.has("inn_cooking") and s.inn_cooking is Dictionary: cooking = s.inn_cooking
	if s.has("inn_cuisine"): cuisine = int(s.inn_cuisine)
	if s.has("inn_jiaozi"): jiaozi = int(s.inn_jiaozi)
	if s.has("inn_pending") and s.inn_pending is Dictionary: pending = s.inn_pending
	if s.has("inn_dish_cooks") and s.inn_dish_cooks is Dictionary: dish_cooks = s.inn_dish_cooks

# ============ 配置读取（inn.json，代码默认值兜底） ============
func _st() -> Dictionary:
	return g._inn_configs.get("settings", {})

func get_careers() -> Array:
	return g._inn_configs.get("careers", ["士", "农", "工", "商", "侠"])

func get_packs() -> Array:
	return g._inn_configs.get("packs", [])

func get_pack(pack_id: String) -> Dictionary:
	for pack in get_packs():
		if str(pack.get("id", "")) == pack_id: return pack
	return {}

func get_exchange_list() -> Array:
	return g._inn_configs.get("exchange", [])

func get_dish_name(pack: Dictionary, career: String) -> String:
	var dishes: Dictionary = pack.get("dishes", {})
	return str(dishes.get(career, ""))

# ============ 职业轮班（周一士~周五侠，周末全职业；Godot weekday：0=周日 … 6=周六） ============
func get_today_bonus_careers() -> Array:
	var map: Dictionary = g._inn_configs.get("weekday_bonus", {})
	var wd := int(Time.get_datetime_dict_from_system().get("weekday", 0))
	if map.has(str(wd)):
		return [str(map[str(wd)])]
	return get_careers()   # 周末全职业加成

func is_bonus_career(career: String) -> bool:
	return career in get_today_bonus_careers()

# ============ 营业（单灶位，懒结算） ============
func is_cooking() -> bool:
	return not cooking.is_empty()

func get_cuisine() -> int:
	return cuisine

func get_jiaozi() -> int:
	return jiaozi

# 开始营业：消耗 count 个食材包，按门客职业定菜，进入计时（营业中不可再开）
func start_cooking(pack_id: String, hero_id: String, count: int) -> bool:
	if not cooking.is_empty(): return false
	var pack := get_pack(pack_id)
	if pack.is_empty() or count <= 0: return false
	if not g.heroes.has(hero_id): return false
	var career := str(g.heroes[hero_id].get("category", ""))
	if get_dish_name(pack, career) == "": return false
	var item := str(pack.get("item", pack_id))
	if int(g.items.get(item, 0)) < count: return false
	g.items[item] = int(g.items.get(item, 0)) - count
	cooking = {"pack_id": pack_id, "career": career, "hero_id": hero_id,
		"count": count, "start_time": int(Time.get_unix_time_from_system())}
	return true

# 懒结算：把按包时长已完成的次数切出，收益存入收益罐（待领取），推进计时；返回本次结算次数
# 轮班×2 按结算时刻的当日判定（跨天完成的份额吃结算日加成）
func _settle() -> int:
	if cooking.is_empty(): return 0
	var pack := get_pack(str(cooking.get("pack_id", "")))
	if pack.is_empty():
		cooking = {}
		return 0
	var secs := maxi(1, int(pack.get("seconds", 300)))
	var now := int(Time.get_unix_time_from_system())
	var start := int(cooking.get("start_time", now))
	var done := mini(int(cooking.get("count", 0)), maxi(0, floori(float(now - start) / float(secs))))
	if done <= 0: return 0
	var career := str(cooking.get("career", ""))
	var mult := 2 if is_bonus_career(career) else 1
	pending["cuisine"] = int(pending.get("cuisine", 0)) + done * int(pack.get("cuisine", 0)) * mult
	pending["jiao"] = int(pending.get("jiao", 0)) + done * int(pack.get("jiao", 0)) * mult
	var key := str(cooking.get("pack_id", "")) + "|" + career
	var cooks: Dictionary = pending.get("cooks", {})
	cooks[key] = int(cooks.get(key, 0)) + done
	pending["cooks"] = cooks
	cooking["start_time"] = start + done * secs
	cooking["count"] = int(cooking.get("count", 0)) - done
	if int(cooking["count"]) <= 0:
		cooking = {}
	return done

# ============ 收益罐（营业收益待领取；领取才入账+累计菜谱） ============
func get_pending() -> Dictionary:
	return pending

func has_pending() -> bool:
	return int(pending.get("cuisine", 0)) > 0 or int(pending.get("jiao", 0)) > 0

# 领取收益罐：厨艺值/交子入账 + 烹饪次数累计进菜谱，返回入账明细 {"cuisine","jiao","cook_times"}
func claim() -> Dictionary:
	var out := {"cuisine": int(pending.get("cuisine", 0)), "jiao": int(pending.get("jiao", 0)), "cook_times": 0}
	var cooks: Dictionary = pending.get("cooks", {})
	for key in cooks.keys():
		dish_cooks[key] = int(dish_cooks.get(key, 0)) + int(cooks[key])
		out["cook_times"] += int(cooks[key])
	cuisine += int(pending.get("cuisine", 0))
	jiaozi += int(pending.get("jiao", 0))
	pending = {"cuisine": 0, "jiao": 0, "cooks": {}}
	return out

# 营业状态（查询即结算）：空闲 {"active":false}；营业中含菜名/进度/剩余
func get_status() -> Dictionary:
	var settled := _settle()
	if cooking.is_empty():
		return {"active": false, "settled": settled}
	var pack := get_pack(str(cooking.get("pack_id", "")))
	var secs := maxi(1, int(pack.get("seconds", 300)))
	var now := int(Time.get_unix_time_from_system())
	var career := str(cooking.get("career", ""))
	var into := clampi(now - int(cooking.get("start_time", now)), 0, secs)
	return {
		"active": true, "settled": settled,
		"dish": get_dish_name(pack, career), "pack_name": str(pack.get("name", "")),
		"career": career, "hero_id": str(cooking.get("hero_id", "")),
		"count_left": int(cooking.get("count", 0)),
		"into": into, "secs": secs,
		"remain_total": int(cooking.get("count", 0)) * secs - into,
		"bonus": is_bonus_career(career),
	}

# ============ 菜谱（每道菜独立等级，烹饪次数升级） ============
func get_dish_cooks(pack_id: String, career: String) -> int:
	return int(dish_cooks.get(pack_id + "|" + career, 0))

# L→L+1 所需烹饪次数：1~10级=1次，11~20级=2次……（每10级+1）
func get_dish_need(level: int) -> int:
	return int(ceil(level / 10.0))

# 由累计烹饪次数推等级（初始1级）
func get_dish_level(pack_id: String, career: String) -> int:
	var n := get_dish_cooks(pack_id, career)
	var level := 1
	var need := 1
	while n >= need:
		n -= need
		level += 1
		need = get_dish_need(level)
	return level

# 距下一级进度 {level, done, need}
func get_dish_progress(pack_id: String, career: String) -> Dictionary:
	var n := get_dish_cooks(pack_id, career)
	var level := 1
	var need := 1
	while n >= need:
		n -= need
		level += 1
		need = get_dish_need(level)
	return {"level": level, "done": n, "need": need}

# 单道菜累计固定赚钱 = Σ_{k=1}^{level-1} 500×ceil(k/10)（给该职业全部门客）
func get_dish_income(pack_id: String, career: String) -> int:
	var level := get_dish_level(pack_id, career)
	var base := int(_st().get("dish_level_income_base", 500))
	var total := 0
	for k in range(1, level):
		total += base * get_dish_need(k)
	return total

# 某职业全部门客的客栈菜谱固定赚钱总和（HeroData 接入点）
func get_career_income_bonus(career: String) -> int:
	var total := 0
	for pack in get_packs():
		total += get_dish_income(str(pack.get("id", "")), career)
	return total

# ============ 厨艺值支出（side_skill_system「庖丁解牛」升级接口） ============
# 扣厨艺值，余额不足返回 false（庖丁解牛为每门客副业技能，曲线/上限在 side_skill_system）
func try_spend_cuisine(cost: int) -> bool:
	if cuisine < cost: return false
	cuisine -= cost
	return true

# ============ 兑换商店（交子货币，无限购） ============
# 购买：扣交子 +1 个商品道具
func buy_exchange(index: int) -> bool:
	var list := get_exchange_list()
	if index < 0 or index >= list.size(): return false
	var e: Dictionary = list[index]
	var cost := int(e.get("cost", 0))
	if jiaozi < cost: return false
	jiaozi -= cost
	var item := str(e.get("item", ""))
	if item != "":
		g.items[item] = int(g.items.get(item, 0)) + 1
	return true

# 合成：碎片类 need 个合 1 个目标道具（残帖10合1门客帖 / 印碎片20合1令）
func compose_exchange(index: int) -> bool:
	var list := get_exchange_list()
	if index < 0 or index >= list.size(): return false
	var e: Dictionary = list[index]
	var comp: Dictionary = e.get("compose", {})
	if comp.is_empty(): return false
	var from := str(e.get("item", ""))
	var to := str(comp.get("to", ""))
	var need := int(comp.get("need", 1))
	if int(g.items.get(from, 0)) < need: return false
	g.items[from] = int(g.items.get(from, 0)) - need
	if to != "":
		g.items[to] = int(g.items.get(to, 0)) + 1
	return true
