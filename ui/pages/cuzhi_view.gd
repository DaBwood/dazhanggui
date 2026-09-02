class_name CuzhiView
extends RefCounted
# 【促织园视图】闯荡子视图：促织架/捉促织/促织庙/特惠商城
# 架构与其他闯荡子视图一致（RefCounted + build_xxx_view(page, vbox)）

var c       # game_controller
var data    # GameData
var sys     # CuzhiSystem

const BG = Color("#1e1b2e")
const CARD = Color("#2a2640")
const BORDER = Color("#5a4a7a")
const TITLE_COL = Color("#ffdd88")

# 根面板（挂载到闯荡页下的实际节点）
var _panel: Panel

# 子视图节点
var _main: Control
var _shelf: Control
var _catch: Control
var _temple: Control
var _shop: Control

# 运行时缓存
var _shelf_grid: GridContainer
var _catch_result_lbl: Label
var _catch_progress_lbl: Label
var _catch_btn: Button
var _temple_list: VBoxContainer
var _temple_career_btns: Array = []
var _current_temple_career: String = ""

func _init(p_c):
	c = p_c
	data = p_c.data
	sys = data.cuzhi_system

# ========== 构建入口（由 adventure_page 调用）==========
func build_cuzhi_view(page: Control, vbox: VBoxContainer):
	# 创建入口按钮
	var cuzhi_btn = Button.new()
	cuzhi_btn.text = "促织园"
	cuzhi_btn.custom_minimum_size = Vector2(180, 60)
	cuzhi_btn.pressed.connect(show_cuzhi_view)
	vbox.get_node("AdventureEntryGrid").add_child(cuzhi_btn)

	# 创建促织园主面板
	_panel = Panel.new()
	_panel.name = "CuzhiView"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	_panel.z_index = 15
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sty = StyleBoxFlat.new()
	sty.bg_color = BG
	_panel.add_theme_stylebox_override("panel", sty)
	page.add_child(_panel)

	_main = _build_main_view()
	_panel.add_child(_main)

	_shelf = _build_shelf_view()
	_shelf.visible = false
	_panel.add_child(_shelf)

	_catch = _build_catch_view()
	_catch.visible = false
	_panel.add_child(_catch)

	_temple = _build_temple_view()
	_temple.visible = false
	_panel.add_child(_temple)

	_shop = _build_shop_view()
	_shop.visible = false
	_panel.add_child(_shop)

func show_cuzhi_view():
	_panel.visible = true
	_show_main()

func hide_cuzhi_view():
	_panel.visible = false

# ========== 主界面 ==========
func _build_main_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	var title = Label.new()
	title.text = "促织园"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TITLE_COL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.size = Vector2(600, 50)
	root.add_child(title)

	var progress = Label.new()
	progress.name = "ProgressLabel"
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_theme_font_size_override("font_size", 18)
	progress.add_theme_color_override("font_color", Color("#aaaaaa"))
	progress.position = Vector2(0, 75)
	progress.size = Vector2(600, 30)
	root.add_child(progress)
	_update_progress_label(progress)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(60, 130)
	grid.size = Vector2(480, 500)
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	root.add_child(grid)

	var entries = [
		{"name": "促织架", "desc": "已收集的促织", "callback": _on_shelf},
		{"name": "捉促织", "desc": "消耗促织笼捕捉", "callback": _on_catch},
		{"name": "促织庙", "desc": "消耗缘分提升门客", "callback": _on_temple},
		{"name": "特惠商城", "desc": "购买促织笼", "callback": _on_shop},
	]
	for e in entries:
		var card = _make_entry_card(e.name, e.desc)
		card.pressed.connect(e.callback)
		grid.add_child(card)

	var back = Button.new()
	back.text = "< 返回闯荡"
	back.position = Vector2(20, 20)
	back.size = Vector2(120, 40)
	back.pressed.connect(hide_cuzhi_view)
	root.add_child(back)

	return root

