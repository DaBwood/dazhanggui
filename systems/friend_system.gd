# ============================================================
# 挚友系统（第2批重构：从 game_data.gd 拆分而来）
# 纯逻辑模块：状态仍统一存放在 GameData 中枢，本类通过 g.xxx 访问
# 对外 API 不变：GameData 为每个方法设有同名转发，controller 零改动
# ============================================================
class_name FriendSystem
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
		"friends": g.friends,   # 挚友数据
		"energy": g.energy,   # 精力（谈心消耗）
		"energy_time": g.energy_time,   # 【新增】四批：精力恢复结算时间戳
	}

# 从扁平存档表认领本系统字段（含旧存档兼容逻辑；老存档缺字段则保持初始值）
func load_save_data(s: Dictionary):
	if s.has("friends"): g.friends = s.friends
	if s.has("energy"): g.energy = s.energy
	if s.has("energy_time"): g.energy_time = float(s.energy_time)   # 【新增】四批：精力恢复时间戳（老存档无此字段=立即开始计时的兼容）
	# 清理存档中已不存在的挚友（防止配置删了存档还残留）
	for friend_id in g.friends.keys():
		if not g._friend_configs.has(friend_id):
			g.friends.erase(friend_id)
	# 【删】批次E（2026-09-19）：挚友店铺技能 load 时回填已删——挚友获取路径(91/129行)与
	# 读取守卫(has shop_skills 则懒初始化)已覆盖，新档获取即初始化，不受影响

# ============ 以下为原 game_data.gd 搬迁函数（逻辑未改，仅成员访问加了 g. 前缀） ============

# 当前友好最高的已拥有挚友ID（月老牵线的谈心对象）；没有挚友时返回空串
func _get_highest_friendly_friend() -> String:
	var best_id = ""
	var best_friendly = -1
	for fid in g.friends.keys():
		var fv = g.friends[fid].get("friendly", 0)
		if fv > best_friendly:
			best_friendly = fv
			best_id = fid
	return best_id

# 谈心前的祝福结算：返回 {"target"=谈心挚友ID, "force_twin"=是否必双胞胎, "yuelao"=月老是否生效, "guanyin"=观音是否生效}
# 只有存在徒弟空位（本次谈心能领养）时才消耗层数；没有空位则层数保留、继续累计
func _prepare_chat_adoption(default_friend_id: String) -> Dictionary:
	var bless = {"target": default_friend_id, "force_twin": false, "yuelao": false, "guanyin": false}
	if not g._has_empty_apprentice_slot():
		return bless
	if g.yuelao_count > 0:
		g.yuelao_count -= 1
		var top_id = _get_highest_friendly_friend()
		if top_id != "":
			bless.target = top_id
		bless.yuelao = true
	if g.guanyin_count > 0:
		g.guanyin_count -= 1
		bless.force_twin = true
		bless.guanyin = true
	return bless

# 【新增】四批：精力懒结算——基础每小时恢复1点（c190改速度）；满值不溢出、超出不截断；新存档字段 energy_time，老存档默认当前时刻
func _settle_energy() -> void:
	var now = Time.get_unix_time_from_system()
	if g.energy_time <= 0.0:
		g.energy_time = now
		return
	var cap = g.collection_system.get_energy_cap()
	if g.energy >= cap:
		g.energy_time = now
		return
	var secs = g.collection_system.get_energy_regen_seconds()
	var regen = int((now - g.energy_time) / secs)
	if regen > 0:
		g.energy = min(cap, g.energy + regen)
		g.energy_time += regen * secs

func unlock_friend(friend_id: String) -> bool:
	if g.friends.has(friend_id): return false
	var cfg = g.get_friend_config(friend_id)
	if cfg.is_empty(): return false
	g.friends[friend_id] = cfg
	_init_friend_shop_skills(friend_id)
	# 【新增】宅院挚友卷补发：挚友解锁时继承其固定分组已累计的友好/才华加成
	g.apply_courtyard_friend_unlock_bonus(friend_id)
		# 【新增】宅院挚友卷补发：挚友解锁时继承其固定分组已累计的友好/才华加成
	g.apply_courtyard_friend_unlock_bonus(friend_id)
	# 【新增】藏品补发（二批写入式）：继承友好/才华类藏品已累计加成，新挚友即时享受
	g.collection_system.apply_friend_unlock_bonus(friend_id)
	# 【新增】酒肆补发（写入式+累计值）：继承餐饮/娱乐设施已累计的友好/才华，新挚友即时享受
	g.tavern_system.apply_friend_unlock_bonus(friend_id)
	return true

