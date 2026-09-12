# ============================================================
# 副业技能系统（批次3补：门客面板「副业」tab 的资质类技能统一托管）
# 五个技能均为 每级资质+1，区别只在货币/上限/消耗曲线（side_skill.json 配置）：
#   市井百业：百业经验（每门客池，bank_system）固定300/级，上限300（= 300经验=1资质丹 规律平移）
#   百工百业：行当通识（占位池）固定消耗，上限200（消耗数值待定，跟玩法货币一起定，json 可改）
#   物宝天华：银元（占位池）消耗曲线同庖丁解牛（100+(L-1)+int(L/10)），上限200
#   庖丁解牛：厨艺值（inn_system 全局池）曲线 100+(L-1)+int(L/10)，上限300
#   XX之道：对应职业之道书道具×100/级（士→仕途之道 … 侠→侠义之道），上限200
# 存储 {hero_id: {技能key: 级}} 随 get_save_data 落盘；hangshi/yinyuan 为占位池（待各自玩法接入产出）
# ============================================================
class_name SideSkillSystem
extends RefCounted

# GameData 中枢引用（不标类型，避免类之间循环引用导致解析失败）
var g

func _init(p_g):
	g = p_g

# ============ 存档 ============
var levels: Dictionary = {}   # {hero_id: {"shijing": n, "baigong": n, "wubao": n, "paoding": n, "zhidao": n}}
var hangshi: int = 0          # 行当通识（占位池，待百工百业玩法接入产出）
var yinyuan: int = 0          # 银元（占位池，待物宝天华玩法接入产出）

func get_save_data() -> Dictionary:
	return {"side_levels": levels, "side_hangshi": hangshi, "side_yinyuan": yinyuan}

# 从扁平存档表认领本系统字段（老档缺字段保持初始值，类型防御防一处崩整轮）
func load_save_data(s: Dictionary):
	if s.has("side_levels") and s.side_levels is Dictionary: levels = s.side_levels
	if s.has("side_hangshi"): hangshi = int(s.side_hangshi)
	if s.has("side_yinyuan"): yinyuan = int(s.side_yinyuan)

# ============ 配置读取（side_skill.json，代码默认值兜底） ============
# 技能显示/遍历顺序
func get_skill_keys() -> Array:
	return ["shijing", "baigong", "wubao", "paoding", "zhidao"]

func _cfg(key: String) -> Dictionary:
	var skills: Dictionary = g._side_skill_configs.get("skills", {})
	return skills.get(key, {})

# 庖丁解牛曲线：L→L+1 消耗 = base+(L-1)+int(L/10)：1→2=100、2→3=101 … 12→13=112（用户拍板 2026-09-12）
func _paoding_curve(level: int) -> int:
	var base := int(g._side_skill_configs.get("paoding_curve", {}).get("base", 100))
	if level < 1: return base
	return base + (level - 1) + int(level / 10.0)

# 职业→之道书道具 id
func get_career_book(career: String) -> String:
	var books: Dictionary = g._side_skill_configs.get("career_books", {})
	return str(books.get(career, ""))

# ============ 查询 ============
func get_hero_level(hero_id: String, key: String) -> int:
	var d: Dictionary = levels.get(hero_id, {})
	return int(d.get(key, 0))

func get_max_level(key: String) -> int:
	return int(_cfg(key).get("max", 200))

# 全部门客资质加成接入点：五个副业技能每级各 +1 资质（HeroData 调用）
func get_hero_aptitude_bonus(hero_id: String) -> int:
	var total := 0
	for key in get_skill_keys():
		total += get_hero_level(hero_id, key)
	return total