func _make_entry_card(name_str: String, desc: String) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(220, 220)
	btn.size = Vector2(220, 220)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	var sty = StyleBoxFlat.new()
	sty.bg_color = CARD
	sty.border_color = BORDER
	sty.border_width_bottom = 2
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.corner_radius_bottom_left = 8
	sty.corner_radius_bottom_right = 8
	sty.corner_radius_top_left = 8
	sty.corner_radius_top_right = 8
	btn.add_theme_stylebox_override("normal", sty)
	btn.add_theme_stylebox_override("hover", sty)
	btn.add_theme_stylebox_override("pressed", sty)

	var vbox = VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = name_str
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", TITLE_COL)
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(desc_lbl)

	return btn

func _update_progress_label(lbl: Label = null):
	if lbl == null:
		lbl = _main.get_node_or_null("ProgressLabel")
	if lbl:
		lbl.text = "收集进度：%d / %d" % [sys.get_caught_count(), sys.get_total_crickets()]

func _on_shelf():
	_show_view(_shelf)
	_refresh_shelf()

func _on_catch():
	_show_view(_catch)
	_refresh_catch()

func _on_temple():
	_show_view(_temple)
	_refresh_temple()

func _on_shop():
	_show_view(_shop)
	_refresh_shop()

func _show_view(v: Control):
	_main.visible = false
	_shelf.visible = false
	_catch.visible = false
	_temple.visible = false
	_shop.visible = false
	v.visible = true

func _show_main():
	_show_view(_main)
	_update_progress_label()

# ========== 促织架 ==========
func _build_shelf_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	_make_sub_title("促织架", root)
	var back = _make_sub_back(root)
	back.pressed.connect(_show_main)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 80)
	scroll.size = Vector2(560, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_shelf_grid = GridContainer.new()
	_shelf_grid.columns = 4
	_shelf_grid.add_theme_constant_override("h_separation", 10)
	_shelf_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_shelf_grid)

	return root

func _refresh_shelf():
	for ch in _shelf_grid.get_children():
		ch.queue_free()

	var list = sys.get_caught_list()
	for item in list:
		var card = _make_cricket_card(item)
		_shelf_grid.add_child(card)

	if list.is_empty():
		var empty = Label.new()
		empty.text = "暂无促织，去捉促织吧！"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#888888"))
		_shelf_grid.add_child(empty)

func _make_cricket_card(item: Dictionary) -> Button:
	var cdata = item.data
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(130, 160)
	btn.size = Vector2(130, 160)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var col = Color(sys.get_quality_color(cdata.quality))
	var sty = StyleBoxFlat.new()
	sty.bg_color = CARD
	sty.border_color = col
	sty.border_width_bottom = 3
	sty.border_width_left = 3
	sty.border_width_right = 3
	sty.border_width_top = 3
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	btn.add_theme_stylebox_override("normal", sty)
	btn.add_theme_stylebox_override("hover", sty)
	btn.add_theme_stylebox_override("pressed", sty)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	btn.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = cdata.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", col)
	vbox.add_child(name_lbl)

	var career_lbl = Label.new()
	career_lbl.text = sys.get_career_name(cdata.career) + "·" + sys.get_quality_name(cdata.quality)
	career_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	career_lbl.add_theme_font_size_override("font_size", 12)
	career_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(career_lbl)

	var lv_lbl = Label.new()
	lv_lbl.text = "Lv.%d" % item.level
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 14)
	lv_lbl.add_theme_color_override("font_color", Color("#ffdd88"))
	vbox.add_child(lv_lbl)

	btn.pressed.connect(func(): _show_cricket_detail(item))
	return btn

func _show_cricket_detail(item: Dictionary):
	var cdata = item.data
	var popup = c._create_base_popup("促织详情", Vector2(400, 300))
	popup.z_index = 30

	var vbox = popup.get_child(0).get_child(0)

	var col = Color(sys.get_quality_color(cdata.quality))
	var info = Label.new()
	info.text = "%s  %s·%s\n等级：Lv.%d" % [cdata.name, sys.get_career_name(cdata.career), sys.get_quality_name(cdata.quality), item.level]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", col)
	vbox.add_child(info)

	var exp_needed = sys.get_levelup_exp(item.level)
	var exp_lbl = Label.new()
	if item.level >= _cfg().levelup.max_level:
		exp_lbl.text = "经验：已满级"
	else:
		exp_lbl.text = "经验：%d / %d" % [item.exp, exp_needed]
	exp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exp_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(exp_lbl)

	var desc = Label.new()
	desc.text = "重复捉到同名促织自动转化为经验\n等级影响促织战力（后续玩法使用）"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(desc)

	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")

