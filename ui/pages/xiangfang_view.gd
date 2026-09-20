# ============================================================
# 厢房全屏页（府邸「厢房」入口；Page z35 / 弹窗 z40，照 BaseView 新模式）
# 批次①（2026-09-20）：主界面 + 家具图鉴（升级/套装面板）+ 工坊直购。
# 批次②（2026-09-20）：回收（详情页满级富余件）+ 风水详情弹窗（角标点入）+ 勋章（入口/15级列表/升级，
#   shop bonus 挂点=systems/shop_system.gd get_shop_auto_income 末项）。
# 批次③（2026-09-20）：命盘页（5 盘 Tab/10 槽/卜卦/自动卜卦/加成总览/升级效果，逻辑在 mingpan_system.gd）。
# 批次④（2026-09-20）：HeroData 四链接入（hero_data.gd 三链+game_data.gd 转发块+勋章技能上限写天赋系统）
#   + 升级效果弹窗。四批齐了，本页功能完整。
# 红点口径：照 2026-09-18 拍板——页内展示不穿透地图（批次②起挂：勋章可升级/套装可进阶亮红点）。
# 弹窗刷新：原地重建内容（基座面板不动，只换 VBox 内容），规避"关弹窗+立刻重建同名"自动改名雷（勋章热修同款）。
# ============================================================
class_name XiangfangView
extends BaseView

# 家具五档品质色（档案品质色规范，命格 10 档色表走 mingpan.json 不与这里混用）
const QUALITY_COLORS := {
	"wushuang": "#e74c3c", "chuanqi": "#e67e22", "zhuoyue": "#9b59b6",
	"youxiu": "#3498db", "putong": "#f2f2f2",
}

var _tab: String = "home"        # home / catalog / workshop
var _sel_set: String = "s01"     # 图鉴当前选中套装
var _sel_plate: String = "p1"    # 命盘当前选中盘
var _pending_luck: Dictionary = {}   # 卜卦待二选一的新命格（替换/放弃后清空）
var _upresult: Dictionary = {}       # 升级效果弹窗数据（升级前后等级/舒适度/风水差值）
var _auto_divining: bool = false     # 自动卜卦进行中（再按一次停止）
var _auto_stats: Dictionary = {}     # 自动卜卦暂停时的计数（卦数/装上数）
var _popup_panel: PanelContainer = null   # 当前弹窗基座（原地重建内容用）

func _init(p_c):
	super(p_c)
	_page_name = "XiangfangPage"
	_popup_node_name = "XiangfangPopup"
	_page_bg = "#1e1b2e"

func _sys() -> XiangfangSystem:
	return data.xiangfang_system

func show_xiangfang_view():
	show_view()

func hide_xiangfang_view():
	_popup_panel = null
	hide_view()

func _build(page: Panel):
	if _tab == "catalog":
		_build_catalog_page(page)
		return
	if _tab == "workshop":
		_build_workshop_page(page)
		return
	if _tab == "mingpan":
		_build_mingpan_page(page)
		return
	_build_home_page(page)

# ==================== 主界面 ====================
func _build_home_page(page: Panel):
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14
	root.offset_top = 12
	root.offset_right = -14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 10)
	page.add_child(root)

	# 顶栏：返回 + 标题 + 勋章入口（可升级亮红点）
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(hide_xiangfang_view)
	top.add_child(back)
	var title := Label.new()
	title.text = "厢房"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var medal_btn := Button.new()
	medal_btn.text = "勋章"
	medal_btn.custom_minimum_size = Vector2(72, 40)
	medal_btn.pressed.connect(func(): _show_medal_popup())
	top.add_child(medal_btn)
	_add_btn_dot(medal_btn, _sys().can_upgrade_medal().get("ok", false))

	# 左上风水角标（可点入详情弹窗）：风水值 + 等级 + 距下级
	var fs_btn := Button.new()
	fs_btn.text = "风水 %s · %d 级（距下级还需 %d 点）▸" % [
		c.format_number(_sys().get_fengshui()), _sys().get_fengshui_level(), _sys().get_fengshui_to_next()]
	fs_btn.add_theme_color_override("font_color", Color("#8fd3c7"))
	fs_btn.pressed.connect(func(): _show_fengshui_popup())
	root.add_child(fs_btn)

	# 资源行：舒适度 / 家具币 / 风水符
	var res := HBoxContainer.new()
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	res.add_theme_constant_override("separation", 20)
	root.add_child(res)
	for txt in [
		"舒适度 %s" % c.format_number(_sys().get_total_comfort()),
		"家具币 %s" % c.format_number(_sys().get_jiajibi()),
		"风水符 %s" % c.format_number(_sys().get_talisman_count()),
	]:
		var l := Label.new()
		l.text = txt
		res.add_child(l)

	# 中部入口大卡：家具图鉴 / 工坊
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	center.add_child(grid)
	var catalog_btn := _make_entry_btn("家具图鉴\n（296件 · 20套装）", func():
		_tab = "catalog"
		_refresh())
	grid.add_child(catalog_btn)
	var workshop_btn := _make_entry_btn("工坊\n（家具币直购）", func():
		_tab = "workshop"
		_refresh())
	grid.add_child(workshop_btn)

	# 命盘入口（批次③）
	var mp_center := CenterContainer.new()
	root.add_child(mp_center)
	var mingpan_btn := _make_entry_btn("命盘\n（五行盘 · 卜卦）", func():
		_tab = "mingpan"
		_refresh())
	mp_center.add_child(mingpan_btn)

# 卡片子节点全部 IGNORE：Label/VBox 默认拦点击不冒泡，会吃掉卡片的 gui_input（照 inn_view「点击穿透到卡片」惯例）
func _pass_clicks(card: Control) -> void:
	for child in card.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pass_clicks(child)

# 卡片红点（_add_btn_dot 的 Control 通用版：卡片是 PanelContainer 非 Button，照抄锚点定位实现）
func _card_dot(card: Control, cond: bool) -> void:
	var d := Label.new()
	d.text = "●"
	d.add_theme_color_override("font_color", Color("#e74c3c"))
	d.add_theme_font_size_override("font_size", 14)
	d.anchor_left = 1.0
	d.anchor_right = 1.0
	d.anchor_top = 0.0
	d.anchor_bottom = 0.0
	d.offset_left = -18
	d.offset_right = -2
	d.offset_top = 2
	d.offset_bottom = 18
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.visible = cond
	card.add_child(d)

func _make_entry_btn(text: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 110)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(on_press)
	return btn

