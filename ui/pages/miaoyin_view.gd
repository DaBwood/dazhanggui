# ============================================================
# 妙音坊全屏页（商铺地图 妙音坊「▶」入口；Page z35 / 弹窗 z40，照 BaseView 新模式）
# 第一批：主页骨架 + 收益罐领取 + 加速卡使用弹窗 + 勋章弹窗（含赚速升级挂点）
# 底部【建筑/新秀/满意度/选秀】先占位提示“后续版本开放”：对应批次②③④再接，勿提前透数值。
# 红点口径：只页内展示（勋章可升 / 收益罐可领），不穿透商铺地图（照 2026-09-18 用户拍板）。
# ============================================================
class_name MiaoyinView
extends BaseView

func _init(p_c):
	super(p_c)
	_page_name = "MiaoyinPage"
	_popup_node_name = "MiaoyinPopup"
	_page_bg = "#211d33"

func _sys() -> MiaoyinSystem:
	return data.miaoyin_system

func show_miaoyin_view():
	show_view()

func hide_miaoyin_view():
	hide_view()

func _build(page: Panel):
	_sys().settle_jar()
	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 14
	root.offset_top = 12
	root.offset_right = -14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 10)
	page.add_child(root)

	# 顶栏：返回 + 标题 + 勋章入口
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(72, 40)
	back.pressed.connect(hide_miaoyin_view)
	top.add_child(back)
	var title := Label.new()
	title.text = "妙音坊"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	top.add_child(title)
	var medal_btn := Button.new()
	medal_btn.text = _sys().get_medal_name()
	medal_btn.custom_minimum_size = Vector2(112, 40)
	medal_btn.pressed.connect(_show_medal_popup)
	top.add_child(medal_btn)
	_add_btn_dot(medal_btn, _sys().can_upgrade_medal().get("ok", false))

	# 左上资源行：应援币 + 加速卡入口
	var res := HBoxContainer.new()
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	res.add_theme_constant_override("separation", 8)
	root.add_child(res)
	var yyb_lbl := Label.new()
	yyb_lbl.text = "应援币 %s（+%s/分）" % [c.format_number(int(_sys().yyb)), _fmt_rate(_sys().get_yyb_per_min())]
	yyb_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yyb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.add_child(yyb_lbl)
	var plus := Button.new()
	plus.text = "＋"
	plus.custom_minimum_size = Vector2(42, 36)
	plus.pressed.connect(_on_plus_pressed)
	res.add_child(plus)

	# 中间收益罐：三轨累积，点击领取
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 250)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("#2a2640")
	card_style.set_corner_radius_all(12)
	card_style.set_border_width_all(2)
	card_style.border_color = Color("#6a5f9e")
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var jar_title := Label.new()
	jar_title.text = "收益罐"
	jar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	jar_title.add_theme_font_size_override("font_size", 22)
	jar_title.add_theme_color_override("font_color", Color("#ffd700"))
	cv.add_child(jar_title)
	var pending_total: int = _sys().get_pending_total()
	var pending_lbl := Label.new()
	pending_lbl.text = "可领取：%s" % c.format_number(pending_total)
	pending_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pending_lbl.add_theme_font_size_override("font_size", 20)
	cv.add_child(pending_lbl)
	var rate_lbl := Label.new()
	rate_lbl.text = "产出/分：应援币 %s｜应援物 %s｜缘分物 %s" % [
		_fmt_rate(_sys().get_yyb_per_min()), _fmt_rate(_sys().get_yyw_per_min()), _fmt_rate(_sys().get_yyf_per_min())]
	rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate_lbl.add_theme_font_size_override("font_size", 15)
	rate_lbl.add_theme_color_override("font_color", Color("#bdb7d8"))
	cv.add_child(rate_lbl)
	var claim := Button.new()
	claim.text = "领取收益"
	claim.custom_minimum_size = Vector2(140, 44)
	claim.disabled = pending_total <= 0
	claim.pressed.connect(_on_claim_pressed)
	cv.add_child(claim)
	_add_btn_dot(claim, pending_total > 0)

	# 底部四入口：本批只做占位提示，红点随对应批次接入
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	for name in ["建筑", "新秀", "满意度", "选秀"]:
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(82, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_future.bind(name))
		bottom.add_child(b)
		_add_btn_dot(b, false)

func _fmt_rate(x: float) -> String:
	if x >= 100.0:
		return c.format_number(int(round(x)))
	if x > 0.0:
		return "%.1f" % x
	return "0"

func _show_future(name: String):
	c._show_stage_hint("【%s】后续版本开放" % name)

func _on_plus_pressed():
	var count: int = int(data.items.get("miaoyin_jiasu_ka", 0))
	if count <= 0:
		c._show_stage_hint("没有妙音坊加速卡")
		return
	_show_accel_popup()

func _on_claim_pressed():
	var r: Dictionary = _sys().claim_jar()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "暂无可领取收益")))
		return
	c._show_stage_hint(str(r.get("msg", "领取成功")))
	c.update_all_ui()
	_refresh()

func _rebuild_popup():
	if _popup_kind == "medal":
		_show_medal_popup()
	elif _popup_kind == "accel":
		_show_accel_popup()