# ========== 捉促织 ==========
func _build_catch_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	_make_sub_title("捉促织", root)
	var back = _make_sub_back(root)
	back.pressed.connect(_show_main)

	var cage_lbl = Label.new()
	cage_lbl.name = "CageLabel"
	cage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cage_lbl.add_theme_font_size_override("font_size", 20)
	cage_lbl.position = Vector2(0, 80)
	cage_lbl.size = Vector2(600, 40)
	root.add_child(cage_lbl)

	_catch_progress_lbl = Label.new()
	_catch_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_catch_progress_lbl.add_theme_font_size_override("font_size", 18)
	_catch_progress_lbl.add_theme_color_override("font_color", Color("#ffaa00"))
	_catch_progress_lbl.position = Vector2(0, 130)
	_catch_progress_lbl.size = Vector2(600, 40)
	root.add_child(_catch_progress_lbl)

	_catch_btn = Button.new()
	_catch_btn.text = "捕捉（消耗1个促织笼）"
	_catch_btn.position = Vector2(180, 200)
	_catch_btn.size = Vector2(240, 60)
	_catch_btn.add_theme_font_size_override("font_size", 20)
	var csty = StyleBoxFlat.new()
	csty.bg_color = Color("#4a3a6a")
	csty.corner_radius_bottom_left = 8
	csty.corner_radius_bottom_right = 8
	csty.corner_radius_top_left = 8
	csty.corner_radius_top_right = 8
	_catch_btn.add_theme_stylebox_override("normal", csty)
	_catch_btn.pressed.connect(_do_catch)
	root.add_child(_catch_btn)

	_catch_result_lbl = Label.new()
	_catch_result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_catch_result_lbl.add_theme_font_size_override("font_size", 22)
	_catch_result_lbl.position = Vector2(0, 300)
	_catch_result_lbl.size = Vector2(600, 200)
	root.add_child(_catch_result_lbl)

	var gua_btn = Button.new()
	gua_btn.name = "GuaranteeBtn"
	gua_btn.text = "保底自选"
	gua_btn.position = Vector2(220, 520)
	gua_btn.size = Vector2(160, 50)
	gua_btn.add_theme_font_size_override("font_size", 18)
	gua_btn.pressed.connect(_show_guarantee_selector)
	root.add_child(gua_btn)

	return root

func _refresh_catch():
	var cage = data.get_item_count("cuzhi_cage")
	var clbl = _catch.get_node_or_null("CageLabel")
	if clbl:
		clbl.text = "当前拥有促织笼：%d" % cage
		clbl.add_theme_color_override("font_color", Color("#66ff66") if cage > 0 else Color("#ff6666"))

	var prog = sys.get_guarantee_progress()
	var tgt = sys.get_guarantee_target()
	_catch_progress_lbl.text = "保底进度：%d / %d" % [prog, tgt]

	_catch_btn.disabled = cage <= 0

	var gua_btn = _catch.get_node_or_null("GuaranteeBtn")
	if gua_btn:
		gua_btn.visible = prog >= tgt

	_catch_result_lbl.text = ""

func _do_catch():
	if not sys.can_catch():
		c._show_toast("促织笼不足，去商城购买吧！")
		return

	var result = sys.catch_one()
	var cdata = result.cricket
	var col = Color(sys.get_quality_color(result.quality))

	var new_str = "【新】" if result.is_new else "【重复】"
	_catch_result_lbl.text = "%s捉到了 %s！\n%s·%s" % [new_str, cdata.name, sys.get_career_name(cdata.career), sys.get_quality_name(result.quality)]
	_catch_result_lbl.add_theme_color_override("font_color", col)

	c._show_toast("+%d %s缘分" % [_cfg().fate_per_catch, sys.get_career_name(cdata.career)])

	_refresh_catch()

	if result.guarantee_ready:
		c._show_toast("保底已满！可自选一只促织")