# ==================== 家具图鉴页 ====================
func _build_catalog_page(page: Panel):
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	page.add_child(root)

	# 顶栏
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(func():
		_tab = "home"
		_refresh())
	top.add_child(back)
	var title := Label.new()
	title.text = "家具图鉴"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var workshop_btn := Button.new()
	workshop_btn.text = "工坊"
	workshop_btn.custom_minimum_size = Vector2(72, 40)
	workshop_btn.pressed.connect(func():
		_tab = "workshop"
		_refresh())
	top.add_child(workshop_btn)

	# 主体：左套装列表 + 右家具网格/套装面板
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	# 左：20 套装列表（滚动）
	var set_scroll := ScrollContainer.new()
	set_scroll.custom_minimum_size = Vector2(190, 0)
	set_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(set_scroll)
	var set_vbox := VBoxContainer.new()
	set_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_vbox.add_theme_constant_override("separation", 4)
	set_scroll.add_child(set_vbox)
	for s in _sys().get_set_list():
		var sid: String = str(s.get("id", ""))
		var st: Dictionary = _sys().get_set_owned(sid)
		var row := PanelContainer.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color("#2a2640") if sid == _sel_set else Color("#221e33")
		rs.border_color = Color("#6a5f9e") if sid == _sel_set else Color("#3a3550")
		rs.set_border_width_all(1)
		rs.set_corner_radius_all(4)
		row.add_theme_stylebox_override("panel", rs)
		row.custom_minimum_size = Vector2(178, 52)
		var vl := VBoxContainer.new()
		row.add_child(vl)
		var name_l := Label.new()
		name_l.text = str(s.get("name", ""))
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.add_theme_color_override("font_color", Color("#ffd700"))
		vl.add_child(name_l)
		var info_l := Label.new()
		info_l.text = "Lv%d · %d/%d件" % [_sys().get_set_level(sid), st["owned"], st["total"]]
		info_l.add_theme_font_size_override("font_size", 11)
		info_l.add_theme_color_override("font_color", Color("#aaaaaa"))
		vl.add_child(info_l)
		_pass_clicks(row)   # 子节点穿透，否则文字区吃掉点击
		_card_dot(row, _sys().set_has_action(sid))   # 套内有可操作项亮红点
		row.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_sel_set = sid
				_refresh())
		set_vbox.add_child(row)

	# 右：上下结构（家具网格 + 套装面板）
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	# 家具网格（滚动，3 列卡片）
	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(grid_scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(grid)
	var items: Array = _sys().get_set_furniture(_sel_set)
	for fc in items:
		grid.add_child(_make_furniture_card(fc))

	# 底部套装面板：等级/效果/进度
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#2a2640")
	ps.border_color = Color("#6a5f9e")
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", ps)
	right.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	panel.add_child(pv)
	var set_cfg: Dictionary = _sys().get_set_cfg(_sel_set)
	var head_l := Label.new()
	head_l.text = "%s · 套装等级 Lv%d" % [set_cfg.get("name", ""), _sys().get_set_level(_sel_set)]
	head_l.add_theme_font_size_override("font_size", 14)
	head_l.add_theme_color_override("font_color", Color("#ffd700"))
	pv.add_child(head_l)
	var eff_l := Label.new()
	eff_l.text = "套装效果：" + _sys().get_set_effect_desc(_sel_set)
	eff_l.add_theme_font_size_override("font_size", 12)
	eff_l.add_theme_color_override("font_color", Color("#7ee08a"))
	pv.add_child(eff_l)
	var prog_l := Label.new()
	var own: Dictionary = _sys().get_set_owned(_sel_set)
	prog_l.text = "进度：%d/%d 件（套装等级上限=套内最低件等级 Lv%d）" % [
		own["owned"], own["total"], _sys().get_set_max_level(_sel_set)]
	prog_l.add_theme_font_size_override("font_size", 11)
	prog_l.add_theme_color_override("font_color", Color("#aaaaaa"))
	pv.add_child(prog_l)

	# 解锁/升级按钮：条件达成亮红点；未达成点击弹"需要全套家具达到XX级"（用户 2026-09-20 拍板）
	var set_chk: Dictionary = _sys().can_advance_set(_sel_set)
	var set_btn := Button.new()
	set_btn.text = "解锁" if _sys().get_set_level(_sel_set) == 0 else "升级"
	set_btn.custom_minimum_size = Vector2(0, 34)
	set_btn.pressed.connect(func(): _on_advance_set(_sel_set, set_btn))
	pv.add_child(set_btn)
	_add_btn_dot(set_btn, set_chk.get("ok", false))

# 家具卡片：品质色卡 + 名 + 等级/件数（整卡点击进详情弹窗）
func _make_furniture_card(fc: Dictionary) -> PanelContainer:
	var st: Dictionary = _sys().get_furniture_state(str(fc.get("id", "")))
	var q: Dictionary = _sys().get_quality_cfg(str(fc.get("quality", "")))
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#262238")
	cs.border_color = Color(QUALITY_COLORS.get(str(fc.get("quality", "")), "#ffffff"))
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(5)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(88, 96)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var vl := VBoxContainer.new()
	vl.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vl)
	var name_l := Label.new()
	name_l.text = str(fc.get("name", ""))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.add_theme_color_override("font_color", Color(QUALITY_COLORS.get(str(fc.get("quality", "")), "#ffffff")))
	name_l.clip_text = true
	vl.add_child(name_l)
	var qc_l := Label.new()
	qc_l.text = "%s · %s" % [q.get("name", ""), fc.get("career", "")]
	qc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qc_l.add_theme_font_size_override("font_size", 10)
	qc_l.add_theme_color_override("font_color", Color("#888888"))
	vl.add_child(qc_l)
	# 等级：lv=0 显示未解锁（用户 2026-09-20 拍板）
	var lv_l := Label.new()
	if st["lv"] > 0:
		lv_l.text = "等级 Lv%d" % st["lv"]
		lv_l.add_theme_color_override("font_color", Color("#7ee08a"))
	else:
		lv_l.text = "未解锁"
		lv_l.add_theme_color_override("font_color", Color("#777777"))
	lv_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_l.add_theme_font_size_override("font_size", 11)
	vl.add_child(lv_l)
	var cnt_l := Label.new()
	cnt_l.text = "拥有 %d" % st["cnt"]
	cnt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt_l.add_theme_font_size_override("font_size", 10)
	cnt_l.add_theme_color_override("font_color", Color("#bbbbbb"))
	vl.add_child(cnt_l)
	var fid: String = str(fc.get("id", ""))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_furniture_popup(fid))
	_pass_clicks(card)   # 子节点穿透
	_card_dot(card, _sys().can_upgrade(fid).get("ok", false))   # 可升级/解锁红点（页内展示不穿透）
	return card

