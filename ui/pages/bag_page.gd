# ============================================================
# 背包页（含道具使用/人参/门客盒子选择器）（第3批重构：从 game_controller.gd 拆分而来）
# 纯逻辑模块：场景节点查找/弹窗挂载/共享工具/跨页调用一律经 c.xxx
# （c = game_controller 根脚本，语义与原 controller 内调用完全一致）
# data = GameData 数据中枢，用法与原来完全一致
# ============================================================
class_name BagPage
extends RefCounted

var c      # game_controller 根脚本引用
var data   # GameData 数据中枢引用

	# ── 本页 UI 状态变量（原 game_controller 成员，第3批收尾迁入）──
var _pending_ginseng_count: int = 0
var _pending_ginseng_type: String = ""
# 【新增】2026-09-16 百业札记待使用数量（选中门客后结算）
var _pending_baiye_count: int = 0
#【新增】固定为1的道具类型：数量锁定单次开启（门客/挚友盒解锁对象唯一；促织架按ID唯一存放）
const SINGLE_USE_TYPES: Array = ["hero_box", "friend_box", "wushuang_cuzhi_box", "cos_box",
	"friend_cos_box", "friend_jinyi_box", "friend_multi_box"]

# 【新增】背包底部栏当前页（2026-09-10 商会第二批）：item=物品 compose=合成

# 【新增】2026-11-01 背包复刻并入：默认显示原作 FairyGUI 整窗（ui/pages/bag_fgui_view.gd），
# 右上「旧版」钮可切回旧版功能背包（道具使用/合成选择器全部保留）；"fgui"=原作整窗 "legacy"=旧版
var _fgui: BagFguiView = null

# 【新增】2026-11-01 道具图标：6 位图标 id 图库 + 工程道具 id 映射（clean/item_icons 流水线产出）
const ICON_DIR := "res://assets/items/icons/"
const ICON_MAP_PATH := "res://data/item_icon_map.json"
var _icon_map: Dictionary = {}
var _icon_map_loaded: bool = false
var _icon_tex_cache: Dictionary = {}   # 道具 id -> Texture2D（点开详情弹窗不重复 load 磁盘）

# 【新增】合成配方：小资质丹20合1资质丹；残破缀玉20合1指定缀玉（用户拍板）
const COMPOSE_RECIPES: Array = [
	{"output": "aptitude_pill", "material": "small_aptitude_pill", "ratio": 20},
	{"output": "panzhu_zhuiyu", "material": "canpo_zhuiyu", "ratio": 20},
	{"output": "zhimeng_zhuiyu", "material": "canpo_zhuiyu", "ratio": 20},
	{"output": "yingge_zhuiyu", "material": "canpo_zhuiyu", "ratio": 20},
	{"output": "luohua_zhuiyu", "material": "canpo_zhuiyu", "ratio": 20},
	{"output": "liuyun_zhuiyu", "material": "canpo_zhuiyu", "ratio": 20},
	# 【新增】2026-09-15 客栈兑换商店合成入口移除，三条配方迁移至此（配比原样保留）
	{"output": "hero_token", "material": "can_tie", "ratio": 10},
	{"output": "kaishan_ling", "material": "kaishan_yin", "ratio": 20},
	{"output": "zongjiang_ling", "material": "zongjiang_yin", "ratio": 20},
	# 【新增】2026-09-18 刻钟卡×60→时辰卡；无双精魄×20→珍兽白泽（白泽同驺虞走珍兽产出分支）
	{"output": "hour_card", "material": "kezhong_card", "ratio": 60},
	{"output": "bai_ze", "material": "wushuang_jingpo", "ratio": 20, "output_type": "beast"},
	# 【新增】2026-09-16 无双兽骨×40→珍兽驺虞（产出是珍兽不是道具：格子/弹窗走 output_type 分支）
	{"output": "zou_yu", "material": "wushuang_gugu", "ratio": 40, "output_type": "beast"},
]

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

# 【新增 2026-11-01】离开背包页时收尾：原作整窗是挂在根节点上的覆盖层（不是 BagPage 子节点），
# 必须显式隐藏，否则回府邸还顶着背包窗。顶栏/底栏不再隐藏，无需还原。
func leave_fgui() -> void:
	if _fgui != null:
		_fgui.set_visible(false)

func generate_bag_list():
	if not c.has_node("PageContainer/BagPage"): return
	var bag_page = c.get_node("PageContainer/BagPage")

	# 背包页＝原作 FairyGUI 整窗（2026-11-01 起旧版功能背包已删除，不再有双模式切换）
	# 懒建口径：仅背包页可见时才加载五包+建整窗（_enter_game 启动期调用时页面未显示，跳过不白付加载）
	if not bag_page.visible:
		return
	if _fgui == null:
		_fgui = BagFguiView.new(c)
	if _fgui.ensure_built(bag_page):
		# 整窗挂根节点后不会被页面显隐带着走，进背包必须显式显示
		_fgui.set_visible(true)
		_fgui.refresh_items()
		return
	# 加载失败兜底：旧版背包已删，只能明确提示（不再静默留空白页）
	c._show_success_popup("原作背包界面加载失败，请检查 assets/fgui 下的五个包", 0.0, "warn")


# 【新增】底部栏切换

# 【新增】2026-11-01 背包复刻并入：原作/旧版切换钮（挂 BagPage 宿主右上角，两种模式共用）


