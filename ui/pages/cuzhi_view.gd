class_name CuzhiView
extends RefCounted
# 【促织园视图】闯荡子视图：促织架/捉促织/促织庙/特惠商城/虫师
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
var _worm: Control           # 【新增】虫师主界面

# 运行时缓存
var _shelf_grid: GridContainer
var _catch_result_lbl: Label
var _catch_progress_lbl: Label
var _catch_btn: Button
var _catch_ten_btn: Button   # 【新增】十连按钮
var _temple_list: VBoxContainer
var _temple_career_btns: Array = []
var _current_temple_career: String = ""
var _worm_list: VBoxContainer        # 【新增】虫师门客列表
var _worm_career_btns: Array = []    # 【新增】虫师分类按钮
var _current_worm_career: String = "士"  # 【新增】当前虫师职业
var _peiyu: Control           # 【新增】促织堂视图
var _jar_grid: GridContainer  # 【新增】促织罐网格
var _peiyu_cricket_list: VBoxContainer  # 【新增】促织列表
var _worm_skill_popup: Control = null   # 【新增】当前打开的技能列表弹窗，用于关闭后刷新
var _worm_skill_hero_id: String = ""    # 【新增】当前技能列表对应的门客ID

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

	# 【新增】虫师视图
	_worm = _build_worm_view()
	_worm.visible = false
	_panel.add_child(_worm)
	
	_peiyu = _build_peiyu_view()
	_peiyu.visible = false
	_panel.add_child(_peiyu)

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

	# 【改】增加虫师入口
	var entries = [
		{"name": "促织架", "desc": "已收集的促织", "callback": _on_shelf},
		{"name": "捉促织", "desc": "消耗促织笼捕捉", "callback": _on_catch},
		{"name": "促织庙", "desc": "消耗缘分提升门客", "callback": _on_temple},
		{"name": "虫师", "desc": "培养促织虫书", "callback": _on_worm},
		{"name": "促织堂", "desc": "培育极无双促织", "callback": _on_peiyu},
		{"name": "特惠商城", "desc": "购买促织笼", "callback": _on_shop}
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
	btn.custom_minimum_size = Vector2(220, 180)
	btn.size = Vector2(220, 180)
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

func _on_worm():
	_show_view(_worm)
	_refresh_worm()

func _show_view(v: Control):
	_main.visible = false
	_shelf.visible = false
	_catch.visible = false
	_temple.visible = false
	_shop.visible = false
	_worm.visible = false
	_peiyu.visible = false
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
	career_lbl.text = cdata.career + "·" + sys.get_quality_name(cdata.quality)
	career_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	career_lbl.add_theme_font_size_override("font_size", 12)
	career_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(career_lbl)

	# 【改】显示军衔
	var rank_info = sys.get_cricket_rank_info(item.level)
	var lv_lbl = Label.new()
	lv_lbl.text = rank_info.full_name
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
	c.add_child(popup)

	var vbox = popup.get_child(0)

	var col = Color(sys.get_quality_color(cdata.quality))
	var rank_info = sys.get_cricket_rank_info(item.level)
	var info = Label.new()
	info.text = "%s  %s·%s\n军衔：%s" % [cdata.name, cdata.career, 
	sys.get_quality_name(cdata.quality), rank_info.full_name]
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", col)
	vbox.add_child(info)

	var q = int(cdata.quality)
	var max_lv = item.get("max_level", sys.get_cricket_max_level(q))
	var cost = sys.get_levelup_cost(item.level, q)
	var exp_lbl = Label.new()
	if item.level >= max_lv:
		exp_lbl.text = "军衔：已满阶"
	else:
		exp_lbl.text = "下次升阶需消耗：%d 只同名促织" % cost
	exp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exp_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(exp_lbl)

	var desc = Label.new()
	desc.text = "重复捉到同名促织自动转化为升阶材料\n军衔影响促织战力（后续玩法使用）"
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
	_catch_btn.pressed.connect(func(): _do_catch(1))
	root.add_child(_catch_btn)

	# 【新增】十连捕捉按钮
	_catch_ten_btn = Button.new()
	_catch_ten_btn.text = "十连捕捉（消耗10个促织笼）"
	_catch_ten_btn.position = Vector2(180, 280)
	_catch_ten_btn.size = Vector2(240, 60)
	_catch_ten_btn.add_theme_font_size_override("font_size", 20)
	var ten_sty = StyleBoxFlat.new()
	ten_sty.bg_color = Color("#6a3a5a")
	ten_sty.corner_radius_bottom_left = 8
	ten_sty.corner_radius_bottom_right = 8
	ten_sty.corner_radius_top_left = 8
	ten_sty.corner_radius_top_right = 8
	_catch_ten_btn.add_theme_stylebox_override("normal", ten_sty)
	_catch_ten_btn.pressed.connect(func(): _do_catch(10))
	root.add_child(_catch_ten_btn)

	_catch_result_lbl = Label.new()
	_catch_result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_catch_result_lbl.add_theme_font_size_override("font_size", 22)
	_catch_result_lbl.position = Vector2(0, 360)
	_catch_result_lbl.size = Vector2(600, 200)
	root.add_child(_catch_result_lbl)

	var gua_btn = Button.new()
	gua_btn.name = "GuaranteeBtn"
	gua_btn.text = "保底自选"
	gua_btn.position = Vector2(220, 580)
	gua_btn.size = Vector2(160, 50)
	gua_btn.add_theme_font_size_override("font_size", 18)
	gua_btn.pressed.connect(_show_guarantee_selector)
	root.add_child(gua_btn)

	return root

func _refresh_catch():
	var cage = data.items.get("cuzhi_cage", 0)
	var clbl = _catch.get_node_or_null("CageLabel")
	if clbl:
		clbl.text = "当前拥有促织笼：%d" % cage
		clbl.add_theme_color_override("font_color", Color("#66ff66") if cage > 0 else Color("#ff6666"))

	var prog = sys.get_guarantee_progress()
	var tgt = sys.get_guarantee_target()
	_catch_progress_lbl.text = "保底进度：%d / %d" % [prog, tgt]

	_catch_btn.disabled = cage <= 0
	if _catch_ten_btn:
		_catch_ten_btn.disabled = cage < 10

	var gua_btn = _catch.get_node_or_null("GuaranteeBtn")
	if gua_btn:
		gua_btn.visible = prog >= tgt

	_catch_result_lbl.text = ""

func _do_catch(count: int = 1):
	var cage = data.items.get("cuzhi_cage", 0)
	if cage < count:
		c._show_stage_hint("促织笼不足，去商城购买吧！")
		return

	var results = []
	for i in range(count):
		if data.items.get("cuzhi_cage", 0) <= 0:
			break
		var result = sys.catch_one()
		results.append(result)

	# 结果用弹窗显示
	var title = "捉促织结果" if count == 1 else "十连捕捉结果"
	var popup = c._create_base_popup(title, Vector2(500, 400))
	popup.z_index = 30
	c.add_child(popup)
	var vbox = popup.get_child(0)

	for result in results:
		var cdata = result.cricket
		var col = Color(sys.get_quality_color(result.quality))
		var new_str = "【新】" if result.is_new else "【重复】"
		var quality_name = sys.get_quality_name(result.quality)

		var line = Label.new()
		if result.quality >= 5:
			line.text = "%s%s·%s（%s） +%d %s缘分" % [new_str, cdata.name, quality_name, cdata.career, _cfg().fate_per_catch, cdata.career]
		else:
			line.text = "%s%s·%s（%s）" % [new_str, cdata.name, quality_name, cdata.career]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 16)
		line.add_theme_color_override("font_color", col)
		vbox.add_child(line)

	c._add_ok_button(vbox, func(): popup.queue_free(), "确定")

	_refresh_catch()

	if results.size() > 0 and results[-1].guarantee_ready:
		c._show_stage_hint("保底已满！可自选一只促织")