# ==================== 工坊页 ====================
func _build_workshop_page(page: Panel):
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	page.add_child(root)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(func():
		_tab = "home"
		_refresh())
	top.add_child(back)
	var title := Label.new()
	title.text = "工坊"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var bal := Label.new()
	bal.text = "家具币 %s" % c.format_number(_sys().get_jiajibi())
	bal.custom_minimum_size = Vector2(120, 40)
	bal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(bal)

	# 说明行
	var note := Label.new()
	note.text = "前 5 套装共 %d 件直购（回收满级富余件可得家具币）" % (_sys().get_workshop_items() as Array).size()
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color("#888888"))
	root.add_child(note)

	# 直购网格：不滚动·铺满·按品质高→低排序（64 件≈8列×8行均分页面，用户 2026-09-20 拍板）
	var grid := GridContainer.new()
	grid.columns = 8
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	root.add_child(grid)
	var rank: Dictionary = {"wushuang": 0, "chuanqi": 1, "zhuoyue": 2, "youxiu": 3, "putong": 4}
	var shop_items: Array = _sys().get_workshop_items()
	shop_items.sort_custom(func(a, b): return int(rank.get(str(a.get("quality", "")), 9)) < int(rank.get(str(b.get("quality", "")), 9)))
	for fc in shop_items:
		grid.add_child(_make_workshop_card(fc))

func _make_workshop_card(fc: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#262238")
	cs.border_color = Color(QUALITY_COLORS.get(str(fc.get("quality", "")), "#ffffff"))
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(66, 54)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var vl := VBoxContainer.new()
	vl.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vl)
	var name_l := Label.new()
	name_l.text = str(fc.get("name", ""))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 10)
	name_l.add_theme_color_override("font_color", Color(QUALITY_COLORS.get(str(fc.get("quality", "")), "#ffffff")))
	name_l.clip_text = true
	vl.add_child(name_l)
	var price: int = _sys().get_workshop_price(str(fc.get("quality", "")))
	var price_l := Label.new()
	price_l.text = "%d币" % price
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_l.add_theme_font_size_override("font_size", 10)
	price_l.add_theme_color_override("font_color", Color("#ffd700"))
	vl.add_child(price_l)
	var fid: String = str(fc.get("id", ""))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_buy_popup(fid))
	_pass_clicks(card)   # 子节点穿透
	return card

# ==================== 弹窗（原地重建内容模式） ====================
func _rebuild_popup():
	if _popup_kind == "furniture":
		_show_furniture_popup(_popup_id)
	elif _popup_kind == "buy":
		_show_buy_popup(_popup_id)
	elif _popup_kind == "recycle":
		_show_recycle_popup(_popup_id)
	elif _popup_kind == "fengshui":
		_show_fengshui_popup()
	elif _popup_kind == "medal":
		_show_medal_popup()
	elif _popup_kind == "mingpan_detail":
		_show_luck_detail_popup(_popup_id)
	elif _popup_kind == "divine":
		_show_divine_popup()
	elif _popup_kind == "overview":
		_show_overview_popup()
	elif _popup_kind == "upeffect":
		_show_upeffect_popup()
	elif _popup_kind == "upresult":
		_show_upresult_popup(_popup_id)

# 取弹窗内容 VBox：已有基座则清空内容原地重建（不新建同名节点，规避自动改名雷）；无则新建
func _popup_vbox(title: String, size: Vector2) -> VBoxContainer:
	if _popup_panel != null and is_instance_valid(_popup_panel) and c.get_node_or_null(_popup_node_name) == _popup_panel:
		for child in _popup_panel.get_child(0).get_children():
			_popup_panel.get_child(0).remove_child(child)
			child.queue_free()
		return _popup_panel.get_child(0)
	_close_node(_popup_node_name)
	_popup_panel = c._create_base_popup(title, size)
	_popup_panel.name = _popup_node_name
	_popup_panel.z_index = 40   # 【关键】必须高于全屏页 z35（照妙音坊勋章弹窗模板），否则弹窗被页面盖住"隐身"
	c.add_child(_popup_panel)
	return _popup_panel.get_child(0)

# ---- 家具详情弹窗：效果/拥有/升级/一键升级/满级回收 ----
func _show_furniture_popup(fid: String):
	_popup_kind = "furniture"
	_popup_id = fid
	var fc: Dictionary = _sys().get_furniture_cfg(fid)
	if fc.is_empty():
		close_popup()
		return
	var vbox: VBoxContainer = _popup_vbox("家具详情", Vector2(460, 460))
	var q: Dictionary = _sys().get_quality_cfg(str(fc.get("quality", "")))
	var st: Dictionary = _sys().get_furniture_state(fid)
	var color: Color = Color(QUALITY_COLORS.get(str(fc.get("quality", "")), "#ffffff"))

	var name_l := Label.new()
	name_l.text = "%s（%s · %s）" % [fc.get("name", ""), q.get("name", ""), fc.get("career", "")]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 17)
	name_l.add_theme_color_override("font_color", color)
	vbox.add_child(name_l)

	var lv_l := Label.new()
	lv_l.text = "等级 Lv%d / %d · 持有 %d 件" % [st["lv"], _sys().get_max_lv(), st["cnt"]]
	lv_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_l.add_theme_color_override("font_color", Color("#bbbbbb"))
	vbox.add_child(lv_l)

	# 当前 & 下级效果（无双/传奇=资质；卓越/优秀/普通=固定赚钱）
	var cur_l := Label.new()
	cur_l.text = "当前效果：" + _effect_text(fc, st["lv"]) if st["lv"] > 0 else "当前效果：未解锁"
	cur_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cur_l.add_theme_color_override("font_color", Color("#7ee08a"))
	vbox.add_child(cur_l)
	if st["lv"] < _sys().get_max_lv():
		var cost: int = _sys().get_upgrade_cost(fid, st["lv"])
		var nxt_l := Label.new()
		nxt_l.text = "下级效果：%s（消耗 %d 件同名家具，返 %d 风水符）" % [
			_effect_text(fc, st["lv"] + 1), cost, cost * int(q.get("talisman", 0))]
		nxt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nxt_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nxt_l.add_theme_color_override("font_color", Color("#8fd3c7"))
		vbox.add_child(nxt_l)
	elif st["lv"] >= _sys().get_max_lv():
		# 满级：富余件回收（回收价=品质工坊价×80%，返家具币道具）
		var recyc: int = _sys().get_recyclable_count(fid)
		var max_l := Label.new()
		max_l.text = "已满级（富余 %d 件可回收）" % recyc
		max_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_l.add_theme_color_override("font_color", Color("#ffd700"))
		vbox.add_child(max_l)
		if recyc > 0:
			var rec_btn := Button.new()
			rec_btn.text = "回收富余"
			rec_btn.custom_minimum_size = Vector2(0, 36)
			rec_btn.pressed.connect(func(): _show_recycle_popup(fid))
			vbox.add_child(rec_btn)

	# 升级按钮
	var chk: Dictionary = _sys().can_upgrade(fid)
	var up_btn := Button.new()
	up_btn.text = "解锁" if st["lv"] == 0 else "升级"   # 0→1 语义=解锁（用户拍板）
	up_btn.disabled = not chk.get("ok", false)
	up_btn.custom_minimum_size = Vector2(0, 40)
	up_btn.pressed.connect(func(): _on_upgrade(fid, false, up_btn))
	vbox.add_child(up_btn)
	if not chk.get("ok", false) and st["cnt"] > 0 and st["lv"] < _sys().get_max_lv():
		var reason_l := Label.new()
		reason_l.text = str(chk.get("reason", ""))
		reason_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reason_l.add_theme_color_override("font_color", Color("#e74c3c"))
		vbox.add_child(reason_l)

	var up_all_btn := Button.new()
	up_all_btn.text = "一键升级（连升直到材料尽）"
	up_all_btn.custom_minimum_size = Vector2(0, 40)
	up_all_btn.pressed.connect(func(): _on_upgrade(fid, true, up_all_btn))
	vbox.add_child(up_all_btn)

	c._add_ok_button(vbox, func(): close_popup(), "关闭")