# ---------- 弹窗：勋章（15 级全表；繁荣度=应援币总产出/分；全部商铺赚速 +100%×级） ----------
func _show_medal_popup():
	close_popup()
	_popup_kind = "medal"
	var popup: PanelContainer = c._create_base_popup("妙音坊勋章", Vector2(460, 560))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var lv: int = _sys().get_medal_lv()
	var medals: Array = _sys()._extra("medal").get("medals", [])

	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#2a2640")
	cs.set_corner_radius_all(6)
	cs.set_border_width_all(2)
	cs.border_color = Color("#6a5f9e")
	card.add_theme_stylebox_override("panel", cs)
	vb.add_child(card)
	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 8)
	card.add_child(cvb)
	var head := Label.new()
	head.text = "当前：%s（%d级）" % [_sys().get_medal_name(lv), lv]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color("#e6c07b"))
	cvb.add_child(head)
	var effect := Label.new()
	effect.text = "全部商铺赚速 +%d%%" % int(round(_sys().get_medal_shop_pct() * 100.0))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cvb.add_child(effect)
	var need: int = _sys().get_next_medal_need()
	if need < 0:
		var full := Label.new()
		full.text = "已满级"
		full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		full.add_theme_color_override("font_color", Color("#7ee787"))
		cvb.add_child(full)
	else:
		var next_lbl := Label.new()
		next_lbl.text = "繁荣度 %s / %s" % [c.format_number(_sys().get_prosperity()), c.format_number(need)]
		next_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvb.add_child(next_lbl)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = float(need)
		bar.value = minf(float(_sys().get_prosperity()), float(need))
		bar.show_percentage = true
		bar.custom_minimum_size = Vector2(410, 18)
		cvb.add_child(bar)
		var next_effect := Label.new()
		next_effect.text = "下级效果：全部商铺赚速 +%d%%" % int(round(float(lv + 1) * 100.0))
		next_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		next_effect.add_theme_color_override("font_color", Color("#7ee787"))
		cvb.add_child(next_effect)
	var up := Button.new()
	up.text = "升级勋章"
	up.custom_minimum_size = Vector2(130, 38)
	up.disabled = not _sys().can_upgrade_medal().get("ok", false)
	up.pressed.connect(_on_medal_upgrade)
	cvb.add_child(up)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 225)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for i in range(medals.size()):
		var m: Dictionary = medals[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = "Lv.%d %s" % [int(m.get("lv", i + 1)), str(m.get("name", ""))]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(m.get("lv", 0)) == lv:
			name_lbl.add_theme_color_override("font_color", Color("#ffd700"))
		row.add_child(name_lbl)
		var need_lbl := Label.new()
		need_lbl.text = "繁荣度 %s" % c.format_number(int(m.get("need_prosperity", 0)))
		need_lbl.add_theme_color_override("font_color", Color("#bdb7d8"))
		row.add_child(need_lbl)
		var eff_lbl := Label.new()
		eff_lbl.text = "+%d%%" % int(round(float(m.get("shop_pct", 0.0)) * 100.0))
		eff_lbl.add_theme_color_override("font_color", Color("#e6c07b"))
		row.add_child(eff_lbl)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(100, 36)
	close_btn.pressed.connect(close_popup)
	vb.add_child(close_btn)

func _on_medal_upgrade():
	var r: Dictionary = _sys().upgrade_medal()
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "暂不可升级")))
		return
	c._show_stage_hint("勋章升级成功")
	c.update_all_ui()
	_refresh()

# ---------- 弹窗：妙音坊加速卡（数量选择；每张=立即获得60分钟三轨收益） ----------
func _show_accel_popup():
	close_popup()
	_popup_kind = "accel"
	var count: int = int(data.items.get("miaoyin_jiasu_ka", 0))
	if count <= 0:
		c._show_stage_hint("没有妙音坊加速卡")
		return
	var popup: PanelContainer = c._create_base_popup("使用妙音坊加速卡", Vector2(430, 300))
	popup.name = _popup_node_name
	popup.z_index = 40
	c.add_child(popup)
	var vb: VBoxContainer = popup.get_child(0)
	var own := Label.new()
	own.text = "拥有加速卡：%d" % count
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(own)
	var pair: Dictionary = c._create_slider_spin_pair(vb, count)
	var spin: SpinBox = pair["spin"]
	var hint := Label.new()
	hint.text = "每张立即获得60分钟当前妙音坊三轨收益"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#bdb7d8"))
	vb.add_child(hint)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	var ok := Button.new()
	ok.text = "使用"
	ok.custom_minimum_size = Vector2(82, 36)
	ok.pressed.connect(_on_accel_confirm.bind(spin))
	btns.add_child(ok)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(82, 36)
	cancel.pressed.connect(close_popup)
	btns.add_child(cancel)

func _on_accel_confirm(spin: SpinBox):
	var n: int = int(spin.value)
	var r: Dictionary = data.use_item("miaoyin_jiasu_ka", n)
	if not r.get("ok", false):
		c._show_stage_hint(str(r.get("msg", "使用失败")))
		return
	c._show_stage_hint(str(r.get("msg", "使用成功")))
	c.update_all_ui()
	close_popup()
	_refresh()