func _show_guarantee_selector():
	if sys.get_guarantee_progress() < sys.get_guarantee_target():
		return

	var popup = c._create_base_popup("保底自选", Vector2(560, 640))
	popup.z_index = 30
	c.add_child(popup)

	var vbox = popup.get_child(0)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var hint = Label.new()
	hint.text = "累计消耗已达%d次，自选一只无双促织" % sys.get_guarantee_target()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#ffaa00"))
	vbox.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(500, 0)
	vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var pool = sys.get_catchable_crickets()
	for cdata in pool:
		if int(cdata.quality) != 5:
			continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(220, 70)
		btn.text = cdata.name + "  " + cdata.career
		var col = Color(sys.get_quality_color(cdata.quality))
		btn.add_theme_color_override("font_color_normal", col)
		btn.pressed.connect(func():
			if sys.claim_guarantee(cdata.id):
				c._show_stage_hint("获得 %s！" % cdata.name)
				popup.queue_free()
				_refresh_catch()
			else:
				c._show_stage_hint("兑换失败")
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

	var filter_hbox = HBoxContainer.new()
	filter_hbox.name = "FilterHBox"
	filter_hbox.position = Vector2(20, 80)
	filter_hbox.size = Vector2(560, 50)
	filter_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	filter_hbox.add_theme_constant_override("separation", 8)
	root.add_child(filter_hbox)

	_temple_career_btns.clear()
	for career in ["士", "农", "工", "商", "侠"]:
		var btn = Button.new()
		btn.name = "Filter_" + career
		btn.custom_minimum_size = Vector2(100, 40)
		btn.pressed.connect(func(cr=career): _set_temple_career(cr))
		filter_hbox.add_child(btn)
		_temple_career_btns.append(btn)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 140)
	scroll.size = Vector2(560, 700)
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
	if _current_temple_career == "":
		_current_temple_career = "士"

	var careers = ["士", "农", "工", "商", "侠"]
	for i in range(careers.size()):
		var career = careers[i]
		var btn = _temple_career_btns[i]
		var f = sys.get_career_fate(career)
		btn.text = "%s: %d缘分" % [career, f]
		if _current_temple_career == career:
			btn.add_theme_color_override("font_color", Color("#ffdd88"))
		else:
			btn.add_theme_color_override("font_color", Color("#aaaaaa"))

	for ch in _temple_list.get_children():
		ch.queue_free()


	for hero_id in data.heroes:
		var h = data.heroes[hero_id]
		var hero_career = h.get("category", "")
		if hero_career != _current_temple_career:
			continue
		var row = _make_temple_hero_row(hero_id, h)
		_temple_list.add_child(row)