# ---- 回收弹窗：满级富余件数量选择，返家具币 ----
func _show_recycle_popup(fid: String):
	_popup_kind = "recycle"
	_popup_id = fid
	var fc: Dictionary = _sys().get_furniture_cfg(fid)
	var avail: int = _sys().get_recyclable_count(fid)
	if fc.is_empty() or avail <= 0:
		close_popup()
		return
	var vbox: VBoxContainer = _popup_vbox("回收家具", Vector2(440, 280))
	var price: int = _sys().get_recycle_price(str(fc.get("quality", "")))

	var name_l := Label.new()
	name_l.text = "%s · 回收价 %d 家具币/件（可回收 %d 件）" % [fc.get("name", ""), price, avail]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_l)

	var pair: Dictionary = c.ui_helpers._create_slider_spin_pair(vbox, avail, 1)
	var total_l := Label.new()
	total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(total_l)
	var _upd := func():
		total_l.text = "合计返还：%d 家具币" % (int(pair["spin"].value) * price)
	pair["slider"].value_changed.connect(func(_v): _upd.call())
	pair["spin"].value_changed.connect(func(_v): _upd.call())
	_upd.call()

	var rec_btn := Button.new()
	rec_btn.text = "回收"
	rec_btn.custom_minimum_size = Vector2(0, 40)
	rec_btn.pressed.connect(func():
		_on_recycle(fid, int(pair["spin"].value), rec_btn))
	vbox.add_child(rec_btn)

	c._add_ok_button(vbox, func(): close_popup(), "关闭")

func _on_recycle(fid: String, n: int, btn: Button):
	var r: Dictionary = _sys().recycle_furniture(fid, n)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "回收失败")))
		_flash_btn(btn)
		return
	c._show_stage_hint("回收成功：+%d 家具币" % int(r.get("gain", 0)))
	_refresh()

# ---- 风水详情弹窗：推导说明 + 10 档品质概率表 ----
func _show_fengshui_popup():
	_popup_kind = "fengshui"
	_popup_id = ""
	var vbox: VBoxContainer = _popup_vbox("风水详情", Vector2(470, 470))
	var fs_l: int = _sys().get_fengshui_level()

	var head_l := Label.new()
	head_l.text = "风水 %s · %d 级（距下级还需 %d 点）" % [
		c.format_number(_sys().get_fengshui()), fs_l, _sys().get_fengshui_to_next()]
	head_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_l.add_theme_font_size_override("font_size", 16)
	head_l.add_theme_color_override("font_color", Color("#8fd3c7"))
	vbox.add_child(head_l)

	var note_l := Label.new()
	note_l.text = "来源：无双家具等级×100（唯一）｜效果：卜卦命格品质概率（命盘批次③开放）"
	note_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_l.add_theme_font_size_override("font_size", 11)
	note_l.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(note_l)

	# 10 档概率表：当前等级 vs 下一级（用户拍板：只看这两列）
	var cur_rows: Array = _sys().get_fengshui_rows(fs_l)
	var nxt_rows: Array = _sys().get_fengshui_rows(fs_l + 1)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)
	var head_row := Label.new()
	head_row.text = "品质　　当前　→　下一级"
	head_row.add_theme_font_size_override("font_size", 12)
	head_row.add_theme_color_override("font_color", Color("#aaaaaa"))
	rows.add_child(head_row)
	for i in range(mini(cur_rows.size(), nxt_rows.size())):
		var row_l := Label.new()
		row_l.text = "%s　%.2f%% → %.2f%%" % [
			cur_rows[i]["name"], float(cur_rows[i]["pct"]) * 100.0, float(nxt_rows[i]["pct"]) * 100.0]
		row_l.add_theme_font_size_override("font_size", 13)
		row_l.add_theme_color_override("font_color", Color("#dddddd"))
		rows.add_child(row_l)

	c._add_ok_button(vbox, func(): close_popup(), "关闭")