func _item_icon_texture(item_id: String) -> Texture2D:
	if _icon_tex_cache.has(item_id):
		return _icon_tex_cache[item_id]
	if not _icon_map_loaded:
		_icon_map_loaded = true
		if FileAccess.file_exists(ICON_MAP_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ICON_MAP_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				var m: Variant = parsed.get("map", null)
				if typeof(m) == TYPE_DICTIONARY:
					_icon_map = m
	var ent: Dictionary = _icon_map.get(item_id, {})
	var icon_id := str(ent.get("icon", ""))
	if icon_id == "":
		_icon_tex_cache[item_id] = null
		return null
	var path := ICON_DIR + icon_id + ".png"
	if not ResourceLoader.exists(path):
		_icon_tex_cache[item_id] = null
		return null
	var tex := load(path) as Texture2D
	_icon_tex_cache[item_id] = tex
	return tex

# 【新增 2026-11-01】点格子→详情弹窗改为延迟一帧创建：弹窗要建遮罩 + 九切片皮肤 + 匾额灯笼十余个节点，
# 服装详情：图标 + 归属（谁的什么皮肤）+ 去哪解锁/升级
# 背包里的服装是「凭证」，真正穿戴/升级在门客换装界面
func _show_cos_detail_popup(cos_id: String):
	var hero_id := ""
	var cfg: Dictionary = {}
	var heroes: Dictionary = data.costume_configs.get("hero_costumes", {})
	for hid in heroes.keys():
		for item in heroes[hid]:
			if str(item.get("id", "")) == cos_id:
				hero_id = hid
				cfg = item
				break
		if not cfg.is_empty():
			break
	var cos_name: String = str(cfg.get("name", cos_id))
	var quality: String = str(cfg.get("quality", "素装"))
	var hero_name: String = hero_id
	var hcfg: Dictionary = data.get_hero_config(hero_id)
	if not hcfg.is_empty():
		hero_name = str(hcfg.get("name", hero_id))
	var skin: String = str(cfg.get("skin", ""))
	var tex: Texture2D = null
	if skin != "":
		var p: String = "res://assets/costumes/icons/%s.png" % skin
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	var popup = c._create_base_popup("服装详情", Vector2(400, 470) if tex != null else Vector2(400, 380))
	popup.name = "ItemDetailPopup"
	var vbox = popup.get_child(0)
	if tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = tex
		icon_rect.custom_minimum_size = Vector2(112, 112)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)
	var name_lbl := Label.new()
	name_lbl.text = "【%s】%s" % [quality, cos_name]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_lbl)
	var owner_lbl := Label.new()
	owner_lbl.text = "归属：%s" % hero_name
	owner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(owner_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = "已获得的服装，可在「门客 → %s → 换装」里穿戴、解锁与升级。" % hero_name
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)
	var go_btn := Button.new()
	go_btn.text = "去换装"
	go_btn.custom_minimum_size = Vector2(160, 40)
	go_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go_btn.pressed.connect(_on_cos_detail_go.bind(hero_id))
	vbox.add_child(go_btn)
	c.add_child(popup)

func _on_cos_detail_go(hero_id: String):
	c._safe_close("ItemDetailPopup")
	if data.costume_system != null and c.costume_view != null:
		c.costume_view.show_hero_costume_popup(hero_id)


# 在 FGUI 的点击回调栈里同步建会明显顿一下；延迟一帧既不丢操作，点击帧也不再卡。
func _show_item_detail_popup(item_id: String):
	_show_item_detail_popup_now.call_deferred(item_id)

func _show_item_detail_popup_now(item_id: String):
	# 同名弹窗已在场先收掉（延迟一帧可能叠出两个）
	var old: Node = c.get_node_or_null("ItemDetailPopup")
	if old != null:
		old.queue_free()
	# 【新增】服装道具（cos:<cos_id>）：不是 items.json 里的条目，单独走服装详情
	if item_id.begins_with("cos:"):
		_show_cos_detail_popup(item_id.substr(4))
		return
	var cfg = data.ITEM_CONFIG.get(item_id, {})
	var count = data.items.get(item_id, 0)
	if item_id == "lottery_ticket":
		count = data.lottery_ticket

	var tex := _item_icon_texture(item_id)

	var popup = c._create_base_popup(cfg.get("name", "物品详情"), Vector2(400, 460) if tex != null else Vector2(400, 380))
	popup.name = "ItemDetailPopup"
	var vbox = popup.get_child(0)

	# 图标（原作详情弹窗顶部大图标；缺图时不占位）
	if tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = tex
		icon_rect.custom_minimum_size = Vector2(112, 112)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)

	# 数量
	var count_lbl = Label.new()
	count_lbl.text = "数量：x%d" % count
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_lbl)

	# 描述
	var desc_lbl = Label.new()
	desc_lbl.text = cfg.get("desc", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)

	var use_cfg = cfg.get("use", {})
	if use_cfg.is_empty() or count <= 0:
		c.add_child(popup)
		return

	var qty_spin: SpinBox = null
	if SINGLE_USE_TYPES.has(use_cfg.get("type", "")):
		# 【新增】固定为1类型：锁定数量，不显示选择器
		var fix_lbl = Label.new()
		fix_lbl.text = "使用数量：1"
		fix_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(fix_lbl)
	else:
		# 数量选择器：滑条+输入框双向同步，默认1（min_val 即初始值，复用全局辅助默认口径）
		var pair = c._create_slider_spin_pair(vbox, count)
		qty_spin = pair.spin

	var use_btn = Button.new()
	use_btn.text = use_cfg.get("btn", "使用")
	use_btn.custom_minimum_size = Vector2(120, 40)
	use_btn.pressed.connect(func():
		_on_detail_use(item_id, 1 if qty_spin == null else int(qty_spin.value), popup))
	vbox.add_child(use_btn)

	c.add_child(popup)