# ========== 计算函数 ==========

# 挚友店铺技能列表
func _init_friend_shop_skills(friend_id: String):
	if not g.friends.has(friend_id): return
	var f = g.friends[friend_id]
	var categories = ["士", "农", "工", "商", "侠"]
	var skills = []
	for i in range(400):
		skills.append({
			"category": categories[i % 5],
			"bonus": 0.05,
			"refresh_count": 0
		})
	f.shop_skills = skills

# 店铺技能槽位数（分段线性：前期快、后期慢；锚点：2万友好=100个、5万=150个、20万=250个封顶）
# 0~2万：每200友好+1（共100）；2万~5万：每600友好+1（共+50）；5万~20万：每1500友好+1（共+100）
func get_shop_skill_slots(friendly) -> int:
	if friendly <= 20000: return int(friendly / 200)
	if friendly <= 50000: return 100 + int((friendly - 20000) / 600)
	return min(250, 150 + int((friendly - 50000) / 1500))

func get_friend_shop_skills(friend_id: String) -> Array:
	if not g.friends.has(friend_id): return []
	var f = g.friends[friend_id]
	if not f.has("shop_skills"):
		_init_friend_shop_skills(friend_id)
	var max_slots = get_shop_skill_slots(f.friendly)
	var skills = f.shop_skills
	var result = []
	for i in range(min(max_slots, skills.size())):
		result.append(skills[i])
	return result

func refresh_friend_shop_skill(friend_id: String, skill_index: int, use_wish_stone: bool = false) -> bool:
	if not g.friends.has(friend_id): return false
	var f = g.friends[friend_id]
	if not f.has("shop_skills"): _init_friend_shop_skills(friend_id)
	var skills = f.shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	
	var max_slots = get_shop_skill_slots(f.friendly)
	if skill_index >= max_slots: return false
	
	var skill = skills[skill_index]
	if skill.bonus >= 0.30: return false
	
	if use_wish_stone:
		var wish_cost = 1
		if g.items.get("wish_stone", 0) < wish_cost:
			return false
		g.items.wish_stone -= wish_cost
		skill.refresh_count += 1
		var new_bonus = randf_range(0.20, 0.31)
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	else:
		var cost = 100 * int(pow(2, skill.refresh_count))
		if g.money < cost: return false
		g.money -= cost
		skill.refresh_count += 1
		
		var roll = randf()
		var new_bonus: float
		if roll < 0.9:
			# 90% 概率刷新出 5% ~ 19% 的加成
			new_bonus = randf_range(0.05, 0.199)
		else:
			# 10% 概率刷新出 20% ~ 30% 的加成
			new_bonus = randf_range(0.20, 0.31)
		
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	return true

# 挚友给门客的加成
func get_friend_hero_bonus(friend_id: String) -> int:
	if not g.friends.has(friend_id): return 0
	var f = g.friends[friend_id]
	var fixed_total = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
	var percent = 1.0 + f.percent_skill_level * 0.05
	return int(fixed_total * percent)

# ========== 才艺技能（酒肆才艺经验的消费端） ==========
# 多才多艺：每级缘分门客固定赚钱 +5000；单次消耗 = 100 + 5×当前等级 才艺经验（Lv.0→1 耗 100）
# 超群绝伦：每级缘分门客资质 +1；      单次消耗 = 5000 + 15×当前等级 才艺经验（Lv.0→1 耗 5000）
# 两技能等级均无上限、逐挚友独立；存档键 caiyi_skills（旧档缺省按 0 级处理，零迁移）
const CAIYI_SKILLS := {
	"duocai": {"name": "多才多艺", "effect": "income", "value_per_level": 5000, "cost_base": 100, "cost_per_level": 5},
	"chaoqun": {"name": "超群绝伦", "effect": "aptitude", "value_per_level": 1, "cost_base": 5000, "cost_per_level": 15},
}