func _show_guarantee_selector():
	if sys.get_guarantee_progress() < sys.get_guarantee_target():
		return

	var popup = c._create_base_popup("保底自选", Vector2(500, 600))
	popup.z_index = 30

	var vbox = popup.get_child(0).get_child(0)

	var hint = Label.new()
	hint.text = "累计消耗已达%d次，自选一只促织" % sys.get_guarantee_target()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#ffaa00"))
	vbox.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 400)
	vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	var pool = sys.get_catchable_crickets()
	for cdata in pool:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(140, 60)
		btn.text = cdata.name + "\n" + sys.get_career_name(cdata.career)
		var col = Color(sys.get_quality_color(cdata.quality))
		btn.add_theme_color_override("font_color_normal", col)
		btn.pressed.connect(func():
			if sys.claim_guarantee(cdata.id):
				c._show_toast("获得 %s！" % cdata.name)
				popup.queue_free()
				_refresh_catch()
			else:
				c._show_toast("兑换失败")
		)
		grid.add_child(btn)

	c._add_ok_button(vbox, func(): popup.queue_free(), "取消")

# ========== 促织庙 ==========
func _build_temple_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	_make_sub_title("促织庙", root)
	var back = _make_sub_back(root)
	back.pressed.connect(_show_main)

	var fate_panel = Panel.new()
	fate_panel.position = Vector2(20, 80)
	fate_panel.size = Vector2(560, 60)
	var fsty = StyleBoxFlat.new()
	fsty.bg_color = CARD
	fsty.corner_radius_bottom_left = 6
	fsty.corner_radius_bottom_right = 6
	fsty.corner_radius_top_left = 6
	fsty.corner_radius_top_right = 6
	fate_panel.add_theme_stylebox_override("panel", fsty)
	root.add_child(fate_panel)

	var fhbox = HBoxContainer.new()
	fhbox.alignment = BoxContainer.ALIGNMENT_CENTER
	fhbox.anchors_preset = Control.PRESET_FULL_RECT
	fate_panel.add_child(fhbox)

	for career in ["shi", "nong", "gong", "shang", "xia"]:
		var lbl = Label.new()
		lbl.name = "Fate_" + career
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		fhbox.add_child(lbl)

	var filter_hbox = HBoxContainer.new()
	filter_hbox.position = Vector2(20, 150)
	filter_hbox.size = Vector2(560, 40)
	filter_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(filter_hbox)

	var all_btn = Button.new()
	all_btn.text = "全部"
	all_btn.pressed.connect(func(): _set_temple_career(""))
	filter_hbox.add_child(all_btn)
	_temple_career_btns.append(all_btn)

	for career in ["shi", "nong", "gong", "shang", "xia"]:
		var btn = Button.new()
		btn.text = sys.get_career_name(career)
		btn.pressed.connect(func(cr=career): _set_temple_career(cr))
		filter_hbox.add_child(btn)
		_temple_career_btns.append(btn)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 200)
	scroll.size = Vector2(560, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_temple_list = VBoxContainer.new()
	_temple_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_temple_list)

	return root

func _set_temple_career(career: String):
	_current_temple_career = career
	_refresh_temple()

func _refresh_temple():
	for ch in _temple_list.get_children():
		ch.queue_free()

	for career in ["shi", "nong", "gong", "shang", "xia"]:
		var lbl = _temple.get_node_or_null("Fate_" + career)
		if lbl:
			var f = sys.get_career_fate(career)
			lbl.text = "%s:%d" % [sys.get_career_name(career), f]
			lbl.add_theme_color_override("font_color", Color("#ffdd88") if f > 0 else Color("#888888"))

	var heroes = data.heroes
	for h in heroes:
		if _current_temple_career != "" and h.career != _current_temple_career:
			continue
		var row = _make_temple_hero_row(h)
		_temple_list.add_child(row)