# 【新增】详情弹窗统一使用入口：0提示选数量；按类型分派（直接消耗按N / 二次选择带N / 固定1直开）
func _on_detail_use(item_id: String, qty: int, popup: Control):
	var use_cfg = data.ITEM_CONFIG.get(item_id, {}).get("use", {})
	var count = int(data.items.get(item_id, 0))
	if qty <= 0:
		c._show_success_popup("请先选择使用数量", 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	if qty > count:
		qty = count
	match use_cfg.get("type", ""):
		"quantity":
			popup.queue_free()
			_use_items(item_id, qty)
		"ginseng":
			popup.queue_free()
			_pending_ginseng_count = qty
			_pending_ginseng_type = item_id
			_show_ginseng_selector()
		"baiye_zhaji":
			# 【新增】2026-09-16 百业札记：选数量→门客选择器（按赚速降序）→该门客百业经验+10/本
			popup.queue_free()
			_pending_baiye_count = qty
			_show_baiye_selector()
		"soul_stone_box":
			popup.queue_free()
			_open_soul_boxes(item_id, "normal", qty)
		"soul_wushuang_box":
			popup.queue_free()
			_open_soul_boxes(item_id, "wushuang", qty)
		"hero_box":
			popup.queue_free()
			_show_hero_box_selector()
		"friend_box":
			popup.queue_free()
			if has_method("_show_friend_box_selector"):
				_show_friend_box_selector()
			else:
				c._show_success_popup("挚友盒子功能开发中", 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		"item_box":
			popup.queue_free()
			_show_item_box_selector(qty)
		"cos_box":
			# 【新增】服装盒子：先关详情弹窗再开选择器（与 hero_box 等先例一致）
			popup.queue_free()
			_show_cos_box_selector()
		"friend_cos_box":
			# 【新增】挚友素装盒：选该挚友本人或其任一素装
			popup.queue_free()
			_show_friend_cos_box_selector(item_id)
		"friend_jinyi_box":
			# 【新增】挚友锦衣盒：选该挚友的锦衣之一
			popup.queue_free()
			_show_friend_jinyi_box_selector(item_id)
		"friend_multi_box":
			# 【新增】挚友锦盒：选五个挚友素装盒之一
			popup.queue_free()
			_show_friend_multi_box_selector(item_id)
		"manhuang_box":
			popup.queue_free()
			_show_manhuang_box_selector(qty)
		"hun_gu_box":
			popup.queue_free()
			_show_hungu_box_selector(qty)
		"wushuang_cuzhi_box":
			popup.queue_free()
			c.show_wushuang_box_selector()
		"suit_frag_box":
			popup.queue_free()
			c.show_suit_frag_box_selector(item_id, qty)
		"zixuan_baoyin":
			# 【新增】2026-09-18 自选宝印：N连开扣N个，二选一得N个所选
			popup.queue_free()
			_show_zixuan_baoyin_selector(qty, false)
		"zixuan_baoyin_fragment":
			# 【新增】2026-09-18 自选宝印碎片：N连开扣N个，二选一得N个所选
			popup.queue_free()
			_show_zixuan_baoyin_selector(qty, true)
		"treasure_box":   # 【新增】珍宝箱：五种商品×500随机
			popup.queue_free()
			_open_treasure_boxes(qty)

# 【新增】按数量使用道具（结算体抽出，详情弹窗与时辰卡入口共用）
func _use_items(item_id: String, count: int):
	var result = data.use_item(item_id, count)
	if result.get("ok", false):
		update_bag_list()
		c.update_all_ui()
		# 带 gains 明细的道具（关卡宝箱）弹窗展示明细，其余维持飘字提示
		if result.has("gains"):
			_show_item_gains_popup("打开关卡宝箱", result.gains)
		else:
			c._show_success_popup(result.get("msg", "使用成功"), 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	else:
		c._show_success_popup(result.get("msg", "使用失败"), 0.0, "warn")   # 【改】飘字退休→warn 弹窗

func _on_item_use_confirmed(spin: SpinBox):
	var count = int(spin.value)
	var item_id = c._quantity_item_id
	c._quantity_item_id = ""
	c._close_quantity_selector()
	if item_id == "":
		return
	_use_items(item_id, count)   # 【改】结算体已抽出，与详情弹窗共用

func update_bag_list():
	generate_bag_list()


func _show_ginseng_selector():
	# 【改】UI统一批A：迁弹窗工厂（✕/遮罩/居中接管，删【取消】钮与自建样式）
	if c.has_node("GinsengSelector"): return

	var panel = c._create_base_popup("选择门客使用%s" % data.ITEM_CONFIG.get(_pending_ginseng_type, {}).get("name", "人参"), Vector2(500, 400))
	panel.name = "GinsengSelector"
	var vbox = panel.get_child(0)

	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(480, 300)   # 选择器固定显示区（组件滚动区默认无下限高）

	# 门客按实时赚速降序排列（走收入缓存表）
	var hero_ids = data.heroes.keys()
	hero_ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hero_id in hero_ids:
		var h = data.heroes[hero_id]
		var btn = Button.new()
		btn.text = "【%s】%s Lv.%d | %s/秒" % [h.name, h.category, h.level, c.format_number(data.get_hero_income(hero_id))]
		btn.pressed.connect(_on_ginseng_target_selected.bind(hero_id))
		list.add_child(btn)

	c.add_child(panel)

func _on_ginseng_target_selected(hero_id: String):
	var count = _pending_ginseng_count
	var item_id = _pending_ginseng_type
	if item_id == "":
		_close_ginseng_selector()
		return
	if data.items.get(item_id, 0) < count:
		_close_ginseng_selector()
		return
	
	data.items[item_id] -= count
	if item_id == "ginseng":
		data.heroes[hero_id].extra_income += 2000 * count
	else:
		data.heroes[hero_id].extra_income += 20000 * count
	
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""
	_close_ginseng_selector()
	update_bag_list()
	c.update_all_ui()

func _close_ginseng_selector():
	# 【改】迁工厂后挂 c 根节点，_safe_close 连带摘遮罩
	c._safe_close("GinsengSelector")
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""

# 【新增】2026-09-16 百业札记门客选择器：结构同人参选择器（按实时赚速降序，按钮带赚速与当前百业经验）
func _show_baiye_selector():
	# 【改】UI统一批A：迁弹窗工厂（✕/遮罩/居中接管，删【取消】钮与自建样式）
	if c.has_node("BaiyeSelector"): return

	var panel = c._create_base_popup("选择门客使用百业札记（+%d百业经验/本）" % int(data.ITEM_CONFIG.get("baiye_zhaji", {}).get("use", {}).get("per", 10)), Vector2(500, 400))
	panel.name = "BaiyeSelector"
	var vbox = panel.get_child(0)

	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(480, 300)   # 选择器固定显示区（组件滚动区默认无下限高）

	# 门客按实时赚速降序排列（同人参选择器）
	var hero_ids = data.heroes.keys()
	hero_ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hero_id in hero_ids:
		var h = data.heroes[hero_id]
		var btn = Button.new()
		btn.text = "【%s】%s Lv.%d | %s/秒 | 百业经验 %s" % [h.name, h.category, h.level,
			c.format_number(data.get_hero_income(hero_id)), c.format_number(data.hero_system.get_baiye(hero_id))]
		btn.pressed.connect(_on_baiye_target_selected.bind(hero_id))
		list.add_child(btn)

	c.add_child(panel)

func _on_baiye_target_selected(hero_id: String):
	var count = _pending_baiye_count
	if count <= 0 or int(data.items.get("baiye_zhaji", 0)) < count:
		_close_baiye_selector()
		return
	# 每本 +per 百业经验（per 进道具 use 配置，不硬编码）；入钱庄百业个人池
	var per: int = int(data.ITEM_CONFIG.get("baiye_zhaji", {}).get("use", {}).get("per", 10))
	data.items["baiye_zhaji"] = int(data.items.get("baiye_zhaji", 0)) - count
	data.hero_system.add_baiye(hero_id, per * count)
	c._show_success_popup("【%s】百业经验 +%d" % [data.heroes[hero_id].name, per * count], 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	_pending_baiye_count = 0
	_close_baiye_selector()
	update_bag_list()
	c.update_all_ui()

func _close_baiye_selector():
	# 【改】迁工厂后挂 c 根节点，_safe_close 连带摘遮罩
	c._safe_close("BaiyeSelector")
	_pending_baiye_count = 0

func _show_hero_box_selector():
	if c.has_node("HeroBoxSelector"): return
	
	var panel = c._create_base_popup("选择门客", Vector2(460, 500), Vector2(346, 120))
	panel.name = "HeroBoxSelector"
	var vbox = panel.get_child(0)
	
	# 按名字搜索（物品盒子同款）
	var search = LineEdit.new()
	search.placeholder_text = "输入门客名字搜索…"
	vbox.add_child(search)
	c._hook_web_cjk_input(search, "门客名字")
	
	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(440, 336)   # 选择器固定显示区（组件滚动区默认无下限高）
	
	var entries: Array = []
	var has_unlockable = false
	for hero_id in data.get_all_hero_ids():
		if data.heroes.has(hero_id): continue  # 已拥有的跳过
		
		var cfg = data.get_hero_config(hero_id)
		var btn = Button.new()
		var vip_lv = data.get_hero_unlock_vip(hero_id)
		btn.text = "【%s】%s  |  VIP%d解锁" % [cfg.name, cfg.category, vip_lv]
		btn.pressed.connect(_on_hero_box_selected.bind(hero_id))
		list.add_child(btn)
		entries.append({"btn": btn, "text": cfg.name})
		has_unlockable = true
	search.text_changed.connect(func(t: String): _filter_named_buttons(entries, t))
	
	if not has_unlockable:
		var empty = Label.new()
		empty.text = "所有门客已拥有"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	
	c.add_child(panel)

# 【新增】挚友盒子选择弹窗：列出所有未拥有的挚友，点击即获得（不可重复）
func _show_friend_box_selector():
	if c.has_node("FriendBoxSelector"): return
	
	var panel = c._create_base_popup("选择挚友", Vector2(460, 500), Vector2(346, 120))
	panel.name = "FriendBoxSelector"
	var vbox = panel.get_child(0)
	
	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(440, 380)   # 选择器固定显示区（组件滚动区默认无下限高）
	
	var has_unlockable = false
	for friend_id in data.get_all_friend_ids():
		if data.friends.has(friend_id): continue  # 已拥有的跳过
		
		var cfg = data.get_friend_config(friend_id)
		var btn = Button.new()
		var vip_lv = data.get_friend_unlock_vip(friend_id)
		btn.text = "【%s】%s  |  VIP%d解锁" % [cfg.name, "挚友", vip_lv]
		btn.pressed.connect(_on_friend_box_selected.bind(friend_id))
		list.add_child(btn)
		has_unlockable = true
	
	if not has_unlockable:
		var empty = Label.new()
		empty.text = "所有挚友已拥有"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	
	c.add_child(panel)

# 【改】魂石宝箱N连开：一次扣N个，N个结果汇总进一个弹窗
func _open_soul_boxes(item_id: String, kind: String, n: int):
	if int(data.items.get(item_id, 0)) < n:
		c._show_success_popup("没有可开启的" + data.ITEM_CONFIG.get(item_id, {}).get("name", "宝箱"), 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	data.items[item_id] = int(data.items.get(item_id, 0)) - n
	var lines: Array = []
	for i in range(n):
		var res: Dictionary = data.soul_system.open_box(kind)
		var st: Dictionary = res.get("stone", {})
		var parts: Array = []
		for cell in st.get("cells", []):
			parts.append("%s+%d" % [cell.get("color", "?"), int(cell.get("apt", 0))])
		lines.append("【%s】魂石（%d格）：%s" % [st.get("quality", "?"), st.get("cells", []).size(), "  ".join(parts)])
	# 结果汇总弹窗
	var popup = c._create_base_popup("开启结果（%d个）" % n, Vector2(460, 420))
	popup.name = "SoulBoxResultPopup"
	var svbox = popup.get_child(0)
	var list: VBoxContainer = c.popup_scroll(svbox)
	list.custom_minimum_size = Vector2(0, 320)   # 结果/获得列表固定显示高度（组件滚动区默认无下限高）
	for line in lines:
		var lbl = Label.new()
		lbl.text = line
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(lbl)
	c.add_child(popup)
	update_bag_list()
	c.update_all_ui()

# 【新增】挚友盒子选择回调
func _on_friend_box_selected(friend_id: String):
	if data.items.get("friend_box", 0) < 1:
		c._safe_close("FriendBoxSelector")
		return
	
	data.items.friend_box -= 1
	data.unlock_friend(friend_id)
	
	var cfg = data.get_friend_config(friend_id)
	c._safe_close("FriendBoxSelector")
	# 【改】成功反馈铺开：获得弹窗
	c._show_success_popup("获得挚友\n【%s】" % cfg.name)
	c.update_all_ui()
	update_bag_list()

# 【改】物品盒子选择弹窗：数量由详情弹窗带入，这里只选道具
func _show_item_box_selector(p_qty: int):
	if c.has_node("ItemBoxSelector"): return

	var have = data.items.get("item_box", 0)
	if have <= 0: return

	var panel = c._create_base_popup("物品盒子（使用%d个）" % p_qty, Vector2(460, 520), Vector2(346, 100))
	panel.name = "ItemBoxSelector"
	var vbox = panel.get_child(0)

	var qty_lbl = Label.new()
	qty_lbl.text = "选择道具，获得 ×%d" % p_qty
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(qty_lbl)

	# 【新增】按名字搜索（道具多，防眼花缭乱）
	var search = LineEdit.new()
	search.placeholder_text = "输入道具名字搜索…"
	vbox.add_child(search)
	c._hook_web_cjk_input(search, "道具名字")   # Web 端中文 IME 引擎级未修，聚焦弹原生 prompt

	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(440, 360)   # 选择器固定显示区（组件滚动区默认无下限高）

	# 只排除物品盒子自身（防止递归）；服装/门客等盒子只能开出对应类别，无递归风险
	var exclude_ids = ["item_box"]
	var entries: Array = []
	for item_id in data.ITEM_CONFIG.keys():
		if item_id in exclude_ids: continue

		var cfg = data.ITEM_CONFIG[item_id]
		var btn = Button.new()
		btn.text = cfg.name
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.pressed.connect(_on_item_box_selected.bind(item_id, p_qty))
		list.add_child(btn)
		entries.append({"btn": btn, "text": btn.text})
	search.text_changed.connect(func(t): _filter_named_buttons(entries, t))


	c.add_child(panel)

# 【改】物品盒子选择回调（批量）：N由详情弹窗带入，扣N盒得N个选定道具
func _on_item_box_selected(item_id: String, count: int):
	if data.items.get("item_box", 0) < count:
		c._safe_close("ItemBoxSelector")
		return
	data.items.item_box -= count
	data.items[item_id] = data.items.get(item_id, 0) + count
	var cfg = data.ITEM_CONFIG.get(item_id, {})
	c._safe_close("ItemBoxSelector")
	c._show_success_popup("使用%d个物品盒子，获得【%s】×%d" % [count, cfg.get("name", item_id), count], 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	c.update_all_ui()
	update_bag_list()

# 【新增】搜索过滤：按名字筛选弹窗按钮（物品盒子/服装盒子通用）
func _filter_named_buttons(entries: Array, text: String) -> void:
	var q := text.strip_edges().to_lower()
	for e in entries:
		e["btn"].visible = (q == "" or String(e["text"]).to_lower().contains(q))

# 【新增】服装盒子选择弹窗：从所有服装中选一件（加库存不自动解锁，到所属门客服装页解锁）
# 【新增】挚友盒子：素装盒 / 锦衣盒 / 多选锦盒（2026-11-02 用户口径）
# 素装盒 = 选「该挚友本人」或「该挚友任一素装」；锦衣盒 = 选该挚友任一锦衣；
# 锦盒(friend_multi_box) = 选五个挚友素装盒之一。
func _friend_id_from_box(item_id: String) -> String:
	for prefix in ["friend_cos_box_", "friend_jinyi_box_"]:
		if item_id.begins_with(prefix):
			return item_id.substr(prefix.length())
	return ""

func _box_option_rows(friend_id: String, quality: String, with_friend: bool) -> Array:
	var rows: Array = []
	var fname: String = data.get_friend_config(friend_id).get("name", friend_id)
	if with_friend:
		rows.append({"label": "【挚友】%s" % fname, "kind": "friend", "id": friend_id, "name": fname,
			"owned": data.friends.has(friend_id)})
	for cfg in data.costume_system.get_friend_costume_cfgs(friend_id):
		if quality != "" and str(cfg.get("quality", "")) != quality:
			continue
		var cos_id := str(cfg.get("id", ""))
		rows.append({"label": "【%s】%s" % [cfg.get("quality", ""), cfg.get("name", "")],
			"kind": "cos", "id": cos_id, "name": str(cfg.get("name", "")),
			"quality": str(cfg.get("quality", "")), "skin": str(cfg.get("skin", "")),
			"owned": data.costume_system.get_friend_cos_copies(friend_id, cos_id) > 0})
	return rows

# 选择器行的木牌底：暗底 + 品质色描边；已拥有时整体压灰
func _style_option_row(btn: Button, quality: String, owned: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3b342c") if owned else Color("#4a3524")
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color("#6d6259") if owned else _quality_border_color(quality)
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, sb)
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = Color("#3b342c")
	btn.add_theme_stylebox_override("disabled", dis)
	var fc := Color("#cfc6b8") if owned else Color("#f6e6c8")
	btn.add_theme_color_override("font_color", fc)
	btn.add_theme_color_override("font_hover_color", fc)
	btn.add_theme_color_override("font_disabled_color", Color("#cfc6b8"))

func _quality_border_color(quality: String) -> Color:
	match quality:
		"素装":
			return Color("#6bb3e0")
		"华服":
			return Color("#f0a13c")
		"锦衣":
			return Color("#e0553a")
		"堇书":
			return Color("#a05fd0")
	return Color("#8a7a5e")

	# 选择器行图标：挚友=头像、服装=服装图标、盒子=道具图标；找不到图返回空
func _box_row_icon_path(row: Dictionary) -> String:
	var kind := str(row.get("kind", ""))
	if kind == "friend":
		var p := "res://assets/portraits/friends_head/%s.png" % str(row.get("id", ""))
		return p if ResourceLoader.exists(p) else ""
	if kind == "cos":
		var skin := str(row.get("skin", ""))
		if skin == "":
			return ""
		var cp := "res://assets/costumes/icons/%s.png" % skin
		return cp if ResourceLoader.exists(cp) else ""
	return ""

# 把贴图缩到指定边长（Button 的 icon 直接用原图会撑成 120px）
func _scaled_icon(path: String, side: int) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var src: Texture2D = load(path) as Texture2D
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null:
		return src
	img = img.duplicate()
	img.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

# 背包道具图标的资源路径（GLoader 直接吃 res:// 路径）
func _item_icon_path(item_id: String) -> String:
	_item_icon_texture(item_id)          # 确保 _icon_map 已懒加载
	var ent: Dictionary = _icon_map.get(item_id, {})
	var icon_id := str(ent.get("icon", ""))
	if icon_id == "":
		return ""
	var p := "res://assets/items/icons/%s.png" % icon_id
	return p if ResourceLoader.exists(p) else ""

# 打开原作「选择奖励」弹窗（HHPropBag.PropChooseView）；失败时退回自绘版
# 盒子选择器：沿用我们自己的弹窗外观，内部逻辑照原作
#   - 每行：图标 + 名称 + 「− 数量 +」步进器
#   - 底部：已选择: k/N个 + 使用
#   - 已拥有：灰掉不可选
# 步进器统一入口：加减一次，并受「总数=need」约束
func _qty_change(allocs: Array, idx: int, delta: int, need: int, refresh: Callable) -> void:
	var total := 0
	for v in allocs:
		total += int(v)
	if delta > 0:
		if total >= need:
			return
		allocs[idx] = int(allocs[idx]) + 1
	else:
		if int(allocs[idx]) <= 0:
			return
		allocs[idx] = int(allocs[idx]) - 1
	refresh.call()

# 长按连续触发（0.45s 后每 0.08s 一次）：原作「*长按可以快速更改数量」
func _bind_longpress(btn: Button, cb: Callable) -> void:
	var state := {"timer": null}
	btn.button_down.connect(func():
		if state["timer"] != null:
			return
		var t := Timer.new()
		t.wait_time = 0.08
		c.add_child(t)
		t.timeout.connect(cb)
		state["timer"] = t
		await c.get_tree().create_timer(0.45).timeout
		if state["timer"] == t and is_instance_valid(t):
			t.start())
	btn.button_up.connect(func():
		var t2 = state["timer"]
		if t2 != null and is_instance_valid(t2):
			t2.queue_free()
		state["timer"] = null)

func _style_row_panel(p: PanelContainer, quality: String, owned: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3b342c") if owned else Color("#4a3524")
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color("#6d6259") if owned else _quality_border_color(quality)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)

# 盒子选择器：我们的弹窗外观 + 原作逻辑
#   - 每行：图标 + 名称/状态 + 「− 数量 +」步进器（上限=要选的数量）
#   - 底部：已选择: k/N个 + 使用（凑满 N 才能点）
#   - 已拥有：整行灰掉、步进器禁用
func _open_friend_box_selector(item_id: String, title: String, rows: Array, need: int = 1) -> void:
	if c.has_node("FriendBoxSelector"):
		return
	need = maxi(need, 1)
	var panel = c._create_base_popup(title, Vector2(480, 580), Vector2(346, 100))
	panel.name = "FriendBoxSelector"
	var vbox = panel.get_child(0)
	var tip := Label.new()
	tip.text = "可以从下方中选择%d个奖励" % need
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_color_override("font_color", Color("#7a4a12"))
	vbox.add_child(tip)
	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(440, 340)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "暂无可选内容（后续版本开放）"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)

	var allocs: Array = []
	allocs.resize(rows.size())
	for i in rows.size():
		allocs[i] = 0
	var count_lbl := Label.new()
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.text = "已选择: 0/%d个" % need
	var use_btn := Button.new()
	use_btn.text = "使用"
	use_btn.disabled = true

	var refresh := func():
		var total := 0
		for v in allocs:
			total += int(v)
		count_lbl.text = "已选择: %d/%d个" % [total, need]
		use_btn.disabled = total != need
		for i2 in rows.size():
			var row_node := list.get_child(i2) as PanelContainer
			if row_node == null:
				continue
			var minus := row_node.find_child("QtyMinus", true, false) as Button
			var plus := row_node.find_child("QtyPlus", true, false) as Button
			var lab := row_node.find_child("QtyLabel", true, false) as RichTextLabel
			if lab != null:
				lab.text = "[center][color=#f6e6c8]%d[/color][/center]" % int(allocs[i2])
			if minus != null:
				minus.disabled = int(allocs[i2]) <= 0
			if plus != null:
				plus.disabled = total >= need

	for i in rows.size():
		var row: Dictionary = rows[i]
		var owned := bool(row.get("owned", false))
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(430, 64)
		_style_row_panel(pc, str(row.get("quality", "")), owned)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		pc.add_child(line)
		var icon_path := _box_row_icon_path(row)
		if icon_path == "" and str(row.get("kind", "")) == "give":
			icon_path = _item_icon_path(str(row.get("id", "")))
		var tex := _scaled_icon(icon_path, 52)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(52, 52)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			line.add_child(tr)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 0)
		# 弹窗主题把 Label 的字色压成深棕；用 RichTextLabel + bbcode 强制亮色
		var nm := RichTextLabel.new()
		nm.bbcode_enabled = true
		nm.fit_content = true
		nm.scroll_active = false
		nm.custom_minimum_size = Vector2(0, 24)
		nm.text = "[color=%s]%s[/color]" % ["#bbb3a6" if owned else "#f6e6c8", str(row.get("label", ""))]
		vb.add_child(nm)
		var sub := RichTextLabel.new()
		sub.bbcode_enabled = true
		sub.fit_content = true
		sub.scroll_active = false
		sub.custom_minimum_size = Vector2(0, 16)
		sub.text = "[color=%s][font_size=12]%s[/font_size][/color]" % ["#a09a8e" if owned else "#9fd6a0", "已拥有" if owned else "可获取"]
		vb.add_child(sub)
		line.add_child(vb)

		var minus := Button.new()
		minus.name = "QtyMinus"
		minus.text = "−"
		minus.custom_minimum_size = Vector2(40, 40)
		minus.disabled = true
		line.add_child(minus)
		var ql := RichTextLabel.new()
		ql.name = "QtyLabel"
		ql.bbcode_enabled = true
		ql.fit_content = false
		ql.scroll_active = false
		ql.custom_minimum_size = Vector2(36, 40)
		ql.text = "[center][color=#f6e6c8]0[/color][/center]"
		line.add_child(ql)
		var plus := Button.new()
		plus.name = "QtyPlus"
		plus.text = "+"
		plus.custom_minimum_size = Vector2(40, 40)
		plus.disabled = owned or need <= 0
		line.add_child(plus)

		if not owned:
			var idx := i
			_bind_longpress(plus, func(): _qty_change(allocs, idx, 1, need, refresh))
			_bind_longpress(minus, func(): _qty_change(allocs, idx, -1, need, refresh))
			plus.pressed.connect(func():
				var total := 0
				for v in allocs:
					total += int(v)
				if total < need:
					allocs[idx] = int(allocs[idx]) + 1
					refresh.call())
			minus.pressed.connect(func():
				if int(allocs[idx]) > 0:
					allocs[idx] = int(allocs[idx]) - 1
					refresh.call())
		list.add_child(pc)

	vbox.add_child(count_lbl)
	var tip2 := Label.new()
	tip2.text = "*长按可以快速更改数量"
	tip2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip2.add_theme_font_size_override("font_size", 12)
	tip2.add_theme_color_override("font_color", Color("#c0503f"))
	vbox.add_child(tip2)
	use_btn.pressed.connect(func():
		var picks: Array = []
		for i3 in rows.size():
			var n3 := int(allocs[i3])
			if n3 > 0:
				picks.append({"row": rows[i3], "times": n3})
		if picks.is_empty():
			return
		for p3 in picks:
			_on_friend_box_option_selected(item_id, p3["row"], int(p3["times"])))
	vbox.add_child(use_btn)
	refresh.call()
	c.add_child(panel)


func _on_friend_box_option_selected(item_id: String, row: Dictionary, times: int = 1):
	# 已拥有的本体不可再选（界面上已 disabled，这里再兜一道）
	if bool(row.get("owned", false)):
		return
	var left := int(data.items.get(item_id, 0))
	if left < 1:
		c._safe_close("FriendBoxSelector")
		return
	times = clampi(times, 1, left)
	data.items[item_id] = left - times
	var msg := ""
	if row.get("kind", "") == "friend":
		var ok: bool = data.unlock_friend(str(row.get("id", "")))
		msg = ("获得挚友【%s】" % row.get("name", "")) if ok else "该挚友已拥有，道具已消耗"
	elif row.get("kind", "") == "give":
		var give_id := str(row.get("id", ""))
		data.items[give_id] = int(data.items.get(give_id, 0)) + 1
		msg = "获得【%s】×1" % row.get("name", give_id)
	else:
		var res: Dictionary = data.costume_system.grant_friend_costume(
			_friend_id_from_box(item_id), str(row.get("id", "")))
		msg = str(res.get("msg", "获取失败"))
	c._safe_close("FriendBoxSelector")
	c._safe_close("OrigChoosePopup")
	c._show_success_popup(msg, 0.0, "ok")
	c.update_all_ui()
	update_bag_list()

func _show_friend_cos_box_selector(item_id: String, qty: int = 1):
	var fid := _friend_id_from_box(item_id)
	_open_friend_box_selector(item_id, "素装盒（选%d项）" % qty, _box_option_rows(fid, "素装", true), qty)

func _show_friend_jinyi_box_selector(item_id: String, qty: int = 1):
	var fid := _friend_id_from_box(item_id)
	_open_friend_box_selector(item_id, "锦衣盒（选%d项）" % qty, _box_option_rows(fid, "锦衣", false), qty)

func _show_friend_multi_box_selector(item_id: String, qty: int = 1):
	var rows: Array = []
	for box_id in data.ITEM_CONFIG.get("friend_multi_box", {}).get("friends", []):
		var cfg: Dictionary = data.ITEM_CONFIG.get(box_id, {})
		rows.append({"label": str(cfg.get("name", box_id)), "kind": "give", "id": str(box_id),
			"name": str(cfg.get("name", box_id))})
	_open_friend_box_selector(item_id, "挚友锦盒（选%d项）" % qty, rows, qty)

func _show_cos_box_selector():
	if c.has_node("CosBoxSelector"): return
	if data.items.get("cos_box", 0) < 1: return
	var panel = c._create_base_popup("服装盒子（选1件）", Vector2(460, 520), Vector2(346, 100))
	panel.name = "CosBoxSelector"
	var vbox = panel.get_child(0)
	# 【新增】按名字搜索（支持搜服装名或门客名）
	var search = LineEdit.new()
	search.placeholder_text = "输入服装或门客名字搜索…"
	vbox.add_child(search)
	c._hook_web_cjk_input(search, "服装或门客名字")   # Web 端中文 IME 引擎级未修，聚焦弹原生 prompt
	var list: VBoxContainer = c.popup_scroll(vbox)
	list.custom_minimum_size = Vector2(440, 400)   # 选择器固定显示区（组件滚动区默认无下限高）
	var entries: Array = []
	for e in data.costume_system.get_all_cos_entries():
		var btn = Button.new()
		btn.text = "【%s】%s（%s）" % [e["quality"], e["name"], e["hero_name"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(430, 52)
		var skin := str(e.get("skin", ""))
		if skin != "":
			btn.icon = _scaled_icon("res://assets/costumes/icons/%s.png" % skin, 44)
		btn.expand_icon = false
		_style_option_row(btn, str(e.get("quality", "")), false)
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.pressed.connect(_on_cos_box_selected.bind(e))
		list.add_child(btn)
		entries.append({"btn": btn, "text": btn.text})
	search.text_changed.connect(func(t): _filter_named_buttons(entries, t))
	c.add_child(panel)

# 【新增】服装盒子回调：扣1盒，给该服装所属门客加1库存
func _on_cos_box_selected(e: Dictionary):
	if data.items.get("cos_box", 0) < 1:
		c._safe_close("CosBoxSelector")
		return
	data.items.cos_box = int(data.items.get("cos_box", 0)) - 1
	var res = data.costume_system.gain_hero_cos_stock(e["hero_id"], e["cos_id"], 1)
	c._safe_close("CosBoxSelector")
	if res.get("ok", false):
		# 【改】2026-09-24 未拥有门客→待领池提示（招募后自动到账）
		if res.get("pending", false):
			c._show_success_popup("【%s】%s 已存入待领池，招募%s后自动到账" % [e["quality"], e["name"], e["hero_name"]], 0.0, "ok")   # 【改】飘字退休→ok 弹窗
		else:
			c._show_success_popup("【%s】%s 库存+1（共%d，请到%s服装页解锁）" % [e["quality"], e["name"], res["stock"], e["hero_name"]], 0.0, "ok")   # 【改】飘字退休→ok 弹窗
	else:
		c._show_success_popup(res.get("msg", "获取失败"), 0.0, "warn")   # 【改】飘字退休→warn 弹窗
	c.update_all_ui()
	update_bag_list()
func _on_hero_box_selected(hero_id: String):
	if data.items.get("hero_box", 0) < 1:
		c._safe_close("HeroBoxSelector")
		return
	
	data.items.hero_box -= 1
	data.unlock_hero(hero_id)
	
	var cfg = data.get_hero_config(hero_id)
	c._safe_close("HeroBoxSelector")
	# 【改】成功反馈铺开：获得弹窗
	c._show_success_popup("获得门客\n【%s】" % cfg.name)
	c.update_all_ui()
	update_bag_list()
	c.ensure_hero_list()

# 【新增】道具获得明细弹窗（关卡宝箱等批量开启道具用）：按配置表顺序逐项列出获得物，点确定关闭
func _show_item_gains_popup(title: String, gains: Dictionary):
	var popup = c._create_base_popup(title, Vector2(420, 480), Vector2(366, 100))
	popup.name = "ItemGainsPopup"
	var vb = popup.get_child(0)
	var list: VBoxContainer = c.popup_scroll(vb)
	list.custom_minimum_size = Vector2(0, 340)   # 结果/获得列表固定显示高度（组件滚动区默认无下限高）
	# 按 ITEM_CONFIG 配置顺序展示（未在配置里的 id 排最后，防御性处理）
	var ordered = []
	for iid in data.ITEM_CONFIG.keys():
		if gains.has(iid):
			ordered.append(iid)
	for iid in gains.keys():
		if not ordered.has(iid):
			ordered.append(iid)
	for iid in ordered:
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "【%s】×%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), gains[iid]]
		list.add_child(lbl)
	c.add_child(popup)

# 【改】蛮荒礼盒选择器：带数量（选1种道具 ×100×N）
func _show_manhuang_box_selector(p_qty: int):
	var popup = c._create_base_popup("蛮荒礼盒（使用%d个）" % p_qty, Vector2(420, 420))
	var vbox = popup.get_child(0)
	var hint = Label.new()
	hint.text = "选择一种道具，获得 ×%d" % (100 * p_qty)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	var options: Dictionary = data._manhuang_configs.get("box_options", {})
	for iid in options.keys():
		# 【改】批次B13：选项改大卡按钮（整卡可点，去"整行信息+右侧小按钮"）
		var btn = Button.new()
		btn.text = "%s ×%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), 100 * p_qty]
		btn.custom_minimum_size = Vector2(360, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_manhuang_box_pick.bind(popup, iid, p_qty))
		vbox.add_child(btn)
	c.add_child(popup)

# 【改】蛮荒礼盒确认：扣N个礼盒、发100×N个所选道具
func _on_manhuang_box_pick(popup, item_id: String, qty: int):
	if int(data.items.get("manhuang_box", 0)) < qty:
		c._show_success_popup("蛮荒礼盒不足！", 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	data.items["manhuang_box"] -= qty
	data.items[item_id] = int(data.items.get(item_id, 0)) + 100 * qty
	popup.queue_free()
	# 【改】成功反馈铺开：获得弹窗
	c._show_success_popup("获得\n【%s】×%d" % [data.ITEM_CONFIG.get(item_id, {}).get("name", item_id), 100 * qty])
	c.update_bag_list()

# 【新增】2026-09-18 自选宝印/自选宝印碎片选择器：N连开=扣N个盒子，二选一得N个所选
func _show_zixuan_baoyin_selector(p_qty: int, is_fragment: bool):
	var src_id := "baoyin_fragment" if is_fragment else "zixuan_baoyin"
	var title := "自选宝印碎片（使用%d个）" % p_qty if is_fragment else "自选宝印（使用%d个）" % p_qty
	var popup = c._create_base_popup(title, Vector2(420, 320))
	var vbox = popup.get_child(0)
	var hint = Label.new()
	hint.text = "选择一种，获得 ×%d" % p_qty
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	# 【修】2026-09-18 配表实际ID：整印=开山令/宗匠令，碎片=kaishan_yin/zongjiang_yin（原 *_yin_fragment 不存在）
	var first_id := "kaishan_yin" if is_fragment else "kaishan_ling"
	var second_id := "zongjiang_yin" if is_fragment else "zongjiang_ling"
	for target_id in [first_id, second_id]:
		# 【改】批次B13：选项改大卡按钮（整卡可点）
		var btn = Button.new()
		btn.text = "%s ×%d" % [data.ITEM_CONFIG.get(target_id, {}).get("name", target_id), p_qty]
		btn.custom_minimum_size = Vector2(360, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_zixuan_baoyin_pick.bind(popup, src_id, target_id, p_qty))
		vbox.add_child(btn)
	c.add_child(popup)

# 【新增】2026-09-18 自选宝印确认：扣N个源道具，发N个所选目标
func _on_zixuan_baoyin_pick(popup, src_id: String, target_id: String, qty: int):
	if int(data.items.get(src_id, 0)) < qty:
		c._show_success_popup("%s不足！" % data.ITEM_CONFIG.get(src_id, {}).get("name", src_id), 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	data.items[src_id] -= qty
	data.items[target_id] = int(data.items.get(target_id, 0)) + qty
	popup.queue_free()
	# 【改】成功反馈铺开：获得弹窗
	c._show_success_popup("获得\n【%s】×%d" % [data.ITEM_CONFIG.get(target_id, {}).get("name", target_id), qty])
	c.update_bag_list()

# 【改】魂骨盒子选择器：带数量（同部位同品级 ×N）
func _show_hungu_box_selector(p_qty: int):
	var popup = c._create_base_popup("魂骨盒子（使用%d个）" % p_qty, Vector2(560, 520))
	popup.name = "HunGuBoxSelector"
	var vbox = popup.get_child(0)
	var hint = Label.new()
	hint.text = "选择 部位+品级，获得对应魂骨 ×%d" % p_qty
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	var sp = data.soulpower_system
	var qualities: Dictionary = data._soulpower_configs.get("qualities", {})
	for q in qualities.keys():
		# 【改】批次B13：品级改节标题行，部位钮放大拉伸（去"左侧标签+小按钮"行）
		var qlbl = Label.new()
		qlbl.text = q
		qlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qlbl.add_theme_font_size_override("font_size", 15)
		qlbl.add_theme_color_override("font_color", Color(qualities[q].get("color", "#ffffff")))
		vbox.add_child(qlbl)
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 6)
		for slot in sp.get_slots():
			var btn = Button.new()
			btn.text = sp.get_slot_name(slot).replace("骨", "")
			btn.custom_minimum_size = Vector2(0, 44)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 13)
			btn.pressed.connect(_on_hungu_box_pick.bind(popup, slot, q, p_qty))
			row.add_child(btn)
		vbox.add_child(row)
	c.add_child(popup)

# 【改】魂骨盒子确认：扣N个盒子，生成N个同部位同品级魂骨
func _on_hungu_box_pick(popup, slot: String, quality: String, qty: int):
	if int(data.items.get("hun_gu_box", 0)) < qty:
		c._show_success_popup("魂骨盒子不足！", 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	data.items["hun_gu_box"] -= qty
	for i in range(qty):
		data.soulpower_system.gen_bone(slot, quality)
	popup.queue_free()
	# 【改】成功反馈铺开：获得弹窗
	c._show_success_popup("获得\n【%s·%s】×%d" % [quality, data.soulpower_system.get_slot_name(slot), qty])
	c.update_bag_list()


# ============================================================
# 背包底部栏·合成页签 + 珍宝箱（2026-09-10 商会第二批，用户拍板）
# 合成：小资质丹×20→资质丹×1；残破缀玉×20→指定缀玉×1（六种配方见 COMPOSE_RECIPES）
# 珍宝箱：五种商品（火器/瓷器/琼浆/茶叶/宣纸）随机其一×500
# ============================================================

# 背包格子统一样式（物品/合成页签共用）
func _show_compose_popup(recipe: Dictionary):
	var out_id := str(recipe.get("output", ""))
	var mat_id := str(recipe.get("material", ""))
	var ratio := int(recipe.get("ratio", 20))
	var is_beast := str(recipe.get("output_type", "")) == "beast"   # 【新增】2026-09-16 兽骨→驺虞分支
	var out_cfg: Dictionary = data.ITEM_CONFIG.get(out_id, {})
	var out_name: String = out_cfg.get("name", out_id)
	if is_beast:
		out_name = str(data.get_beast_config(out_id).get("name", out_id))   # 产出是珍兽，名字读珍兽配置
	var mat_cfg: Dictionary = data.ITEM_CONFIG.get(mat_id, {})
	var mat_have := int(data.items.get(mat_id, 0))
	@warning_ignore("integer_division")   # 合成上限取整是有意行为
	var max_n := int(mat_have / ratio)
	var popup = c._create_base_popup("合成·%s" % out_name, Vector2(400, 340))
	popup.name = "ComposePopup"
	var vbox: VBoxContainer = popup.get_child(0)
	var info = Label.new()
	info.text = "%s ×%d  →  %s ×1" % [mat_cfg.get("name", mat_id), ratio, out_name]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info)
	if max_n <= 0:
		var lack = Label.new()
		lack.text = "材料不足（现有 %d 个）" % mat_have
		lack.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lack)
		c.add_child(popup)
		return
	var pair: Dictionary = c._create_slider_spin_pair(vbox, max_n, 0)
	var ok_btn = Button.new()
	ok_btn.text = "合成"
	ok_btn.custom_minimum_size = Vector2(120, 40)
	ok_btn.pressed.connect(func():
		var n := int(pair.spin.value)
		if n <= 0:
			c._show_success_popup("请先选择合成数量", 0.0, "warn")   # 【改】飘字退休→warn 弹窗
			return
		data.items[mat_id] = int(data.items.get(mat_id, 0)) - n * ratio
		if is_beast:
			# 【新增】2026-09-16 珍兽产出：入珍兽栏（驺虞 max_count 999 可重复，add_beast 恒成功）
			for i in range(n):
				data.add_beast(out_id)
			data.save_game()
			popup.queue_free()
			update_bag_list()
			c.update_all_ui()
			# 【改】成功反馈铺开：合成成功弹窗
			c._show_success_popup("合成成功\n珍兽【%s】×%d" % [out_name, n])
			return
		data.items[out_id] = int(data.items.get(out_id, 0)) + n
		data.save_game()
		popup.queue_free()
		update_bag_list()
		c.update_all_ui()
		_show_item_gains_popup("合成结果", {out_id: n}))
	vbox.add_child(ok_btn)
	c.add_child(popup)

# 珍宝箱：N连开，五种商品随机其一×500入背包（商品使用=随机一名对应职业门客基础赚速+500）
func _open_treasure_boxes(count: int):
	if int(data.items.get("treasure_box", 0)) < count:
		c._show_success_popup("珍宝箱数量不足", 0.0, "warn")   # 【改】飘字退休→warn 弹窗
		return
	data.items["treasure_box"] = int(data.items.get("treasure_box", 0)) - count
	var goods := ["huo_qi", "ci_qi", "qiong_jiang", "cha_ye", "xuan_zhi"]
	var gains := {}
	for i in count:
		var it: String = goods[randi() % goods.size()]   # 【修】数组索引返回Variant，:=推断不出
		data.items[it] = int(data.items.get(it, 0)) + 500
		gains[it] = gains.get(it, 0) + 500
	data.save_game()
	update_bag_list()
	c.update_all_ui()
	_show_item_gains_popup("打开珍宝箱", gains)