func get_caiyi_skill_level(friend_id: String, skill_key: String) -> int:
	if not g.friends.has(friend_id): return 0
	var f = g.friends[friend_id]
	return int(f.get("caiyi_skills", {}).get(skill_key, 0))

# level < 0 时取当前等级；返回从该级升到下一级的单次消耗
func get_caiyi_skill_cost(friend_id: String, skill_key: String, level: int = -1) -> int:
	if not CAIYI_SKILLS.has(skill_key): return 0
	if level < 0: level = get_caiyi_skill_level(friend_id, skill_key)
	var cfg = CAIYI_SKILLS[skill_key]
	return int(cfg["cost_base"]) + int(cfg["cost_per_level"]) * level

# 升级：batch=true 时最多连升 10 级，才艺经验不足则升剩余级数；返回实际升级级数
func upgrade_caiyi_skill(friend_id: String, skill_key: String, batch: bool) -> int:
	if not g.friends.has(friend_id) or not CAIYI_SKILLS.has(skill_key): return 0
	var pool = g.tavern_system.get_caiyi(friend_id)
	var lv = get_caiyi_skill_level(friend_id, skill_key)
	var target = 10 if batch else 1
	var upgraded = 0
	for i in range(target):
		var cost = get_caiyi_skill_cost(friend_id, skill_key, lv + upgraded)
		if pool < cost: break
		pool -= cost
		upgraded += 1
	if upgraded <= 0: return 0
	var f = g.friends[friend_id]
	var skills = f.get("caiyi_skills", {})
	skills[skill_key] = lv + upgraded
	f["caiyi_skills"] = skills
	# 扣除酒肆才艺经验池实际消耗
	g.tavern_system.spend_caiyi(friend_id, g.tavern_system.get_caiyi(friend_id) - pool)
	return upgraded

# 超群绝伦效果：缘分门客资质加成（由 HeroData.get_total_aptitude 按 bound_heroes 接入）
# ========== 芳华技能（妙音坊缘分物消费端，2026-09-19 实装；方案=妙音坊设计方案§十四） ==========
# 9 技能链式解锁，效果全部挂"缘分门客"（同才华轨：固定→get_friend_fixed_bonus /
# 资质→get_friend_aptitude_bonus / 百分比→get_friend_percent_bonus）。存档=挚友档内 fanghua_skills[9]，
# 旧档缺省全 0 懒创建零迁移（方案原写 save["miaoyin"]["fanghua"]，随才华轨改挚友档内存储，save/load 零改动）。
# ⚠️ 挚友"职业"由 friends.json 的 yyf_career 字段提供（映射五种缘分之花）——实装前挚友无此字段，
#    初版映射已写入 friends.json；调整映射只改 json 不改代码
const FANGHUA_SKILLS := [
	{"name": "伊人芳华", "k": 1,     "kind": "fixed",    "value": 3000},   # 美名≥伊人
	{"name": "佳人芳华", "k": 150,   "kind": "aptitude", "value": 1},      # 伊人100级 且 美名≥佳人
	{"name": "丽人芳华", "k": 400,   "kind": "aptitude", "value": 1},      # 佳人100级 且 美名≥丽人
	{"name": "红粉芳华", "k": 5,     "kind": "percent",  "value": 0.001},  # 丽人150级 且 美名≥红粉
	{"name": "婵娟芳华", "k": 1500,  "kind": "aptitude", "value": 1},      # 红粉200级 且 美名≥婵娟【拟补档】
	{"name": "花魁芳华", "k": 4000,  "kind": "aptitude", "value": 1},      # 婵娟250级 且 美名≥花魁【拟补档】
	{"name": "国色芳华", "k": 10000, "kind": "percent",  "value": 0.001},  # 美名≥国色
	{"name": "仙子芳华", "k": 25000, "kind": "percent",  "value": 0.001},  # 美名≥仙子
	{"name": "天仙芳华", "k": 60000, "kind": "percent",  "value": 0.001},  # 美名≥天仙
]
# 前置技能等级门槛：下标 1~5 需前一技能达到（佳人←伊人100/丽人←佳人100/红粉←丽人150/婵娟←红粉200/花魁←婵娟250）
const FANGHUA_PREV_LEVEL := [0, 100, 100, 150, 200, 250, 0, 0, 0]
# 美名门槛：芳华九档与 FRIEND_TITLES 同名同序，伊人=TITLES[3] … 天仙=TITLES[11]
const FANGHUA_TITLE_BASE := 3