# ---- 勋章弹窗：统一样式（照钓鱼/妙音坊勋章模板，用户 2026-09-20 拍板） ----
func _show_medal_popup():
	_popup_kind = "medal"
	_popup_id = ""
	var vbox: VBoxContainer = _popup_vbox("勋章", Vector2(460, 420))
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2a2640")
	style.border_color = Color("#6a5f9e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	vbox.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head_row := HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_theme_constant_override("separation", 6)
	vb.add_child(head_row)
	var head := Label.new()
	head.text = "勋章：%s（%d级）" % [_sys().get_medal_name(), _sys().medal_lv]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	head_row.add_child(head)
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.custom_minimum_size = Vector2(24, 24)
	help_btn.tooltip_text = "点击查看勋章规则"
	help_btn.pressed.connect(_on_medal_help)
	head_row.add_child(help_btn)
	var effect := Label.new()
	effect.text = "全部商铺赚速 +%d%%" % int(_sys().get_medal_shop_pct() * 100)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.add_theme_color_override("font_color", Color("#e6c07b"))
	vb.add_child(effect)
	var nxt: Dictionary = _sys().get_next_medal_cfg()
	if nxt.is_empty():
		var max_lbl := Label.new()
		max_lbl.text = "已满级"
		max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		max_lbl.add_theme_color_override("font_color", Color("#9a93b8"))
		vb.add_child(max_lbl)
	else:
		var need: int = int(nxt.get("need_comfort", 0))
		var next_lbl := Label.new()
		next_lbl.text = "下一级需舒适度 %s（当前 %s）" % [c.format_number(need), c.format_number(_sys().get_total_comfort())]
		next_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(next_lbl)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = maxf(1.0, float(need))
		bar.value = minf(float(_sys().get_total_comfort()), float(need))
		bar.show_percentage = true
		bar.custom_minimum_size = Vector2(410, 18)
		vb.add_child(bar)
		var next_effect := Label.new()
		next_effect.text = "下级效果：全部商铺赚速 +%d%%" % int(float(nxt.get("shop_pct", 0.0)) * 100.0)
		next_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next_effect.add_theme_color_override("font_color", Color("#7ee787"))
		vb.add_child(next_effect)
		var up_btn := Button.new()
		up_btn.text = "升级勋章"
		up_btn.custom_minimum_size = Vector2(130, 38)
		up_btn.disabled = not _sys().can_upgrade_medal().get("ok", false)
		up_btn.pressed.connect(_on_medal_upgrade)
		vb.add_child(up_btn)
	c._add_ok_button(vbox, func(): close_popup(), "关闭")

func _on_medal_help():
	c._show_stage_hint("厢房勋章：舒适度达到门槛即可升级（舒适度只作门槛不消耗）；每级全部商铺赚速+100%；技能等级上限效果挂起未接入。")

func _on_medal_upgrade():
	var r: Dictionary = _sys().upgrade_medal()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "暂不可升级")))
		return
	c._show_stage_hint("勋章升级成功")
	_refresh()   # 页+弹窗按状态原地重建（进度条/红点同步）

# 套装解锁/升级：条件未达→红色提示+按钮闪红；成功→提示并刷新（页+弹窗按状态原地重建）
func _on_advance_set(sid: String, btn: Button):
	var r: Dictionary = _sys().advance_set(sid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "条件未达成")))
		_flash_btn(btn)
		return
	c._show_stage_hint("套装升级成功：Lv%d" % int(r.get("lv", 0)))
	_refresh()

func _effect_text(fc: Dictionary, lv: int) -> String:
	var q: Dictionary = _sys().get_quality_cfg(str(fc.get("quality", "")))
	if str(q.get("attr", "")) == "aptitude":
		return "%s类门客资质 +%d" % [fc.get("career", ""), lv * int(q.get("attr_per_lv", 0))]
	return "%s类门客赚钱 +%s" % [fc.get("career", ""), c.format_number(lv * int(q.get("attr_per_lv", 0)))]

func _on_upgrade(fid: String, is_all: bool, btn: Button):
	# 升级前快照（效果弹窗差值用）
	var st0: Dictionary = _sys().get_furniture_state(fid)
	var comfort0: int = _sys().get_total_comfort()
	var fs0: int = _sys().get_fengshui()
	var r: Dictionary = _sys().upgrade_all(fid) if is_all else _sys().upgrade_furniture(fid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "无法升级")))
		_flash_btn(btn)
		return
	var st1: Dictionary = _sys().get_furniture_state(fid)
	_upresult = {
		"lv0": st0["lv"], "lv1": st1["lv"],
		"d_comfort": _sys().get_total_comfort() - comfort0,
		"d_fengshui": _sys().get_fengshui() - fs0,
	}
	_popup_kind = "upresult"
	_popup_id = fid
	c._show_stage_hint("升级成功：Lv%d" % st1["lv"])
	_refresh()   # 重建页面+按弹窗状态原地重建

# ---- 工坊购买弹窗：滑条+SpinBox 数量选择 ----
func _show_buy_popup(fid: String):
	_popup_kind = "buy"
	_popup_id = fid
	var fc: Dictionary = _sys().get_furniture_cfg(fid)
	if fc.is_empty():
		close_popup()
		return
	var vbox: VBoxContainer = _popup_vbox("购买家具", Vector2(440, 280))
	var price: int = _sys().get_workshop_price(str(fc.get("quality", "")))
	var max_n: int = maxi(1, int(floor(_sys().get_jiajibi() / float(price))))

	var name_l := Label.new()
	name_l.text = "%s · 单价 %d 家具币（持有 %d）" % [
		fc.get("name", ""), price, _sys().get_furniture_state(fid)["cnt"]]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 15)
	vbox.add_child(name_l)

	var pair: Dictionary = c.ui_helpers._create_slider_spin_pair(vbox, max_n, 1)
	var total_l := Label.new()
	total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(total_l)
	var _upd := func():
		total_l.text = "合计：%d 家具币（余额 %d）" % [int(pair["spin"].value) * price, _sys().get_jiajibi()]
	pair["slider"].value_changed.connect(func(_v): _upd.call())
	pair["spin"].value_changed.connect(func(_v): _upd.call())
	_upd.call()

	var buy_btn := Button.new()
	buy_btn.text = "购买"
	buy_btn.custom_minimum_size = Vector2(0, 40)
	buy_btn.pressed.connect(func():
		_on_buy(fid, int(pair["spin"].value), buy_btn))
	vbox.add_child(buy_btn)

	c._add_ok_button(vbox, func(): close_popup(), "关闭")

func _on_buy(fid: String, n: int, btn: Button):
	var r: Dictionary = _sys().buy_furniture(fid, n)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "购买失败")))
		_flash_btn(btn)
		return
	c._show_stage_hint("购买成功：%s ×%d" % [_sys().get_furniture_cfg(fid).get("name", ""), n])
	_refresh()

# 按钮闪红（捕获节点版：回调/闭包捕获按钮，先 is_instance_valid 守卫——闪红后紧跟页面重建是惯例，防悬挂崩溃）
func _flash_btn(btn: Button):
	if not is_instance_valid(btn):
		return
	var normal: StyleBox = btn.get_theme_stylebox("normal")
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.55, 0.12, 0.12)
	btn.add_theme_stylebox_override("normal", red)
	btn.add_theme_stylebox_override("hover", red)
	btn.add_theme_stylebox_override("pressed", red)
	var tw := btn.create_tween()
	tw.tween_interval(0.2)
	tw.tween_callback(func():
		if not is_instance_valid(btn):
			return
		if normal != null:
			btn.add_theme_stylebox_override("normal", normal)
		btn.remove_theme_stylebox_override("hover")
		btn.remove_theme_stylebox_override("pressed"))
# ==================== 命盘页（批次③） ====================
func _msys() -> MingpanSystem:
	return data.mingpan_system

