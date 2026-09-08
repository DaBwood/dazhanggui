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
#【新增】固定为1的道具类型：数量锁定单次开启（门客/挚友盒解锁对象唯一；促织架按ID唯一存放）
const SINGLE_USE_TYPES: Array = ["hero_box", "friend_box", "wushuang_cuzhi_box"]

# 由 game_controller._ready 创建本模块时注入引用
func _init(p_c):
	c = p_c
	data = p_c.data

# ============ 以下为原 game_controller.gd 搬迁函数（逻辑未改，仅根节点访问加了 c. 前缀） ============

func generate_bag_list():
	if not c.has_node("PageContainer/BagPage"): return
	var bag_page = c.get_node("PageContainer/BagPage")
	
	# 【改】BagScroll 填满 BagPage，BagGrid 必须放在 BagScroll 内部
	var scroll: ScrollContainer
	if bag_page.has_node("BagScroll"):
		scroll = bag_page.get_node("BagScroll")
	else:
		scroll = ScrollContainer.new()
		scroll.name = "BagScroll"
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		bag_page.add_child(scroll)
	
	# 自动创建 GridContainer（如果没有），作为 ScrollContainer 的子节点
	var grid: GridContainer
	if scroll.has_node("BagGrid"):
		grid = scroll.get_node("BagGrid")
	else:
		grid = GridContainer.new()
		grid.name = "BagGrid"
		grid.columns = 5
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
	
	# 清空旧格子
	for child in grid.get_children():
		child.queue_free()
	
	# 【改】为每种已拥有物品生成简洁按钮，只显示名称；数量0不进背包
	for item_id in data.ITEM_CONFIG.keys():
		var cfg = data.ITEM_CONFIG[item_id]
		
		# 跳过隐藏道具（如鱼食）
		if cfg.get("hide_in_bag", false):
			continue
		
		var count = data.items.get(item_id, 0)
		if item_id == "lottery_ticket":
			count = data.lottery_ticket
		# 【新增】背包列表只显示已拥有物品，数量为 0 的道具不生成格子
		if int(count) <= 0:
			continue

		var btn = Button.new()
		btn.name = item_id + "_btn"
		btn.text = "%s\nx%d" % [cfg.name, count]   # 名称第一行，数量第二行
		btn.custom_minimum_size = Vector2(0, 50)    # 不限制宽度，高度44容纳两行
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 【修】手机端：按钮默认 STOP 会拦截触摸滚动，改 PASS 让滑动事件穿透到 ScrollContainer
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		# 文字样式
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.8))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		# 按钮样式：深色底+淡边框
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.14, 0.18)
		btn_style.border_color = Color(0.35, 0.32, 0.40)
		btn_style.border_width_bottom = 2
		btn_style.corner_radius_top_left = 3
		btn_style.corner_radius_top_right = 3
		btn_style.corner_radius_bottom_left = 3
		btn_style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", btn_style)
		var hover_style = btn_style.duplicate()
		hover_style.bg_color = Color(0.22, 0.20, 0.28)
		hover_style.border_color = Color(0.50, 0.45, 0.60)
		btn.add_theme_stylebox_override("hover", hover_style)
		var press_style = btn_style.duplicate()
		press_style.bg_color = Color(0.10, 0.09, 0.13)
		btn.add_theme_stylebox_override("pressed", press_style)
		# 点击打开详情弹窗
		btn.pressed.connect(_show_item_detail_popup.bind(item_id))
		grid.add_child(btn)

# 【改】物品详情弹窗：名称/数量/描述 + 数量选择器（滑条+输入框，默认0）+ 使用按钮
# 0 点使用提示选数量；>0 按 use.type 分派：直接消耗类按N结算，需二次选择的带N进选择器
func _show_item_detail_popup(item_id: String):
	var cfg = data.ITEM_CONFIG.get(item_id, {})
	var count = data.items.get(item_id, 0)
	if item_id == "lottery_ticket":
		count = data.lottery_ticket

	var popup = c._create_base_popup(cfg.get("name", "物品详情"), Vector2(400, 380))
	popup.name = "ItemDetailPopup"
	var vbox = popup.get_child(0)

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
		c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
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
		# 数量选择器：滑条+输入框双向同步，默认0（复用全局辅助）
		var pair = c._create_slider_spin_pair(vbox, count, 0)
		qty_spin = pair.spin

	var use_btn = Button.new()
	use_btn.text = use_cfg.get("btn", "使用")
	use_btn.custom_minimum_size = Vector2(120, 40)
	use_btn.pressed.connect(func():
		_on_detail_use(item_id, 1 if qty_spin == null else int(qty_spin.value), popup))
	vbox.add_child(use_btn)

	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 【新增】详情弹窗统一使用入口：0提示选数量；按类型分派（直接消耗按N / 二次选择带N / 固定1直开）