func _make_temple_hero_row(h) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(540, 80)
	panel.size = Vector2(540, 80)
	var psty = StyleBoxFlat.new()
	psty.bg_color = CARD
	psty.corner_radius_bottom_left = 6
	psty.corner_radius_bottom_right = 6
	psty.corner_radius_top_left = 6
	psty.corner_radius_top_right = 6
	panel.add_theme_stylebox_override("panel", psty)

	var hbox = HBoxContainer.new()
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	var name_lbl = Label.new()
	name_lbl.text = h.name
	name_lbl.custom_minimum_size = Vector2(100, 0)
	name_lbl.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_lbl)

	var lv = sys.get_temple_level(h.id)
	var bonus = sys.get_temple_bonus(h.id)
	var info = Label.new()
	info.text = "+%d%% 赚速（Lv.%d）" % [int(bonus * 100), lv]
	info.custom_minimum_size = Vector2(140, 0)
	info.add_theme_color_override("font_color", Color("#66ff66"))
	hbox.add_child(info)

	var cost = sys.get_temple_cost(h.id)
	var career = h.career
	var _fate = sys.get_career_fate(career)
	var can = sys.can_upgrade_temple(h.id, career)

	var cost_lbl = Label.new()
	cost_lbl.text = "下次：%d %s缘分" % [cost, sys.get_career_name(career)]
	cost_lbl.custom_minimum_size = Vector2(160, 0)
	cost_lbl.add_theme_color_override("font_color", Color("#ffaa00") if can else Color("#ff6666"))
	hbox.add_child(cost_lbl)

	var up_btn = Button.new()
	up_btn.text = "升级" if lv < _cfg().temple.max_level else "已满"
	up_btn.disabled = not can
	up_btn.custom_minimum_size = Vector2(80, 40)
	up_btn.pressed.connect(func():
		if sys.upgrade_temple(h.id, career):
			c._show_toast("%s 促织庙 +1" % h.name)
			_refresh_temple()
			data._on_income_changed()
	)
	hbox.add_child(up_btn)

	return panel

# ========== 特惠商城 ==========
func _build_shop_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	_make_sub_title("特惠商城", root)
	var back = _make_sub_back(root)
	back.pressed.connect(_show_main)

	var vbox = VBoxContainer.new()
	vbox.position = Vector2(100, 120)
	vbox.size = Vector2(400, 600)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	root.add_child(vbox)

	var goods = [
		{"name": "促织笼 ×1", "price": 10, "count": 1},
		{"name": "促织笼 ×10", "price": 90, "count": 10},
		{"name": "促织笼 ×50", "price": 400, "count": 50},
	]
	for g in goods:
		var row = _make_shop_row(g)
		vbox.add_child(row)

	return root

func _make_shop_row(g: Dictionary) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(400, 80)
	panel.size = Vector2(400, 80)
	var psty = StyleBoxFlat.new()
	psty.bg_color = CARD
	psty.corner_radius_bottom_left = 6
	psty.corner_radius_bottom_right = 6
	psty.corner_radius_top_left = 6
	psty.corner_radius_top_right = 6
	panel.add_theme_stylebox_override("panel", psty)

	var hbox = HBoxContainer.new()
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	var name_lbl = Label.new()
	name_lbl.text = g.name
	name_lbl.custom_minimum_size = Vector2(150, 0)
	name_lbl.add_theme_font_size_override("font_size", 18)
	hbox.add_child(name_lbl)

	var price_lbl = Label.new()
	price_lbl.text = "%d 元宝" % g.price
	price_lbl.custom_minimum_size = Vector2(100, 0)
	price_lbl.add_theme_color_override("font_color", Color("#ffaa00"))
	hbox.add_child(price_lbl)

	var buy_btn = Button.new()
	buy_btn.text = "购买"
	buy_btn.custom_minimum_size = Vector2(80, 40)
	buy_btn.pressed.connect(func():
		if data.yuanbao < g.price:
			c._show_toast("元宝不足！")
			return
		data.yuanbao -= g.price
		data.add_item("cuzhi_cage", g.count)
		c._show_toast("购买成功！+%d 促织笼" % g.count)
		c._update_top_bar()
		_refresh_shop()
	)
	hbox.add_child(buy_btn)

	return panel

func _refresh_shop():
	pass

# ========== 通用组件 ==========
func _make_sub_title(text: String, parent: Control) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", TITLE_COL)
	lbl.position = Vector2(0, 20)
	lbl.size = Vector2(600, 50)
	parent.add_child(lbl)
	return lbl

func _make_sub_back(parent: Control) -> Button:
	var btn = Button.new()
	btn.text = "< 返回"
	btn.position = Vector2(20, 20)
	btn.size = Vector2(100, 40)
	parent.add_child(btn)
	return btn

func _cfg() -> Dictionary:
	return sys._cfg