func _build_mingpan_page(page: Panel):
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 6)
	page.add_child(root)

	# 顶栏
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(func():
		_tab = "home"
		_refresh())
	top.add_child(back)
	var title := Label.new()
	title.text = "命盘"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var overview_btn := Button.new()
	overview_btn.text = "加成总览"
	overview_btn.custom_minimum_size = Vector2(90, 40)
	overview_btn.pressed.connect(func(): _show_overview_popup())
	top.add_child(overview_btn)

	# 进度行：命盘等级 + 进度条
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 8)
	root.add_child(prog_row)
	var prog_lbl := Label.new()
	prog_lbl.text = "命盘 %d 级" % _msys().plate_lv
	prog_lbl.add_theme_font_size_override("font_size", 14)
	prog_row.add_child(prog_lbl)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = float(_msys().get_current_need())
	bar.value = float(_msys().plate_exp)
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_row.add_child(bar)
	var exp_lbl := Label.new()
	exp_lbl.text = "%d/%d" % [_msys().plate_exp, _msys().get_current_need()]
	prog_row.add_child(exp_lbl)

	# 盘 Tab（未解锁置灰+悬停看条件）
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	for pid in _msys().get_plate_list():
		var pcfg: Dictionary = _msys().get_plate_cfg(pid)
		var pbtn := Button.new()
		pbtn.text = str(pcfg.get("name", pid))
		pbtn.custom_minimum_size = Vector2(64, 34)
		var unlocked: bool = _msys().is_unlocked_plate(pid)
		pbtn.disabled = not unlocked
		if not unlocked:
			pbtn.tooltip_text = _msys().get_unlock_desc(pid)
		if pid == _sel_plate and unlocked:
			pbtn.add_theme_color_override("font_color", Color("#ffd700"))
		var pid2: String = str(pid)
		pbtn.pressed.connect(func():
			_sel_plate = pid2
			_refresh())
		tabs.add_child(pbtn)

	# 盘区（当前选中盘未解锁则回退 p1）
	if not _msys().is_unlocked_plate(_sel_plate):
		_sel_plate = "p1"
	var plate_area := VBoxContainer.new()
	plate_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	plate_area.add_theme_constant_override("separation", 4)
	root.add_child(plate_area)
	_fill_plate_area(plate_area)

	# 底部操作：卜卦 / 自动卜卦 / 升级效果
	var ops := HBoxContainer.new()
	ops.alignment = BoxContainer.ALIGNMENT_CENTER
	ops.add_theme_constant_override("separation", 10)
	root.add_child(ops)
	var divine_btn := Button.new()
	divine_btn.text = "卜卦（风水符 %d/%d）" % [_msys().get_talisman_count(), _msys().get_divine_cost()]
	divine_btn.custom_minimum_size = Vector2(180, 42)
	divine_btn.pressed.connect(func(): _on_divine(divine_btn))
	ops.add_child(divine_btn)
	var auto_btn := Button.new()
	auto_btn.text = "停止" if _auto_divining else "自动卜卦"
	auto_btn.custom_minimum_size = Vector2(110, 42)
	auto_btn.pressed.connect(func(): _on_auto_divine())
	ops.add_child(auto_btn)
	var upeffect_btn := Button.new()
	upeffect_btn.text = "升级效果"
	upeffect_btn.custom_minimum_size = Vector2(110, 42)
	upeffect_btn.pressed.connect(func(): _show_upeffect_popup())
	ops.add_child(upeffect_btn)

# 盘区：外圈 6 槽（3 列）+ 内圈 4 槽（4 列）
func _fill_plate_area(plate_area: VBoxContainer):
	var pcfg: Dictionary = _msys().get_plate_cfg(_sel_plate)
	var outer_lbl := Label.new()
	outer_lbl.text = "外圈 · 资质命格（%s）" % str(pcfg.get("gan", ""))
	outer_lbl.add_theme_font_size_override("font_size", 12)
	outer_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	plate_area.add_child(outer_lbl)
	var outer_grid := GridContainer.new()
	outer_grid.columns = 3
	outer_grid.add_theme_constant_override("h_separation", 6)
	outer_grid.add_theme_constant_override("v_separation", 6)
	plate_area.add_child(outer_grid)
	for i in range(6):
		outer_grid.add_child(_make_slot_card(_sel_plate, i))
	var inner_lbl := Label.new()
	inner_lbl.text = "内圈 · 四象赚钱"
	inner_lbl.add_theme_font_size_override("font_size", 12)
	inner_lbl.add_theme_color_override("font_color", Color("#aaaaaa"))
	plate_area.add_child(inner_lbl)
	var inner_grid := GridContainer.new()
	inner_grid.columns = 4
	inner_grid.add_theme_constant_override("h_separation", 6)
	inner_grid.add_theme_constant_override("v_separation", 6)
	plate_area.add_child(inner_grid)
	for i in range(6, 10):
		inner_grid.add_child(_make_slot_card(_sel_plate, i))

# 槽位卡：空槽=槽名；有命格=品质色+品质名+Lv+总值
func _make_slot_card(pid: String, idx: int) -> PanelContainer:
	var pcfg: Dictionary = _msys().get_plate_cfg(pid)
	var slot_name: String = str(pcfg.get("outer", [])[idx]) if idx < 6 else str(pcfg.get("inner", [])[idx - 6])
	var sd: Dictionary = _msys().get_slot_luck(pid, idx)
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#262238")
	var qcolor: String = _msys().get_quality_color(str(sd.get("q", ""))) if not sd.is_empty() else "#4a4460"
	cs.border_color = Color(qcolor)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(5)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(118, 62)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var vl := VBoxContainer.new()
	vl.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vl)
	var name_l := Label.new()
	name_l.text = slot_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 12)
	name_l.add_theme_color_override("font_color", Color("#bbbbbb"))
	vl.add_child(name_l)
	var info_l := Label.new()
	if sd.is_empty():
		info_l.text = "空"
		info_l.add_theme_color_override("font_color", Color("#666666"))
	else:
		var qcfg: Dictionary = _msys().get_quality_cfg(str(sd.get("q", "")))
		var total: float = _msys().luck_value(sd)
		var unit: String = "资质+%d" % int(total) if idx < 6 else "+%.2f%%" % total
		info_l.text = "%s Lv%d · %s" % [qcfg.get("name", ""), int(sd.get("lv", 1)), unit]
		info_l.add_theme_color_override("font_color", Color(_msys().get_quality_color(str(sd.get("q", "")))))
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_l.add_theme_font_size_override("font_size", 11)
	vl.add_child(info_l)
	var pid2: String = pid
	var idx2: int = idx
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_luck_detail_popup("%s:%d" % [pid2, idx2]))
	_pass_clicks(card)
	return card