func _on_detail_use(item_id: String, qty: int, popup: Control):
	var use_cfg = data.ITEM_CONFIG.get(item_id, {}).get("use", {})
	var count = int(data.items.get(item_id, 0))
	if qty <= 0:
		c._show_stage_hint("请先选择使用数量")
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
				c._show_stage_hint("挚友盒子功能开发中")
		"item_box":
			popup.queue_free()
			_show_item_box_selector(qty)
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

# 【新增】按数量使用道具（结算体抽出，详情弹窗与小时卡入口共用）
func _use_items(item_id: String, count: int):
	var result = data.use_item(item_id, count)
	if result.get("ok", false):
		update_bag_list()
		c.update_all_ui()
		# 带 gains 明细的道具（关卡宝箱）弹窗展示明细，其余维持飘字提示
		if result.has("gains"):
			_show_item_gains_popup("打开关卡宝箱", result.gains)
		else:
			c._show_stage_hint(result.get("msg", "使用成功"))
	else:
		c._show_stage_hint(result.get("msg", "使用失败"))

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
	var bag_page = c.get_node("PageContainer/BagPage")
	if bag_page.has_node("GinsengSelector"): return
	
	var panel = PanelContainer.new()
	panel.name = "GinsengSelector"
	panel.custom_minimum_size = Vector2(500, 400)
	var vs = c.get_viewport_rect().size
	panel.position = Vector2((vs.x - 500) / 2, (vs.y - 400) / 2)
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	 # 【修】补弹窗背景样式，解决默认背景过淡与底层混淆
	var sel_style = StyleBoxFlat.new()
	sel_style.bg_color = Color("#1e1b2e")   # 弹窗统一底色；觉得不够深可改 #15121e
	sel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sel_style)
	
	var title = Label.new()
	title.text = "选择门客使用%s" % data.ITEM_CONFIG.get(_pending_ginseng_type, {}).get("name", "人参")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 280)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	# 【改】门客按实时赚速降序排列（原按字典顺序）
	var hero_ids = data.heroes.keys()
	hero_ids.sort_custom(func(a, b): return data.get_hero_income(a) > data.get_hero_income(b))
	for hero_id in hero_ids:
		var h = data.heroes[hero_id]
		var btn = Button.new()
		# 【改】按钮文本补上赚速（排序依据可见，否则顺序看起来是乱的；与其他选择器样式一致）
		btn.text = "【%s】%s Lv.%d | %s/秒" % [h.name, h.category, h.level, c.format_number(data.get_hero_income(hero_id))]
		btn.pressed.connect(_on_ginseng_target_selected.bind(hero_id))
		list.add_child(btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_close_ginseng_selector)
	vbox.add_child(cancel_btn)
	
	bag_page.add_child(panel)

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
	var bag_page = c.get_node("PageContainer/BagPage")
	if bag_page.has_node("GinsengSelector"):
		bag_page.get_node("GinsengSelector").queue_free()
	_pending_ginseng_count = 0
	_pending_ginseng_type = ""

func _show_hero_box_selector():
	if c.has_node("HeroBoxSelector"): return
	
	var panel = c._create_base_popup("选择门客", Vector2(460, 500), Vector2(346, 120))
	panel.name = "HeroBoxSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 380)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
	var has_unlockable = false
	for hero_id in data.get_all_hero_ids():
		if data.heroes.has(hero_id): continue  # 已拥有的跳过
		
		var cfg = data.get_hero_config(hero_id)
		var btn = Button.new()
		var vip_lv = data.get_hero_unlock_vip(hero_id)
		btn.text = "【%s】%s  |  VIP%d解锁" % [cfg.name, cfg.category, vip_lv]
		btn.pressed.connect(_on_hero_box_selected.bind(hero_id))
		list.add_child(btn)
		has_unlockable = true
	
	if not has_unlockable:
		var empty = Label.new()
		empty.text = "所有门客已拥有"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("HeroBoxSelector"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

# 【新增】挚友盒子选择弹窗：列出所有未拥有的挚友，点击即获得（不可重复）
func _show_friend_box_selector():
	if c.has_node("FriendBoxSelector"): return
	
	var panel = c._create_base_popup("选择挚友", Vector2(460, 500), Vector2(346, 120))
	panel.name = "FriendBoxSelector"
	var vbox = panel.get_child(0)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 380)
	vbox.add_child(scroll)
	
	var list = VBoxContainer.new()
	scroll.add_child(list)
	
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
	
	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("FriendBoxSelector"))
	vbox.add_child(cancel)
	
	c.add_child(panel)