func _make_temple_hero_row(hero_id: String, h: Dictionary) -> Panel:
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


	var career = h.get("category", "")
	var lv = sys.get_temple_level(hero_id)
	var bonus = sys.get_temple_bonus(hero_id)
	var info = Label.new()
	info.text = "+%d%% 赚速（Lv.%d）" % [int(bonus * 100), lv]
	info.custom_minimum_size = Vector2(140, 0)
	info.add_theme_color_override("font_color", Color("#66ff66"))
	hbox.add_child(info)

	var cost = sys.get_temple_cost(hero_id)
	var can = sys.can_upgrade_temple(hero_id, career)

	var cost_lbl = Label.new()
	cost_lbl.text = "下次：%d %s缘分" % [cost, career]
	cost_lbl.custom_minimum_size = Vector2(160, 0)
	cost_lbl.add_theme_color_override("font_color", Color("#ffaa00") if can else Color("#ff6666"))
	hbox.add_child(cost_lbl)

	var up_btn = Button.new()
	up_btn.text = "升级" if lv < _cfg().temple.max_level else "已满"
	up_btn.disabled = not can
	up_btn.custom_minimum_size = Vector2(80, 40)
	up_btn.pressed.connect(func():
		if sys.upgrade_temple(hero_id, career):
			c._show_stage_hint("%s 促织庙 +1" % h.name)
			_refresh_temple()
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
		{"name": "促织蜜膏礼包", "price": 288, "items": {"cuzhi_migao": 60, "wood_comb": 12, "rouge": 12}},
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
			c._show_stage_hint("元宝不足！")
			return
		data.yuanbao -= g.price
		data.items["cuzhi_cage"] = data.items.get("cuzhi_cage", 0) + g.count
		
		if g.has("items"):
				for item_id in g.items.keys():
					data.items[item_id] = data.items.get(item_id, 0) + g.items[item_id]
		c._show_stage_hint("购买成功！+%d 促织笼" % g.count)
		c.update_money_label()
		_refresh_shop()
		)
	hbox.add_child(buy_btn)

	return panel

func _refresh_shop():
	pass

# ========== 虫师 ==========
func _build_worm_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	_make_sub_title("虫师", root)
	var back = _make_sub_back(root)
	back.pressed.connect(_show_main)

	var filter_hbox = HBoxContainer.new()
	filter_hbox.name = "WormFilterHBox"
	filter_hbox.position = Vector2(20, 80)
	filter_hbox.size = Vector2(560, 50)
	filter_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	filter_hbox.add_theme_constant_override("separation", 8)
	root.add_child(filter_hbox)

	_worm_career_btns.clear()
	for career in ["士", "农", "工", "商", "侠"]:
		var btn = Button.new()
		btn.name = "WormFilter_" + career
		btn.custom_minimum_size = Vector2(100, 40)
		btn.pressed.connect(func(cr=career): _set_worm_career(cr))
		filter_hbox.add_child(btn)
		_worm_career_btns.append(btn)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 140)
	scroll.size = Vector2(560, 700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_worm_list = VBoxContainer.new()
	_worm_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_worm_list)

	return root

func _set_worm_career(career: String):
	_current_worm_career = career
	_refresh_worm()

func _refresh_worm():
	if _current_worm_career == "":
		_current_worm_career = "士"

	var careers = ["士", "农", "工", "商", "侠"]
	for i in range(careers.size()):
		var career = careers[i]
		var btn = _worm_career_btns[i]
		var f = sys.get_career_fate(career)
		btn.text = "%s: %d缘分" % [career, f]
		if _current_worm_career == career:
			btn.add_theme_color_override("font_color", Color("#ffdd88"))
		else:
			btn.add_theme_color_override("font_color", Color("#aaaaaa"))

	for ch in _worm_list.get_children():
		ch.queue_free()

	for hero_id in data.heroes:
		var h = data.heroes[hero_id]
		var hero_career = h.get("category", "")
		if hero_career != _current_worm_career:
			continue
		var row = _make_worm_hero_row(hero_id, h)
		_worm_list.add_child(row)