# 槽位命格详情弹窗
func _show_luck_detail_popup(popup_id: String):
	var parts: PackedStringArray = popup_id.split(":")
	if parts.size() != 2:
		close_popup()
		return
	var pid: String = parts[0]
	var idx: int = int(parts[1])
	_popup_kind = "mingpan_detail"
	_popup_id = popup_id
	var sd: Dictionary = _msys().get_slot_luck(pid, idx)
	var vbox: VBoxContainer = _popup_vbox("命格详情", Vector2(440, 360))
	var pcfg: Dictionary = _msys().get_plate_cfg(pid)
	var slot_name: String = str(pcfg.get("outer", [])[idx]) if idx < 6 else str(pcfg.get("inner", [])[idx - 6])
	if sd.is_empty():
		var empty_l := Label.new()
		empty_l.text = "%s · 空槽" % slot_name
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_l)
		c._add_ok_button(vbox, func(): close_popup(), "关闭")
		return
	var qcfg: Dictionary = _msys().get_quality_cfg(str(sd.get("q", "")))
	var head := Label.new()
	head.text = "%s · %s Lv%d" % [slot_name, qcfg.get("name", ""), int(sd.get("lv", 1))]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(_msys().get_quality_color(str(sd.get("q", "")))))
	vbox.add_child(head)
	var heroes: Dictionary = sd.get("heroes", {})
	for hid in heroes.keys():
		var hero_name: String = str((data.heroes.get(hid, {}) as Dictionary).get("name", hid))
		var val: float = float(heroes[hid])
		var line := Label.new()
		line.text = "%s：%s" % [hero_name, ("资质 +%d" % int(val)) if idx < 6 else ("赚钱 +%.2f%%" % val)]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_color_override("font_color", Color("#dddddd"))
		vbox.add_child(line)
	c._add_ok_button(vbox, func(): close_popup(), "关闭")

# 卜卦一卦
func _on_divine(btn: Button):
	var r: Dictionary = _msys().divine()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "无法卜卦")))
		_flash_btn(btn)
		return
	_pending_luck = r.get("luck", {})
	if int(r.get("ups", 0)) > 0:
		c._show_stage_hint("命盘升级：%d 级！" % _msys().plate_lv)
	_show_divine_popup()

# 卜卦对比弹窗：新命格 vs 槽内原命格（涨绿跌红，铁律：不模糊文案）
func _show_divine_popup():
	if _pending_luck.is_empty():
		close_popup()
		return
	_popup_kind = "divine"
	_popup_id = ""
	var luck: Dictionary = _pending_luck
	var vbox: VBoxContainer = _popup_vbox("卜卦", Vector2(480, 470))
	var pid: String = str(luck.get("plate", ""))
	var idx: int = int(luck.get("slot", 0))
	var pcfg: Dictionary = _msys().get_plate_cfg(pid)
	var slot_name: String = str(pcfg.get("outer", [])[idx]) if idx < 6 else str(pcfg.get("inner", [])[idx - 6])
	var qcfg: Dictionary = _msys().get_quality_cfg(str(luck.get("q", "")))
	var is_outer: bool = idx < 6

	var head := Label.new()
	head.text = "新命格：%s盘 · %s · %s Lv%d" % [pcfg.get("name", ""), slot_name, qcfg.get("name", ""), int(luck.get("lv", 1))]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(_msys().get_quality_color(str(luck.get("q", "")))))
	vbox.add_child(head)

	# 新命格明细
	for hid in (luck.get("heroes", {}) as Dictionary).keys():
		var hero_name: String = str((data.heroes.get(hid, {}) as Dictionary).get("name", hid))
		var val: float = float(luck["heroes"][hid])
		var line := Label.new()
		line.text = "%s：%s" % [hero_name, ("资质 +%d" % int(val)) if is_outer else ("赚钱 +%.2f%%" % val)]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_color_override("font_color", Color("#dddddd"))
		vbox.add_child(line)

	# 对比行：同槽同量纲总值，涨绿跌红
	var old: Dictionary = _msys().get_slot_luck(pid, idx)
	var unit: String = "资质" if is_outer else "赚钱%"
	var new_v: float = _msys().luck_value(luck)
	if old.is_empty():
		var empty_l := Label.new()
		empty_l.text = "%s 空槽 → 直接装上" % slot_name
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_l.add_theme_color_override("font_color", Color("#7ee787"))
		vbox.add_child(empty_l)
	else:
		var old_v: float = _msys().luck_value(old)
		var diff: float = new_v - old_v
		var cmp_l := Label.new()
		cmp_l.text = "%s 对比：%s %s vs %s（%+.2f）" % [
			slot_name, unit, _fmt_val(old_v, is_outer), _fmt_val(new_v, is_outer), diff]
		cmp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cmp_l.add_theme_color_override("font_color", Color("#7ee787") if diff >= 0.0 else Color("#e74c3c"))
		vbox.add_child(cmp_l)
		# 真实赚速增量（替换基准，用户拍板）：装上后总赚速变化，涨绿跌红
		var d_money: float = _msys().luck_money_impact(luck)
		var money_l := Label.new()
		money_l.text = "装上后赚速变化：%+d/秒" % int(d_money)
		money_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		money_l.add_theme_color_override("font_color", Color("#7ee787") if d_money >= 0.0 else Color("#e74c3c"))
		vbox.add_child(money_l)
		var old_q: String = str((_msys().get_quality_cfg(str(old.get("q", ""))) as Dictionary).get("name", ""))
		var old_l := Label.new()
		old_l.text = "原命格：%s Lv%d" % [old_q, int(old.get("lv", 1))]
		old_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		old_l.add_theme_color_override("font_color", Color("#888888"))
		vbox.add_child(old_l)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)
	var install_btn := Button.new()
	install_btn.text = "替换装上"
	install_btn.custom_minimum_size = Vector2(130, 40)
	install_btn.pressed.connect(_on_install_pending)
	btn_row.add_child(install_btn)
	var drop_btn := Button.new()
	drop_btn.text = "放弃"
	drop_btn.custom_minimum_size = Vector2(130, 40)
	drop_btn.pressed.connect(func():
		_pending_luck = {}
		if _auto_divining:
			c._show_stage_hint("已放弃（自动卜卦继续）")
			_refresh()
			_auto_resume()
			return
		close_popup()
		_refresh())
	btn_row.add_child(drop_btn)

func _fmt_val(v: float, is_outer: bool) -> String:
	return "%d" % int(v) if is_outer else "%.2f%%" % v