func _get_fanghua_arr(friend_id: String) -> Array:
	# 读存档挚友实体（g.friends 存的是解锁时刻配置拷贝；芳华等级是玩家数据必须读存档）
	var f = g.friends.get(friend_id, {})   # 挚友不存在=空字典兜底，调用方只传已拥有挚友
	if not f.has("fanghua_skills"):
		f["fanghua_skills"] = [0, 0, 0, 0, 0, 0, 0, 0, 0]   # 懒创建：旧档零迁移
	var arr = f["fanghua_skills"]
	while arr.size() < 9:
		arr.append(0)
	return arr

func get_fanghua_level(friend_id: String, idx: int) -> int:
	return int(_get_fanghua_arr(friend_id)[idx])

func get_fanghua_unlock_state(friend_id: String, idx: int) -> Dictionary:
	# {unlocked, reason}；reason 非空=未解锁原因（UI 直接展示在消耗位）
	var arr = _get_fanghua_arr(friend_id)
	var title_idx = get_friend_title_index(friend_id)
	var need_title = FANGHUA_TITLE_BASE + idx
	if title_idx < need_title:
		return {"unlocked": false, "reason": "需美名「%s」" % g.FRIEND_TITLES[need_title].title}
	var prev_req = FANGHUA_PREV_LEVEL[idx]
	if prev_req > 0 and arr[idx - 1] < prev_req:
		return {"unlocked": false, "reason": "需「%s」%d级" % [FANGHUA_SKILLS[idx - 1].name, prev_req]}
	return {"unlocked": true, "reason": ""}

func get_fanghua_cost(friend_id: String, idx: int) -> int:
	# 消耗 = ceil(100 × kᵢ × 当前等级^1.6)（方案§十四定稿公式）
	var lv = _get_fanghua_arr(friend_id)[idx]
	return int(ceil(100.0 * float(FANGHUA_SKILLS[idx].k) * pow(float(lv), 1.6)))

func get_fanghua_flower(friend_id: String) -> String:
	# 缘分之花道具 id（yyf_wudao/shengyue/yueqi/chuangzuo/yitai），映射在 friends.json 的 yyf_career。
	# ⚠️必须读配置 g.get_friend_config 不读存档快照：g.friends 是解锁时刻的配置拷贝，老档挚友没有 yyf_career 字段（踩坑32）
	return str(g.get_friend_config(friend_id).get("yyf_career", "yyf_yueqi"))

func upgrade_fanghua(friend_id: String, idx: int, batch: bool) -> Dictionary:
	# 返回 {upgraded, msg}；batch=十连（最多10级，花不足则升剩余级数，与才艺同口径）
	var arr = _get_fanghua_arr(friend_id)
	var st = get_fanghua_unlock_state(friend_id, idx)
	if not st.unlocked:
		return {"upgraded": 0, "msg": st.reason}
	var flower = get_fanghua_flower(friend_id)
	var limit = 10 if batch else 1
	var upgraded := 0
	while upgraded < limit:
		var cost = get_fanghua_cost(friend_id, idx)
		if int(g.items.get(flower, 0)) < cost:
			break
		g.items[flower] -= cost
		arr[idx] += 1
		upgraded += 1
	if upgraded == 0:
		return {"upgraded": 0, "msg": "缘分之花不足！"}
	return {"upgraded": upgraded, "msg": ""}

func get_friend_aptitude_bonus(friend_id: String) -> int:
	var fhq = _get_fanghua_arr(friend_id)   # 【新增】芳华·佳人/丽人/婵娟/花魁：缘分门客资质 +1/级
	return get_caiyi_skill_level(friend_id, "chaoqun") * int(CAIYI_SKILLS["chaoqun"]["value_per_level"]) \
		+ (fhq[1] + fhq[2] + fhq[4] + fhq[5])