func _make_worm_hero_row(hero_id: String, h: Dictionary) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(540, 70)
	btn.size = Vector2(540, 70)

	var sty = StyleBoxFlat.new()
	sty.bg_color = CARD
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	btn.add_theme_stylebox_override("normal", sty)
	btn.add_theme_stylebox_override("hover", sty)
	btn.add_theme_stylebox_override("pressed", sty)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	btn.add_child(hbox)

	var name_lbl = Label.new()
	name_lbl.text = h.name
	name_lbl.custom_minimum_size = Vector2(120, 0)
	name_lbl.add_theme_font_size_override("font_size", 18)
	hbox.add_child(name_lbl)

	# 【改】同步并显示技能数量
	sys._sync_worm_skills(hero_id)
	var skills = sys.get_hero_worm_skills(hero_id)
	var info = Label.new()
	info.text = "技能：%d 个" % skills.size()
	info.custom_minimum_size = Vector2(140, 0)
	info.add_theme_color_override("font_color", Color("#66ff66"))
	hbox.add_child(info)

	btn.pressed.connect(func(): _show_hero_worm_skills(hero_id, h))
	return btn

func _show_hero_worm_skills(hero_id: String, h: Dictionary):
	sys._sync_worm_skills(hero_id)
	var skills = sys.get_hero_worm_skills(hero_id)
	
	# 【新增】关闭旧的技能列表弹窗（防止重复打开多个）
	if _worm_skill_popup != null and is_instance_valid(_worm_skill_popup):
		_worm_skill_popup.queue_free()
	
	var popup = c._create_base_popup("%s 虫师技能" % h.name, Vector2(520, 640))
	popup.z_index = 30
	c.add_child(popup)
	# 【新增】保存引用，供升级弹窗关闭后刷新
	_worm_skill_popup = popup
	_worm_skill_hero_id = hero_id

	
	var vbox = popup.get_child(0)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(480, 0)
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	# 【新增】按星级从小到大排序
	var indices = range(skills.size())
	indices.sort_custom(func(a, b): return int(skills[a].star) < int(skills[b].star))

	for idx in indices:
		var skill = skills[idx]
		var cid = skill.cricket_id
		var cdata = sys._crickets_by_id.get(cid)
		if cdata == null: continue
		var row = _make_worm_skill_row(hero_id, idx, skill, cdata)
		list.add_child(row)

	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")

func _make_worm_skill_row(hero_id: String, idx: int, skill: Dictionary, cdata: Dictionary) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(460, 70)
	btn.size = Vector2(460, 70)

	var col = Color(sys.get_quality_color(cdata.quality))
	var sty = StyleBoxFlat.new()
	sty.bg_color = CARD
	sty.border_color = col
	sty.border_width_bottom = 2
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.corner_radius_bottom_left = 4
	sty.corner_radius_bottom_right = 4
	sty.corner_radius_top_left = 4
	sty.corner_radius_top_right = 4
	btn.add_theme_stylebox_override("normal", sty)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	btn.add_child(hbox)

	var name_lbl = Label.new()
	name_lbl.text = cdata.name
	name_lbl.custom_minimum_size = Vector2(100, 0)
	name_lbl.add_theme_color_override("font_color", col)
	hbox.add_child(name_lbl)

	var star_lbl = Label.new()
	star_lbl.text = "★%d" % skill.star
	star_lbl.custom_minimum_size = Vector2(50, 0)
	star_lbl.add_theme_color_override("font_color", Color("#ffdd88"))
	hbox.add_child(star_lbl)

	var lv_lbl = Label.new()
	lv_lbl.text = "Lv.%d" % skill.level
	lv_lbl.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(lv_lbl)

	var bonus = sys.get_worm_skill_bonus(hero_id, idx)
	var is_pct = int(skill.star) >= 5
	var bonus_str = ""
	if skill.level <= 0:
		bonus_str = "未激活"
	elif is_pct:
		bonus_str = "+%.0f%%" % (bonus * 100)
	else:
		bonus_str = "+%s" % c.format_number(int(bonus))
	var bonus_lbl = Label.new()
	bonus_lbl.text = bonus_str
	bonus_lbl.custom_minimum_size = Vector2(100, 0)
	bonus_lbl.add_theme_color_override("font_color", Color("#66ff66"))
	hbox.add_child(bonus_lbl)

	btn.pressed.connect(func(): _show_worm_skill_upgrade(hero_id, idx, skill, cdata))
	return btn