func _on_install_pending():
	if _pending_luck.is_empty():
		close_popup()
		return
	_msys().install_luck(_pending_luck)
	_pending_luck = {}
	if _auto_divining:
		_auto_stats["replaced"] = int(_auto_stats.get("replaced", 0)) + 1
		c._show_stage_hint("已装上（自动卜卦继续）")
		_refresh()
		_auto_resume()
		return
	c._show_stage_hint("命格已装上")
	_refresh()

# 自动卜卦（用户拍板节奏）：每 0.5 秒一卦；低于/等于槽内现值的自动消失，更高的弹窗暂停手动二选一；
# 选择后自动续抽，直到符尽或手动按「停止」
func _on_auto_divine():
	if _auto_divining:
		_auto_divining = false
		c._show_stage_hint("已停止自动卜卦")
		_refresh()
		return
	if not _msys().can_divine():
		c._show_stage_hint("风水符不足")
		return
	_auto_divining = true
	_refresh()
	_auto_divine_step(0, 0)

func _auto_divine_step(rolls: int, replaced: int):
	if not _auto_divining:
		return
	if not _msys().can_divine():
		_auto_divining = false
		c._show_stage_hint("自动卜卦结束：共 %d 卦，装上 %d 个" % [rolls, replaced])
		_refresh()
		return
	var r: Dictionary = _msys().divine()
	if not r.get("ok", false):
		_auto_divining = false
		_refresh()
		return
	rolls += 1
	if int(r.get("ups", 0)) > 0:
		c._show_stage_hint("命盘升级：%d 级！" % _msys().plate_lv)
	var luck: Dictionary = r.get("luck", {})
	var delta: float = _msys().luck_money_impact(luck)   # 真实赚速增量（临时换装重算，>0 更好）
	var better: bool = delta > 0.0
	if better:
		# 更好的命格：暂停弹窗，玩家手动二选一后由 _auto_resume 续抽
		_auto_stats = {"rolls": rolls, "replaced": replaced}
		_pending_luck = luck
		_show_divine_popup()
	else:
		_refresh()   # 进度条跳动
		await c.get_tree().create_timer(0.5).timeout
		_auto_divine_step(rolls, replaced)

# 自动卜卦暂停后恢复（替换/放弃按钮都走这里）
func _auto_resume():
	if _auto_stats.is_empty():
		return
	var rolls: int = int(_auto_stats.get("rolls", 0))
	var replaced: int = int(_auto_stats.get("replaced", 0))
	_auto_stats = {}
	_refresh()
	await c.get_tree().create_timer(0.5).timeout
	_auto_divine_step(rolls, replaced)

# 加成总览：按门客聚合全部盘贡献
func _show_overview_popup():
	_popup_kind = "overview"
	_popup_id = ""
	var vbox: VBoxContainer = _popup_vbox("加成总览", Vector2(440, 420))
	var totals: Dictionary = _msys().get_hero_totals()
	if totals.is_empty():
		var empty_l := Label.new()
		empty_l.text = "暂无命格加成，先去卜卦吧"
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_l)
	else:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(scroll)
		var rows := VBoxContainer.new()
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_theme_constant_override("separation", 3)
		scroll.add_child(rows)
		for hid in totals.keys():
			var hero_name: String = str((data.heroes.get(hid, {}) as Dictionary).get("name", hid))
			var t: Dictionary = totals[hid]
			var line := Label.new()
			line.text = "%s　资质 +%d　赚钱 +%.2f%%" % [hero_name, int(t.get("apt", 0.0)), float(t.get("pct", 0.0))]
			line.add_theme_font_size_override("font_size", 13)
			rows.add_child(line)
	c._add_ok_button(vbox, func(): close_popup(), "关闭")

# 升级效果：当前 vs 下级 命格等级区间六档概率对照
func _show_upeffect_popup():
	_popup_kind = "upeffect"
	_popup_id = ""
	var vbox: VBoxContainer = _popup_vbox("升级效果", Vector2(440, 380))
	var cur: Array = _msys().get_level_dist(_msys().plate_lv)
	var nxt: Array = _msys().get_level_dist(_msys().plate_lv + 1)
	var head := Label.new()
	head.text = "命格等级区间（命盘 %d 级 → %d 级）" % [_msys().plate_lv, _msys().plate_lv + 1]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", Color("#ffd700"))
	vbox.add_child(head)
	for k in range(cur.size()):
		var line := Label.new()
		line.text = "%d 级：现 %.2f%% → 下级 %.2f%%" % [
			_msys().plate_lv + k, float(cur[k]) * 100.0, float(nxt[k]) * 100.0]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_color_override("font_color", Color("#dddddd") if float(nxt[k]) <= float(cur[k]) else Color("#7ee787"))
		vbox.add_child(line)
	c._add_ok_button(vbox, func(): close_popup(), "关闭")


# ---- 升级效果弹窗（批次④）：旧→新具体数值，涨绿跌红铁律 ----
func _show_upresult_popup(fid: String):
	if _upresult.is_empty():
		close_popup()
		return
	var fc: Dictionary = _sys().get_furniture_cfg(fid)
	if fc.is_empty():
		close_popup()
		return
	_popup_kind = "upresult"
	_popup_id = fid
	var vbox: VBoxContainer = _popup_vbox("升级效果", Vector2(440, 330))
	var lv0: int = int(_upresult.get("lv0", 0))
	var lv1: int = int(_upresult.get("lv1", 0))

	var head := Label.new()
	head.text = "%s　Lv%d → Lv%d" % [fc.get("name", ""), lv0, lv1]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(QUALITY_COLORS.get(str(fc.get("quality", "")), "#ffffff")))
	vbox.add_child(head)

	# 主属性效果：lv0=0（未解锁）时旧值按 0 显示
	var eff := Label.new()
	eff.text = "%s → %s" % [_effect_text(fc, lv0), _effect_text(fc, lv1)]
	eff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eff.add_theme_color_override("font_color", Color("#7ee787"))
	vbox.add_child(eff)

	var dc: int = int(_upresult.get("d_comfort", 0))
	if dc != 0:
		var comfort_l := Label.new()
		comfort_l.text = "舒适度 +%d（当前 %s）" % [dc, c.format_number(_sys().get_total_comfort())]
		comfort_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		comfort_l.add_theme_color_override("font_color", Color("#8fd3c7"))
		vbox.add_child(comfort_l)

	var dfs: int = int(_upresult.get("d_fengshui", 0))
	if dfs != 0:
		var fs_l := Label.new()
		fs_l.text = "风水 +%d（当前 %s · %d 级）" % [dfs, c.format_number(_sys().get_fengshui()), _sys().get_fengshui_level()]
		fs_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fs_l.add_theme_color_override("font_color", Color("#8fd3c7"))
		vbox.add_child(fs_l)

	c._add_ok_button(vbox, func(): close_popup(), "关闭")