# 【改】魂石宝箱N连开：一次扣N个，N个结果汇总进一个弹窗
func _open_soul_boxes(item_id: String, kind: String, n: int):
	if int(data.items.get(item_id, 0)) < n:
		c._show_stage_hint("没有可开启的" + data.ITEM_CONFIG.get(item_id, {}).get("name", "宝箱"))
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
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svbox.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for line in lines:
		var lbl = Label.new()
		lbl.text = line
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(lbl)
	c._add_ok_button(svbox, func(): popup.queue_free(), "关闭")
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
	c._show_stage_hint("获得挚友【%s】" % cfg.name)
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

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 360)
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	scroll.add_child(list)

	# 排除盒子类道具，防止递归
	var exclude_ids = ["hero_box", "friend_box", "item_box"]
	for item_id in data.ITEM_CONFIG.keys():
		if item_id in exclude_ids: continue

		var cfg = data.ITEM_CONFIG[item_id]
		var btn = Button.new()
		btn.text = cfg.name
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		btn.pressed.connect(_on_item_box_selected.bind(item_id, p_qty))
		list.add_child(btn)

	var cancel = Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): c._safe_close("ItemBoxSelector"))
	vbox.add_child(cancel)

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
	c._show_stage_hint("使用%d个物品盒子，获得【%s】×%d" % [count, cfg.get("name", item_id), count])
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
	c._show_stage_hint("获得门客【%s】" % cfg.name)
	c.update_all_ui()
	update_bag_list()
	c.generate_hero_list() 

# 【新增】道具获得明细弹窗（关卡宝箱等批量开启道具用）：按配置表顺序逐项列出获得物，点确定关闭
func _show_item_gains_popup(title: String, gains: Dictionary):
	var popup = c._create_base_popup(title, Vector2(420, 480), Vector2(366, 100))
	popup.name = "ItemGainsPopup"
	var vb = popup.get_child(0)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	vb.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
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
	c._add_ok_button(vb, func(): popup.queue_free(), "确定")
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
		var line = HBoxContainer.new()
		var lbl = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "%s×%d" % [data.ITEM_CONFIG.get(iid, {}).get("name", iid), 100 * p_qty]
		line.add_child(lbl)
		var btn = Button.new()
		btn.text = "选择"
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(_on_manhuang_box_pick.bind(popup, iid, p_qty))
		line.add_child(btn)
		vbox.add_child(line)
	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 【改】蛮荒礼盒确认：扣N个礼盒、发100×N个所选道具
func _on_manhuang_box_pick(popup, item_id: String, qty: int):
	if int(data.items.get("manhuang_box", 0)) < qty:
		c._show_stage_hint("蛮荒礼盒不足！")
		return
	data.items["manhuang_box"] -= qty
	data.items[item_id] = int(data.items.get(item_id, 0)) + 100 * qty
	popup.queue_free()
	c._show_stage_hint("获得【%s】×%d" % [data.ITEM_CONFIG.get(item_id, {}).get("name", item_id), 100 * qty])
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
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		var qlbl = Label.new()
		qlbl.text = q
		qlbl.custom_minimum_size = Vector2(70, 40)
		qlbl.add_theme_color_override("font_color", Color(qualities[q].get("color", "#ffffff")))
		row.add_child(qlbl)
		for slot in sp.get_slots():
			var btn = Button.new()
			btn.text = sp.get_slot_name(slot).replace("骨", "")
			btn.custom_minimum_size = Vector2(74, 40)
			btn.pressed.connect(_on_hungu_box_pick.bind(popup, slot, q, p_qty))
			row.add_child(btn)
		vbox.add_child(row)
	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")
	c.add_child(popup)

# 【改】魂骨盒子确认：扣N个盒子，生成N个同部位同品级魂骨
func _on_hungu_box_pick(popup, slot: String, quality: String, qty: int):
	if int(data.items.get("hun_gu_box", 0)) < qty:
		c._show_stage_hint("魂骨盒子不足！")
		return
	data.items["hun_gu_box"] -= qty
	for i in range(qty):
		data.soulpower_system.gen_bone(slot, quality)
	popup.queue_free()
	c._show_stage_hint("获得【%s·%s】×%d（珍兽详情 → 魂力培养 装配）" % [quality, data.soulpower_system.get_slot_name(slot), qty])
	c.update_bag_list()