func _show_worm_skill_upgrade(hero_id: String, idx: int, skill: Dictionary, cdata: Dictionary):
	# 【修复】int(skill.star) 防御 float 问题
	var is_pct = int(skill.star) >= 5
	# 【改】弹窗高度从 320 增加到 380，容纳军衔提示行
	var popup = c._create_base_popup("%s 技能升级" % cdata.name, Vector2(440, 380))
	popup.z_index = 30
	c.add_child(popup)

	var vbox = popup.get_child(0)

	var info = Label.new()
	# 【修复】int(skill.star) 防御 float 问题
	info.text = "★%d虫书  Lv.%d" % [int(skill.star), int(skill.level)]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 20)
	info.add_theme_color_override("font_color", Color("#ffdd88"))
	vbox.add_child(info)

	var bonus = sys.get_worm_skill_bonus(hero_id, idx)
	var bonus_str = ""
	if skill.level <= 0:
		bonus_str = "未激活"
	elif is_pct:
		bonus_str = "+%.0f%%" % (bonus * 100)
	else:
		bonus_str = "+%s" % c.format_number(int(bonus))
	var bonus_lbl = Label.new()
	bonus_lbl.text = "当前加成：%s" % bonus_str
	bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(bonus_lbl)

	# 【新增】军衔阶别限制提示（考虑初始阶别差异）
	var required_offset = sys.get_worm_skill_required_rank(int(skill.level))
	var cricket_level = sys.get_cricket_level(skill.cricket_id)
	var current_rank = sys.get_cricket_rank_index(cricket_level)
	var cdata_q = int(cdata.quality)
	var init_rank = sys.get_cricket_init_rank(cdata_q)
	var required_absolute = init_rank + required_offset
	var rank_ok = current_rank >= required_absolute
	var current_rank_info = sys.get_cricket_rank_info(cricket_level)
	var required_rank_name = sys.get_cricket_rank_info(required_absolute * 9).rank_name
	var rank_lbl = Label.new()
	if rank_ok:
		rank_lbl.text = "促织军衔：%s（满足要求）" % current_rank_info.full_name
		rank_lbl.add_theme_color_override("font_color", Color("#66ff66"))
	else:
		# 【改】提示显示还需提升多少阶
		var need_up = required_absolute - current_rank
		rank_lbl.text = "促织军衔：%s  |  需达到：%s（还需提升%d阶）" % [current_rank_info.full_name, required_rank_name, need_up]
		rank_lbl.add_theme_color_override("font_color", Color("#ff6666"))
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rank_lbl)

	# 【修复】int(skill.star) 防御 float 问题
	var exp_item = "cuzhi_exp_high" if int(skill.star) >= 5 else "cuzhi_exp_low"
	var exp_name = "高级促织心得" if int(skill.star) >= 5 else "低级促织心得"
	var cost = sys.get_worm_skill_upgrade_cost(hero_id, idx)
	var can = sys.can_upgrade_worm_skill(hero_id, idx)
	var exp_have = data.items.get(exp_item, 0)

	var cost_lbl = Label.new()
	cost_lbl.text = "拥有%s：%d  |  升级消耗：%d" % [exp_name, exp_have, cost]
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_color_override("font_color", Color("#ffaa00") if can else Color("#ff6666"))
	vbox.add_child(cost_lbl)

	var up_btn = Button.new()
	up_btn.text = "升级"
	up_btn.disabled = not can
	up_btn.pressed.connect(func():
		if sys.upgrade_worm_skill(hero_id, idx):
			c._show_stage_hint("升级成功！")
			popup.queue_free()
			# 【新增】刷新底层技能列表，再打开新的升级弹窗
			_refresh_worm_skill_list()
			_show_worm_skill_upgrade(hero_id, idx, sys.get_hero_worm_skills(hero_id)[idx], cdata)
		else:
			c._show_stage_hint("升级失败")
	)
	vbox.add_child(up_btn)

	c._add_ok_button(vbox, func(): 
		popup.queue_free()
		# 【新增】关闭升级弹窗后刷新底层技能列表
		_refresh_worm_skill_list(),
		"关闭")

# 【新增】刷新当前打开的技能列表弹窗（升级/关闭后调用）
func _refresh_worm_skill_list():
	if _worm_skill_popup == null or not is_instance_valid(_worm_skill_popup):
		return
	if _worm_skill_hero_id == "":
		return
	
	# 找到列表容器（在 ScrollContainer 内）
	var vbox = _worm_skill_popup.get_child(0)
	var scroll = null
	var list = null
	for ch in vbox.get_children():
		if ch is ScrollContainer:
			scroll = ch
			break
	if scroll == null or scroll.get_child_count() == 0:
		return
	list = scroll.get_child(0)
	
	# 清空旧行
	for ch in list.get_children():
		ch.queue_free()
	
	# 重新构建
	sys._sync_worm_skills(_worm_skill_hero_id)
	var skills = sys.get_hero_worm_skills(_worm_skill_hero_id)
	# 【新增】按星级从小到大排序
	var indices = range(skills.size())
	indices.sort_custom(func(a, b): return int(skills[a].star) < int(skills[b].star))

	for idx in indices:
		var skill = skills[idx]
		var cid = skill.cricket_id
		var cdata = sys._crickets_by_id.get(cid)
		if cdata == null: continue
		var row = _make_worm_skill_row(_worm_skill_hero_id, idx, skill, cdata)
		list.add_child(row)


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


