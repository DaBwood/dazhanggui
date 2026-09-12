# ============================================================
# 钱庄玩法系统（商铺地图化批次2：柜台委任 / 百业经验个人池 / 筹算值 / 信誉值）
# 纯逻辑模块：状态内部持有，经 get_save_data/load_save_data 落盘（game_data 只接线）
# 规则（档案三十六节 + 2026-09-12 用户拍板）：
#   柜台：前5个免费；之后受钱庄店铺等级上限约束（每2级+1个解锁额度），每个花5000元宝点「+」手动解锁（用户 2026-09-12 拍板），上限30
#   产出：固定收益 每20分钟 = 1百业经验 + 40筹算值 + 40信誉值（与门客赚速不挂钩）
#   封顶：单柜台最多累计24小时，离线照走（领取时按 start_time 懒结算）
#   百业经验：每门客独立池；门客面板资质技能可勾选改用百业经验抵扣（300×每级丹数）
#   筹算值：升级独立店铺技能「财源广进」（结构/加成与原技能一模一样，仅货币不同；初始消耗6、×1.008/级）
#   信誉值：升钱庄玩法内等级（上限100，消耗=100×1.5^当前等级）
#           每级：徒弟赚速固定+500 / 徒弟赚速+2% / 珍兽等级上限+2 / 觉醒上限每10级+1
# ============================================================
class_name BankSystem
extends RefCounted

# GameData 中枢引用（不标类型，避免类之间循环引用导致解析失败）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档（本系统持有的字段） ============
var counters: Array = []        # 柜台 [{hero_id, start_time}]，长度随解锁数懒增长
var baiye: Dictionary = {}      # 百业经验个人池 {hero_id: 数量}
var chousuan: int = 0           # 筹算值
var xinyu: int = 0              # 信誉值
var xinyu_level: int = 0        # 钱庄玩法内等级（信誉等级）
var counter_unlocked: int = 0   # 手动解锁的柜台数（前5个免费，之后每个花元宝解锁）

# 提供本系统的存档字段（由 GameData.save_game 合并进扁平存档表）
func get_save_data() -> Dictionary:
	return {
		"bank_counters": counters,
		"bank_baiye": baiye,
		"bank_chousuan": chousuan,
		"bank_xinyu": xinyu,
		"bank_xinyu_level": xinyu_level,
		"bank_counter_unlocked": counter_unlocked,
	}

# 从扁平存档表认领本系统字段（老档缺字段则保持初始值，类型防御防一处崩整轮）
func load_save_data(s: Dictionary):
	if s.has("bank_counters") and s.bank_counters is Array: counters = s.bank_counters
	if s.has("bank_baiye") and s.bank_baiye is Dictionary: baiye = s.bank_baiye
	if s.has("bank_chousuan"): chousuan = int(s.bank_chousuan)
	if s.has("bank_xinyu"): xinyu = int(s.bank_xinyu)
	if s.has("bank_xinyu_level"): xinyu_level = int(s.bank_xinyu_level)
	if s.has("bank_counter_unlocked"): counter_unlocked = int(s.bank_counter_unlocked)
	_ensure_counters()

# ============ 配置读取（bank.json settings，代码默认值兜底） ============
func _st() -> Dictionary:
	return g._bank_configs.get("settings", {})

func get_tick_seconds() -> int:
	return int(_st().get("tick_seconds", 1200))

func get_cap_seconds() -> int:
	return int(_st().get("cap_seconds", 86400))

# 百业经验抵扣单价：1颗资质丹 = 300 百业经验
func get_baiye_per_pill() -> int:
	return int(_st().get("baiye_per_pill", 300))

# ============ 柜台 ============
# 已解锁柜台数 = 前5个免费 + 手动解锁数（用户拍板：不随店铺等级自动解锁），封顶30
func get_counter_count() -> int:
	var st: Dictionary = _st()
	return mini(int(st.get("counter_initial", 5)) + counter_unlocked, int(st.get("counter_max", 30)))

# 手动解锁一个柜台的花费（元宝）
func get_counter_unlock_cost() -> int:
	return int(_st().get("counter_unlock_cost", 5000))

func can_unlock_more() -> bool:
	return get_counter_count() < get_counter_total()

# 等级上限：钱庄店铺(hq.level)每2级+1个解锁额度（1级5个、3级6个、5级7个……），封顶30
# +卡交互（用户拍板）：等级到了花元宝新增柜台；等级不到点+提示升级地图上的钱庄店铺
func get_max_unlockable() -> int:
	var st: Dictionary = _st()
	var per_levels := int(st.get("counter_per_levels", 2))
	return mini(int(st.get("counter_initial", 5)) + floori(maxi(0, int(g.hq.level) - 1) / float(per_levels)), int(st.get("counter_max", 30)))

