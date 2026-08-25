# ============================================================
# 徒弟系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name ApprenticeSystem
extends RefCounted

# GameData 中枢引用（不标注类型，避免类之间循环引用导致解析失败）
var g

# 由 GameData._init 创建本系统时注入中枢引用
func _init(p_g):
	g = p_g

# ============ 存档：本系统拥有的字段 ============
# 提供本系统的存档字段（由 GameData.save_game 合并进扁平存档表，格式与旧版完全一致）
func get_save_data() -> Dictionary:
	return {
		"apprentices": g.apprentices,   # 徒弟槽位
		"graduated_apprentices": g.graduated_apprentices,   # 已结业徒弟
		"apprentice_vigor": g.apprentice_vigor,   # 各槽位活力
		"apprentice_vigor_time": g.apprentice_vigor_time,   # 活力结算时间戳
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	# 【修复】旧版漏读 graduated_apprentices，导致已结业徒弟重启游戏后丢失；
	# 必须先读结业列表，再做下面的槽位迁移（迁移会向结业列表追加）
	if s.has("graduated_apprentices"): g.graduated_apprentices = s.graduated_apprentices
	if s.has("apprentices"):
		g.apprentices = s.apprentices
		# 兼容旧存档：补齐到5个槽位
		while g.apprentices.size() < 5:
			g.apprentices.append(null)
		# 旧存档单人徒弟（字典）包成数组；已结业的移到结业列表
		for i in range(g.apprentices.size()):
			var entry = g.apprentices[i]
			if entry == null: continue
			if entry is Dictionary:
				entry = [entry]
			var remaining = []
			for a in entry:
				if a.get("state", "") in ["magician", "lover", "married"]:
					g.graduated_apprentices.append(a)
				else:
					remaining.append(a)
			if remaining.size() > 0:
				g.apprentices[i] = remaining
			else:
				g.apprentices[i] = null
	if s.has("apprentice_vigor"): g.apprentice_vigor = s.apprentice_vigor
	if s.has("apprentice_vigor_time"): g.apprentice_vigor_time = s.apprentice_vigor_time

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 是否存在已解锁的空徒弟槽位（月老/观音祝福生效的前提）
func _has_empty_apprentice_slot() -> bool:
	for i in range(5):
		if not is_apprentice_slot_unlocked(i): break
		var entry = g.apprentices[i]
		if entry == null or (entry is Array and entry.is_empty()):
			return true
	return false

# ========== 徒弟：槽位 ==========

# 已解锁的徒弟槽位数（按身份等级）
func get_apprentice_slot_count() -> int:
	var count = 0
	for lv in g.APPRENTICE_UNLOCK_LEVELS:
		if g.identity_level >= lv:
			count += 1
	return count

# 指定槽位是否已解锁
func is_apprentice_slot_unlocked(slot: int) -> bool:
	return slot >= 0 and slot < get_apprentice_slot_count()

# 懒结算槽位活力：每分钟恢复1点，500只是自动恢复的上限（道具可超上限）
func _settle_slot_vigor(slot: int):
	var now = Time.get_unix_time_from_system()
	var last = g.apprentice_vigor_time[slot]
	if last <= 0:
		g.apprentice_vigor_time[slot] = now
		return
	# 活力已满（或超出上限）：不再恢复，但绝不能截断超出部分
	if g.apprentice_vigor[slot] >= g.APPRENTICE_VIGOR_MAX:
		g.apprentice_vigor_time[slot] = now
		return
	@warning_ignore("narrowing_conversion")
	var regen = int((now - last) / 60)
	if regen > 0:
		g.apprentice_vigor[slot] = min(g.APPRENTICE_VIGOR_MAX, g.apprentice_vigor[slot] + regen)
		@warning_ignore("narrowing_conversion")
		g.apprentice_vigor_time[slot] = last + regen * 60

# 获取槽位当前活力（先结算恢复）
func get_slot_vigor(slot: int) -> int:
	_settle_slot_vigor(slot)
	return g.apprentice_vigor[slot]

# ========== 徒弟：领养 ==========

# 与挚友领养徒弟：占用第一个已解锁的空位，1%概率双胞胎（同槽位两名，性别职业各自独立随机）
# 【修改】force_twin=true（观音祝福）时必定双胞胎
# 返回领养数量：0=没有空位，1=单人，2=双胞胎
func adopt_apprentice(friend_id: String, force_twin: bool = false) -> int:
	if not g.friends.has(friend_id): return 0
	for i in range(5):
		if not is_apprentice_slot_unlocked(i): break
		var entry = g.apprentices[i]
		if entry == null or (entry is Array and entry.is_empty()):
			var list = [_create_apprentice(friend_id)]
			if force_twin or randf() < g.APPRENTICE_TWIN_CHANCE:
				list.append(_create_apprentice(friend_id))
			g.apprentices[i] = list
			return list.size()
	return 0

# 创建一个徒弟（性别/职业独立随机，品质按领养时挚友美名定格）
func _create_apprentice(friend_id: String) -> Dictionary:
	var gender = "男" if randi() % 2 == 0 else "女"
	var pool = g.APPRENTICE_MALE_NAMES if gender == "男" else g.APPRENTICE_FEMALE_NAMES
	return {
		"name": g.SURNAMES[randi() % g.SURNAMES.size()] + pool[randi() % pool.size()],
		"gender": gender,
		"career": g.APPRENTICE_CAREERS[randi() % g.APPRENTICE_CAREERS.size()],
		"friend_id": friend_id,        # 领养来源挚友
		"quality_idx": max(0, g.get_friend_title_index(friend_id)),  # 品质按领养时美名定格
		"progress": 0,                 # 培养进度
		"state": "training",           # training/adult/magician/lover/married
		"magic_bonus": 0.0,            # 魔法师加成比例
		"spouse": {},                  # 配偶信息
		"spouse_income": 0,            # 联姻获得的赚速
		"income_bonus": 0,               # 【新增】徒弟赚速加成（结业时按职业加成池定格）
	}

# ========== 徒弟：赚速 ==========

# 单个徒弟的当前赚速
# 顺序：成年值 = 品质赚速+友好×10%+徒弟赚速加成 → 按进度线性 → 魔法师加成 → 联姻加成
func _get_single_apprentice_income(a: Dictionary) -> int:
	var f = g.friends.get(a.friend_id, {})
	var q = clamp(a.get("quality_idx", 0), 0, g.FRIEND_TITLES.size() - 1)
	var adult = g.FRIEND_TITLES[q].income + int(f.get("friendly", 0) * 0.1) + a.get("income_bonus", 0)
	var income = int(adult * a.progress / float(g.APPRENTICE_MAX_PROGRESS))
	if a.state == "magician":
		income = int(income * (1.0 + a.magic_bonus))
	elif a.state == "married":
		income += a.get("spouse_income", 0)
	return income

# 槽位总赚速：同槽每个徒弟单独计算后求和（双胞胎即两倍）
func get_apprentice_income(slot: int) -> int:
	var entry = g.apprentices[slot]
	if entry == null: return 0
	var list = entry if entry is Array else [entry]   # 兼容旧存档
	var total = 0
	for a in list:
		total += _get_single_apprentice_income(a)
	return total

# 已结业徒弟赚速（结业列表里都是单人条目）
func get_graduated_income(index: int) -> int:
	if index < 0 or index >= g.graduated_apprentices.size(): return 0
	return _get_single_apprentice_income(g.graduated_apprentices[index])

# ========== 徒弟：培养 / 结业 / 联姻 ==========

# 培养：10000铜钱 + 1活力 → 同槽所有徒弟进度各+4、阅历+3100；满进度成年
func train_apprentice(slot: int) -> Dictionary:
	if slot < 0 or slot >= 5: return {"ok": false, "reason": "槽位错误"}
	var entry = g.apprentices[slot]
	if entry == null: return {"ok": false, "reason": "空位"}
	var list = entry if entry is Array else [entry]
	if list.is_empty(): return {"ok": false, "reason": "空位"}
	if list[0].state != "training": return {"ok": false, "reason": "培养已完成"}
	if g.money < g.APPRENTICE_TRAIN_COST: return {"ok": false, "reason": "铜钱不足"}
	_settle_slot_vigor(slot)
	if g.apprentice_vigor[slot] < 1: return {"ok": false, "reason": "活力不足"}
	g.money -= g.APPRENTICE_TRAIN_COST
	g.apprentice_vigor[slot] -= 1
	# 双胞胎占同一槽位，一起培养
	for a in list:
		a.progress = min(g.APPRENTICE_MAX_PROGRESS, a.progress + g.APPRENTICE_PROGRESS_PER_TRAIN)
	g.items.experience += g.APPRENTICE_TRAIN_EXP
	var adult = list[0].progress >= g.APPRENTICE_MAX_PROGRESS
	if adult:
		for a in list:
			a.state = "adult"
	return {"ok": true, "adult": adult}

# 一键培养：连续培养直到活力耗尽 / 铜钱不足 / 已成年
func train_apprentice_batch(slot: int) -> Dictionary:
	var count = 0
	var adult = false
	while true:
		var r = train_apprentice(slot)
		if not r.ok:
			# 至少成功过一次就算成功，带上中断原因
			if count > 0:
				return {"ok": true, "count": count, "adult": adult, "stop_reason": r.reason}
			return r
		count += 1
		adult = adult or r.get("adult", false)
		if adult: break
	return {"ok": true, "count": count, "adult": adult}

# 使用活力丹：指定槽位活力 +5/个，不受自动恢复上限限制
func use_vitality_pill(slot: int, count: int) -> bool:
	if slot < 0 or slot >= 5 or count <= 0: return false
	if g.items.get("vitality_pill", 0) < count: return false
	_settle_slot_vigor(slot)
	g.items.vitality_pill -= count
	g.apprentice_vigor[slot] += 5 * count
	return true

# 结业转职（逐个进行，双胞胎轮流选择）："magician"=魔法师 / "lover"=现充
# 每次处理槽位里第一个待结业的徒弟，全部结业后槽位空出
func graduate_apprentice_one(slot: int, path: String) -> bool:
	if slot < 0 or slot >= 5: return false
	var entry = g.apprentices[slot]
	if entry == null: return false
	var list = entry if entry is Array else [entry]
	if list.is_empty(): return false
	var a = list[0]
	if a.state != "adult": return false
	a.income_bonus = g.get_charity_career_bonus(a.career)
	if path == "magician":
		a.magic_bonus = randf_range(0.7, 1.4)
		a.state = "magician"
	elif path == "lover":
		a.state = "lover"
	else:
		return false
	# 移入已结业列表
	g.graduated_apprentices.append(a)
	list.remove_at(0)
	# 槽位腾空（双胞胎的另一个还在的话保留槽位）
	if list.size() > 0:
		g.apprentices[slot] = list
	else:
		g.apprentices[slot] = null
	return true

# 生成联姻对象：性别相反、赚速与当前徒弟相同（index为已结业列表下标）
func generate_spouse(index: int) -> Dictionary:
	if index < 0 or index >= g.graduated_apprentices.size(): return {}
	var a = g.graduated_apprentices[index]
	if a == null: return {}
	var gender = "女" if a.gender == "男" else "男"
	var pool = g.APPRENTICE_MALE_NAMES if gender == "男" else g.APPRENTICE_FEMALE_NAMES
	return {
		"name": g.SURNAMES[randi() % g.SURNAMES.size()] + pool[randi() % pool.size()],
		"gender": gender,
		"career": g.APPRENTICE_CAREERS[randi() % g.APPRENTICE_CAREERS.size()],
		"income": get_graduated_income(index),
	}

# 联姻：获得对象赚速，进入已婚（index为已结业列表下标）
func marry_apprentice(index: int, spouse: Dictionary) -> bool:
	if index < 0 or index >= g.graduated_apprentices.size(): return false
	var a = g.graduated_apprentices[index]
	if a == null or a.state != "lover": return false
	a.spouse = spouse
	a.spouse_income = spouse.get("income", 0)
	a.state = "married"
	g.goal_system.add_stat("marry_count")   # 【第6批新增】挚友目标：联姻计数
	return true