# 挚友的固定加成（天生丽质 → 额外赚速）
func get_friend_fixed_bonus(friend_id: String) -> int:
	if not g.friends.has(friend_id): return 0
	var f = g.friends[friend_id]
	var total = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
	# 【新增】多才多艺（挚友才艺技能）：每级缘分门客固定赚钱 +5000
	total += get_caiyi_skill_level(friend_id, "duocai") * int(CAIYI_SKILLS["duocai"]["value_per_level"])
	total += _get_fanghua_arr(friend_id)[0] * 3000   # 【新增】芳华·伊人：缘分门客固定赚钱 +3000/级
	return total

# 挚友的百分比加成（花开富贵 → 百分比）
func get_friend_percent_bonus(friend_id: String) -> float:
	if not g.friends.has(friend_id): return 0.0
	var f = g.friends[friend_id]
	var fhp = _get_fanghua_arr(friend_id)   # 【新增】芳华·红粉/国色/仙子/天仙：缘分门客赚速 +0.1%/级
	return f.percent_skill_level * 0.05 + (fhp[3] + fhp[6] + fhp[7] + fhp[8]) * 0.001

# 谈心
# 谈心：随机一位已拥有挚友，缘分+才华，有空位则领养徒弟
# 【修改】月老层数>0且有徒弟空位：本次谈心对象改为友好最高的挚友；观音层数>0且有徒弟空位：本次领养必为双胞胎
func chat_with_friend(once: bool = true) -> Dictionary:
	_settle_energy()   # 【新增】四批：谈心/赠礼前结算精力恢复
	
	if g.energy <= 0: return {"ok": false, "reason": "精力不足"}
	
	var results = []
	if once:
		g.energy -= 1
		var keys = g.friends.keys()
		var fid = keys[randi() % keys.size()]
		# 【新增】月老/观音祝福结算（没有徒弟空位时不消耗层数）
		var bless = _prepare_chat_adoption(fid)
		fid = bless.target
		var f = g.friends[fid]
		
		var bond_gain = int(round(f.talent * (1.0 + g.collection_system.get_chat_bond_pct() + g.collection_system.get_friend_bond_category_pct(f.category))))   # 【改】三批+四批：凝冰套装%+职业单品%（c071/073/079/081）
		f.bond += bond_gain
		# 有空位则与本次谈心的挚友领养一位徒弟（观音生效时必双胞胎）
		var n = g.adopt_apprentice(fid, bless.force_twin)
		results.append({"friend_id": fid, "name": f.name, "gain": bond_gain, "adopted": n > 0, "twin": n == 2, "yuelao": bless.yuelao, "guanyin": bless.guanyin})
	else:
		while g.energy > 0:
			g.energy -= 1
			var keys = g.friends.keys()
			var fid = keys[randi() % keys.size()]
			# 【新增】一键谈心逐次结算月老/观音祝福
			var bless = _prepare_chat_adoption(fid)
			fid = bless.target
			var f = g.friends[fid]
			
			var bond_gain = int(round(f.talent * (1.0 + g.collection_system.get_chat_bond_pct() + g.collection_system.get_friend_bond_category_pct(f.category))))   # 【改】三批+四批：凝冰套装%+职业单品%（c071/073/079/081）
			f.bond += bond_gain
			# 一键谈心：有几个空位，前几位挚友就各领养一位
			var n = g.adopt_apprentice(fid, bless.force_twin)
			results.append({"friend_id": fid, "name": f.name, "gain": bond_gain, "adopted": n > 0, "twin": n == 2, "yuelao": bless.yuelao, "guanyin": bless.guanyin})
	
	return {"ok": true, "results": results}