# 花元宝手动解锁一个柜台（项目惯例：直接检查并扣 g.yuanbao，无 spend 方法；扣款成功才+1并懒建柜台）
func unlock_counter() -> bool:
	if not can_unlock_more(): return false
	var cost := get_counter_unlock_cost()
	if g.yuanbao < cost: return false
	g.yuanbao -= cost
	counter_unlocked += 1
	_ensure_counters()
	return true

func get_counter_total() -> int:
	return int(_st().get("counter_max", 30))

# 柜台数组懒增长到已解锁数量（店铺升级后自动出现新柜台，读档/显示时都调）
func _ensure_counters():
	var need := get_counter_count()
	while counters.size() < need:
		counters.append({"hero_id": "", "start_time": 0})

func get_counter_hero(idx: int) -> String:
	if idx < 0 or idx >= counters.size(): return ""
	return str(counters[idx].get("hero_id", ""))

# 委任门客（不锁定：可同时被派遣店铺/商战/多柜台）；新委任从当前时刻起计时
func assign_hero(idx: int, hero_id: String) -> bool:
	_ensure_counters()
	if idx < 0 or idx >= get_counter_count(): return false
	if not g.heroes.has(hero_id): return false
	counters[idx] = {"hero_id": hero_id, "start_time": Time.get_unix_time_from_system()}
	return true

# 某柜台已累积秒数（封顶24小时；领取时才结算，故离线期间自然累积）
func get_accrued_seconds(idx: int) -> int:
	if idx < 0 or idx >= counters.size(): return 0
	if get_counter_hero(idx) == "": return 0
	var start := int(counters[idx].get("start_time", 0))
	var elapsed := int(Time.get_unix_time_from_system()) - start
	return clampi(elapsed, 0, get_cap_seconds())

# 待结算产量 {baiye, chousuan, xinyu}
func get_pending(idx: int) -> Dictionary:
	var ticks := floori(get_accrued_seconds(idx) / float(get_tick_seconds()))
	var st: Dictionary = _st()
	return {
		"baiye": ticks * int(st.get("tick_baiye", 1)),
		"chousuan": ticks * int(st.get("tick_chousuan", 40)),
		"xinyu": ticks * int(st.get("tick_xinyu", 40)),
	}

# 领取单个柜台：三资源入池、计时重置（门客保留在柜台继续产出）
func collect_counter(idx: int) -> Dictionary:
	var hid := get_counter_hero(idx)
	if hid == "" or not g.heroes.has(hid): return {}
	var gain := get_pending(idx)
	if int(gain["baiye"]) + int(gain["chousuan"]) + int(gain["xinyu"]) <= 0: return {}
	baiye[hid] = int(baiye.get(hid, 0)) + int(gain["baiye"])
	chousuan += int(gain["chousuan"])
	xinyu += int(gain["xinyu"])
	counters[idx]["start_time"] = Time.get_unix_time_from_system()   # 重置计时
	gain["hero_id"] = hid
	return gain

# 一键全领：汇总所有柜台
func collect_all() -> Dictionary:
	_ensure_counters()
	var total := {"baiye": 0, "chousuan": 0, "xinyu": 0}
	for i in range(mini(counters.size(), get_counter_count())):
		var gain := collect_counter(i)
		if gain.is_empty(): continue
		total["baiye"] += int(gain["baiye"])
		total["chousuan"] += int(gain["chousuan"])
		total["xinyu"] += int(gain["xinyu"])
	return total

# 撤下：先把已累积的结算给该门客，再清空柜台（不吞产出）
func unassign_hero(idx: int) -> Dictionary:
	var gain := collect_counter(idx)
	if idx >= 0 and idx < counters.size():
		counters[idx] = {"hero_id": "", "start_time": 0}
	return gain

# ============ 百业经验（每门客个人池） ============
func get_baiye(hero_id: String) -> int:
	return int(baiye.get(hero_id, 0))

func get_baiye_total() -> int:
	var total := 0
	for k in baiye.keys():
		total += int(baiye[k])
	return total

# 用百业经验抵扣 pills 颗资质丹（300×pills 经验），成功扣池返回 true
func spend_baiye_for_pills(hero_id: String, pills: int) -> bool:
	var need := pills * get_baiye_per_pill()
	if get_baiye(hero_id) < need: return false
	baiye[hero_id] = get_baiye(hero_id) - need
	return true