func _on_peiyu():
	_show_view(_peiyu)
	_refresh_peiyu()


# ========== 促织堂 ==========
func _build_peiyu_view() -> Control:
	var root = Control.new()
	root.size = Vector2(600, 900)

	_make_sub_title("促织堂", root)
	var back = _make_sub_back(root)
	back.pressed.connect(_show_main)

	var hint = Label.new()
	hint.name = "PeiyuHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("#aaaaaa"))
	hint.position = Vector2(0, 70)
	hint.size = Vector2(600, 30)
	root.add_child(hint)

	var jar_title = Label.new()
	jar_title.text = "促织罐"
	jar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jar_title.add_theme_font_size_override("font_size", 20)
	jar_title.add_theme_color_override("font_color", TITLE_COL)
	jar_title.position = Vector2(0, 105)
	jar_title.size = Vector2(600, 30)
	root.add_child(jar_title)

	_jar_grid = GridContainer.new()
	_jar_grid.columns = 2
	_jar_grid.position = Vector2(60, 140)
	_jar_grid.size = Vector2(480, 200)
	_jar_grid.add_theme_constant_override("h_separation", 16)
	_jar_grid.add_theme_constant_override("v_separation", 16)
	root.add_child(_jar_grid)

	var list_title = Label.new()
	list_title.text = "极无双促织"
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_title.add_theme_font_size_override("font_size", 20)
	list_title.add_theme_color_override("font_color", TITLE_COL)
	list_title.position = Vector2(0, 350)
	list_title.size = Vector2(600, 30)
	root.add_child(list_title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 390)
	scroll.size = Vector2(560, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_peiyu_cricket_list = VBoxContainer.new()
	_peiyu_cricket_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_peiyu_cricket_list)

	return root

func _refresh_peiyu():
	# 解锁提示
	var hint = _peiyu.get_node_or_null("PeiyuHint")
	if hint:
		if sys.is_peiyu_unlocked():
			hint.text = "已解锁培育功能 | 罐数：%d/%d" % [sys.get_jar_count(), sys.get_max_jar_count()]
		else:
			hint.text = "需任意促织达到八品·上尉解锁"

	# 刷新罐
	for ch in _jar_grid.get_children():
		ch.queue_free()

	var jars = data.cuzhi_jars
	for i in range(jars.size()):
		var jar = jars[i]
		var card = _make_jar_card(i, jar)
		_jar_grid.add_child(card)

	# 刷新促织列表
	for ch in _peiyu_cricket_list.get_children():
		ch.queue_free()

	var list = sys.get_caught_list()
	for item in list:
		if int(item.data.quality) != 6:
			continue
		# 【新增】过滤：只有属于系列的促织才显示在促织堂
		if sys.get_cricket_series(item.id) == "":
			continue
		var row = _make_peiyu_cricket_row(item)
		_peiyu_cricket_list.add_child(row)

func _make_jar_card(idx: int, jar: Dictionary) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(220, 90)
	btn.size = Vector2(220, 90)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var is_unlocked = idx < sys.get_jar_count() 
	var is_used = jar.get("cid", "") != ""
	# 【改】未解锁用灰色边框，已解锁空闲用绿色边框，培育中用亮绿色边框
	var col = Color("#66ff66") if is_used else (Color("#888888") if is_unlocked else Color("#444444"))
	var sty = StyleBoxFlat.new()
	sty.bg_color = CARD
	sty.border_color = col
	sty.border_width_bottom = 2
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	btn.add_theme_stylebox_override("normal", sty)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	btn.add_child(vbox)

	var idx_lbl = Label.new()
	idx_lbl.text = "罐 %d" % (idx + 1)
	idx_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	idx_lbl.add_theme_color_override("font_color", TITLE_COL)
	vbox.add_child(idx_lbl)

	if not is_unlocked:
		# 【新增】未解锁罐
		var lock_lbl = Label.new()
		lock_lbl.text = "未解锁"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_color_override("font_color", Color("#666666"))
		vbox.add_child(lock_lbl)
	elif is_used:
		var cdata = sys._crickets_by_id.get(jar.cid)
		var pname = _cfg().get("parts", {}).get(jar.part, jar.part)
		var name_lbl = Label.new()
		name_lbl.text = "%s - %s" % [cdata.name if cdata else "?", pname]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(name_lbl)

		var remain = sys.get_remaining_seconds(jar)
		var time_lbl = Label.new()
		if remain > 0:
			time_lbl.text = _fmt_time(remain)
			time_lbl.add_theme_color_override("font_color", Color("#ffaa00"))
		else:
			time_lbl.text = "可收获"
			time_lbl.add_theme_color_override("font_color", Color("#66ff66"))
		time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(time_lbl)

		btn.pressed.connect(func(): _show_jar_action(jar))
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "空闲"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color("#888888"))
		vbox.add_child(empty_lbl)


	return btn

