# ============================================================
# 厢房全屏页（府邸「厢房」入口；Page z35 / 弹窗 z40，照 BaseView 新模式）
# 批次①（2026-09-20）：主界面 + 家具图鉴（升级/套装面板）+ 工坊直购。
# 批次②（2026-09-20）：回收（详情页满级富余件）+ 风水详情弹窗（角标点入）+ 勋章（入口/15级列表/升级，
#   shop bonus 挂点=systems/shop_system.gd get_shop_auto_income 末项）；批次③：命盘页；批次④：HeroData 接入。
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

	# 底注：命盘入口批次③
	var note := Label.new()
	note.text = "命盘玩法后续版本开放"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("#888888"))
	root.add_child(note)

# 卡片子节点全部 IGNORE：Label/VBox 默认拦点击不冒泡，会吃掉卡片的 gui_input（照 inn_view「点击穿透到卡片」惯例）
func _pass_clicks(card: Control) -> void:
	for child in card.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pass_clicks(child)

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
	up_btn.text = "升级"
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

	# 10 档概率表（当前风水等级权重，峰值 P 标注）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)
	for row in _sys().get_fengshui_rows(fs_l):
		var row_l := Label.new()
		row_l.text = "%s　%.2f%%（峰值 %d 级）" % [row["name"], float(row["pct"]) * 100.0, int(row["P"])]
		row_l.add_theme_font_size_override("font_size", 13)
		row_l.add_theme_color_override("font_color", Color("#dddddd") if int(row["P"]) > fs_l else Color("#888888"))
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
	var r: Dictionary = _sys().upgrade_all(fid) if is_all else _sys().upgrade_furniture(fid)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("reason", "无法升级")))
		_flash_btn(btn)
		return
	var msg: String = "升级成功：Lv%d" % int(r.get("lv", 0)) if not is_all else "一键升级 %d 次" % int(r.get("times", 0))
	c._show_stage_hint(msg)
	_refresh()   # 重建页面（角标/套装等级）+ 按弹窗状态原地重建详情

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