# ============ 筹算值（门客店铺技能第二货币轨） ============
# ============ 筹算值（独立技能「财源广进」，结构/加成与原店铺技能一模一样） ============
const CAIYUAN_NAME := "财源广进"

func get_chousuan() -> int:
	return chousuan

# 确保门客已拥有「财源广进」：独立店铺技能，结构镜像第一个店铺技能（等级1起步，规则与原技能一致）
# 懒创建（首次打开副业页/委任选择器/升级时），旧档零迁移
func ensure_caiyuan_skill(hero_id: String) -> void:
	if not g.heroes.has(hero_id): return
	var skills: Array = g.heroes[hero_id].get("shop_skills", [])
	for s in skills:
		if str(s.get("name", "")) == CAIYUAN_NAME: return
	if skills.is_empty(): return
	var base: Dictionary = skills[0]
	skills.append({
		"name": CAIYUAN_NAME,
		"level": 1,
		"max_level": int(base.get("max_level", 200)),
		"base_percent": float(base.get("base_percent", 0.0)),
		"percent_per_level": float(base.get("percent_per_level", 0.0)),
	})

# 取财源广进技能（无则懒创建后仍返回；找不到返回空 Dictionary）
func get_caiyuan_skill(hero_id: String) -> Dictionary:
	ensure_caiyuan_skill(hero_id)
	if not g.heroes.has(hero_id): return {}
	var skills: Array = g.heroes[hero_id].get("shop_skills", [])
	for s in skills:
		if str(s.get("name", "")) == CAIYUAN_NAME: return s
	return {}

# 财源广进 Lv.→下一级 消耗：初始6，每级 ×1.008（Lv.1→2 花6）
func get_chousuan_cost(cur_level: int) -> int:
	var st: Dictionary = _st()
	return maxi(1, int(ceil(float(st.get("chousuan_cost_base", 6)) * pow(float(st.get("chousuan_cost_mult", 1.008)), maxi(0, cur_level - 1)))))

# 财源广进升级：结构/上限与原店铺技能一致，仅货币=筹算值；mode="single" 升1级，"bulk" 一键升满
func upgrade_caiyuan_skill(hero_id: String, mode: String = "single") -> bool:
	var skill := get_caiyuan_skill(hero_id)
	if skill.is_empty(): return false
	var max_lv := int(skill.get("max_level", 200))
	var lv := int(skill.get("level", 1))
	if lv >= max_lv: return false
	if mode == "single":
		var cost := get_chousuan_cost(lv)
		if chousuan < cost: return false
		chousuan -= cost
		skill["level"] = lv + 1
		return true
	else:
		var upgraded := 0
		while lv + upgraded < max_lv:
			var cost := get_chousuan_cost(lv + upgraded)
			if chousuan < cost: break
			chousuan -= cost
			upgraded += 1
		if upgraded > 0:
			skill["level"] = lv + upgraded
			return true
		return false

# ============ 信誉值（钱庄玩法内等级） ============
func get_xinyu() -> int:
	return xinyu

func get_xinyu_level() -> int:
	return xinyu_level

func get_xinyu_max_level() -> int:
	return int(_st().get("xinyu_max_level", 100))

# 升级消耗 = 100 × 1.5^当前等级
func get_xinyu_cost() -> int:
	var st: Dictionary = _st()
	return maxi(1, int(ceil(float(st.get("xinyu_cost_base", 100)) * pow(float(st.get("xinyu_cost_mult", 1.5)), xinyu_level))))

func upgrade_xinyu_level() -> bool:
	if xinyu_level >= get_xinyu_max_level(): return false
	var cost := get_xinyu_cost()
	if xinyu < cost: return false
	xinyu -= cost
	xinyu_level += 1
	return true

# ---- 信誉等级加成（读取式，各系统热路径接入，零存档写入） ----
# 徒弟赚速固定 +500/级
func get_apprentice_flat_bonus() -> int:
	return xinyu_level * int(_st().get("xinyu_apprentice_flat", 500))

# 徒弟赚速 +2%/级（小数制，并入徒弟赚速乘区）
func get_apprentice_pct_bonus() -> float:
	return xinyu_level * float(_st().get("xinyu_apprentice_pct", 0.02))

# 珍兽等级上限 +2/级
func get_beast_level_cap_bonus() -> int:
	return xinyu_level * int(_st().get("xinyu_beast_level_per_lv", 2))

# 珍兽觉醒上限 每10级信誉 +1
func get_awaken_limit_bonus() -> int:
	return floori(xinyu_level / 10.0) * int(_st().get("xinyu_awaken_per_10lv", 1))