# 下级消耗（含货币显示名）；已满级返回 cost=-1
func get_next_cost(hero_id: String, key: String) -> Dictionary:
	var cur := get_hero_level(hero_id, key)
	if cur >= get_max_level(key):
		return {"cost": -1, "currency": ""}
	var conf := _cfg(key)
	var cost := 0
	var cur_name := ""
	match str(conf.get("currency", "")):
		"baiye":
			cost = int(conf.get("cost", 300))   # 固定300/级
			cur_name = "百业经验"
		"hangshi":
			cost = int(conf.get("cost", 100))   # 固定消耗（数值占位，待定）
			cur_name = "行当通识"
		"yinyuan":
			cost = _paoding_curve(cur)          # 曲线同庖丁解牛
			cur_name = "银元"
		"cuisine":
			cost = _paoding_curve(cur)          # 庖丁解牛曲线
			cur_name = "厨艺值"
		"career_book":
			cost = int(conf.get("cost", 100))   # 100本/级
			var book_id := get_career_book(str(g.heroes.get(hero_id, {}).get("category", "")))
			cur_name = book_id
			if g.ITEM_CONFIG.has(book_id):
				cur_name = str(g.ITEM_CONFIG[book_id].get("name", book_id))
	return {"cost": cost, "currency": cur_name}

# 供 hero_page 副业 tab 渲染的行数据
func get_hero_skill_rows(hero_id: String) -> Array:
	var rows := []
	if not g.heroes.has(hero_id): return rows
	for key in get_skill_keys():
		var conf := _cfg(key)
		var lv := get_hero_level(hero_id, key)
		var cost_info := get_next_cost(hero_id, key)
		var disp_name := str(conf.get("name", key))
		# 之道按职业显示具体书名（如 仕途之道）
		if str(conf.get("currency", "")) == "career_book":
			var book_id := get_career_book(str(g.heroes[hero_id].get("category", "")))
			if g.ITEM_CONFIG.has(book_id):
				disp_name = str(g.ITEM_CONFIG[book_id].get("name", disp_name))
		rows.append({"key": key, "name": disp_name, "level": lv,
			"max": int(conf.get("max", 200)), "cost": int(cost_info.get("cost", 0)),
			"currency": str(cost_info.get("currency", ""))})
	return rows

# ============ 升级（mode="single" 升1级 / "bulk" 一键升满） ============
func upgrade(hero_id: String, key: String, mode: String = "single") -> int:
	if not g.heroes.has(hero_id): return 0
	var max_lv := get_max_level(key)
	var up := 0
	var limit := 1 if mode == "single" else (max_lv - get_hero_level(hero_id, key))
	while up < limit and get_hero_level(hero_id, key) + up < max_lv:
		if not _spend_one(hero_id, key, get_hero_level(hero_id, key) + up): break
		up += 1
	if up > 0:
		var d: Dictionary = levels.get(hero_id, {})
		d[key] = get_hero_level(hero_id, key) + up
		levels[hero_id] = d
	return up

# 扣一次「level→level+1」所需货币，余额不足返回 false（各货币池归属不变：百业经验在 bank、厨艺值在 inn）
func _spend_one(hero_id: String, key: String, level: int) -> bool:
	var conf := _cfg(key)
	match str(conf.get("currency", "")):
		"baiye":
			# 复用「300百业经验=1资质丹」抵扣规则：1级=300经验
			return g.bank_system.spend_baiye_for_pills(hero_id, 1)
		"hangshi":
			var cost_h := int(conf.get("cost", 100))
			if hangshi < cost_h: return false
			hangshi -= cost_h
			return true
		"yinyuan":
			var cost_y := _paoding_curve(level)
			if yinyuan < cost_y: return false
			yinyuan -= cost_y
			return true
		"cuisine":
			return g.inn_system.try_spend_cuisine(_paoding_curve(level))
		"career_book":
			var book := get_career_book(str(g.heroes[hero_id].get("category", "")))
			var need := int(conf.get("cost", 100))
			if book == "" or int(g.items.get(book, 0)) < need: return false
			g.items[book] = int(g.items.get(book, 0)) - need
			return true
	return false