# 与指定挚友谈心（游山玩水/吟诗作对共用）：缘分+才华，有空位则领养徒弟
# 不消耗精力，消耗由调用方（元宝/玫瑰香水）负责
# 【修改】指定谈心不触发月老（对象已由玩家指定），观音祝福正常生效（必双胞胎）
func chat_with_specific_friend(friend_id: String) -> Dictionary:
	_settle_energy()   # 【新增】四批：谈心/赠礼前结算精力恢复
	if not g.friends.has(friend_id): return {"ok": false, "reason": "未拥有该挚友"}
	var f = g.friends[friend_id]
	
	var bond_gain = int(round(f.talent * (1.0 + g.collection_system.get_chat_bond_pct() + g.collection_system.get_friend_bond_category_pct(f.category))))   # 【改】三批+四批：凝冰套装%+职业单品%（c071/073/079/081）
	f.bond += bond_gain
	# 【新增】观音祝福：有徒弟空位才生效并消耗一层
	var force_twin = false
	var guanyin_used = false
	if g.guanyin_count > 0 and g._has_empty_apprentice_slot():
		g.guanyin_count -= 1
		force_twin = true
		guanyin_used = true
	var n = g.adopt_apprentice(friend_id, force_twin)
	return {"ok": true, "name": f.name, "gain": bond_gain, "adopted": n > 0, "twin": n == 2, "guanyin": guanyin_used}

# 升级固定技能
func upgrade_friend_fixed(friend_id: String) -> bool:
	if not g.friends.has(friend_id): return false
	var f = g.friends[friend_id]
	var cost = (f.fixed_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.fixed_skill_level += 1
	return true

# 升级百分比技能
func upgrade_friend_percent(friend_id: String) -> bool:
	if not g.friends.has(friend_id): return false
	var f = g.friends[friend_id]
	var cost = (f.percent_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.percent_skill_level += 1
	return true

# 赠送
func gift_friend(friend_id: String, item_id: String) -> bool:
	_settle_energy()   # 【新增】四批：谈心/赠礼前结算精力恢复
	if not g.friends.has(friend_id): return false
	if not g.items.has(item_id) or g.items[item_id] <= 0: return false
	var f = g.friends[friend_id]
	match item_id:
		"wood_comb":
			g.items.wood_comb -= 1
			f.friendly += 1
		"rouge":
			g.items.rouge -= 1
			f.talent += 1
		"tong_zan":
			# 铜簪：友好度+2
			f.friendly += 2
		"yin_erhuan":
			# 银耳环：友好度+5
			f.friendly += 5
		"xiang_nang":
			# 香囊：才华+2
			f.talent += 2
		"huarong_xia":
			# 花容匣：才华+5
			f.talent += 5
		_:
			return false
	return true

# 挚友当前美名下标（2026-09-19 改手动晋升制）：读存档 title_index 字段，-1=无美名。
# 旧档无该字段=首次访问按旧自动规则（_calc_title_index）定格回填，不追溯、不自动涨，
# 此后只能靠 promote_title() 手动晋升（用户拍板：可晋升时美名标签亮红点提示）。
func get_friend_title_index(friend_id: String) -> int:
	if not g.friends.has(friend_id): return -1
	var f = g.friends[friend_id]
	if not f.has("title_index"):
		f["title_index"] = _calc_title_index(f)   # 懒迁移：旧自动档定格为已晋升档
	return int(f["title_index"])

# 旧自动规则：友好+才华双达标取最高档（仅用于旧档首访回填，新档晋升不走这里）
func _calc_title_index(f: Dictionary) -> int:
	var idx = -1
	for i in range(g.FRIEND_TITLES.size()):
		if f.friendly >= g.FRIEND_TITLES[i].req and f.talent >= g.FRIEND_TITLES[i].req:
			idx = i
	return idx

# 可晋升的下一档下标（属性双达标 且 未晋升到顶），-1=不可晋升——美名红点判定唯一入口
func get_promotable_title_index(friend_id: String) -> int:
	if not g.friends.has(friend_id): return -1
	var nxt = get_friend_title_index(friend_id) + 1
	if nxt >= g.FRIEND_TITLES.size(): return -1
	var f = g.friends[friend_id]
	if f.friendly >= g.FRIEND_TITLES[nxt].req and f.talent >= g.FRIEND_TITLES[nxt].req:
		return nxt
	return -1

# 手动晋升美名：条件达标则定格下一档并返回 true，否则 false
func promote_title(friend_id: String) -> bool:
	var nxt = get_promotable_title_index(friend_id)
	if nxt < 0: return false
	g.friends[friend_id]["title_index"] = nxt
	return true

# 挚友当前美名（无美名返回"无"）
func get_friend_title(friend_id: String) -> String:
	var idx = get_friend_title_index(friend_id)
	return g.FRIEND_TITLES[idx].title if idx >= 0 else "无"