func _fmt_time(sec: int) -> String:
	var h = int(sec / 3600.0)
	var m = int((sec % 3600) / 60.0)
	var s = sec % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]

func _show_jar_action(jar: Dictionary):
	if jar.get("cid", "") == "":
		return
	var remain = sys.get_remaining_seconds(jar)
	var cdata = sys._crickets_by_id.get(jar.cid)
	var pname = _cfg().get("parts", {}).get(jar.part, jar.part)

	var popup = c._create_base_popup("培育中", Vector2(400, 320))
	popup.z_index = 30
	c.add_child(popup)
	var vbox = popup.get_child(0)

	var info = Label.new()
	info.text = "%s - %s\\n剩余时间：%s" % [cdata.name if cdata else "?", pname, _fmt_time(remain)]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 18)
	vbox.add_child(info)

	# 加速
	var have = data.items.get("cuzhi_migao", 0)
	var have_lbl = Label.new()
	have_lbl.text = "拥有促织蜜膏：%d" % have
	have_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	have_lbl.add_theme_color_override("font_color", Color("#ffaa00"))
	vbox.add_child(have_lbl)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	# +10 按钮
	var btn10 = Button.new()
	btn10.text = "+10"
	btn10.custom_minimum_size = Vector2(70, 40)
	btn10.disabled = have < 10 or remain <= 0
	btn10.pressed.connect(func():
		if sys.speedup(jar, 10):
			c._show_stage_hint("加速成功！")
			popup.queue_free()
			_refresh_peiyu()
	)
	hbox.add_child(btn10)

	# 【新增】一键使用：自动计算实际需要多少个蜜膏，用多少扣多少
	var need = int(ceil(remain / 600.0))   # 每个蜜膏减600秒=10分钟，向上取整
	var use_count = mini(need, have)
	var auto_btn = Button.new()
	auto_btn.text = "一键使用(%d)" % use_count
	auto_btn.custom_minimum_size = Vector2(120, 40)
	auto_btn.disabled = use_count <= 0 or remain <= 0
	auto_btn.pressed.connect(func():
		if sys.speedup(jar, use_count):
			c._show_stage_hint("加速成功！使用%d个" % use_count)
			popup.queue_free()
			_refresh_peiyu()
	)
	hbox.add_child(auto_btn)

	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")

func _make_peiyu_cricket_row(item: Dictionary) -> Button:
	var cid = item.id
	var cdata = item.data
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(540, 90)
	btn.size = Vector2(540, 90)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS

	var col = Color(sys.get_quality_color(cdata.quality))
	var sty = StyleBoxFlat.new()
	sty.bg_color = CARD
	sty.border_color = col
	sty.border_width_bottom = 2
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.corner_radius_bottom_left = 6
	sty.corner_radius_bottom_right = 6
	sty.corner_radius_top_left = 6
	sty.corner_radius_top_right = 6
	btn.add_theme_stylebox_override("normal", sty)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	btn.add_child(hbox)

	var name_lbl = Label.new()
	name_lbl.text = cdata.name
	name_lbl.custom_minimum_size = Vector2(100, 0)
	name_lbl.add_theme_color_override("font_color", col)
	hbox.add_child(name_lbl)

	var phase = sys.get_current_phase(cid)
	var phase_cfg = sys.get_phase_cfg(phase)
	var phase_name = phase_cfg.get("name", "未知")
	var parts = data.cuzhi_caught[cid].get("parts", {"head": 0, "jaw": 0, "wing": 0})   
	var part_str = "头%d 牙%d 翅%d" % [parts.head, parts.jaw, parts.wing]
	
	# 【新增】计算该促织当前提供的加成
	var stage_pct = phase_cfg.get("stage_pct", 0.0)
	var income_per_lv = phase_cfg.get("income_per_level", 0)
	var total_lv = parts.head + parts.jaw + parts.wing
	var flat_income = total_lv * income_per_lv
	var bonus_str = "+%.0f%%" % (stage_pct * 100)
	if flat_income > 0:
		bonus_str += " +%s" % c.format_number(flat_income)
	
	var info = Label.new()
	info.text = "%s | %s \n %s" % [phase_name, part_str, bonus_str]
	info.custom_minimum_size = Vector2(180, 0)
	info.add_theme_color_override("font_color", Color("#aaaaaa"))
	hbox.add_child(info)

	# 蜕壳按钮
	var molt_btn = Button.new()
	molt_btn.text = "蜕壳"
	molt_btn.custom_minimum_size = Vector2(70, 36)
	# 【删】molt_btn.disabled = not can_molt  # 不禁用，让点击能进提示
	molt_btn.pressed.connect(func():
		if sys.can_molt(cid):
			if sys.do_molt(cid):
				c._show_stage_hint("蜕壳成功！")
				_refresh_peiyu()
		else:
			_show_molt_blocker(cid)
	)
	hbox.add_child(molt_btn)

	# 培育按钮
	var busy = sys.is_cricket_busy(cid)
	var peiyu_btn = Button.new()
	peiyu_btn.text = "培育中" if busy else "培育"
	peiyu_btn.custom_minimum_size = Vector2(70, 36)
	peiyu_btn.disabled = busy or not sys.is_peiyu_unlocked()
	peiyu_btn.pressed.connect(func(): _show_part_selector(cid, cdata))
	hbox.add_child(peiyu_btn)

	return btn


# 【新增】蜕壳条件不满足时提示具体原因
func _show_molt_blocker(cid: String):
	var phase = sys.get_current_phase(cid)
	var phases = _cfg().get("phases", [])
	if phase >= phases.size() - 1:
		c._show_stage_hint("该促织已达最高阶段，无法继续蜕壳")
		return
	var max_lv = sys.get_part_max_level(cid)
	for part in ["head", "jaw", "wing"]:
		if sys.get_part_level(cid, part) < max_lv:
			c._show_stage_hint("所有部位需培育至%d级方可蜕壳" % max_lv)
			return
	var series = sys.get_cricket_series(cid)
	if series == "":
		c._show_stage_hint("该促织无系列归属，无法蜕壳")
		return
	var item_id = _cfg().get("molt_items", {}).get(series, "")
	var item_name = data.ITEM_CONFIG.get(item_id, {}).get("name", item_id)
	var have = data.items.get(item_id, 0)
	c._show_stage_hint("蜕壳需要 %s×1（当前拥有 %d）" % [item_name, have])


func _show_part_selector(cid: String, _cdata: Dictionary):
	var popup = c._create_base_popup("选择培育部位", Vector2(400, 300))
	popup.z_index = 30
	c.add_child(popup)
	var vbox = popup.get_child(0)

	var phase = sys.get_current_phase(cid)
	var phase_cfg = sys.get_phase_cfg(phase)
	var max_lv = phase_cfg.get("max_level", 0)

	for part in ["head", "jaw", "wing"]:
		var cur_lv = sys.get_part_level(cid, part)
		var pname = _cfg().get("parts", {}).get(part, part)
		var is_max = cur_lv >= max_lv
		var jar_busy = sys.is_cricket_busy(cid)

		var hbox = HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(hbox)

		var lbl = Label.new()
		lbl.text = "%s：%d/%d" % [pname, cur_lv, max_lv]
		lbl.custom_minimum_size = Vector2(150, 0)
		hbox.add_child(lbl)

		var btn = Button.new()
		btn.text = "已满" if is_max else ("培育中" if jar_busy else "培育")
		btn.custom_minimum_size = Vector2(100, 40)
		btn.disabled = is_max or jar_busy or not sys.is_any_jar_free()
		btn.pressed.connect(func():
			if sys.start_peiyu(cid, part):
				c._show_stage_hint("开始培育 %s！" % pname)
				popup.queue_free()
				_refresh_peiyu()
		)
		hbox.add_child(btn)

	c._add_ok_button(vbox, func(): popup.queue_free(), "关闭")


# 【新增】打开无双促织盒子选择器（由 bag_page 调用）
func show_wushuang_box_selector():
	var popup = c._create_base_popup("无双促织自选", Vector2(560, 640))
	popup.z_index = 30
	c.add_child(popup)

	var vbox = popup.get_child(0)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var hint = Label.new()
	hint.text = "请选择一只无双促织"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#ffaa00"))
	vbox.add_child(hint)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(500, 0)
	vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var pool = sys.get_all_crickets() 
	for cdata in pool:
		if int(cdata.quality) < 5:
			continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(220, 70)
		btn.text = cdata.name + "  " + cdata.career
		var col = Color(sys.get_quality_color(cdata.quality))
		btn.add_theme_color_override("font_color_normal", col)
		btn.pressed.connect(func():
			if sys.do_wushuang_box_claim(cdata.id):
				c._show_stage_hint("获得 %s！" % cdata.name)
				popup.queue_free()
			else:
				c._show_stage_hint("兑换失败")
		)
		grid.add_child(btn)

	c._add_ok_button(vbox, func(): popup.queue_free(), "取消")
